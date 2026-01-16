-- ============================================================================
-- Fix for Debts and Debt Payments (Base Table in CRM schema)
-- ============================================================================

-- 1. Add missing columns to crm.debts
ALTER TABLE crm.debts
ADD COLUMN IF NOT EXISTS server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE crm.debts
ADD COLUMN IF NOT EXISTS last_modified_by UUID;

-- 2. Add missing columns to crm.debt_payments
ALTER TABLE crm.debt_payments
ADD COLUMN IF NOT EXISTS server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE crm.debt_payments
ADD COLUMN IF NOT EXISTS last_modified_by UUID;

-- 3. Add triggers for server_updated_at (using public.update_server_updated_at helper)
DROP TRIGGER IF EXISTS trg_crm_debts_server_updated_at ON crm.debts;
CREATE TRIGGER trg_crm_debts_server_updated_at
    BEFORE INSERT OR UPDATE ON crm.debts
    FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at();

DROP TRIGGER IF EXISTS trg_crm_debt_payments_server_updated_at ON crm.debt_payments;
CREATE TRIGGER trg_crm_debt_payments_server_updated_at
    BEFORE INSERT OR UPDATE ON crm.debt_payments
    FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at();

-- 4. Create VIEWs in public schema
CREATE OR REPLACE VIEW public.crm_debts AS
SELECT * FROM crm.debts;

CREATE OR REPLACE VIEW public.crm_debt_payments AS
SELECT * FROM crm.debt_payments;

-- 5. Grant Permissions on Views and Tables
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_debts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm.debts TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_debt_payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm.debt_payments TO authenticated;

-- 6. Enable RLS and Add Policies (crm.debts)
ALTER TABLE crm.debts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "debts_select" ON crm.debts;
CREATE POLICY "debts_select" ON crm.debts FOR SELECT
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debts_insert" ON crm.debts;
CREATE POLICY "debts_insert" ON crm.debts FOR INSERT
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debts_update" ON crm.debts;
CREATE POLICY "debts_update" ON crm.debts FOR UPDATE
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debts_delete" ON crm.debts;
CREATE POLICY "debts_delete" ON crm.debts FOR DELETE
    USING (public.crm_can_access(dealer_id));

-- 7. Enable RLS and Add Policies (crm.debt_payments)
ALTER TABLE crm.debt_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "debt_payments_select" ON crm.debt_payments;
CREATE POLICY "debt_payments_select" ON crm.debt_payments FOR SELECT
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debt_payments_insert" ON crm.debt_payments;
CREATE POLICY "debt_payments_insert" ON crm.debt_payments FOR INSERT
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debt_payments_update" ON crm.debt_payments;
CREATE POLICY "debt_payments_update" ON crm.debt_payments FOR UPDATE
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "debt_payments_delete" ON crm.debt_payments;
CREATE POLICY "debt_payments_delete" ON crm.debt_payments FOR DELETE
    USING (public.crm_can_access(dealer_id));

-- 8. Create Sync RPC Function for Debts
DROP FUNCTION IF EXISTS public.sync_debts(jsonb);
CREATE OR REPLACE FUNCTION public.sync_debts(payload jsonb)
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
        FROM crm.debts WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.debts (
                id, dealer_id, counterparty_name, counterparty_phone, direction,
                amount, notes, due_date, created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- 9. Create Sync RPC Function for Debt Payments
DROP FUNCTION IF EXISTS public.sync_debt_payments(jsonb);
CREATE OR REPLACE FUNCTION public.sync_debt_payments(payload jsonb)
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
        FROM crm.debt_payments WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.debt_payments (
                id, dealer_id, debt_id, amount, date,
                note, payment_method, account_id,
                created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
                v_id,
                v_dealer_id,
                (item->>'debt_id')::uuid,
                COALESCE((item->>'amount')::numeric, 0),
                COALESCE((item->>'date')::timestamptz, now()), -- Schema uses timestamptz
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;


-- 10. Create Delete RPC Functions
DROP FUNCTION IF EXISTS public.delete_crm_debts(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_crm_debts(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm.debts
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

DROP FUNCTION IF EXISTS public.delete_crm_debt_payments(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_crm_debt_payments(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm.debt_payments
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- 11. Grant Permissions on New Functions
GRANT EXECUTE ON FUNCTION public.sync_debts(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_debt_payments(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_debts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_debt_payments(uuid, uuid) TO authenticated;
