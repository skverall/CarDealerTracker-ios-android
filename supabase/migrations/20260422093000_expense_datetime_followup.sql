CREATE OR REPLACE FUNCTION public.parse_crm_timestamp(
    p_value text,
    p_fallback timestamptz DEFAULT now()
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_value text;
BEGIN
    v_value := nullif(btrim(p_value), '');
    IF v_value IS NULL THEN
        RETURN p_fallback;
    END IF;

    BEGIN
        RETURN v_value::timestamptz;
    EXCEPTION WHEN others THEN
        BEGIN
            RETURN ((v_value::date)::timestamp AT TIME ZONE 'UTC');
        EXCEPTION WHEN others THEN
            RETURN p_fallback;
        END;
    END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.parse_crm_calendar_date(
    p_value text,
    p_fallback date DEFAULT NULL
)
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_value text;
BEGIN
    v_value := nullif(btrim(p_value), '');
    IF v_value IS NULL THEN
        RETURN p_fallback;
    END IF;

    IF v_value ~ '^\d{4}-\d{2}-\d{2}$' THEN
        BEGIN
            RETURN v_value::date;
        EXCEPTION WHEN others THEN
            RETURN p_fallback;
        END;
    END IF;

    BEGIN
        RETURN ((v_value::timestamptz AT TIME ZONE 'UTC')::date);
    EXCEPTION WHEN others THEN
        BEGIN
            RETURN v_value::date;
        EXCEPTION WHEN others THEN
            RETURN p_fallback;
        END;
    END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.parse_crm_expense_occurred_at(
    p_value text,
    p_fallback timestamptz DEFAULT now()
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_value text;
BEGIN
    v_value := nullif(btrim(p_value), '');
    IF v_value IS NULL THEN
        RETURN p_fallback;
    END IF;

    BEGIN
        RETURN v_value::timestamptz;
    EXCEPTION WHEN others THEN
        BEGIN
            RETURN (((v_value::date)::timestamp + TIME '12:00:00') AT TIME ZONE 'UTC');
        EXCEPTION WHEN others THEN
            RETURN p_fallback;
        END;
    END;
END;
$function$;

REVOKE ALL ON FUNCTION public.parse_crm_timestamp(text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parse_crm_timestamp(text, timestamptz) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.parse_crm_calendar_date(text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parse_crm_calendar_date(text, date) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.parse_crm_expense_occurred_at(text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parse_crm_expense_occurred_at(text, timestamptz) TO authenticated, service_role;

UPDATE crm.expenses
SET date = ((((date AT TIME ZONE 'UTC')::date)::timestamp + TIME '12:00:00') AT TIME ZONE 'UTC')
WHERE created_at < TIMESTAMPTZ '2026-04-09T09:30:00Z'
  AND ((date AT TIME ZONE 'UTC')::time = (created_at AT TIME ZONE 'UTC')::time);

COMMENT ON COLUMN crm.expenses.date IS 'Expense occurrence timestamp in UTC. Legacy date-only rows are re-anchored to noon UTC so old clients keep the intended calendar day more reliably.';

CREATE OR REPLACE FUNCTION public.sync_account_transactions(payload jsonb)
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
        FROM crm.account_transactions
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.account_transactions (
                id,
                dealer_id,
                account_id,
                transaction_type,
                amount,
                date,
                note,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'account_id')::uuid,
                item->>'transaction_type',
                COALESCE((item->>'amount')::numeric, 0),
                public.parse_crm_timestamp(
                    item->>'date',
                    public.parse_crm_timestamp(item->>'created_at', now())
                ),
                item->>'note',
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                account_id = EXCLUDED.account_id,
                transaction_type = EXCLUDED.transaction_type,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                note = EXCLUDED.note,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm.account_transactions.dealer_id = EXCLUDED.dealer_id
              AND crm.account_transactions.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_vehicles(payload jsonb)
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
    normalized_vin text;
    existing_vin_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;
        normalized_vin := upper(trim(COALESCE(item->>'vin', '')));
        PERFORM public.assert_crm_access(v_dealer_id);

        IF length(normalized_vin) = 17 THEN
            SELECT id INTO existing_vin_id
            FROM crm.vehicles
            WHERE dealer_id = v_dealer_id
              AND deleted_at IS NULL
              AND upper(trim(vin)) = normalized_vin
              AND id <> v_id
            LIMIT 1;

            IF existing_vin_id IS NOT NULL THEN
                RAISE EXCEPTION USING
                    ERRCODE = '23505',
                    MESSAGE = 'VIN_CONFLICT',
                    DETAIL = existing_vin_id::text;
            END IF;
        END IF;

        SELECT updated_at INTO existing_updated_at
        FROM crm.vehicles
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.vehicles (
                id,
                dealer_id,
                vin,
                make,
                model,
                year,
                purchase_price,
                purchase_account_id,
                purchase_date,
                status,
                notes,
                created_at,
                sale_price,
                sale_date,
                photo_url,
                asking_price,
                report_url,
                mileage,
                updated_at,
                deleted_at
            )
            VALUES (
                v_id,
                v_dealer_id,
                normalized_vin,
                item->>'make',
                item->>'model',
                (item->>'year')::int,
                (item->>'purchase_price')::decimal,
                (item->>'purchase_account_id')::uuid,
                COALESCE(public.parse_crm_calendar_date(item->>'purchase_date', NULL::date), CURRENT_DATE),
                item->>'status',
                item->>'notes',
                public.parse_crm_timestamp(item->>'created_at', now()),
                (item->>'sale_price')::decimal,
                public.parse_crm_calendar_date(item->>'sale_date', NULL::date),
                item->>'photo_url',
                (item->>'asking_price')::decimal,
                item->>'report_url',
                COALESCE((item->>'mileage')::int, 0),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vin = EXCLUDED.vin,
                make = EXCLUDED.make,
                model = EXCLUDED.model,
                year = EXCLUDED.year,
                purchase_price = EXCLUDED.purchase_price,
                purchase_account_id = EXCLUDED.purchase_account_id,
                purchase_date = EXCLUDED.purchase_date,
                status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                sale_price = EXCLUDED.sale_price,
                sale_date = EXCLUDED.sale_date,
                photo_url = EXCLUDED.photo_url,
                asking_price = EXCLUDED.asking_price,
                report_url = EXCLUDED.report_url,
                mileage = EXCLUDED.mileage,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.vehicles.dealer_id = EXCLUDED.dealer_id
              AND crm.vehicles.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

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
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.sales.dealer_id = EXCLUDED.dealer_id
              AND crm.sales.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_debts(payload jsonb)
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
        FROM crm.debts
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.debts (
                id,
                dealer_id,
                counterparty_name,
                counterparty_phone,
                direction,
                amount,
                notes,
                due_date,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                item->>'counterparty_name',
                item->>'counterparty_phone',
                item->>'direction',
                COALESCE((item->>'amount')::numeric, 0),
                item->>'notes',
                public.parse_crm_calendar_date(item->>'due_date', NULL::date),
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                counterparty_name = EXCLUDED.counterparty_name,
                counterparty_phone = EXCLUDED.counterparty_phone,
                direction = EXCLUDED.direction,
                amount = EXCLUDED.amount,
                notes = EXCLUDED.notes,
                due_date = EXCLUDED.due_date,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm.debts.dealer_id = EXCLUDED.dealer_id
              AND crm.debts.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_part_batches(payload jsonb)
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
        FROM crm_part_batches
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_batches (
                id,
                dealer_id,
                part_id,
                batch_label,
                quantity_received,
                quantity_remaining,
                unit_cost,
                purchase_date,
                purchase_account_id,
                notes,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'part_id')::uuid,
                item->>'batch_label',
                COALESCE((item->>'quantity_received')::numeric, 0),
                COALESCE((item->>'quantity_remaining')::numeric, 0),
                COALESCE((item->>'unit_cost')::numeric, 0),
                COALESCE(public.parse_crm_calendar_date(item->>'purchase_date', NULL::date), CURRENT_DATE),
                (item->>'purchase_account_id')::uuid,
                item->>'notes',
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                part_id = EXCLUDED.part_id,
                batch_label = EXCLUDED.batch_label,
                quantity_received = EXCLUDED.quantity_received,
                quantity_remaining = EXCLUDED.quantity_remaining,
                unit_cost = EXCLUDED.unit_cost,
                purchase_date = EXCLUDED.purchase_date,
                purchase_account_id = EXCLUDED.purchase_account_id,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm_part_batches.dealer_id = EXCLUDED.dealer_id
              AND crm_part_batches.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_part_sales(payload jsonb)
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
        FROM crm_part_sales
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_sales (
                id,
                dealer_id,
                amount,
                date,
                buyer_name,
                buyer_phone,
                payment_method,
                account_id,
                notes,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                COALESCE((item->>'amount')::numeric, 0),
                COALESCE(public.parse_crm_calendar_date(item->>'date', NULL::date), CURRENT_DATE),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                item->>'notes',
                public.parse_crm_timestamp(item->>'created_at', now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                buyer_name = EXCLUDED.buyer_name,
                buyer_phone = EXCLUDED.buyer_phone,
                payment_method = EXCLUDED.payment_method,
                account_id = EXCLUDED.account_id,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm_part_sales.dealer_id = EXCLUDED.dealer_id
              AND crm_part_sales.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;
