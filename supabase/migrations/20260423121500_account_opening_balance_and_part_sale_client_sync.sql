ALTER TABLE crm.financial_accounts
    ADD COLUMN IF NOT EXISTS opening_balance numeric;

ALTER TABLE public.crm_part_sales
    ADD COLUMN IF NOT EXISTS client_id uuid REFERENCES crm.dealer_clients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_crm_part_sales_client_id
    ON public.crm_part_sales (client_id);

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
                opening_balance = CASE
                    WHEN item ? 'opening_balance' THEN (item->>'opening_balance')::decimal
                    ELSE crm.financial_accounts.opening_balance
                END,
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
                opening_balance,
                updated_at,
                deleted_at
            )
            VALUES (
                (item->>'id')::uuid,
                v_dealer_id,
                item->>'account_type',
                (item->>'balance')::decimal,
                CASE WHEN item ? 'opening_balance' THEN (item->>'opening_balance')::decimal ELSE NULL END,
                (item->>'updated_at')::timestamptz,
                (item->>'deleted_at')::timestamptz
            )
            ON CONFLICT (id) DO UPDATE
            SET account_type = EXCLUDED.account_type,
                balance = EXCLUDED.balance,
                opening_balance = CASE
                    WHEN item ? 'opening_balance' THEN EXCLUDED.opening_balance
                    ELSE crm.financial_accounts.opening_balance
                END,
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
                client_id,
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
                CASE WHEN item ? 'client_id' THEN (item->>'client_id')::uuid ELSE NULL END,
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
                client_id = CASE
                    WHEN item ? 'client_id' THEN (item->>'client_id')::uuid
                    ELSE crm_part_sales.client_id
                END,
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
