CREATE SCHEMA IF NOT EXISTS app_private;

REVOKE ALL ON SCHEMA app_private FROM PUBLIC;
GRANT USAGE ON SCHEMA app_private TO authenticated;
GRANT USAGE ON SCHEMA app_private TO service_role;

CREATE TABLE IF NOT EXISTS app_private.app_feedback_admin_emails (
    email text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (email = lower(btrim(email))),
    CHECK (position('@' IN email) > 1)
);

REVOKE ALL ON TABLE app_private.app_feedback_admin_emails FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE app_private.app_feedback_admin_emails TO service_role;

INSERT INTO app_private.app_feedback_admin_emails (email)
VALUES
    ('aydmaxx@gmail.com'),
    ('aydmaxxmaxx@gmail.com')
ON CONFLICT (email) DO NOTHING;

ALTER TABLE public.app_feedback_requests
    ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
    ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completed_at timestamptz,
    ADD COLUMN IF NOT EXISTS completed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS app_feedback_requests_visible_status_rank_idx
    ON public.app_feedback_requests (is_hidden, status, vote_count DESC, created_at DESC);

CREATE OR REPLACE FUNCTION app_private.current_feedback_email()
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO public
AS $function$
    SELECT lower(btrim(COALESCE(auth.jwt() ->> 'email', '')));
$function$;

CREATE OR REPLACE FUNCTION app_private.is_app_feedback_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO app_private, public
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM app_private.app_feedback_admin_emails a
        WHERE a.email = app_private.current_feedback_email()
    );
$function$;

CREATE OR REPLACE FUNCTION app_private.get_app_feedback_requests(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    title text,
    details text,
    status text,
    vote_count integer,
    has_voted boolean,
    is_mine boolean,
    can_delete boolean,
    can_admin boolean,
    completed_at timestamptz,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO app_private, public
AS $function$
    WITH request_context AS (
        SELECT
            auth.uid() AS user_id,
            app_private.is_app_feedback_admin() AS is_admin
    )
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
              AND v.voter_id = request_context.user_id
        ) AS has_voted,
        COALESCE(r.author_id = request_context.user_id, false) AS is_mine,
        COALESCE(r.author_id = request_context.user_id AND r.status <> 'shipped', false) AS can_delete,
        request_context.is_admin AS can_admin,
        r.completed_at,
        r.created_at
    FROM public.app_feedback_requests r
    CROSS JOIN request_context
    WHERE r.is_hidden = false
      AND request_context.user_id IS NOT NULL
    ORDER BY
        CASE r.status
            WHEN 'open' THEN 1
            WHEN 'planned' THEN 2
            WHEN 'in_progress' THEN 3
            WHEN 'closed' THEN 4
            WHEN 'shipped' THEN 5
            ELSE 6
        END,
        CASE WHEN r.status = 'shipped' THEN r.completed_at END DESC NULLS LAST,
        r.vote_count DESC,
        r.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
$function$;

DROP FUNCTION IF EXISTS public.get_app_feedback_requests(integer);
CREATE FUNCTION public.get_app_feedback_requests(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    title text,
    details text,
    status text,
    vote_count integer,
    has_voted boolean,
    is_mine boolean,
    can_delete boolean,
    can_admin boolean,
    completed_at timestamptz,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO public, app_private
AS $function$
    SELECT *
    FROM app_private.get_app_feedback_requests(p_limit);
$function$;

CREATE OR REPLACE FUNCTION app_private.delete_app_feedback_request(p_request_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO app_private, public
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_updated integer;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    UPDATE public.app_feedback_requests
    SET
        is_hidden = true,
        deleted_at = now(),
        deleted_by = v_uid
    WHERE id = p_request_id
      AND author_id = v_uid
      AND is_hidden = false
      AND status <> 'shipped';

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    IF v_updated = 0 THEN
        RAISE EXCEPTION 'Only the author can delete their own open feedback request';
    END IF;

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_app_feedback_request(p_request_id uuid)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO public, app_private
AS $function$
    SELECT app_private.delete_app_feedback_request(p_request_id);
$function$;

CREATE OR REPLACE FUNCTION app_private.set_app_feedback_status(
    p_request_id uuid,
    p_status text
)
RETURNS TABLE (
    id uuid,
    status text,
    completed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO app_private, public
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_status text := lower(btrim(COALESCE(p_status, '')));
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF NOT app_private.is_app_feedback_admin() THEN
        RAISE EXCEPTION 'Only feedback admins can update idea status';
    END IF;

    IF v_status NOT IN ('open', 'planned', 'in_progress', 'shipped', 'closed') THEN
        RAISE EXCEPTION 'Unsupported feedback status';
    END IF;

    RETURN QUERY
    UPDATE public.app_feedback_requests r
    SET
        status = v_status,
        completed_at = CASE
            WHEN v_status = 'shipped' THEN COALESCE(r.completed_at, now())
            ELSE NULL
        END,
        completed_by = CASE
            WHEN v_status = 'shipped' THEN v_uid
            ELSE NULL
        END
    WHERE r.id = p_request_id
      AND r.is_hidden = false
    RETURNING r.id, r.status, r.completed_at;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Feedback request not found';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_app_feedback_status(
    p_request_id uuid,
    p_status text
)
RETURNS TABLE (
    id uuid,
    status text,
    completed_at timestamptz
)
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO public, app_private
AS $function$
    SELECT *
    FROM app_private.set_app_feedback_status(p_request_id, p_status);
$function$;

INSERT INTO public.app_feedback_requests (
    title,
    details,
    status,
    platform,
    language,
    completed_at
)
SELECT
    'AI advisor for dealers',
    'Dealers asked for an AI advisor. The developer added it.',
    'shipped',
    'unknown',
    'en',
    now()
WHERE NOT EXISTS (
    SELECT 1
    FROM public.app_feedback_requests
    WHERE title = 'AI advisor for dealers'
      AND status = 'shipped'
);

REVOKE ALL ON FUNCTION app_private.current_feedback_email() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app_private.is_app_feedback_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app_private.get_app_feedback_requests(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION app_private.delete_app_feedback_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION app_private.set_app_feedback_status(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION app_private.get_app_feedback_requests(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION app_private.delete_app_feedback_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app_private.set_app_feedback_status(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.get_app_feedback_requests(integer) FROM anon, public;
REVOKE ALL ON FUNCTION public.delete_app_feedback_request(uuid) FROM anon, public;
REVOKE ALL ON FUNCTION public.set_app_feedback_status(uuid, text) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.get_app_feedback_requests(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_app_feedback_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_app_feedback_status(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
