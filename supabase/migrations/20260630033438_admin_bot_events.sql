CREATE SCHEMA IF NOT EXISTS app_private;

CREATE TABLE IF NOT EXISTS app_private.admin_bot_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type text NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    auth_mode text,
    auth_method text,
    provider text,
    source text,
    platform text,
    app_version text,
    app_build text,
    app_region text,
    app_language text,
    currency_code text,
    device_locale text,
    device_country_code text,
    timezone text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_bot_events_created_idx
    ON app_private.admin_bot_events (created_at DESC);

CREATE INDEX IF NOT EXISTS admin_bot_events_user_created_idx
    ON app_private.admin_bot_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_bot_events_type_created_idx
    ON app_private.admin_bot_events (event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_bot_events_timezone_created_idx
    ON app_private.admin_bot_events (timezone, created_at DESC)
    WHERE timezone IS NOT NULL;

CREATE TABLE IF NOT EXISTS app_private.admin_bot_alert_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_key text NOT NULL UNIQUE,
    alert_type text NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    delivered_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_bot_alert_deliveries_user_idx
    ON app_private.admin_bot_alert_deliveries (user_id, delivered_at DESC);

ALTER TABLE app_private.admin_bot_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.admin_bot_alert_deliveries ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE app_private.admin_bot_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE app_private.admin_bot_alert_deliveries FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE app_private.admin_bot_events TO service_role;
GRANT ALL ON TABLE app_private.admin_bot_alert_deliveries TO service_role;

CREATE OR REPLACE FUNCTION public.record_admin_bot_event(
    p_event_type text,
    p_user_id uuid DEFAULT NULL,
    p_auth_mode text DEFAULT NULL,
    p_auth_method text DEFAULT NULL,
    p_provider text DEFAULT NULL,
    p_source text DEFAULT NULL,
    p_platform text DEFAULT NULL,
    p_app_version text DEFAULT NULL,
    p_app_build text DEFAULT NULL,
    p_app_region text DEFAULT NULL,
    p_app_language text DEFAULT NULL,
    p_currency_code text DEFAULT NULL,
    p_device_locale text DEFAULT NULL,
    p_device_country_code text DEFAULT NULL,
    p_timezone text DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_id uuid;
BEGIN
    INSERT INTO app_private.admin_bot_events (
        event_type,
        user_id,
        auth_mode,
        auth_method,
        provider,
        source,
        platform,
        app_version,
        app_build,
        app_region,
        app_language,
        currency_code,
        device_locale,
        device_country_code,
        timezone,
        metadata
    )
    VALUES (
        NULLIF(btrim(p_event_type), ''),
        p_user_id,
        NULLIF(btrim(p_auth_mode), ''),
        NULLIF(btrim(p_auth_method), ''),
        NULLIF(btrim(p_provider), ''),
        NULLIF(btrim(p_source), ''),
        NULLIF(btrim(p_platform), ''),
        NULLIF(btrim(p_app_version), ''),
        NULLIF(btrim(p_app_build), ''),
        NULLIF(btrim(p_app_region), ''),
        NULLIF(btrim(p_app_language), ''),
        NULLIF(btrim(p_currency_code), ''),
        NULLIF(btrim(p_device_locale), ''),
        NULLIF(upper(btrim(p_device_country_code)), ''),
        NULLIF(btrim(p_timezone), ''),
        COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_admin_bot_alert_delivery(
    p_alert_key text,
    p_alert_type text,
    p_user_id uuid DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_inserted boolean := false;
BEGIN
    INSERT INTO app_private.admin_bot_alert_deliveries (
        alert_key,
        alert_type,
        user_id,
        metadata
    )
    VALUES (
        NULLIF(btrim(p_alert_key), ''),
        NULLIF(btrim(p_alert_type), ''),
        p_user_id,
        COALESCE(p_metadata, '{}'::jsonb)
    )
    ON CONFLICT (alert_key) DO NOTHING
    RETURNING true INTO v_inserted;

    RETURN COALESCE(v_inserted, false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_bot_stats(
    p_timezone text DEFAULT 'Asia/Tashkent'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_timezone text := COALESCE(NULLIF(btrim(p_timezone), ''), 'Asia/Tashkent');
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'generated_at', now(),
        'timezone', v_timezone,
        'users', (
            SELECT jsonb_build_object(
                'total', count(*)::int,
                'last_24h', count(*) FILTER (WHERE created_at >= now() - interval '24 hours')::int,
                'last_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')::int,
                'last_30d', count(*) FILTER (WHERE created_at >= now() - interval '30 days')::int
            )
            FROM auth.users
        ),
        'providers', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'provider', provider,
                    'total', total,
                    'last_7d', last_7d,
                    'last_30d', last_30d
                )
                ORDER BY total DESC, provider
            )
            FROM (
                SELECT
                    COALESCE(raw_app_meta_data ->> 'provider', 'unknown') AS provider,
                    count(*)::int AS total,
                    count(*) FILTER (WHERE created_at >= now() - interval '7 days')::int AS last_7d,
                    count(*) FILTER (WHERE created_at >= now() - interval '30 days')::int AS last_30d
                FROM auth.users
                GROUP BY 1
            ) provider_counts
        ), '[]'::jsonb),
        'sessions', (
            SELECT jsonb_build_object(
                'total', count(*)::int,
                'created_24h', count(*) FILTER (WHERE created_at >= now() - interval '24 hours')::int,
                'created_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')::int,
                'created_30d', count(*) FILTER (WHERE created_at >= now() - interval '30 days')::int,
                'refreshed_7d', count(*) FILTER (WHERE refreshed_at >= (now() - interval '7 days')::timestamp)::int
            )
            FROM auth.sessions
        ),
        'events', (
            SELECT jsonb_build_object(
                'auth_24h', count(*) FILTER (WHERE event_type = 'auth_completed' AND created_at >= now() - interval '24 hours')::int,
                'auth_7d', count(*) FILTER (WHERE event_type = 'auth_completed' AND created_at >= now() - interval '7 days')::int,
                'auth_30d', count(*) FILTER (WHERE event_type = 'auth_completed' AND created_at >= now() - interval '30 days')::int,
                'captured_timezones_30d', count(DISTINCT timezone) FILTER (WHERE timezone IS NOT NULL AND created_at >= now() - interval '30 days')::int
            )
            FROM app_private.admin_bot_events
        )
    )
    INTO v_result;

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_bot_recent_users(
    p_limit integer DEFAULT 10,
    p_timezone text DEFAULT 'Asia/Tashkent'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 25);
    v_timezone text := COALESCE(NULLIF(btrim(p_timezone), ''), 'Asia/Tashkent');
BEGIN
    RETURN COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', id,
                'email', email,
                'provider', COALESCE(raw_app_meta_data ->> 'provider', 'unknown'),
                'created_at', created_at,
                'created_local', to_char(created_at AT TIME ZONE v_timezone, 'YYYY-MM-DD HH24:MI'),
                'last_sign_in_at', last_sign_in_at,
                'last_sign_in_local', CASE
                    WHEN last_sign_in_at IS NULL THEN NULL
                    ELSE to_char(last_sign_in_at AT TIME ZONE v_timezone, 'YYYY-MM-DD HH24:MI')
                END
            )
            ORDER BY created_at DESC
        )
        FROM (
            SELECT id, email, raw_app_meta_data, created_at, last_sign_in_at
            FROM auth.users
            ORDER BY created_at DESC
            LIMIT v_limit
        ) recent_users
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_bot_peak_hours(
    p_days integer DEFAULT 30,
    p_timezone text DEFAULT 'Asia/Tashkent'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 180);
    v_timezone text := COALESCE(NULLIF(btrim(p_timezone), ''), 'Asia/Tashkent');
    v_since timestamptz := now() - make_interval(days => v_days);
BEGIN
    RETURN jsonb_build_object(
        'days', v_days,
        'timezone', v_timezone,
        'session_created_hours', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object('hour', local_hour, 'count', event_count)
                ORDER BY event_count DESC, local_hour
            )
            FROM (
                SELECT
                    extract(hour FROM created_at AT TIME ZONE v_timezone)::int AS local_hour,
                    count(*)::int AS event_count
                FROM auth.sessions
                WHERE created_at >= v_since
                GROUP BY 1
                ORDER BY 2 DESC, 1
                LIMIT 8
            ) ranked_hours
        ), '[]'::jsonb),
        'session_refresh_hours', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object('hour', local_hour, 'count', event_count)
                ORDER BY event_count DESC, local_hour
            )
            FROM (
                SELECT
                    extract(hour FROM ((refreshed_at AT TIME ZONE 'UTC') AT TIME ZONE v_timezone))::int AS local_hour,
                    count(*)::int AS event_count
                FROM auth.sessions
                WHERE refreshed_at >= v_since::timestamp
                GROUP BY 1
                ORDER BY 2 DESC, 1
                LIMIT 8
            ) ranked_hours
        ), '[]'::jsonb),
        'captured_user_timezone_hours', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object('hour', local_hour, 'count', event_count)
                ORDER BY event_count DESC, local_hour
            )
            FROM (
                SELECT
                    extract(hour FROM created_at AT TIME ZONE timezone)::int AS local_hour,
                    count(*)::int AS event_count
                FROM app_private.admin_bot_events
                WHERE event_type = 'auth_completed'
                    AND timezone IS NOT NULL
                    AND created_at >= v_since
                GROUP BY 1
                ORDER BY 2 DESC, 1
                LIMIT 8
            ) ranked_hours
        ), '[]'::jsonb)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.record_admin_bot_event(text, uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_admin_bot_alert_delivery(text, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_admin_bot_stats(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_admin_bot_recent_users(integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_admin_bot_peak_hours(integer, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_admin_bot_event(text, uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_admin_bot_alert_delivery(text, text, uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_bot_stats(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_bot_recent_users(integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_bot_peak_hours(integer, text) TO service_role;
