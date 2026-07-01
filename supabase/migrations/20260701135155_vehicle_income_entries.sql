CREATE TABLE IF NOT EXISTS crm.vehicle_income_entries (
    id uuid PRIMARY KEY,
    dealer_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    vehicle_id uuid REFERENCES crm.vehicles(id) ON DELETE SET NULL,
    account_id uuid REFERENCES crm.financial_accounts(id) ON DELETE SET NULL,
    amount numeric NOT NULL DEFAULT 0 CHECK (amount >= 0),
    date date NOT NULL DEFAULT CURRENT_DATE,
    income_type text NOT NULL DEFAULT 'rental',
    payer_name text,
    payment_method text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    server_updated_at timestamptz NOT NULL DEFAULT now(),
    last_modified_by uuid
);

CREATE INDEX IF NOT EXISTS idx_crm_vehicle_income_entries_dealer_server_sync
ON crm.vehicle_income_entries (dealer_id, server_updated_at);

CREATE INDEX IF NOT EXISTS idx_crm_vehicle_income_entries_vehicle_active_date
ON crm.vehicle_income_entries (vehicle_id, deleted_at, date DESC);

CREATE INDEX IF NOT EXISTS idx_crm_vehicle_income_entries_account
ON crm.vehicle_income_entries (account_id);

ALTER TABLE crm.vehicle_income_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vehicle_income_entries_select" ON crm.vehicle_income_entries;
CREATE POLICY "vehicle_income_entries_select" ON crm.vehicle_income_entries FOR SELECT
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_income_entries_insert" ON crm.vehicle_income_entries;
CREATE POLICY "vehicle_income_entries_insert" ON crm.vehicle_income_entries FOR INSERT
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_income_entries_update" ON crm.vehicle_income_entries;
CREATE POLICY "vehicle_income_entries_update" ON crm.vehicle_income_entries FOR UPDATE
    USING (public.crm_can_access(dealer_id))
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "vehicle_income_entries_delete" ON crm.vehicle_income_entries;
CREATE POLICY "vehicle_income_entries_delete" ON crm.vehicle_income_entries FOR DELETE
    USING (public.crm_can_access(dealer_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON crm.vehicle_income_entries TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_crm_vehicle_income_entries_server_updated_at ON crm.vehicle_income_entries;
CREATE TRIGGER trg_crm_vehicle_income_entries_server_updated_at
BEFORE INSERT OR UPDATE ON crm.vehicle_income_entries
FOR EACH ROW EXECUTE FUNCTION public.update_server_updated_at();

CREATE OR REPLACE FUNCTION public.crm_assert_write_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    v_dealer_id uuid;
    v_perm_keys text[];
    v_is_delete boolean := false;
BEGIN
    IF public.crm_is_service_role() THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_dealer_id := OLD.dealer_id;
        v_is_delete := true;
    ELSE
        v_dealer_id := NEW.dealer_id;
        IF TG_OP = 'UPDATE' THEN
            IF to_jsonb(OLD) ? 'deleted_at'
               AND to_jsonb(NEW) ? 'deleted_at'
               AND to_jsonb(OLD) ->> 'deleted_at' IS NULL
               AND to_jsonb(NEW) ->> 'deleted_at' IS NOT NULL THEN
                v_is_delete := true;
            END IF;
        END IF;
    END IF;

    IF v_is_delete THEN
        PERFORM public.assert_crm_permission(v_dealer_id, ARRAY['delete_records']);
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    CASE TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
        WHEN 'crm.dealer_users' THEN
            IF TG_OP <> 'DELETE' AND NEW.id = auth.uid() THEN
                RETURN NEW;
            END IF;
            v_perm_keys := ARRAY['manage_team'];
        WHEN 'crm.financial_accounts' THEN
            v_perm_keys := ARRAY['view_financials'];
        WHEN 'crm.account_transactions' THEN
            v_perm_keys := ARRAY['view_financials'];
        WHEN 'crm.vehicle_income_entries' THEN
            v_perm_keys := ARRAY['view_financials'];
        WHEN 'crm.expense_templates' THEN
            v_perm_keys := ARRAY['view_expenses'];
        WHEN 'crm.expenses' THEN
            v_perm_keys := ARRAY['view_expenses'];
        WHEN 'crm.sales' THEN
            v_perm_keys := ARRAY['create_sale', 'view_financials'];
        WHEN 'crm.debts' THEN
            v_perm_keys := ARRAY['view_financials'];
        WHEN 'crm.debt_payments' THEN
            v_perm_keys := ARRAY['view_financials'];
        WHEN 'crm.dealer_clients' THEN
            v_perm_keys := ARRAY['view_leads'];
        WHEN 'crm.client_interactions' THEN
            v_perm_keys := ARRAY['view_leads'];
        WHEN 'crm.client_reminders' THEN
            v_perm_keys := ARRAY['view_leads'];
        WHEN 'public.crm_parts' THEN
            v_perm_keys := ARRAY['manage_parts_inventory'];
        WHEN 'public.crm_part_batches' THEN
            v_perm_keys := ARRAY['manage_parts_inventory'];
        WHEN 'public.crm_part_sales' THEN
            v_perm_keys := ARRAY['create_part_sale', 'view_financials'];
        WHEN 'public.crm_part_sale_line_items' THEN
            v_perm_keys := ARRAY['create_part_sale', 'view_financials'];
        WHEN 'crm.vehicles' THEN
            IF TG_OP = 'INSERT' THEN
                v_perm_keys := ARRAY['view_vehicle_cost', 'view_financials'];
            ELSIF NEW.purchase_price IS DISTINCT FROM OLD.purchase_price
               OR NEW.purchase_account_id IS DISTINCT FROM OLD.purchase_account_id THEN
                v_perm_keys := ARRAY['view_vehicle_cost', 'view_financials'];
            ELSIF NEW.sale_price IS DISTINCT FROM OLD.sale_price
               OR NEW.sale_date IS DISTINCT FROM OLD.sale_date
               OR NEW.status IS DISTINCT FROM OLD.status THEN
                v_perm_keys := ARRAY['create_sale', 'view_vehicle_cost', 'view_financials'];
            ELSE
                v_perm_keys := ARRAY['view_inventory'];
            END IF;
        ELSE
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CRM_PERMISSION_GUARD_UNMAPPED';
    END CASE;

    PERFORM public.assert_crm_permission(v_dealer_id, v_perm_keys);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.crm_assert_write_permission() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_crm_vehicle_income_entries_permission_guard ON crm.vehicle_income_entries;
CREATE TRIGGER trg_crm_vehicle_income_entries_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.vehicle_income_entries
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

CREATE OR REPLACE FUNCTION public.sync_vehicle_income_entries(payload jsonb)
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
        incoming_updated_at := COALESCE((NULLIF(item->>'updated_at', ''))::timestamptz, now());
        PERFORM public.assert_crm_permission(v_dealer_id, ARRAY['view_financials']);

        SELECT updated_at INTO existing_updated_at
        FROM crm.vehicle_income_entries
        WHERE id = v_id
          AND dealer_id = v_dealer_id;

        IF existing_updated_at IS NULL OR incoming_updated_at > existing_updated_at THEN
            INSERT INTO crm.vehicle_income_entries (
                id,
                dealer_id,
                vehicle_id,
                account_id,
                amount,
                date,
                income_type,
                payer_name,
                payment_method,
                notes,
                created_at,
                updated_at,
                deleted_at,
                last_modified_by
            )
            VALUES (
                v_id,
                v_dealer_id,
                (NULLIF(item->>'vehicle_id', ''))::uuid,
                (NULLIF(item->>'account_id', ''))::uuid,
                COALESCE((NULLIF(item->>'amount', ''))::numeric, 0),
                COALESCE((NULLIF(item->>'date', ''))::date, CURRENT_DATE),
                COALESCE(NULLIF(item->>'income_type', ''), 'rental'),
                NULLIF(item->>'payer_name', ''),
                NULLIF(item->>'payment_method', ''),
                NULLIF(item->>'notes', ''),
                COALESCE((NULLIF(item->>'created_at', ''))::timestamptz, now()),
                incoming_updated_at,
                (NULLIF(item->>'deleted_at', ''))::timestamptz,
                (NULLIF(item->>'last_modified_by', ''))::uuid
            )
            ON CONFLICT (id) DO UPDATE SET
                dealer_id = EXCLUDED.dealer_id,
                vehicle_id = EXCLUDED.vehicle_id,
                account_id = EXCLUDED.account_id,
                amount = EXCLUDED.amount,
                date = EXCLUDED.date,
                income_type = EXCLUDED.income_type,
                payer_name = EXCLUDED.payer_name,
                payment_method = EXCLUDED.payment_method,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                deleted_at = EXCLUDED.deleted_at,
                last_modified_by = EXCLUDED.last_modified_by
            WHERE crm.vehicle_income_entries.dealer_id = EXCLUDED.dealer_id
              AND crm.vehicle_income_entries.updated_at < EXCLUDED.updated_at;
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_vehicle_income_entries(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.vehicle_income_entries
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
    can_manage_team boolean;
    can_view_financials boolean;
    can_view_inventory boolean;
    can_view_expenses boolean;
    can_view_sales boolean;
    can_view_leads boolean;
    can_view_parts boolean;
    can_view_part_sales boolean;
BEGIN
    PERFORM public.assert_crm_access(dealer_id);
    since_ts := since::timestamptz;
    can_manage_team := public.crm_effective_permission(dealer_id, 'manage_team');
    can_view_financials := public.crm_effective_permission(dealer_id, 'view_financials');
    can_view_inventory := public.crm_effective_permission(dealer_id, 'view_inventory');
    can_view_expenses := public.crm_effective_permission(dealer_id, 'view_expenses');
    can_view_sales := public.crm_effective_any_permission(dealer_id, ARRAY['create_sale', 'view_financials']);
    can_view_leads := public.crm_effective_permission(dealer_id, 'view_leads');
    can_view_parts := public.crm_effective_permission(dealer_id, 'view_parts_inventory');
    can_view_part_sales := public.crm_effective_any_permission(dealer_id, ARRAY['create_part_sale', 'view_financials']);

    SELECT jsonb_build_object(
        'server_now', now(),
        'users', CASE WHEN can_manage_team THEN COALESCE((
            SELECT jsonb_agg(row_to_json(u))
            FROM crm.dealer_users u
            WHERE u.dealer_id = get_changes.dealer_id
              AND u.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'accounts', CASE WHEN can_view_financials THEN COALESCE((
            SELECT jsonb_agg(row_to_json(a))
            FROM crm.financial_accounts a
            WHERE a.dealer_id = get_changes.dealer_id
              AND a.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'account_transactions', CASE WHEN can_view_financials THEN COALESCE((
            SELECT jsonb_agg(row_to_json(at))
            FROM crm.account_transactions at
            WHERE at.dealer_id = get_changes.dealer_id
              AND at.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'vehicle_income_entries', CASE WHEN can_view_financials THEN COALESCE((
            SELECT jsonb_agg(row_to_json(vi))
            FROM crm.vehicle_income_entries vi
            WHERE vi.dealer_id = get_changes.dealer_id
              AND vi.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'vehicles', CASE WHEN can_view_inventory THEN COALESCE((
            SELECT jsonb_agg(row_to_json(v))
            FROM crm.vehicles v
            WHERE v.dealer_id = get_changes.dealer_id
              AND v.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'templates', CASE WHEN can_view_expenses THEN COALESCE((
            SELECT jsonb_agg(row_to_json(t))
            FROM crm.expense_templates t
            WHERE t.dealer_id = get_changes.dealer_id
              AND t.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'expenses', CASE WHEN can_view_expenses THEN COALESCE((
            SELECT jsonb_agg(row_to_json(e))
            FROM crm.expenses e
            WHERE e.dealer_id = get_changes.dealer_id
              AND e.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'sales', CASE WHEN can_view_sales THEN COALESCE((
            SELECT jsonb_agg(row_to_json(s))
            FROM crm.sales s
            WHERE s.dealer_id = get_changes.dealer_id
              AND s.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'debts', CASE WHEN can_view_financials THEN COALESCE((
            SELECT jsonb_agg(row_to_json(d))
            FROM crm.debts d
            WHERE d.dealer_id = get_changes.dealer_id
              AND d.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'debt_payments', CASE WHEN can_view_financials THEN COALESCE((
            SELECT jsonb_agg(row_to_json(dp))
            FROM crm.debt_payments dp
            WHERE dp.dealer_id = get_changes.dealer_id
              AND dp.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'clients', CASE WHEN can_view_leads THEN COALESCE((
            SELECT jsonb_agg(row_to_json(c))
            FROM crm.dealer_clients c
            WHERE c.dealer_id = get_changes.dealer_id
              AND c.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'client_interactions', CASE WHEN can_view_leads THEN COALESCE((
            SELECT jsonb_agg(row_to_json(ci))
            FROM crm.client_interactions ci
            WHERE ci.dealer_id = get_changes.dealer_id
              AND ci.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'client_reminders', CASE WHEN can_view_leads THEN COALESCE((
            SELECT jsonb_agg(row_to_json(cr))
            FROM crm.client_reminders cr
            WHERE cr.dealer_id = get_changes.dealer_id
              AND cr.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'parts', CASE WHEN can_view_parts THEN COALESCE((
            SELECT jsonb_agg(row_to_json(p))
            FROM public.crm_parts p
            WHERE p.dealer_id = get_changes.dealer_id
              AND p.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'part_batches', CASE WHEN can_view_parts THEN COALESCE((
            SELECT jsonb_agg(row_to_json(pb))
            FROM public.crm_part_batches pb
            WHERE pb.dealer_id = get_changes.dealer_id
              AND pb.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'part_sales', CASE WHEN can_view_part_sales THEN COALESCE((
            SELECT jsonb_agg(row_to_json(ps))
            FROM public.crm_part_sales ps
            WHERE ps.dealer_id = get_changes.dealer_id
              AND ps.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END,
        'part_sale_line_items', CASE WHEN can_view_part_sales THEN COALESCE((
            SELECT jsonb_agg(row_to_json(psl))
            FROM public.crm_part_sale_line_items psl
            WHERE psl.dealer_id = get_changes.dealer_id
              AND psl.server_updated_at >= since_ts
        ), '[]'::jsonb) ELSE '[]'::jsonb END
    ) INTO result;

    RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_vehicle_income_entries(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_crm_vehicle_income_entries(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_vehicle_income_entries(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_crm_vehicle_income_entries(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_changes(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
