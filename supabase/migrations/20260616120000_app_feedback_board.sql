CREATE TABLE IF NOT EXISTS public.app_feedback_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 4 AND 120),
    details text CHECK (details IS NULL OR char_length(details) <= 1200),
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'planned', 'in_progress', 'shipped', 'closed')),
    platform text CHECK (platform IS NULL OR platform IN ('ios', 'android', 'unknown')),
    language text CHECK (language IS NULL OR char_length(language) <= 12),
    vote_count integer NOT NULL DEFAULT 0 CHECK (vote_count >= 0),
    is_hidden boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS app_feedback_requests_visible_rank_idx
    ON public.app_feedback_requests (is_hidden, status, vote_count DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS app_feedback_requests_author_created_idx
    ON public.app_feedback_requests (author_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.app_feedback_votes (
    request_id uuid NOT NULL REFERENCES public.app_feedback_requests(id) ON DELETE CASCADE,
    voter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (request_id, voter_id)
);

CREATE INDEX IF NOT EXISTS app_feedback_votes_voter_created_idx
    ON public.app_feedback_votes (voter_id, created_at DESC);

ALTER TABLE public.app_feedback_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_feedback_votes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.app_feedback_requests FROM anon, authenticated;
REVOKE ALL ON TABLE public.app_feedback_votes FROM anon, authenticated;
GRANT ALL ON TABLE public.app_feedback_requests TO service_role;
GRANT ALL ON TABLE public.app_feedback_votes TO service_role;

DROP POLICY IF EXISTS app_feedback_requests_select ON public.app_feedback_requests;
DROP POLICY IF EXISTS app_feedback_votes_select ON public.app_feedback_votes;

CREATE OR REPLACE FUNCTION public.touch_app_feedback_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS app_feedback_requests_touch_updated_at ON public.app_feedback_requests;
CREATE TRIGGER app_feedback_requests_touch_updated_at
    BEFORE UPDATE ON public.app_feedback_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_app_feedback_request();

CREATE OR REPLACE FUNCTION public.update_app_feedback_vote_count()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.app_feedback_requests
        SET vote_count = vote_count + 1
        WHERE id = NEW.request_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.app_feedback_requests
        SET vote_count = GREATEST(vote_count - 1, 0)
        WHERE id = OLD.request_id;
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS app_feedback_votes_count_insert ON public.app_feedback_votes;
CREATE TRIGGER app_feedback_votes_count_insert
    AFTER INSERT ON public.app_feedback_votes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_app_feedback_vote_count();

DROP TRIGGER IF EXISTS app_feedback_votes_count_delete ON public.app_feedback_votes;
CREATE TRIGGER app_feedback_votes_count_delete
    AFTER DELETE ON public.app_feedback_votes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_app_feedback_vote_count();

DROP FUNCTION IF EXISTS public.get_app_feedback_requests(integer);
CREATE OR REPLACE FUNCTION public.get_app_feedback_requests(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    title text,
    details text,
    status text,
    vote_count integer,
    has_voted boolean,
    is_mine boolean,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
    SELECT
        r.id,
        r.title,
        r.details,
        r.status,
        r.vote_count,
        EXISTS (
            SELECT 1
            FROM public.app_feedback_votes v
            WHERE v.request_id = r.id
              AND v.voter_id = auth.uid()
        ) AS has_voted,
        COALESCE(r.author_id = auth.uid(), false) AS is_mine,
        r.created_at
    FROM public.app_feedback_requests r
    WHERE r.is_hidden = false
      AND auth.uid() IS NOT NULL
    ORDER BY
        CASE r.status
            WHEN 'shipped' THEN 1
            WHEN 'in_progress' THEN 2
            WHEN 'planned' THEN 3
            WHEN 'open' THEN 4
            ELSE 5
        END,
        r.vote_count DESC,
        r.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
$function$;

DROP FUNCTION IF EXISTS public.create_app_feedback_request(text, text, text, text);
CREATE OR REPLACE FUNCTION public.create_app_feedback_request(
    p_title text,
    p_details text DEFAULT NULL,
    p_platform text DEFAULT 'unknown',
    p_language text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_title text := btrim(COALESCE(p_title, ''));
    v_details text := NULLIF(btrim(COALESCE(p_details, '')), '');
    v_platform text := lower(btrim(COALESCE(p_platform, 'unknown')));
    v_language text := NULLIF(left(btrim(COALESCE(p_language, '')), 12), '');
    v_id uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF char_length(v_title) < 4 OR char_length(v_title) > 120 THEN
        RAISE EXCEPTION 'Title must be between 4 and 120 characters';
    END IF;

    IF v_details IS NOT NULL AND char_length(v_details) > 1200 THEN
        RAISE EXCEPTION 'Details must be 1200 characters or fewer';
    END IF;

    IF v_platform NOT IN ('ios', 'android', 'unknown') THEN
        v_platform := 'unknown';
    END IF;

    INSERT INTO public.app_feedback_requests (
        author_id,
        title,
        details,
        platform,
        language
    ) VALUES (
        v_uid,
        v_title,
        v_details,
        v_platform,
        v_language
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

DROP FUNCTION IF EXISTS public.toggle_app_feedback_vote(uuid);
CREATE OR REPLACE FUNCTION public.toggle_app_feedback_vote(p_request_id uuid)
RETURNS TABLE (
    voted boolean,
    vote_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_removed integer;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.app_feedback_requests
        WHERE id = p_request_id
          AND is_hidden = false
    ) THEN
        RAISE EXCEPTION 'Feedback request not found';
    END IF;

    DELETE FROM public.app_feedback_votes
    WHERE request_id = p_request_id
      AND voter_id = v_uid;

    GET DIAGNOSTICS v_removed = ROW_COUNT;

    IF v_removed > 0 THEN
        RETURN QUERY
        SELECT false, r.vote_count
        FROM public.app_feedback_requests r
        WHERE r.id = p_request_id;
        RETURN;
    END IF;

    INSERT INTO public.app_feedback_votes (request_id, voter_id)
    VALUES (p_request_id, v_uid)
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT true, r.vote_count
    FROM public.app_feedback_requests r
    WHERE r.id = p_request_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_app_feedback_requests(integer) FROM anon, public;
REVOKE ALL ON FUNCTION public.create_app_feedback_request(text, text, text, text) FROM anon, public;
REVOKE ALL ON FUNCTION public.toggle_app_feedback_vote(uuid) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.get_app_feedback_requests(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_app_feedback_request(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_app_feedback_vote(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
