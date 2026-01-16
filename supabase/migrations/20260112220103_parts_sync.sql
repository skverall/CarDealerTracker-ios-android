-- ============================================================================
-- Supabase Parts Sync Backend Migration
-- ============================================================================
-- This migration adds tables, RLS policies, and RPC functions for parts sync
-- Run this in Supabase Dashboard → SQL Editor → New Query → Paste & Run
-- ============================================================================

-- ============================================================================
-- 1. CREATE TABLES
-- ============================================================================

-- crm_parts: Master parts catalog
CREATE TABLE IF NOT EXISTS crm_parts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_modified_by UUID
);

-- crm_part_batches: Inventory batches for parts
CREATE TABLE IF NOT EXISTS crm_part_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES crm_parts(id) ON DELETE CASCADE,
    batch_label TEXT,
    quantity_received NUMERIC NOT NULL DEFAULT 0,
    quantity_remaining NUMERIC NOT NULL DEFAULT 0,
    unit_cost NUMERIC NOT NULL DEFAULT 0,
    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
    purchase_account_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_modified_by UUID
);

-- crm_part_sales: Sales transactions for parts
CREATE TABLE IF NOT EXISTS crm_part_sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    amount NUMERIC NOT NULL DEFAULT 0,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    buyer_name TEXT,
    buyer_phone TEXT,
    payment_method TEXT,
    account_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_modified_by UUID
);

-- crm_part_sale_line_items: Line items linking parts to sales
CREATE TABLE IF NOT EXISTS crm_part_sale_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    sale_id UUID NOT NULL REFERENCES crm_part_sales(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES crm_parts(id) ON DELETE CASCADE,
    batch_id UUID NOT NULL REFERENCES crm_part_batches(id) ON DELETE CASCADE,
    quantity NUMERIC NOT NULL DEFAULT 0,
    unit_price NUMERIC NOT NULL DEFAULT 0,
    unit_cost NUMERIC NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_modified_by UUID
);

-- ============================================================================
-- 2. CREATE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_crm_parts_dealer_id ON crm_parts(dealer_id);
CREATE INDEX IF NOT EXISTS idx_crm_parts_updated_at ON crm_parts(updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_parts_server_updated_at ON crm_parts(server_updated_at);

CREATE INDEX IF NOT EXISTS idx_crm_part_batches_dealer_id ON crm_part_batches(dealer_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_batches_part_id ON crm_part_batches(part_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_batches_updated_at ON crm_part_batches(updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_part_batches_server_updated_at ON crm_part_batches(server_updated_at);

CREATE INDEX IF NOT EXISTS idx_crm_part_sales_dealer_id ON crm_part_sales(dealer_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_sales_updated_at ON crm_part_sales(updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_part_sales_server_updated_at ON crm_part_sales(server_updated_at);

CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_dealer_id ON crm_part_sale_line_items(dealer_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_sale_id ON crm_part_sale_line_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_part_id ON crm_part_sale_line_items(part_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_batch_id ON crm_part_sale_line_items(batch_id);
CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_updated_at ON crm_part_sale_line_items(updated_at);
CREATE INDEX IF NOT EXISTS idx_crm_part_sale_line_items_server_updated_at ON crm_part_sale_line_items(server_updated_at);

-- ============================================================================
-- 3. CREATE TRIGGERS FOR server_updated_at
-- ============================================================================

-- Trigger function (reuse if exists)
CREATE OR REPLACE FUNCTION update_server_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.server_updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for each table
DROP TRIGGER IF EXISTS trg_crm_parts_server_updated_at ON crm_parts;
CREATE TRIGGER trg_crm_parts_server_updated_at
    BEFORE INSERT OR UPDATE ON crm_parts
    FOR EACH ROW EXECUTE FUNCTION update_server_updated_at();

DROP TRIGGER IF EXISTS trg_crm_part_batches_server_updated_at ON crm_part_batches;
CREATE TRIGGER trg_crm_part_batches_server_updated_at
    BEFORE INSERT OR UPDATE ON crm_part_batches
    FOR EACH ROW EXECUTE FUNCTION update_server_updated_at();

DROP TRIGGER IF EXISTS trg_crm_part_sales_server_updated_at ON crm_part_sales;
CREATE TRIGGER trg_crm_part_sales_server_updated_at
    BEFORE INSERT OR UPDATE ON crm_part_sales
    FOR EACH ROW EXECUTE FUNCTION update_server_updated_at();

DROP TRIGGER IF EXISTS trg_crm_part_sale_line_items_server_updated_at ON crm_part_sale_line_items;
CREATE TRIGGER trg_crm_part_sale_line_items_server_updated_at
    BEFORE INSERT OR UPDATE ON crm_part_sale_line_items
    FOR EACH ROW EXECUTE FUNCTION update_server_updated_at();

-- ============================================================================
-- 4. ENABLE RLS AND CREATE POLICIES
-- ============================================================================

-- crm_parts
ALTER TABLE crm_parts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_parts_select" ON crm_parts;
CREATE POLICY "crm_parts_select" ON crm_parts FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_parts_insert" ON crm_parts;
CREATE POLICY "crm_parts_insert" ON crm_parts FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_parts_update" ON crm_parts;
CREATE POLICY "crm_parts_update" ON crm_parts FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_parts_delete" ON crm_parts;
CREATE POLICY "crm_parts_delete" ON crm_parts FOR DELETE
    USING (crm_can_access(dealer_id));

-- crm_part_batches
ALTER TABLE crm_part_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_part_batches_select" ON crm_part_batches;
CREATE POLICY "crm_part_batches_select" ON crm_part_batches FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_batches_insert" ON crm_part_batches;
CREATE POLICY "crm_part_batches_insert" ON crm_part_batches FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_batches_update" ON crm_part_batches;
CREATE POLICY "crm_part_batches_update" ON crm_part_batches FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_batches_delete" ON crm_part_batches;
CREATE POLICY "crm_part_batches_delete" ON crm_part_batches FOR DELETE
    USING (crm_can_access(dealer_id));

-- crm_part_sales
ALTER TABLE crm_part_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_part_sales_select" ON crm_part_sales;
CREATE POLICY "crm_part_sales_select" ON crm_part_sales FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sales_insert" ON crm_part_sales;
CREATE POLICY "crm_part_sales_insert" ON crm_part_sales FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sales_update" ON crm_part_sales;
CREATE POLICY "crm_part_sales_update" ON crm_part_sales FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sales_delete" ON crm_part_sales;
CREATE POLICY "crm_part_sales_delete" ON crm_part_sales FOR DELETE
    USING (crm_can_access(dealer_id));

-- crm_part_sale_line_items
ALTER TABLE crm_part_sale_line_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_part_sale_line_items_select" ON crm_part_sale_line_items;
CREATE POLICY "crm_part_sale_line_items_select" ON crm_part_sale_line_items FOR SELECT
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sale_line_items_insert" ON crm_part_sale_line_items;
CREATE POLICY "crm_part_sale_line_items_insert" ON crm_part_sale_line_items FOR INSERT
    WITH CHECK (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sale_line_items_update" ON crm_part_sale_line_items;
CREATE POLICY "crm_part_sale_line_items_update" ON crm_part_sale_line_items FOR UPDATE
    USING (crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_part_sale_line_items_delete" ON crm_part_sale_line_items;
CREATE POLICY "crm_part_sale_line_items_delete" ON crm_part_sale_line_items FOR DELETE
    USING (crm_can_access(dealer_id));

-- ============================================================================
-- 5. CREATE SYNC RPC FUNCTIONS
-- ============================================================================

-- sync_parts: Upsert parts with last-write-wins
CREATE OR REPLACE FUNCTION sync_parts(payload jsonb)
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

        -- Check existing record
        SELECT updated_at INTO existing_updated_at
        FROM crm_parts WHERE id = v_id;

        -- Last-write-wins: only update if incoming is newer or record doesn't exist
        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_parts (
                id, dealer_id, name, category, notes,
                created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
                v_id,
                v_dealer_id,
                item->>'name',
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
                category = EXCLUDED.category,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- sync_part_batches: Upsert part batches with last-write-wins
CREATE OR REPLACE FUNCTION sync_part_batches(payload jsonb)
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
        FROM crm_part_batches WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_batches (
                id, dealer_id, part_id, batch_label, quantity_received,
                quantity_remaining, unit_cost, purchase_date, purchase_account_id,
                notes, created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- sync_part_sales: Upsert part sales with last-write-wins
CREATE OR REPLACE FUNCTION sync_part_sales(payload jsonb)
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
        FROM crm_part_sales WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_sales (
                id, dealer_id, amount, date, buyer_name, buyer_phone,
                payment_method, account_id, notes,
                created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- sync_part_sale_line_items: Upsert part sale line items with last-write-wins
CREATE OR REPLACE FUNCTION sync_part_sale_line_items(payload jsonb)
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
        FROM crm_part_sale_line_items WHERE id = v_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm_part_sale_line_items (
                id, dealer_id, sale_id, part_id, batch_id,
                quantity, unit_price, unit_cost,
                created_at, updated_at, deleted_at, last_modified_by
            ) VALUES (
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
                last_modified_by = EXCLUDED.last_modified_by;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================================
-- 6. CREATE DELETE RPC FUNCTIONS
-- ============================================================================

-- delete_crm_parts: Soft delete a part
CREATE OR REPLACE FUNCTION delete_crm_parts(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm_parts
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- delete_crm_part_batches: Soft delete a part batch
CREATE OR REPLACE FUNCTION delete_crm_part_batches(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm_part_batches
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- delete_crm_part_sales: Soft delete a part sale
CREATE OR REPLACE FUNCTION delete_crm_part_sales(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm_part_sales
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- delete_crm_part_sale_line_items: Soft delete a part sale line item
CREATE OR REPLACE FUNCTION delete_crm_part_sale_line_items(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE crm_part_sale_line_items
    SET deleted_at = now(), updated_at = now()
    WHERE id = p_id AND dealer_id = p_dealer_id;
END;
$$;

-- ============================================================================
-- 7. UPDATE get_changes FUNCTION TO INCLUDE PARTS
-- ============================================================================

-- Drop the old version with timestamp signature if it exists to avoid ambiguity
DROP FUNCTION IF EXISTS get_changes(uuid, timestamp with time zone);

CREATE OR REPLACE FUNCTION get_changes(dealer_id uuid, since text)
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
            FROM crm_dealer_users u
            WHERE u.dealer_id = get_changes.dealer_id
            AND u.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'accounts', COALESCE((
            SELECT jsonb_agg(row_to_json(a))
            FROM crm_financial_accounts a
            WHERE a.dealer_id = get_changes.dealer_id
            AND a.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'account_transactions', COALESCE((
            SELECT jsonb_agg(row_to_json(at))
            FROM crm_account_transactions at
            WHERE at.dealer_id = get_changes.dealer_id
            AND at.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'vehicles', COALESCE((
            SELECT jsonb_agg(row_to_json(v))
            FROM crm_vehicles v
            WHERE v.dealer_id = get_changes.dealer_id
            AND v.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'templates', COALESCE((
            SELECT jsonb_agg(row_to_json(t))
            FROM crm_expense_templates t
            WHERE t.dealer_id = get_changes.dealer_id
            AND t.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'expenses', COALESCE((
            SELECT jsonb_agg(row_to_json(e))
            FROM crm_expenses e
            WHERE e.dealer_id = get_changes.dealer_id
            AND e.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'sales', COALESCE((
            SELECT jsonb_agg(row_to_json(s))
            FROM crm_sales s
            WHERE s.dealer_id = get_changes.dealer_id
            AND s.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debts', COALESCE((
            SELECT jsonb_agg(row_to_json(d))
            FROM crm_debts d
            WHERE d.dealer_id = get_changes.dealer_id
            AND d.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'debt_payments', COALESCE((
            SELECT jsonb_agg(row_to_json(dp))
            FROM crm_debt_payments dp
            WHERE dp.dealer_id = get_changes.dealer_id
            AND dp.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'clients', COALESCE((
            SELECT jsonb_agg(row_to_json(c))
            FROM crm_dealer_clients c
            WHERE c.dealer_id = get_changes.dealer_id
            AND c.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'parts', COALESCE((
            SELECT jsonb_agg(row_to_json(p))
            FROM crm_parts p
            WHERE p.dealer_id = get_changes.dealer_id
            AND p.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_batches', COALESCE((
            SELECT jsonb_agg(row_to_json(pb))
            FROM crm_part_batches pb
            WHERE pb.dealer_id = get_changes.dealer_id
            AND pb.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_sales', COALESCE((
            SELECT jsonb_agg(row_to_json(ps))
            FROM crm_part_sales ps
            WHERE ps.dealer_id = get_changes.dealer_id
            AND ps.server_updated_at >= since_ts
        ), '[]'::jsonb),
        'part_sale_line_items', COALESCE((
            SELECT jsonb_agg(row_to_json(psl))
            FROM crm_part_sale_line_items psl
            WHERE psl.dealer_id = get_changes.dealer_id
            AND psl.server_updated_at >= since_ts
        ), '[]'::jsonb)
    ) INTO result;

    RETURN result;
END;
$$;

-- ============================================================================
-- 8. GRANT PERMISSIONS
-- ============================================================================

-- Grant execute on new functions to authenticated users
GRANT EXECUTE ON FUNCTION sync_parts(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_part_batches(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_part_sales(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_part_sale_line_items(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_crm_parts(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_crm_part_batches(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_crm_part_sales(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_crm_part_sale_line_items(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_changes(uuid, text) TO authenticated;

-- Grant table access to authenticated users (RLS will handle authorization)
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_parts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_part_batches TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_part_sales TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm_part_sale_line_items TO authenticated;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
