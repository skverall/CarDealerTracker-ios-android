CREATE TABLE IF NOT EXISTS public.organization_deal_desk_settings (
    organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
    is_enabled boolean NOT NULL DEFAULT false,
    business_region_code text NOT NULL DEFAULT 'generic' CHECK (business_region_code IN ('USA', 'Canada', 'generic')),
    default_template_code text NOT NULL DEFAULT 'generic' CHECK (default_template_code IN ('usa', 'canada', 'generic')),
    template_version integer NOT NULL DEFAULT 1 CHECK (template_version >= 1),
    tax_overrides jsonb NOT NULL DEFAULT '[]'::jsonb,
    fee_overrides jsonb NOT NULL DEFAULT '[]'::jsonb,
    updated_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.organization_deal_desk_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.organization_deal_desk_settings FROM anon, authenticated;
GRANT ALL ON TABLE public.organization_deal_desk_settings TO service_role;

CREATE OR REPLACE FUNCTION public.ensure_deal_desk_read_access(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_role text;
    v_permissions jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
    END IF;

    IF p_organization_id IS NULL OR NOT public.crm_can_access(p_organization_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
    END IF;

    v_role := lower(COALESCE(public.get_my_role(p_organization_id), ''));
    IF v_role IN ('owner', 'admin') THEN
        RETURN;
    END IF;

    v_permissions := COALESCE(public.get_my_permissions(p_organization_id), '{}'::jsonb);
    IF COALESCE((v_permissions ->> 'all')::boolean, false)
       OR COALESCE((v_permissions ->> 'create_sale')::boolean, false) THEN
        RETURN;
    END IF;

    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_deal_desk_write_access(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_role text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
    END IF;

    IF p_organization_id IS NULL OR NOT public.crm_can_access(p_organization_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
    END IF;

    v_role := lower(COALESCE(public.get_my_role(p_organization_id), ''));
    IF v_role NOT IN ('owner', 'admin') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'DEAL_DESK_ACCESS_DENIED';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_organization_deal_desk_settings(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_record public.organization_deal_desk_settings%ROWTYPE;
BEGIN
    PERFORM public.ensure_deal_desk_read_access(p_organization_id);

    INSERT INTO public.organization_deal_desk_settings (
        organization_id,
        is_enabled,
        business_region_code,
        default_template_code,
        template_version,
        tax_overrides,
        fee_overrides
    )
    VALUES (
        p_organization_id,
        false,
        'generic',
        'generic',
        1,
        '[]'::jsonb,
        '[]'::jsonb
    )
    ON CONFLICT (organization_id) DO NOTHING;

    SELECT *
    INTO v_record
    FROM public.organization_deal_desk_settings
    WHERE organization_id = p_organization_id;

    RETURN jsonb_build_object(
        'isEnabled', COALESCE(v_record.is_enabled, false),
        'businessRegionCode', COALESCE(v_record.business_region_code, 'generic'),
        'defaultTemplateCode', COALESCE(v_record.default_template_code, 'generic'),
        'templateVersion', COALESCE(v_record.template_version, 1),
        'taxOverrides', COALESCE(v_record.tax_overrides, '[]'::jsonb),
        'feeOverrides', COALESCE(v_record.fee_overrides, '[]'::jsonb)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_organization_deal_desk_settings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_organization_deal_desk_settings(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_organization_deal_desk_settings(
    p_organization_id uuid,
    p_is_enabled boolean DEFAULT false,
    p_business_region_code text DEFAULT 'generic',
    p_default_template_code text DEFAULT NULL,
    p_template_version integer DEFAULT 1,
    p_tax_overrides jsonb DEFAULT '[]'::jsonb,
    p_fee_overrides jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_business_region_code text;
    v_default_template_code text;
BEGIN
    PERFORM public.ensure_deal_desk_write_access(p_organization_id);

    v_business_region_code := CASE upper(COALESCE(p_business_region_code, 'generic'))
        WHEN 'USA' THEN 'USA'
        WHEN 'CANADA' THEN 'Canada'
        ELSE 'generic'
    END;

    v_default_template_code := CASE lower(COALESCE(p_default_template_code, ''))
        WHEN 'usa' THEN 'usa'
        WHEN 'canada' THEN 'canada'
        WHEN 'generic' THEN 'generic'
        ELSE CASE v_business_region_code
            WHEN 'USA' THEN 'usa'
            WHEN 'Canada' THEN 'canada'
            ELSE 'generic'
        END
    END;

    INSERT INTO public.organization_deal_desk_settings (
        organization_id,
        is_enabled,
        business_region_code,
        default_template_code,
        template_version,
        tax_overrides,
        fee_overrides,
        updated_by,
        updated_at
    )
    VALUES (
        p_organization_id,
        COALESCE(p_is_enabled, false),
        v_business_region_code,
        v_default_template_code,
        GREATEST(COALESCE(p_template_version, 1), 1),
        COALESCE(p_tax_overrides, '[]'::jsonb),
        COALESCE(p_fee_overrides, '[]'::jsonb),
        auth.uid(),
        now()
    )
    ON CONFLICT (organization_id) DO UPDATE
    SET is_enabled = EXCLUDED.is_enabled,
        business_region_code = EXCLUDED.business_region_code,
        default_template_code = EXCLUDED.default_template_code,
        template_version = EXCLUDED.template_version,
        tax_overrides = EXCLUDED.tax_overrides,
        fee_overrides = EXCLUDED.fee_overrides,
        updated_by = auth.uid(),
        updated_at = now();

    RETURN public.get_organization_deal_desk_settings(p_organization_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_organization_deal_desk_settings(uuid, boolean, text, text, integer, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_organization_deal_desk_settings(uuid, boolean, text, text, integer, jsonb, jsonb) TO authenticated;

ALTER TABLE crm.sales
    ADD COLUMN IF NOT EXISTS deal_desk_payload jsonb,
    ADD COLUMN IF NOT EXISTS deal_desk_template_code text,
    ADD COLUMN IF NOT EXISTS deal_desk_template_version integer,
    ADD COLUMN IF NOT EXISTS jurisdiction_type text,
    ADD COLUMN IF NOT EXISTS jurisdiction_code text,
    ADD COLUMN IF NOT EXISTS out_the_door_total numeric,
    ADD COLUMN IF NOT EXISTS cash_received_now numeric,
    ADD COLUMN IF NOT EXISTS amount_financed numeric,
    ADD COLUMN IF NOT EXISTS monthly_payment_estimate numeric;

CREATE OR REPLACE FUNCTION public.sync_sales(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    v_id uuid;
    v_dealer_id uuid;
    existing_updated_at timestamptz;
    incoming_updated_at timestamptz;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;
        PERFORM public.assert_crm_access(v_dealer_id);

        SELECT updated_at INTO existing_updated_at
        FROM crm.sales
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.sales (
                id,
                dealer_id,
                vehicle_id,
                amount,
                sale_price,
                profit,
                date,
                buyer_name,
                buyer_phone,
                payment_method,
                account_id,
                vat_refund_percent,
                vat_refund_amount,
                notes,
                deal_desk_payload,
                deal_desk_template_code,
                deal_desk_template_version,
                jurisdiction_type,
                jurisdiction_code,
                out_the_door_total,
                cash_received_now,
                amount_financed,
                monthly_payment_estimate,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'vehicle_id')::uuid,
                COALESCE((item->>'amount')::decimal, 0),
                COALESCE((item->>'sale_price')::decimal, (item->>'amount')::decimal),
                (item->>'profit')::decimal,
                COALESCE(public.parse_crm_calendar_date(item->>'date', NULL::date), CURRENT_DATE),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                (item->>'vat_refund_percent')::decimal,
                (item->>'vat_refund_amount')::decimal,
                item->>'notes',
                CASE WHEN item ? 'deal_desk_payload' THEN item->'deal_desk_payload' ELSE NULL END,
                CASE WHEN item ? 'deal_desk_template_code' THEN NULLIF(item->>'deal_desk_template_code', '') ELSE NULL END,
                CASE WHEN item ? 'deal_desk_template_version' THEN GREATEST(COALESCE((item->>'deal_desk_template_version')::integer, 1), 1) ELSE NULL END,
                CASE WHEN item ? 'jurisdiction_type' THEN NULLIF(item->>'jurisdiction_type', '') ELSE NULL END,
                CASE WHEN item ? 'jurisdiction_code' THEN NULLIF(item->>'jurisdiction_code', '') ELSE NULL END,
                CASE WHEN item ? 'out_the_door_total' THEN (item->>'out_the_door_total')::numeric ELSE NULL END,
                CASE WHEN item ? 'cash_received_now' THEN (item->>'cash_received_now')::numeric ELSE NULL END,
                CASE WHEN item ? 'amount_financed' THEN (item->>'amount_financed')::numeric ELSE NULL END,
                CASE WHEN item ? 'monthly_payment_estimate' THEN (item->>'monthly_payment_estimate')::numeric ELSE NULL END,
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vehicle_id = EXCLUDED.vehicle_id,
                amount = EXCLUDED.amount,
                sale_price = EXCLUDED.sale_price,
                profit = EXCLUDED.profit,
                date = EXCLUDED.date,
                buyer_name = EXCLUDED.buyer_name,
                buyer_phone = EXCLUDED.buyer_phone,
                payment_method = EXCLUDED.payment_method,
                account_id = EXCLUDED.account_id,
                vat_refund_percent = EXCLUDED.vat_refund_percent,
                vat_refund_amount = EXCLUDED.vat_refund_amount,
                notes = EXCLUDED.notes,
                deal_desk_payload = CASE
                    WHEN item ? 'deal_desk_payload' THEN item->'deal_desk_payload'
                    ELSE crm.sales.deal_desk_payload
                END,
                deal_desk_template_code = CASE
                    WHEN item ? 'deal_desk_template_code' THEN NULLIF(item->>'deal_desk_template_code', '')
                    ELSE crm.sales.deal_desk_template_code
                END,
                deal_desk_template_version = CASE
                    WHEN item ? 'deal_desk_template_version' THEN GREATEST(COALESCE((item->>'deal_desk_template_version')::integer, 1), 1)
                    ELSE crm.sales.deal_desk_template_version
                END,
                jurisdiction_type = CASE
                    WHEN item ? 'jurisdiction_type' THEN NULLIF(item->>'jurisdiction_type', '')
                    ELSE crm.sales.jurisdiction_type
                END,
                jurisdiction_code = CASE
                    WHEN item ? 'jurisdiction_code' THEN NULLIF(item->>'jurisdiction_code', '')
                    ELSE crm.sales.jurisdiction_code
                END,
                out_the_door_total = CASE
                    WHEN item ? 'out_the_door_total' THEN (item->>'out_the_door_total')::numeric
                    ELSE crm.sales.out_the_door_total
                END,
                cash_received_now = CASE
                    WHEN item ? 'cash_received_now' THEN (item->>'cash_received_now')::numeric
                    ELSE crm.sales.cash_received_now
                END,
                amount_financed = CASE
                    WHEN item ? 'amount_financed' THEN (item->>'amount_financed')::numeric
                    ELSE crm.sales.amount_financed
                END,
                monthly_payment_estimate = CASE
                    WHEN item ? 'monthly_payment_estimate' THEN (item->>'monthly_payment_estimate')::numeric
                    ELSE crm.sales.monthly_payment_estimate
                END,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.sales.dealer_id = EXCLUDED.dealer_id
              AND crm.sales.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;
