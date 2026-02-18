CREATE OR REPLACE FUNCTION public.get_changes(dealer_id uuid, since text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    since_ts timestamptz;
    result jsonb;
BEGIN
    since_ts := since::timestamptz;

    SELECT jsonb_build_object(
        'server_now', now(),
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
$function$;

GRANT EXECUTE ON FUNCTION public.get_changes(uuid, text) TO authenticated;
