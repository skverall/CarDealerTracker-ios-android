CREATE OR REPLACE FUNCTION public.crm_is_service_role()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO public, pg_temp
AS $function$
DECLARE
    v_claim_role text := current_setting('request.jwt.claim.role', true);
    v_claims text := current_setting('request.jwt.claims', true);
    v_claims_json jsonb;
BEGIN
    IF v_claim_role = 'service_role' THEN
        RETURN true;
    END IF;

    IF v_claims IS NOT NULL AND btrim(v_claims) <> '' THEN
        BEGIN
            v_claims_json := v_claims::jsonb;
            IF v_claims_json ->> 'role' = 'service_role' THEN
                RETURN true;
            END IF;
        EXCEPTION WHEN others THEN
            RETURN false;
        END;
    END IF;

    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crm_effective_permission(p_dealer_id uuid, p_perm_key text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, pg_temp
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_role text;
    v_permissions jsonb := '{}'::jsonb;
    v_perm text := lower(coalesce(p_perm_key, ''));
    v_default boolean := false;
BEGIN
    IF public.crm_is_service_role() THEN
        RETURN true;
    END IF;

    IF v_uid IS NULL OR p_dealer_id IS NULL OR v_perm = '' THEN
        RETURN false;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.organizations o
        WHERE o.id = p_dealer_id
          AND o.owner_id = v_uid
    ) THEN
        RETURN true;
    END IF;

    SELECT dtm.role::text, COALESCE(dtm.permissions, '{}'::jsonb)
    INTO v_role, v_permissions
    FROM public.dealer_team_members dtm
    WHERE dtm.organization_id = p_dealer_id
      AND dtm.user_id = v_uid
      AND COALESCE(dtm.status, 'active') = 'active'
    ORDER BY dtm.created_at ASC
    LIMIT 1;

    IF v_role IS NULL THEN
        RETURN false;
    END IF;

    IF jsonb_typeof(v_permissions -> 'all') = 'boolean'
       AND (v_permissions ->> 'all')::boolean THEN
        RETURN true;
    END IF;

    CASE lower(v_role)
        WHEN 'owner' THEN
            v_default := true;
        WHEN 'admin' THEN
            v_default := v_perm IN (
                'view_inventory',
                'create_sale',
                'view_parts_inventory',
                'manage_parts_inventory',
                'create_part_sale',
                'view_leads',
                'view_expenses',
                'view_vehicle_cost',
                'view_vehicle_profit',
                'view_part_cost',
                'view_part_profit',
                'view_financials',
                'manage_team',
                'delete_records'
            );
        WHEN 'sales' THEN
            v_default := v_perm IN (
                'view_inventory',
                'create_sale',
                'view_parts_inventory',
                'create_part_sale',
                'view_leads',
                'view_expenses'
            );
        WHEN 'viewer' THEN
            v_default := v_perm IN (
                'view_inventory',
                'view_parts_inventory'
            );
        ELSE
            v_default := false;
    END CASE;

    IF jsonb_typeof(v_permissions -> v_perm) = 'boolean' THEN
        RETURN (v_permissions ->> v_perm)::boolean;
    END IF;

    RETURN v_default;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crm_effective_any_permission(p_dealer_id uuid, p_perm_keys text[])
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO public, auth, pg_temp
AS $function$
DECLARE
    v_perm text;
BEGIN
    IF p_perm_keys IS NULL OR array_length(p_perm_keys, 1) IS NULL THEN
        RETURN false;
    END IF;

    FOREACH v_perm IN ARRAY p_perm_keys
    LOOP
        IF public.crm_effective_permission(p_dealer_id, v_perm) THEN
            RETURN true;
        END IF;
    END LOOP;

    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assert_crm_permission(p_dealer_id uuid, p_perm_keys text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    IF NOT public.crm_effective_any_permission(p_dealer_id, p_perm_keys) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CRM_PERMISSION_DENIED';
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.crm_is_service_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_effective_permission(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_effective_any_permission(uuid, text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assert_crm_permission(uuid, text[]) TO authenticated, service_role;

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

DROP TRIGGER IF EXISTS trg_crm_dealer_users_permission_guard ON crm.dealer_users;
CREATE TRIGGER trg_crm_dealer_users_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.dealer_users
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_financial_accounts_permission_guard ON crm.financial_accounts;
CREATE TRIGGER trg_crm_financial_accounts_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.financial_accounts
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_account_transactions_permission_guard ON crm.account_transactions;
CREATE TRIGGER trg_crm_account_transactions_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.account_transactions
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_vehicles_permission_guard ON crm.vehicles;
CREATE TRIGGER trg_crm_vehicles_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.vehicles
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_expense_templates_permission_guard ON crm.expense_templates;
CREATE TRIGGER trg_crm_expense_templates_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.expense_templates
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_expenses_permission_guard ON crm.expenses;
CREATE TRIGGER trg_crm_expenses_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.expenses
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_sales_permission_guard ON crm.sales;
CREATE TRIGGER trg_crm_sales_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.sales
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_debts_permission_guard ON crm.debts;
CREATE TRIGGER trg_crm_debts_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.debts
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_debt_payments_permission_guard ON crm.debt_payments;
CREATE TRIGGER trg_crm_debt_payments_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.debt_payments
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_dealer_clients_permission_guard ON crm.dealer_clients;
CREATE TRIGGER trg_crm_dealer_clients_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.dealer_clients
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_client_interactions_permission_guard ON crm.client_interactions;
CREATE TRIGGER trg_crm_client_interactions_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.client_interactions
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_client_reminders_permission_guard ON crm.client_reminders;
CREATE TRIGGER trg_crm_client_reminders_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON crm.client_reminders
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_parts_permission_guard ON public.crm_parts;
CREATE TRIGGER trg_crm_parts_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.crm_parts
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_part_batches_permission_guard ON public.crm_part_batches;
CREATE TRIGGER trg_crm_part_batches_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.crm_part_batches
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_part_sales_permission_guard ON public.crm_part_sales;
CREATE TRIGGER trg_crm_part_sales_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.crm_part_sales
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

DROP TRIGGER IF EXISTS trg_crm_part_sale_line_items_permission_guard ON public.crm_part_sale_line_items;
CREATE TRIGGER trg_crm_part_sale_line_items_permission_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.crm_part_sale_line_items
FOR EACH ROW EXECUTE FUNCTION public.crm_assert_write_permission();

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

GRANT EXECUTE ON FUNCTION public.get_changes(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_vehicle_share_link(
    p_vehicle_id uuid,
    p_dealer_id uuid,
    p_contact_phone text,
    p_contact_whatsapp text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    v_id uuid;
    v_vehicle_exists boolean;
BEGIN
    PERFORM public.assert_crm_permission(p_dealer_id, ARRAY['view_inventory']);

    SELECT true INTO v_vehicle_exists
    FROM crm.vehicles v
    WHERE v.id = p_vehicle_id
      AND v.dealer_id = p_dealer_id
      AND v.deleted_at IS NULL
    LIMIT 1;

    IF COALESCE(v_vehicle_exists, false) IS NOT TRUE THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'VEHICLE_SHARE_ACCESS_DENIED';
    END IF;

    SELECT id INTO v_id
    FROM crm.vehicle_share_links
    WHERE vehicle_id = p_vehicle_id
      AND dealer_id = p_dealer_id
      AND is_active = true
    LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO crm.vehicle_share_links (
            dealer_id,
            vehicle_id,
            contact_phone,
            contact_whatsapp,
            created_at,
            updated_at,
            last_shared_at
        ) VALUES (
            p_dealer_id,
            p_vehicle_id,
            p_contact_phone,
            p_contact_whatsapp,
            now(),
            now(),
            now()
        ) RETURNING id INTO v_id;
    ELSE
        UPDATE crm.vehicle_share_links
        SET contact_phone = p_contact_phone,
            contact_whatsapp = p_contact_whatsapp,
            updated_at = now(),
            last_shared_at = now()
        WHERE id = v_id;
    END IF;

    RETURN v_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_vehicle_share_link(uuid, uuid, text, text) TO authenticated;
