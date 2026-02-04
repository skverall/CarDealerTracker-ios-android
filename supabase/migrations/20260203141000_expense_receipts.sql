-- Migration: Expense receipt attachments
-- Date: 2026-02-03

-- 1) Add receipt_path to base table if it exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'crm'
          AND table_name = 'expenses'
    ) THEN
        ALTER TABLE crm.expenses
            ADD COLUMN IF NOT EXISTS receipt_path TEXT,
            ADD COLUMN IF NOT EXISTS expense_type TEXT;

        DROP VIEW IF EXISTS public.crm_expenses;
        CREATE OR REPLACE VIEW public.crm_expenses AS
        SELECT * FROM crm.expenses;

        GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_expenses TO authenticated;
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'crm_expenses'
    ) THEN
        ALTER TABLE public.crm_expenses
            ADD COLUMN IF NOT EXISTS receipt_path TEXT;
    END IF;
END $$;

-- 2) Ensure sync_expenses handles receipt_path
DROP FUNCTION IF EXISTS public.sync_expenses(jsonb);

CREATE OR REPLACE FUNCTION public.sync_expenses(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    item jsonb;
    v_id uuid;
    v_dealer_id uuid;
    existing_updated_at timestamptz;
    incoming_updated_at timestamptz;
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(payload)
    LOOP
        v_id := (item->>'id')::uuid;
        v_dealer_id := (item->>'dealer_id')::uuid;
        incoming_updated_at := (item->>'updated_at')::timestamptz;

        SELECT updated_at INTO existing_updated_at
        FROM crm.expenses WHERE id = v_id;

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
            ) VALUES (
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
                deleted_at = EXCLUDED.deleted_at;
        END IF;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_expenses(jsonb) TO authenticated;

-- 3) Storage bucket + policies for receipts
INSERT INTO storage.buckets (id, name, public)
VALUES ('expense-receipts', 'expense-receipts', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "expense_receipts_select" ON storage.objects;
CREATE POLICY "expense_receipts_select" ON storage.objects
FOR SELECT
USING (
    bucket_id = 'expense-receipts'
    AND crm_can_access((split_part(name, '/', 1))::uuid)
);

DROP POLICY IF EXISTS "expense_receipts_insert" ON storage.objects;
CREATE POLICY "expense_receipts_insert" ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'expense-receipts'
    AND crm_can_access((split_part(name, '/', 1))::uuid)
);

DROP POLICY IF EXISTS "expense_receipts_update" ON storage.objects;
CREATE POLICY "expense_receipts_update" ON storage.objects
FOR UPDATE
USING (
    bucket_id = 'expense-receipts'
    AND crm_can_access((split_part(name, '/', 1))::uuid)
);

DROP POLICY IF EXISTS "expense_receipts_delete" ON storage.objects;
CREATE POLICY "expense_receipts_delete" ON storage.objects
FOR DELETE
USING (
    bucket_id = 'expense-receipts'
    AND crm_can_access((split_part(name, '/', 1))::uuid)
);
