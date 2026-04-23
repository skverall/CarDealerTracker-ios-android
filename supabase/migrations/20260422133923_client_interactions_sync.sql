CREATE TABLE IF NOT EXISTS crm.client_interactions (
    id uuid PRIMARY KEY,
    dealer_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    client_id uuid NOT NULL REFERENCES crm.dealer_clients(id) ON DELETE CASCADE,
    title text,
    detail text,
    occurred_at timestamptz NOT NULL,
    stage text NOT NULL DEFAULT 'update',
    value numeric,
    interaction_type text,
    outcome text,
    duration_minutes integer NOT NULL DEFAULT 0,
    is_follow_up_required boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    server_updated_at timestamptz NOT NULL DEFAULT now(),
    last_modified_by uuid
);

CREATE INDEX IF NOT EXISTS idx_crm_client_interactions_dealer_id
    ON crm.client_interactions (dealer_id);

CREATE INDEX IF NOT EXISTS idx_crm_client_interactions_client_id
    ON crm.client_interactions (client_id);

CREATE INDEX IF NOT EXISTS idx_crm_client_interactions_updated_at
    ON crm.client_interactions (updated_at);

CREATE INDEX IF NOT EXISTS idx_crm_client_interactions_server_updated_at
    ON crm.client_interactions (server_updated_at);

DROP TRIGGER IF EXISTS trg_crm_client_interactions_server_updated_at
    ON crm.client_interactions;

CREATE TRIGGER trg_crm_client_interactions_server_updated_at
    BEFORE INSERT OR UPDATE ON crm.client_interactions
    FOR EACH ROW
    EXECUTE FUNCTION public.update_server_updated_at();

CREATE OR REPLACE VIEW public.crm_client_interactions AS
SELECT *
FROM crm.client_interactions;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_client_interactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON crm.client_interactions TO authenticated;

ALTER TABLE crm.client_interactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "crm_client_interactions_select" ON crm.client_interactions;
CREATE POLICY "crm_client_interactions_select" ON crm.client_interactions
    FOR SELECT
    USING (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_client_interactions_insert" ON crm.client_interactions;
CREATE POLICY "crm_client_interactions_insert" ON crm.client_interactions
    FOR INSERT
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_client_interactions_update" ON crm.client_interactions;
CREATE POLICY "crm_client_interactions_update" ON crm.client_interactions
    FOR UPDATE
    USING (public.crm_can_access(dealer_id))
    WITH CHECK (public.crm_can_access(dealer_id));

DROP POLICY IF EXISTS "crm_client_interactions_delete" ON crm.client_interactions;
CREATE POLICY "crm_client_interactions_delete" ON crm.client_interactions
    FOR DELETE
    USING (public.crm_can_access(dealer_id));

CREATE OR REPLACE FUNCTION public.sync_client_interactions(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
DECLARE
    item jsonb;
    result_record crm.client_interactions%ROWTYPE;
    results jsonb := '[]'::jsonb;
    v_dealer_id uuid;
BEGIN
    FOR item IN
        SELECT *
        FROM jsonb_array_elements(COALESCE(payload, '[]'::jsonb))
    LOOP
        v_dealer_id := (item->>'dealer_id')::uuid;
        PERFORM public.assert_crm_access(v_dealer_id);

        INSERT INTO crm.client_interactions (
            id,
            dealer_id,
            client_id,
            title,
            detail,
            occurred_at,
            stage,
            value,
            interaction_type,
            outcome,
            duration_minutes,
            is_follow_up_required,
            created_at,
            updated_at,
            deleted_at
        )
        VALUES (
            (item->>'id')::uuid,
            v_dealer_id,
            (item->>'client_id')::uuid,
            item->>'title',
            item->>'detail',
            (item->>'occurred_at')::timestamptz,
            COALESCE(NULLIF(item->>'stage', ''), 'update'),
            NULLIF(item->>'value', '')::numeric,
            item->>'interaction_type',
            item->>'outcome',
            COALESCE(NULLIF(item->>'duration_minutes', '')::integer, 0),
            COALESCE((item->>'is_follow_up_required')::boolean, false),
            (item->>'created_at')::timestamptz,
            (item->>'updated_at')::timestamptz,
            (item->>'deleted_at')::timestamptz
        )
        ON CONFLICT (id) DO UPDATE
        SET client_id = EXCLUDED.client_id,
            title = EXCLUDED.title,
            detail = EXCLUDED.detail,
            occurred_at = EXCLUDED.occurred_at,
            stage = EXCLUDED.stage,
            value = EXCLUDED.value,
            interaction_type = EXCLUDED.interaction_type,
            outcome = EXCLUDED.outcome,
            duration_minutes = EXCLUDED.duration_minutes,
            is_follow_up_required = EXCLUDED.is_follow_up_required,
            updated_at = EXCLUDED.updated_at,
            deleted_at = EXCLUDED.deleted_at
        WHERE crm.client_interactions.dealer_id = EXCLUDED.dealer_id
          AND crm.client_interactions.updated_at < EXCLUDED.updated_at
        RETURNING * INTO result_record;

        IF NOT FOUND THEN
            SELECT *
            INTO result_record
            FROM crm.client_interactions
            WHERE id = (item->>'id')::uuid
              AND dealer_id = v_dealer_id;
        END IF;

        results := results || to_jsonb(result_record);
    END LOOP;

    RETURN results;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_crm_client_interactions(p_id uuid, p_dealer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO public, crm, pg_temp
AS $function$
BEGIN
    PERFORM public.assert_crm_access(p_dealer_id);

    UPDATE crm.client_interactions
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
        'client_interactions', COALESCE((
            SELECT jsonb_agg(row_to_json(ci))
            FROM crm.client_interactions ci
            WHERE ci.dealer_id = get_changes.dealer_id
              AND ci.server_updated_at >= since_ts
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

GRANT EXECUTE ON FUNCTION public.sync_client_interactions(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_client_interactions(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_changes(uuid, text) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_crm_client_interactions_dealer_server_sync
    ON crm.client_interactions (dealer_id, server_updated_at);
