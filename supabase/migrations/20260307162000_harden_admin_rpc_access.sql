CREATE OR REPLACE FUNCTION public.require_admin_session(
    p_session_token text,
    p_admin_user_id uuid DEFAULT NULL::uuid
)
RETURNS public.admin_users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    session_record public.admin_sessions%ROWTYPE;
    admin_record public.admin_users%ROWTYPE;
BEGIN
    IF p_session_token IS NULL OR btrim(p_session_token) = '' THEN
        RAISE EXCEPTION 'Invalid or expired admin session';
    END IF;

    SELECT *
    INTO session_record
    FROM public.admin_sessions
    WHERE session_token = p_session_token
      AND is_active = true
      AND expires_at > now();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired admin session';
    END IF;

    SELECT *
    INTO admin_record
    FROM public.admin_users
    WHERE id = session_record.admin_user_id
      AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admin user not found or inactive';
    END IF;

    IF p_admin_user_id IS NOT NULL AND admin_record.id <> p_admin_user_id THEN
        RAISE EXCEPTION 'Admin session mismatch';
    END IF;

    UPDATE public.admin_sessions
    SET last_activity_at = now()
    WHERE id = session_record.id;

    RETURN admin_record;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats(
    p_session_token text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN public.get_admin_dashboard_stats();
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_users_for_admin(
    p_session_token text,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_search text DEFAULT NULL::text,
    p_status_filter text DEFAULT NULL::text,
    p_sort_by text DEFAULT 'created_at'::text,
    p_sort_order text DEFAULT 'desc'::text
)
RETURNS TABLE(
    user_id uuid,
    email text,
    full_name text,
    phone text,
    location text,
    is_dealer boolean,
    verification_status text,
    created_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    email_confirmed_at timestamp with time zone,
    banned_until timestamp with time zone,
    deleted_at timestamp with time zone,
    listings_count integer,
    messages_count integer,
    account_status text,
    total_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN QUERY
    SELECT *
    FROM public.get_users_for_admin(
        p_limit,
        p_offset,
        p_search,
        p_status_filter,
        p_sort_by,
        p_sort_order
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_user_details(
    p_session_token text,
    p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN public.admin_get_user_details(p_user_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_user_profile_with_log(
    p_session_token text,
    p_user_id uuid,
    p_admin_user_id uuid,
    p_full_name text DEFAULT NULL::text,
    p_phone text DEFAULT NULL::text,
    p_location text DEFAULT NULL::text,
    p_verification_status text DEFAULT NULL::text,
    p_is_dealer boolean DEFAULT NULL::boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token, p_admin_user_id);

    RETURN public.admin_update_user_profile_with_log(
        p_user_id,
        admin_record.id,
        p_full_name,
        p_phone,
        p_location,
        p_verification_status,
        p_is_dealer
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_suspend_user_with_log(
    p_session_token text,
    p_user_id uuid,
    p_admin_user_id uuid,
    p_suspend boolean,
    p_duration_hours integer DEFAULT 24,
    p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token, p_admin_user_id);

    RETURN public.admin_suspend_user_with_log(
        p_user_id,
        admin_record.id,
        p_suspend,
        p_duration_hours,
        p_reason
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_activity_logs(
    p_session_token text,
    p_user_id uuid,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(
    id uuid,
    action text,
    details jsonb,
    admin_username text,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN QUERY
    SELECT *
    FROM public.get_user_activity_logs(
        p_user_id,
        p_limit,
        p_offset
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_bulk_suspend_users(
    p_session_token text,
    p_user_ids uuid[],
    p_admin_user_id uuid,
    p_suspend boolean,
    p_duration_hours integer DEFAULT 24,
    p_reason text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token, p_admin_user_id);

    RETURN public.admin_bulk_suspend_users(
        p_user_ids,
        admin_record.id,
        p_suspend,
        p_duration_hours,
        p_reason
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_bulk_update_verification(
    p_session_token text,
    p_user_ids uuid[],
    p_admin_user_id uuid,
    p_verification_status text,
    p_reason text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token, p_admin_user_id);

    RETURN public.admin_bulk_update_verification(
        p_user_ids,
        admin_record.id,
        p_verification_status,
        p_reason
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_export_users_data(
    p_session_token text,
    p_user_ids uuid[] DEFAULT NULL::uuid[],
    p_include_activity_logs boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN public.admin_export_users_data(
        p_user_ids,
        p_include_activity_logs
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_listings_for_admin(
    p_session_token text,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_search text DEFAULT NULL::text,
    p_status_filter text DEFAULT NULL::text,
    p_sort_by text DEFAULT 'created_at'::text,
    p_sort_order text DEFAULT 'desc'::text
)
RETURNS TABLE(
    id uuid,
    title text,
    make text,
    model text,
    year integer,
    price integer,
    status text,
    moderation_status text,
    user_name text,
    user_email text,
    views integer,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    total_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN QUERY
    SELECT *
    FROM public.get_listings_for_admin(
        p_limit,
        p_offset,
        p_search,
        p_status_filter,
        p_sort_by,
        p_sort_order
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_messages_for_admin(
    p_session_token text,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_search text DEFAULT NULL::text
)
RETURNS TABLE(
    id uuid,
    content text,
    sender_name text,
    sender_email text,
    receiver_name text,
    receiver_email text,
    listing_title text,
    listing_id uuid,
    is_read boolean,
    created_at timestamp with time zone,
    total_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token);

    RETURN QUERY
    SELECT *
    FROM public.get_messages_for_admin(
        p_limit,
        p_offset,
        p_search
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_delete_listing(
    p_session_token text,
    p_listing_id uuid,
    p_admin_user_id uuid,
    p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, extensions, pg_temp
AS $function$
DECLARE
    admin_record public.admin_users;
    result jsonb;
BEGIN
    SELECT * INTO admin_record
    FROM public.require_admin_session(p_session_token, p_admin_user_id);

    result := public.admin_delete_listing(
        p_listing_id,
        admin_record.id,
        p_reason
    );

    IF COALESCE((result ->> 'success')::boolean, false) THEN
        PERFORM public.log_admin_activity(
            admin_record.id,
            'delete_listing',
            'listing',
            p_listing_id::text,
            jsonb_build_object('reason', p_reason)
        );
    END IF;

    RETURN result;
END;
$function$;

ALTER FUNCTION public.cleanup_old_application_logs()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.delete_user_account(uuid)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.update_message_reports_updated_at()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_app_config(text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.generate_report_slug()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.log_admin_activity(uuid, text, text, text, jsonb, inet, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.update_conversation_timestamp()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.validate_admin_session(text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_moderate_listing(uuid, uuid, text, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.ensure_single_cover_image()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.is_whitelisted_report_author(uuid)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.logout_admin(text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_listing_images(uuid)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.update_listings_search_vector()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_admin_dashboard_stats()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.clean_expired_admin_sessions()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_update_user_profile(uuid, text, text, text, text, boolean)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_suspend_user(uuid, boolean, integer)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_listings_for_admin(integer, integer, text, text, text, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_report_by_slug(text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_users_for_admin(integer, integer, text, text, text, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.update_account_balance()
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.log_user_activity(uuid, text, uuid, jsonb, inet, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_get_user_details(uuid)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_user_activity_logs(uuid, integer, integer)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_update_user_profile_with_log(uuid, uuid, text, text, text, text, boolean)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_suspend_user_with_log(uuid, uuid, boolean, integer, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_bulk_suspend_users(uuid[], uuid, boolean, integer, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_bulk_update_verification(uuid[], uuid, text, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_delete_listing(uuid, uuid, text)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.admin_export_users_data(uuid[], boolean)
    SET search_path TO public, auth, extensions, pg_temp;

ALTER FUNCTION public.get_messages_for_admin(integer, integer, text)
    SET search_path TO public, auth, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public.cleanup_old_application_logs() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_moderate_listing(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_admin_dashboard_stats() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile(uuid, text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_suspend_user(uuid, boolean, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_listings_for_admin(integer, integer, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_users_for_admin(integer, integer, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_admin_activity(uuid, text, text, text, jsonb, inet, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_user_activity(uuid, text, uuid, jsonb, inet, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_user_details(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_user_activity_logs(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile_with_log(uuid, uuid, text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_suspend_user_with_log(uuid, uuid, boolean, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_suspend_users(uuid[], uuid, boolean, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_update_verification(uuid[], uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_listing(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_export_users_data(uuid[], boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_messages_for_admin(integer, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_user_account(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_admin_dashboard_stats(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_users_for_admin(text, integer, integer, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_get_user_details(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile_with_log(text, uuid, uuid, text, text, text, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_suspend_user_with_log(text, uuid, uuid, boolean, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_activity_logs(text, uuid, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_suspend_users(text, uuid[], uuid, boolean, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_update_verification(text, uuid[], uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_export_users_data(text, uuid[], boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_listings_for_admin(text, integer, integer, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_messages_for_admin(text, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_listing(text, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_stats(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_for_admin(text, integer, integer, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_details(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile_with_log(text, uuid, uuid, text, text, text, text, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_suspend_user_with_log(text, uuid, uuid, boolean, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_activity_logs(text, uuid, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bulk_suspend_users(text, uuid[], uuid, boolean, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bulk_update_verification(text, uuid[], uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_export_users_data(text, uuid[], boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_listings_for_admin(text, integer, integer, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_messages_for_admin(text, integer, integer, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_listing(text, uuid, uuid, text) TO anon, authenticated;
