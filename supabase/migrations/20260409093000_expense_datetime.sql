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
            RETURN ((v_value::date)::timestamp AT TIME ZONE 'UTC');
        EXCEPTION WHEN others THEN
            RETURN p_fallback;
        END;
    END;
END;
$function$;

REVOKE ALL ON FUNCTION public.parse_crm_expense_occurred_at(text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.parse_crm_expense_occurred_at(text, timestamptz) TO authenticated, service_role;

ALTER TABLE crm.expenses
    ALTER COLUMN date DROP DEFAULT;

DROP VIEW IF EXISTS public.crm_expenses;

ALTER TABLE crm.expenses
    ALTER COLUMN date TYPE timestamptz
    USING (
        (
            date::timestamp
            + COALESCE((created_at AT TIME ZONE 'UTC')::time, TIME '00:00:00')
        ) AT TIME ZONE 'UTC'
    );

ALTER TABLE crm.expenses
    ALTER COLUMN date SET DEFAULT now();

COMMENT ON COLUMN crm.expenses.date IS 'Expense occurrence timestamp in UTC. Legacy date-only rows were backfilled with the UTC time-of-day from created_at.';

CREATE VIEW public.crm_expenses AS
 SELECT id,
    dealer_id,
    amount,
    date,
    expense_description,
    category,
    created_at,
    vehicle_id,
    user_id,
    account_id,
    updated_at,
    deleted_at,
    server_updated_at,
    last_modified_by,
    description,
    receipt_path,
    expense_type
   FROM crm.expenses;

GRANT ALL ON TABLE public.crm_expenses TO anon, authenticated, service_role;

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
    incoming_date timestamptz;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;
        incoming_date := public.parse_crm_expense_occurred_at(
            item->>'date',
            public.parse_crm_expense_occurred_at(item->>'created_at', now())
        );

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
                incoming_date,
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

REVOKE ALL ON FUNCTION public.sync_expenses(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_expenses(jsonb) TO authenticated;
