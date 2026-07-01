ALTER TABLE public.app_feedback_requests
    ADD COLUMN IF NOT EXISTS view_count integer NOT NULL DEFAULT 0 CHECK (view_count >= 0);

CREATE TABLE IF NOT EXISTS public.app_feedback_views (
    request_id uuid NOT NULL REFERENCES public.app_feedback_requests(id) ON DELETE CASCADE,
    viewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (request_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS app_feedback_views_viewer_created_idx
    ON public.app_feedback_views (viewer_id, created_at DESC);

ALTER TABLE public.app_feedback_views ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.app_feedback_views FROM anon, authenticated;
GRANT ALL ON TABLE public.app_feedback_views TO service_role;

CREATE OR REPLACE FUNCTION public.update_app_feedback_view_count()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE public.app_feedback_requests
    SET view_count = view_count + 1
    WHERE id = NEW.request_id;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS app_feedback_views_count_insert ON public.app_feedback_views;
CREATE TRIGGER app_feedback_views_count_insert
    AFTER INSERT ON public.app_feedback_views
    FOR EACH ROW
    EXECUTE FUNCTION public.update_app_feedback_view_count();

CREATE OR REPLACE FUNCTION app_private.record_app_feedback_view(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO app_private, public
AS $function$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.app_feedback_views (request_id, viewer_id)
    VALUES (p_request_id, v_uid)
    ON CONFLICT DO NOTHING;
END;
$function$;

DROP FUNCTION IF EXISTS public.record_app_feedback_view(uuid);
CREATE FUNCTION public.record_app_feedback_view(p_request_id uuid)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO public, app_private
AS $function$
    SELECT app_private.record_app_feedback_view(p_request_id);
$function$;

-- Widen get_app_feedback_requests to also return view_count. Drop the public wrapper
-- first since (as a LANGUAGE sql function) it depends on the app_private definition.
DROP FUNCTION IF EXISTS public.get_app_feedback_requests(integer);
DROP FUNCTION IF EXISTS app_private.get_app_feedback_requests(integer);

CREATE FUNCTION app_private.get_app_feedback_requests(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    title text,
    details text,
    status text,
    vote_count integer,
    view_count integer,
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
        r.view_count,
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

CREATE FUNCTION public.get_app_feedback_requests(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    title text,
    details text,
    status text,
    vote_count integer,
    view_count integer,
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

REVOKE ALL ON FUNCTION public.record_app_feedback_view(uuid) FROM anon, public;
REVOKE ALL ON FUNCTION app_private.record_app_feedback_view(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app_private.get_app_feedback_requests(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_app_feedback_requests(integer) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.record_app_feedback_view(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app_private.record_app_feedback_view(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app_private.get_app_feedback_requests(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_feedback_requests(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
