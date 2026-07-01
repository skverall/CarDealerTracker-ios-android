CREATE OR REPLACE FUNCTION public.admin_archive_listing(
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_session_token text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_admin public.admin_users%ROWTYPE;
    v_rows integer;
BEGIN
    BEGIN
        SELECT * INTO v_admin
        FROM public.require_admin_session(p_session_token, p_admin_user_id);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END;

    UPDATE public.listings
    SET deleted_at = COALESCE(deleted_at, now()),
        updated_at = now()
    WHERE id = p_listing_id
    RETURNING 1 INTO v_rows;

    IF v_rows IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
    END IF;

    PERFORM public.log_admin_activity(v_admin.id, 'archive_listing', 'listing', p_listing_id::text);
    RETURN jsonb_build_object('success', true, 'message', 'Listing archived');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_moderate_listing(
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_action text,
    p_reason text DEFAULT NULL::text,
    p_session_token text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_admin public.admin_users%ROWTYPE;
    v_new_status text;
    v_rows integer;
BEGIN
    IF p_action = 'approve' THEN
        v_new_status := 'approved';
    ELSIF p_action = 'reject' THEN
        v_new_status := 'rejected';
    ELSE
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    BEGIN
        SELECT * INTO v_admin
        FROM public.require_admin_session(p_session_token, p_admin_user_id);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END;

    IF v_admin.role NOT IN ('admin', 'moderator', 'super_admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
    END IF;

    UPDATE public.listings
    SET moderation_status = v_new_status,
        moderation_reason = p_reason,
        moderated_at = now(),
        moderated_by = v_admin.id,
        status = CASE WHEN v_new_status = 'approved' THEN 'active' ELSE status END,
        is_draft = CASE
            WHEN v_new_status = 'approved' THEN false
            WHEN v_new_status = 'rejected' THEN true
            ELSE is_draft
        END
    WHERE id = p_listing_id
    RETURNING 1 INTO v_rows;

    IF v_rows IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
    END IF;

    PERFORM public.log_admin_activity(
        v_admin.id,
        'moderate_listing',
        'listing',
        p_listing_id::text,
        jsonb_build_object('status', v_new_status, 'reason', p_reason)
    );

    RETURN jsonb_build_object('success', true, 'message', 'Listing updated');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_moderate_listing(
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_action text,
    p_reason text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    result json;
    listing_title text;
BEGIN
    PERFORM 1
    FROM public.admin_users au
    WHERE au.id = p_admin_user_id
      AND au.is_active = true
      AND au.role IN ('admin', 'moderator', 'super_admin');

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Not authorized');
    END IF;

    SELECT title INTO listing_title
    FROM public.listings
    WHERE id = p_listing_id;

    IF listing_title IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Listing not found');
    END IF;

    IF p_action = 'approve' THEN
        UPDATE public.listings
        SET moderation_status = 'approved',
            status = 'active',
            is_draft = false,
            updated_at = now()
        WHERE id = p_listing_id;

        PERFORM public.log_user_activity(
            (SELECT user_id FROM public.listings WHERE id = p_listing_id),
            'listing_approved',
            p_admin_user_id,
            json_build_object('listing_id', p_listing_id, 'listing_title', listing_title, 'action', 'approved')::jsonb
        );

        result := json_build_object('success', true, 'message', 'Listing approved successfully');
    ELSIF p_action = 'reject' THEN
        UPDATE public.listings
        SET moderation_status = 'rejected',
            is_draft = true,
            updated_at = now()
        WHERE id = p_listing_id;

        PERFORM public.log_user_activity(
            (SELECT user_id FROM public.listings WHERE id = p_listing_id),
            'listing_rejected',
            p_admin_user_id,
            json_build_object('listing_id', p_listing_id, 'listing_title', listing_title, 'action', 'rejected', 'reason', p_reason)::jsonb
        );

        result := json_build_object('success', true, 'message', 'Listing rejected successfully');
    ELSE
        result := json_build_object('success', false, 'error', 'Invalid action. Use approve or reject');
    END IF;

    RETURN result;
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_restore_listing(
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_session_token text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_admin public.admin_users%ROWTYPE;
    v_rows integer;
BEGIN
    BEGIN
        SELECT * INTO v_admin
        FROM public.require_admin_session(p_session_token, p_admin_user_id);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END;

    UPDATE public.listings
    SET status = 'active',
        deleted_at = NULL,
        updated_at = now()
    WHERE id = p_listing_id
    RETURNING 1 INTO v_rows;

    IF v_rows IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
    END IF;

    PERFORM public.log_admin_activity(v_admin.id, 'restore_listing', 'listing', p_listing_id::text);
    RETURN jsonb_build_object('success', true, 'message', 'Listing restored to active');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_listing_fields(
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_title text DEFAULT NULL::text,
    p_description text DEFAULT NULL::text,
    p_price numeric DEFAULT NULL::numeric,
    p_location text DEFAULT NULL::text,
    p_session_token text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_admin public.admin_users%ROWTYPE;
    v_rows integer;
BEGIN
    BEGIN
        SELECT * INTO v_admin
        FROM public.require_admin_session(p_session_token, p_admin_user_id);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END;

    UPDATE public.listings
    SET title = COALESCE(p_title, title),
        description = COALESCE(p_description, description),
        price = COALESCE(p_price, price),
        city = COALESCE(p_location, city),
        updated_at = now()
    WHERE id = p_listing_id
    RETURNING 1 INTO v_rows;

    IF v_rows IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
    END IF;

    PERFORM public.log_admin_activity(
        v_admin.id,
        'update_listing_fields',
        'listing',
        p_listing_id::text,
        jsonb_build_object(
            'title_updated', p_title IS NOT NULL,
            'description_updated', p_description IS NOT NULL,
            'price_updated', p_price IS NOT NULL,
            'location_updated', p_location IS NOT NULL
        )
    );

    RETURN jsonb_build_object('success', true, 'message', 'Listing updated');
END;
$function$;

NOTIFY pgrst, 'reload schema';
