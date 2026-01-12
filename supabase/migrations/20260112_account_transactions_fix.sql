-- ============================================================================
-- Fix for Account Transactions (Base Table in CRM schema)
-- ============================================================================

-- 1. Add missing columns to crm.account_transactions
ALTER TABLE crm.account_transactions 
ADD COLUMN IF NOT EXISTS server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE crm.account_transactions 
ADD COLUMN IF NOT EXISTS last_modified_by UUID;

-- 2. Create helper function for triggers if not exists (in public)
CREATE OR REPLACE FUNCTION public.update_server_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.server_updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Add triggers for server_updated_at on crm.account_transactions
DROP TRIGGER IF EXISTS trg_crm_account_transactions_server_updated_at ON crm.account_transactions;
CREATE TRIGGER trg_crm_account_transactions_server_updated_at
    BEFORE INSERT OR UPDATE ON crm.account_transactions
    FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at();

-- 4. Create VIEW in public schema to expose the table (standard pattern in this DB)
CREATE OR REPLACE VIEW public.crm_account_transactions AS
SELECT * FROM crm.account_transactions;

-- 5. Grant Permissions on View and Table
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_account_transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm.account_transactions TO authenticated;

-- Ensure RLS is enabled on base table
ALTER TABLE crm.account_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "account_transactions_select" ON crm.account_transactions;
CREATE POLICY "account_transactions_select" ON crm.account_transactions FOR SELECT
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "account_transactions_insert" ON crm.account_transactions;
CREATE POLICY "account_transactions_insert" ON crm.account_transactions FOR INSERT
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "account_transactions_update" ON crm.account_transactions;
CREATE POLICY "account_transactions_update" ON crm.account_transactions FOR UPDATE
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "account_transactions_delete" ON crm.account_transactions;
CREATE POLICY "account_transactions_delete" ON crm.account_transactions FOR DELETE
    USING (public.crm_can_access(dealer_id));


-- 6. Create Sync RPC Function (targeting BASE TABLE crm.account_transactions)
DROP FUNCTION IF EXISTS public.sync_account_transactions(jsonb);
CREATE OR REPLACE FUNCTION public.sync_account_transactions(payload jsonb)
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
        FROM crm.account_transactions WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.account_transactions (
                id, dealer_id, account_id, transaction_type, amount,
                date, note, created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- 7. Create Delete RPC Function
DROP FUNCTION IF EXISTS public.delete_crm_account_transactions(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_crm_account_transactions(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm.account_transactions
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- 8. Grant Permissions on Functions
GRANT EXECUTE ON FUNCTION public.sync_account_transactions(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_account_transactions(uuid, uuid) TO authenticated;

-- 9. Re-apply get_changes
DROP FUNCTION IF EXISTS public.get_changes(uuid, text);
CREATE OR REPLACE FUNCTION public.get_changes(dealer_id uuid, since text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    since_ts timestamptz;
    result jsonb;
BEGIN
    -- Parse the since timestamp
    since_ts := since::timestamptz;

    -- Build the result JSON with all entity types including parts
    SELECT jsonb_build_object(
        'users', COALESCE((
            SELECT jsonb_agg(row_to_json(u))
            FROM public.crm_dealer_users u
            WHERE u.dealer_id = get_changes.dealer_id
            AND u.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'accounts', COALESCE((
            SELECT jsonb_agg(row_to_json(a))
            FROM public.crm_financial_accounts a
            WHERE a.dealer_id = get_changes.dealer_id
            AND a.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'account_transactions', COALESCE((
            SELECT jsonb_agg(row_to_json(at))
            FROM public.crm_account_transactions at
            WHERE at.dealer_id = get_changes.dealer_id
            AND at.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'vehicles', COALESCE((
            SELECT jsonb_agg(row_to_json(v))
            FROM public.crm_vehicles v
            WHERE v.dealer_id = get_changes.dealer_id
            AND v.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'templates', COALESCE((
            SELECT jsonb_agg(row_to_json(t))
            FROM public.crm_expense_templates t
            WHERE t.dealer_id = get_changes.dealer_id
            AND t.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'expenses', COALESCE((
            SELECT jsonb_agg(row_to_json(e))
            FROM public.crm_expenses e
            WHERE e.dealer_id = get_changes.dealer_id
            AND e.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'sales', COALESCE((
            SELECT jsonb_agg(row_to_json(s))
            FROM public.crm_sales s
            WHERE s.dealer_id = get_changes.dealer_id
            AND s.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debts', COALESCE((
            SELECT jsonb_agg(row_to_json(d))
            FROM public.crm_debts d
            WHERE d.dealer_id = get_changes.dealer_id
            AND d.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debt_payments', COALESCE((
            SELECT jsonb_agg(row_to_json(dp))
            FROM public.crm_debt_payments dp
            WHERE dp.dealer_id = get_changes.dealer_id
            AND dp.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'clients', COALESCE((
            SELECT jsonb_agg(row_to_json(c))
            FROM public.crm_dealer_clients c
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
$$;
