CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

CREATE TABLE IF NOT EXISTS public.monthly_report_preferences (
    organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    is_enabled boolean NOT NULL DEFAULT false,
    timezone_identifier text NOT NULL DEFAULT 'UTC',
    delivery_day integer NOT NULL DEFAULT 2 CHECK (delivery_day BETWEEN 1 AND 28),
    delivery_hour integer NOT NULL DEFAULT 9 CHECK (delivery_hour BETWEEN 0 AND 23),
    delivery_minute integer NOT NULL DEFAULT 0 CHECK (delivery_minute BETWEEN 0 AND 59),
    updated_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.organization_holding_cost_settings (
    organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
    is_enabled boolean NOT NULL DEFAULT false,
    annual_rate_percent numeric(8,4) NOT NULL DEFAULT 15,
    updated_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (annual_rate_percent >= 0 AND annual_rate_percent <= 100)
);

CREATE TABLE IF NOT EXISTS public.monthly_report_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    report_year integer NOT NULL CHECK (report_year BETWEEN 2000 AND 2100),
    report_month integer NOT NULL CHECK (report_month BETWEEN 1 AND 12),
    delivery_type text NOT NULL CHECK (delivery_type IN ('scheduled', 'test')),
    delivery_key text NOT NULL,
    status text NOT NULL CHECK (status IN ('processing', 'sent', 'failed')),
    attempt_count integer NOT NULL DEFAULT 1 CHECK (attempt_count > 0),
    requested_by uuid,
    recipient_count integer NOT NULL DEFAULT 0 CHECK (recipient_count >= 0),
    recipients jsonb NOT NULL DEFAULT '[]'::jsonb,
    subject text,
    report_title text,
    report_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    provider_message_id text,
    error_message text,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    delivered_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS monthly_report_deliveries_unique_key
    ON public.monthly_report_deliveries (organization_id, report_year, report_month, delivery_key);

CREATE INDEX IF NOT EXISTS monthly_report_deliveries_status_idx
    ON public.monthly_report_deliveries (status, attempted_at DESC);

ALTER TABLE public.monthly_report_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_holding_cost_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_report_deliveries ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.monthly_report_preferences FROM anon, authenticated;
REVOKE ALL ON TABLE public.organization_holding_cost_settings FROM anon, authenticated;
REVOKE ALL ON TABLE public.monthly_report_deliveries FROM anon, authenticated;

GRANT ALL ON TABLE public.monthly_report_preferences TO service_role;
GRANT ALL ON TABLE public.organization_holding_cost_settings TO service_role;
GRANT ALL ON TABLE public.monthly_report_deliveries TO service_role;

CREATE OR REPLACE FUNCTION public.ensure_monthly_report_manager_access(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_role text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'MONTHLY_REPORT_ACCESS_DENIED';
    END IF;

    IF p_organization_id IS NULL OR NOT public.crm_can_access(p_organization_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'MONTHLY_REPORT_ACCESS_DENIED';
    END IF;

    v_role := lower(COALESCE(public.get_my_role(p_organization_id), ''));

    IF v_role NOT IN ('owner', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'MONTHLY_REPORT_ACCESS_DENIED';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_monthly_report_manager_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_monthly_report_manager_access(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.build_monthly_report_preferences_payload(
    p_version integer,
    p_is_enabled boolean,
    p_timezone_identifier text,
    p_delivery_day integer,
    p_delivery_hour integer,
    p_delivery_minute integer
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT jsonb_build_object(
        'version', p_version,
        'isEnabled', p_is_enabled,
        'timezoneIdentifier', p_timezone_identifier,
        'deliveryDay', p_delivery_day,
        'deliveryHour', p_delivery_hour,
        'deliveryMinute', p_delivery_minute
    );
$function$;

REVOKE ALL ON FUNCTION public.build_monthly_report_preferences_payload(integer, boolean, text, integer, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.build_monthly_report_preferences_payload(integer, boolean, text, integer, integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.get_monthly_report_preferences(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_record public.monthly_report_preferences%ROWTYPE;
BEGIN
    PERFORM public.ensure_monthly_report_manager_access(p_organization_id);

    SELECT *
    INTO v_record
    FROM public.monthly_report_preferences
    WHERE organization_id = p_organization_id;

    RETURN public.build_monthly_report_preferences_payload(
        COALESCE(v_record.version, 1),
        COALESCE(v_record.is_enabled, false),
        COALESCE(NULLIF(btrim(v_record.timezone_identifier), ''), 'UTC'),
        COALESCE(v_record.delivery_day, 2),
        COALESCE(v_record.delivery_hour, 9),
        COALESCE(v_record.delivery_minute, 0)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_monthly_report_preferences(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_monthly_report_preferences(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_monthly_report_preferences(
    p_organization_id uuid,
    p_version integer DEFAULT 1,
    p_is_enabled boolean DEFAULT false,
    p_timezone_identifier text DEFAULT 'UTC',
    p_delivery_day integer DEFAULT 2,
    p_delivery_hour integer DEFAULT 9,
    p_delivery_minute integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_timezone_identifier text := COALESCE(NULLIF(btrim(p_timezone_identifier), ''), 'UTC');
BEGIN
    PERFORM public.ensure_monthly_report_manager_access(p_organization_id);

    INSERT INTO public.monthly_report_preferences (
        organization_id,
        version,
        is_enabled,
        timezone_identifier,
        delivery_day,
        delivery_hour,
        delivery_minute,
        updated_by,
        updated_at
    )
    VALUES (
        p_organization_id,
        GREATEST(COALESCE(p_version, 1), 1),
        COALESCE(p_is_enabled, false),
        v_timezone_identifier,
        LEAST(GREATEST(COALESCE(p_delivery_day, 2), 1), 28),
        LEAST(GREATEST(COALESCE(p_delivery_hour, 9), 0), 23),
        LEAST(GREATEST(COALESCE(p_delivery_minute, 0), 0), 59),
        auth.uid(),
        now()
    )
    ON CONFLICT (organization_id) DO UPDATE
    SET version = EXCLUDED.version,
        is_enabled = EXCLUDED.is_enabled,
        timezone_identifier = EXCLUDED.timezone_identifier,
        delivery_day = EXCLUDED.delivery_day,
        delivery_hour = EXCLUDED.delivery_hour,
        delivery_minute = EXCLUDED.delivery_minute,
        updated_by = auth.uid(),
        updated_at = now();

    RETURN public.get_monthly_report_preferences(p_organization_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_monthly_report_preferences(uuid, integer, boolean, text, integer, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_monthly_report_preferences(uuid, integer, boolean, text, integer, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_organization_holding_cost_settings(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_record public.organization_holding_cost_settings%ROWTYPE;
BEGIN
    PERFORM public.ensure_monthly_report_manager_access(p_organization_id);

    SELECT *
    INTO v_record
    FROM public.organization_holding_cost_settings
    WHERE organization_id = p_organization_id;

    RETURN jsonb_build_object(
        'isEnabled', COALESCE(v_record.is_enabled, false),
        'annualRatePercent', COALESCE(v_record.annual_rate_percent, 15)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_organization_holding_cost_settings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_holding_cost_settings(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_organization_holding_cost_settings(
    p_organization_id uuid,
    p_is_enabled boolean DEFAULT false,
    p_annual_rate_percent numeric DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
BEGIN
    PERFORM public.ensure_monthly_report_manager_access(p_organization_id);

    INSERT INTO public.organization_holding_cost_settings (
        organization_id,
        is_enabled,
        annual_rate_percent,
        updated_by,
        updated_at
    )
    VALUES (
        p_organization_id,
        COALESCE(p_is_enabled, false),
        LEAST(GREATEST(COALESCE(p_annual_rate_percent, 15), 0), 100),
        auth.uid(),
        now()
    )
    ON CONFLICT (organization_id) DO UPDATE
    SET is_enabled = EXCLUDED.is_enabled,
        annual_rate_percent = EXCLUDED.annual_rate_percent,
        updated_by = auth.uid(),
        updated_at = now();

    RETURN public.get_organization_holding_cost_settings(p_organization_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_organization_holding_cost_settings(uuid, boolean, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_organization_holding_cost_settings(uuid, boolean, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_due_monthly_report_dispatches(
    p_now timestamptz DEFAULT now(),
    p_window_minutes integer DEFAULT 5
)
RETURNS TABLE(
    organization_id uuid,
    organization_name text,
    timezone_identifier text,
    report_year integer,
    report_month integer,
    scheduled_for timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
    WITH preference_rows AS (
        SELECT
            p.organization_id,
            o.name AS organization_name,
            p.timezone_identifier,
            p.delivery_day,
            p.delivery_hour,
            p.delivery_minute,
            timezone(p.timezone_identifier, p_now) AS local_now
        FROM public.monthly_report_preferences p
        JOIN public.organizations o
          ON o.id = p.organization_id
        WHERE p.is_enabled = true
    ),
    schedule_rows AS (
        SELECT
            pr.organization_id,
            pr.organization_name,
            pr.timezone_identifier,
            make_timestamptz(
                EXTRACT(YEAR FROM pr.local_now)::integer,
                EXTRACT(MONTH FROM pr.local_now)::integer,
                LEAST(
                    pr.delivery_day,
                    EXTRACT(DAY FROM (date_trunc('month', pr.local_now) + INTERVAL '1 month - 1 day'))::integer
                ),
                pr.delivery_hour,
                pr.delivery_minute,
                0,
                pr.timezone_identifier
            ) AS scheduled_for
        FROM preference_rows pr
    )
    SELECT
        sr.organization_id,
        sr.organization_name,
        sr.timezone_identifier,
        EXTRACT(YEAR FROM ((sr.scheduled_for AT TIME ZONE sr.timezone_identifier) - INTERVAL '1 month'))::integer AS report_year,
        EXTRACT(MONTH FROM ((sr.scheduled_for AT TIME ZONE sr.timezone_identifier) - INTERVAL '1 month'))::integer AS report_month,
        sr.scheduled_for
    FROM schedule_rows sr
    WHERE p_now >= sr.scheduled_for
      AND p_now < sr.scheduled_for + make_interval(mins => GREATEST(COALESCE(p_window_minutes, 5), 1));
$function$;

REVOKE ALL ON FUNCTION public.get_due_monthly_report_dispatches(timestamptz, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_due_monthly_report_dispatches(timestamptz, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_monthly_report_delivery(
    p_organization_id uuid,
    p_report_year integer,
    p_report_month integer,
    p_delivery_type text,
    p_delivery_key text,
    p_requested_by uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_delivery_id uuid;
BEGIN
    IF COALESCE(p_delivery_key, '') = '' THEN
        RAISE EXCEPTION 'MONTHLY_REPORT_DELIVERY_KEY_REQUIRED';
    END IF;

    IF lower(COALESCE(p_delivery_type, '')) NOT IN ('scheduled', 'test') THEN
        RAISE EXCEPTION 'MONTHLY_REPORT_DELIVERY_TYPE_INVALID';
    END IF;

    INSERT INTO public.monthly_report_deliveries (
        organization_id,
        report_year,
        report_month,
        delivery_type,
        delivery_key,
        status,
        requested_by,
        attempted_at,
        updated_at
    )
    VALUES (
        p_organization_id,
        p_report_year,
        p_report_month,
        lower(p_delivery_type),
        p_delivery_key,
        'processing',
        p_requested_by,
        now(),
        now()
    )
    ON CONFLICT (organization_id, report_year, report_month, delivery_key) DO UPDATE
    SET status = 'processing',
        requested_by = COALESCE(EXCLUDED.requested_by, public.monthly_report_deliveries.requested_by),
        attempt_count = public.monthly_report_deliveries.attempt_count + 1,
        attempted_at = now(),
        updated_at = now(),
        error_message = NULL
    WHERE public.monthly_report_deliveries.status = 'failed'
       OR (
            public.monthly_report_deliveries.status = 'processing'
        AND public.monthly_report_deliveries.attempted_at < now() - INTERVAL '10 minutes'
       )
    RETURNING id
    INTO v_delivery_id;

    RETURN v_delivery_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_monthly_report_delivery(uuid, integer, integer, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_monthly_report_delivery(uuid, integer, integer, text, text, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_monthly_report_delivery_sent(
    p_delivery_id uuid,
    p_recipient_count integer,
    p_recipients jsonb,
    p_subject text,
    p_report_title text,
    p_report_summary jsonb,
    p_provider_message_id text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
BEGIN
    UPDATE public.monthly_report_deliveries
    SET status = 'sent',
        recipient_count = GREATEST(COALESCE(p_recipient_count, 0), 0),
        recipients = COALESCE(p_recipients, '[]'::jsonb),
        subject = p_subject,
        report_title = p_report_title,
        report_summary = COALESCE(p_report_summary, '{}'::jsonb),
        provider_message_id = p_provider_message_id,
        delivered_at = now(),
        updated_at = now(),
        error_message = NULL
    WHERE id = p_delivery_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_monthly_report_delivery_sent(uuid, integer, jsonb, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_monthly_report_delivery_sent(uuid, integer, jsonb, text, text, jsonb, text) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_monthly_report_delivery_failed(
    p_delivery_id uuid,
    p_error_message text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
BEGIN
    UPDATE public.monthly_report_deliveries
    SET status = 'failed',
        error_message = LEFT(COALESCE(p_error_message, 'Monthly report delivery failed'), 1000),
        updated_at = now()
    WHERE id = p_delivery_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_monthly_report_delivery_failed(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_monthly_report_delivery_failed(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.is_valid_monthly_report_cron_secret(p_secret text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO public, vault, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM vault.decrypted_secrets
        WHERE name = 'monthly_report_cron_secret'
          AND decrypted_secret = COALESCE(p_secret, '')
    );
$function$;

REVOKE ALL ON FUNCTION public.is_valid_monthly_report_cron_secret(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_monthly_report_cron_secret(text) TO service_role;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM vault.decrypted_secrets
        WHERE name = 'monthly_report_cron_secret'
    ) THEN
        PERFORM vault.create_secret(extensions.gen_random_uuid()::text, 'monthly_report_cron_secret', 'Cron secret for monthly report dispatch');
    END IF;
END;
$$;

DO $$
DECLARE
    v_job_id bigint;
BEGIN
    SELECT jobid
    INTO v_job_id
    FROM cron.job
    WHERE jobname = 'monthly-report-dispatch';

    IF v_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(v_job_id);
    END IF;

    PERFORM cron.schedule(
        'monthly-report-dispatch',
        '*/5 * * * *',
        $job$
        SELECT net.http_post(
            url := 'https://haordpdxyyreliyzmire.supabase.co/functions/v1/monthly_report_dispatch',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-monthly-report-secret', (
                    SELECT decrypted_secret
                    FROM vault.decrypted_secrets
                    WHERE name = 'monthly_report_cron_secret'
                )
            ),
            body := jsonb_build_object(
                'mode', 'scheduled',
                'invokedAt', now()
            ),
            timeout_milliseconds := 10000
        );
        $job$
    );
END;
$$;
