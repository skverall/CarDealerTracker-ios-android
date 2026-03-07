CREATE OR REPLACE FUNCTION public.assert_crm_access(p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $function$
BEGIN
    IF p_dealer_id IS NULL OR NOT public.crm_can_access(p_dealer_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CRM_ACCESS_DENIED';
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.assert_crm_access(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_users(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record crm.dealer_users%ROWTYPE;
    results jsonb := '[]'::jsonb;
    existing_id uuid;
    v_dealer_id uuid;
    is_deleted boolean;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);
        is_deleted := (item->>'deleted_at') IS NOT NULL;
        existing_id := NULL;

        IF NOT is_deleted THEN
            SELECT id INTO existing_id
            FROM crm.dealer_users
            WHERE dealer_id = v_dealer_id
              AND lower(name) = lower(item->>'name')
              AND deleted_at IS NULL
              AND id <> (item->>'id')::uuid;
        END IF;

        IF existing_id IS NOT NULL THEN
            UPDATE crm.dealer_users
            SET name = item->>'name',
                first_name = item->>'first_name',
                last_name = item->>'last_name',
                email = item->>'email',
                phone = item->>'phone',
                avatar_url = item->>'avatar_url',
                updated_at = (item->>'updated_at')::timestamptz,
                deleted_at = (item->>'deleted_at')::timestamptz
            WHERE id = existing_id
              AND dealer_id = v_dealer_id
              AND updated_at < (item->>'updated_at')::timestamptz
            RETURNING * INTO result_record;

            IF NOT FOUND THEN
                SELECT * INTO result_record
                FROM crm.dealer_users
                WHERE id = existing_id
                  AND dealer_id = v_dealer_id;
            END IF;
        ELSE
            INSERT INTO crm.dealer_users (
                id,
                dealer_id,
                name,
                first_name,
                last_name,
                email,
                phone,
                avatar_url,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (
                (item->>'id')::uuid,
                v_dealer_id,
                item->>'name',
                item->>'first_name',
                item->>'last_name',
                item->>'email',
                item->>'phone',
                item->>'avatar_url',
                (item->>'created_at')::timestamptz,
                (item->>'updated_at')::timestamptz,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE
            SET name = EXCLUDED.name,
                first_name = EXCLUDED.first_name,
                last_name = EXCLUDED.last_name,
                email = EXCLUDED.email,
                phone = EXCLUDED.phone,
                avatar_url = EXCLUDED.avatar_url,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.dealer_users.dealer_id = EXCLUDED.dealer_id
              AND crm.dealer_users.updated_at < EXCLUDED.updated_at
            RETURNING * INTO result_record;

            IF NOT FOUND THEN
                SELECT * INTO result_record
                FROM crm.dealer_users
                WHERE id = (item->>'id')::uuid
                  AND dealer_id = v_dealer_id;
            END IF;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_accounts(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record crm.financial_accounts%ROWTYPE;
    results jsonb := '[]'::jsonb;
    existing_id uuid;
    v_dealer_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);

        SELECT id INTO existing_id
        FROM crm.financial_accounts
        WHERE dealer_id = v_dealer_id
          AND lower(account_type) = lower(item->>'account_type')
          AND deleted_at IS NULL
          AND id <> (item->>'id')::uuid;

        IF existing_id IS NOT NULL THEN
            UPDATE crm.financial_accounts
            SET balance = (item->>'balance')::decimal,
                updated_at = (item->>'updated_at')::timestamptz,
                deleted_at = (item->>'deleted_at')::timestamptz
            WHERE id = existing_id
              AND dealer_id = v_dealer_id
              AND updated_at < (item->>'updated_at')::timestamptz
            RETURNING * INTO result_record;

            IF NOT FOUND THEN
                SELECT * INTO result_record
                FROM crm.financial_accounts
                WHERE id = existing_id
                  AND dealer_id = v_dealer_id;
            END IF;
        ELSE
            INSERT INTO crm.financial_accounts (
                id,
                dealer_id,
                account_type,
                balance,
                updated_at,
                deleted_at
            )
            VALUES (
                (item->>'id')::uuid,
                v_dealer_id,
                item->>'account_type',
                (item->>'balance')::decimal,
                (item->>'updated_at')::timestamptz,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE
            SET account_type = EXCLUDED.account_type,
                balance = EXCLUDED.balance,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.financial_accounts.dealer_id = EXCLUDED.dealer_id
              AND crm.financial_accounts.updated_at < EXCLUDED.updated_at
            RETURNING * INTO result_record;

            IF NOT FOUND THEN
                SELECT * INTO result_record
                FROM crm.financial_accounts
                WHERE id = (item->>'id')::uuid
                  AND dealer_id = v_dealer_id;
            END IF;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

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
                COALESCE((item->>'date')::date, CURRENT_DATE),
                item->>'note',
                COALESCE((item->>'created_at')::timestamptz, now()),
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
                COALESCE((item->>'purchase_date')::date, now()::date),
                item->>'status',
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
                (item->>'sale_price')::decimal,
                (item->>'sale_date')::date,
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

CREATE OR REPLACE FUNCTION public.sync_templates(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record public.crm_expense_templates%ROWTYPE;
    results jsonb := '[]'::jsonb;
    v_dealer_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);

        INSERT INTO public.crm_expense_templates (
            id,
            dealer_id,
            name,
            category,
            default_description,
            default_amount,
            updated_at,
            deleted_at
        )
        VALUES (
            (item->>'id')::uuid,
            v_dealer_id,
            item->>'name',
            item->>'category',
            item->>'default_description',
            (item->>'default_amount')::decimal,
            (item->>'updated_at')::timestamptz,
            (item->>'deleted_at')::timestamptz
        )
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            category = EXCLUDED.category,
            default_description = EXCLUDED.default_description,
            default_amount = EXCLUDED.default_amount,
            updated_at = EXCLUDED.updated_at,
            deleted_at = EXCLUDED.deleted_at
        WHERE public.crm_expense_templates.dealer_id = EXCLUDED.dealer_id
          AND public.crm_expense_templates.updated_at < EXCLUDED.updated_at
        RETURNING * INTO result_record;

        IF NOT FOUND THEN
            SELECT * INTO result_record
            FROM public.crm_expense_templates
            WHERE id = (item->>'id')::uuid
              AND dealer_id = v_dealer_id;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_expenses(payload jsonb)
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
        FROM crm.expenses
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.expenses (
                id,
                dealer_id,
                amount,
                date,
                description,
                expense_description,
                category,
                vehicle_id,
                user_id,
                account_id,
                expense_type,
                receipt_path,
                created_at,
                updated_at,
                deleted_at
            )
            VALUES (
                v_id,
                v_dealer_id,
                COALESCE((item->>'amount')::decimal, 0),
                COALESCE((item->>'date')::date, CURRENT_DATE),
                item->>'description',
                item->>'description',
                item->>'category',
                (item->>'vehicle_id')::uuid,
                (item->>'user_id')::uuid,
                (item->>'account_id')::uuid,
                item->>'expense_type',
                item->>'receipt_path',
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                description = EXCLUDED.description,
                expense_description = EXCLUDED.expense_description,
                category = EXCLUDED.category,
                vehicle_id = EXCLUDED.vehicle_id,
                user_id = EXCLUDED.user_id,
                account_id = EXCLUDED.account_id,
                expense_type = EXCLUDED.expense_type,
                receipt_path = EXCLUDED.receipt_path,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at
            WHERE crm.expenses.dealer_id = EXCLUDED.dealer_id
              AND crm.expenses.updated_at < EXCLUDED.updated_at;
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
                COALESCE((item->>'date')::timestamptz, now()),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                (item->>'vat_refund_percent')::decimal,
                (item->>'vat_refund_amount')::decimal,
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
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
                (item->>'due_date')::date,
                COALESCE((item->>'created_at')::timestamptz, now()),
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

CREATE OR REPLACE FUNCTION public.sync_debt_payments(payload jsonb)
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
        FROM crm.debt_payments
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.debt_payments (
                id,
                dealer_id,
                debt_id,
                amount,
                date,
                note,
                payment_method,
                account_id,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'debt_id')::uuid,
                COALESCE((item->>'amount')::numeric, 0),
                COALESCE((item->>'date')::timestamptz, now()),
                item->>'note',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                debt_id = EXCLUDED.debt_id,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                note = EXCLUDED.note,
                payment_method = EXCLUDED.payment_method,
                account_id = EXCLUDED.account_id,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm.debt_payments.dealer_id = EXCLUDED.dealer_id
              AND crm.debt_payments.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_clients(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record public.crm_dealer_clients%ROWTYPE;
    results jsonb := '[]'::jsonb;
    v_dealer_id uuid;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);

        INSERT INTO public.crm_dealer_clients (
            id,
            dealer_id,
            name,
            phone,
            email,
            notes,
            request_details,
            preferred_date,
            created_at,
            updated_at,
            deleted_at,
            status,
            vehicle_id
        )
        VALUES (
            (item->>'id')::uuid,
            v_dealer_id,
            item->>'name',
            item->>'phone',
            item->>'email',
            item->>'notes',
            item->>'request_details',
            (item->>'preferred_date')::timestamptz,
            (item->>'created_at')::timestamptz,
            (item->>'updated_at')::timestamptz,
            (item->>'deleted_at')::timestamptz,
            item->>'status',
            (item->>'vehicle_id')::uuid
        )
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            notes = EXCLUDED.notes,
            request_details = EXCLUDED.request_details,
            preferred_date = EXCLUDED.preferred_date,
            updated_at = EXCLUDED.updated_at,
            deleted_at = EXCLUDED.deleted_at,
            status = EXCLUDED.status,
            vehicle_id = EXCLUDED.vehicle_id
        WHERE public.crm_dealer_clients.dealer_id = EXCLUDED.dealer_id
          AND public.crm_dealer_clients.updated_at < EXCLUDED.updated_at
        RETURNING * INTO result_record;

        IF NOT FOUND THEN
            SELECT * INTO result_record
            FROM public.crm_dealer_clients
            WHERE id = (item->>'id')::uuid
              AND dealer_id = v_dealer_id;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_parts(payload jsonb)
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
        FROM crm_parts
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_parts (
                id,
                dealer_id,
                name,
                code,
                category,
                notes,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                item->>'name',
                item->>'code',
                item->>'category',
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                name = EXCLUDED.name,
                code = EXCLUDED.code,
                category = EXCLUDED.category,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm_parts.dealer_id = EXCLUDED.dealer_id
              AND crm_parts.updated_at < EXCLUDED.updated_at;
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
                COALESCE((item->>'purchase_date')::date, CURRENT_DATE),
                (item->>'purchase_account_id')::uuid,
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
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
                COALESCE((item->>'date')::date, CURRENT_DATE),
                item->>'buyer_name',
                item->>'buyer_phone',
                item->>'payment_method',
                (item->>'account_id')::uuid,
                item->>'notes',
                COALESCE((item->>'created_at')::timestamptz, now()),
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

CREATE OR REPLACE FUNCTION public.sync_part_sale_line_items(payload jsonb)
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
        FROM crm_part_sale_line_items
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_sale_line_items (
                id,
                dealer_id,
                sale_id,
                part_id,
                batch_id,
                quantity,
                unit_price,
                unit_cost,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                (item->>'sale_id')::uuid,
                (item->>'part_id')::uuid,
                (item->>'batch_id')::uuid,
                COALESCE((item->>'quantity')::numeric, 0),
                COALESCE((item->>'unit_price')::numeric, 0),
                COALESCE((item->>'unit_cost')::numeric, 0),
                COALESCE((item->>'created_at')::timestamptz, now()),
                incoming_updated_at,
                (item->>'deleted_at')::timestamptz,
                (item->>'last_modified_by')::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                sale_id = EXCLUDED.sale_id,
                part_id = EXCLUDED.part_id,
                batch_id = EXCLUDED.batch_id,
                quantity = EXCLUDED.quantity,
                unit_price = EXCLUDED.unit_price,
                unit_cost = EXCLUDED.unit_cost,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm_part_sale_line_items.dealer_id = EXCLUDED.dealer_id
              AND crm_part_sale_line_items.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_vehicles(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.vehicles
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_expenses(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.expenses
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_sales(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.sales
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_dealer_clients(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE public.crm_dealer_clients
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_dealer_users(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.dealer_users
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_financial_accounts(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.financial_accounts
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_account_transactions(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.account_transactions
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_expense_templates(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE public.crm_expense_templates
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_debts(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.debts
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_debt_payments(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.debt_payments
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_parts(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm_parts
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_part_batches(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm_part_batches
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_part_sales(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm_part_sales
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_part_sale_line_items(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm_part_sale_line_items
    SET deleted_at = now(),
        updated_at = now()
    WHERE id = p_id
      AND dealer_id = p_dealer_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_changes(dealer_id uuid, since text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    since_ts timestamptz;
    result jsonb;
BEGIN
    PERFORM public.assert_crm_access(dealer_id);
    since_ts := since::timestamptz;

    SELECT jsonb_build_object(
        'server_now', now(),
        'users', COALESCE((
            SELECT jsonb_agg(row_to_json(u))
            FROM crm.dealer_users u
            WHERE u.dealer_id = get_changes.dealer_id
              AND u.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'accounts', COALESCE((
            SELECT jsonb_agg(row_to_json(a))
            FROM crm.financial_accounts a
            WHERE a.dealer_id = get_changes.dealer_id
              AND a.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'account_transactions', COALESCE((
            SELECT jsonb_agg(row_to_json(at))
            FROM crm.account_transactions at
            WHERE at.dealer_id = get_changes.dealer_id
              AND at.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'vehicles', COALESCE((
            SELECT jsonb_agg(row_to_json(v))
            FROM crm.vehicles v
            WHERE v.dealer_id = get_changes.dealer_id
              AND v.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'templates', COALESCE((
            SELECT jsonb_agg(row_to_json(t))
            FROM crm.expense_templates t
            WHERE t.dealer_id = get_changes.dealer_id
              AND t.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'expenses', COALESCE((
            SELECT jsonb_agg(row_to_json(e))
            FROM crm.expenses e
            WHERE e.dealer_id = get_changes.dealer_id
              AND e.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'sales', COALESCE((
            SELECT jsonb_agg(row_to_json(s))
            FROM crm.sales s
            WHERE s.dealer_id = get_changes.dealer_id
              AND s.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debts', COALESCE((
            SELECT jsonb_agg(row_to_json(d))
            FROM crm.debts d
            WHERE d.dealer_id = get_changes.dealer_id
              AND d.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debt_payments', COALESCE((
            SELECT jsonb_agg(row_to_json(dp))
            FROM crm.debt_payments dp
            WHERE dp.dealer_id = get_changes.dealer_id
              AND dp.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'clients', COALESCE((
            SELECT jsonb_agg(row_to_json(c))
            FROM crm.dealer_clients c
            WHERE c.dealer_id = get_changes.dealer_id
              AND c.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'parts', COALESCE((
            SELECT jsonb_agg(row_to_json(p))
            FROM public.crm_parts p
            WHERE p.dealer_id = get_changes.dealer_id
              AND p.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_batches', COALESCE((
            SELECT jsonb_agg(row_to_json(pb))
            FROM public.crm_part_batches pb
            WHERE pb.dealer_id = get_changes.dealer_id
              AND pb.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_sales', COALESCE((
            SELECT jsonb_agg(row_to_json(ps))
            FROM public.crm_part_sales ps
            WHERE ps.dealer_id = get_changes.dealer_id
              AND ps.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_sale_line_items', COALESCE((
            SELECT jsonb_agg(row_to_json(psl))
            FROM public.crm_part_sale_line_items psl
            WHERE psl.dealer_id = get_changes.dealer_id
              AND psl.server_updated_at >= since_ts
        ), '[]'::jsonb)
    ) INTO result;

    RETURN result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.sync_users(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_accounts(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_account_transactions(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_vehicles(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_templates(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_expenses(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_sales(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_debts(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_debt_payments(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_clients(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_parts(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_part_batches(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_part_sales(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_part_sale_line_items(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_vehicles(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_expenses(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_sales(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_dealer_clients(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_dealer_users(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_financial_accounts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_account_transactions(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_expense_templates(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_debts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_debt_payments(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_parts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_part_batches(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_part_sales(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_part_sale_line_items(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_changes(uuid, text) TO authenticated;

ALTER VIEW IF EXISTS public.crm_account_transactions SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_dealer_users SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_debt_payments SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_debts SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_expenses SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_financial_accounts SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_sales SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_vehicle_photos SET (security_invoker = true);
ALTER VIEW IF EXISTS public.crm_vehicles SET (security_invoker = true);

CREATE INDEX IF NOT EXISTS idx_crm_expenses_vehicle_id ON crm.expenses (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_crm_expenses_user_id ON crm.expenses (user_id);
CREATE INDEX IF NOT EXISTS idx_crm_expenses_account_id ON crm.expenses (account_id);
CREATE INDEX IF NOT EXISTS idx_crm_sales_vehicle_id ON crm.sales (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_crm_sales_account_id ON crm.sales (account_id);
CREATE INDEX IF NOT EXISTS idx_crm_debt_payments_account_id ON crm.debt_payments (account_id);
CREATE INDEX IF NOT EXISTS idx_crm_dealer_clients_vehicle_id ON crm.dealer_clients (vehicle_id);

CREATE INDEX IF NOT EXISTS idx_crm_dealer_users_dealer_server_sync ON crm.dealer_users (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_fin_accounts_dealer_server_sync ON crm.financial_accounts (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_acct_tx_dealer_server_sync ON crm.account_transactions (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_vehicles_dealer_server_sync ON crm.vehicles (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_exp_templates_dealer_server_sync ON crm.expense_templates (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_expenses_dealer_server_sync ON crm.expenses (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_sales_dealer_server_sync ON crm.sales (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_debts_dealer_server_sync ON crm.debts (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_debt_pay_dealer_server_sync ON crm.debt_payments (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_dealer_clients_dealer_server_sync ON crm.dealer_clients (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_pub_crm_parts_dealer_server_sync ON public.crm_parts (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_pub_crm_part_batches_dealer_server_sync ON public.crm_part_batches (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_pub_crm_part_sales_dealer_server_sync ON public.crm_part_sales (dealer_id, server_updated_at);
CREATE INDEX IF NOT EXISTS idx_pub_crm_psli_dealer_server_sync ON public.crm_part_sale_line_items (dealer_id, server_updated_at);
