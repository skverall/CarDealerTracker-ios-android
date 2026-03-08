DO $$
DECLARE
    signature text;
    signatures text[] := ARRAY[
        'public.delete_crm_dealer_users()',
        'public.delete_crm_expenses()',
        'public.delete_crm_financial_accounts()',
        'public.delete_crm_sales()',
        'public.delete_crm_vehicles()',
        'public.insert_crm_dealer_users()',
        'public.insert_crm_expenses()',
        'public.insert_crm_financial_accounts()',
        'public.insert_crm_sales()',
        'public.insert_crm_vehicles()',
        'public.update_crm_expenses()',
        'public.update_crm_sales()',
        'public.update_crm_vehicles()',
        'public.upsert_crm_dealer_clients(jsonb)',
        'public.upsert_crm_dealer_users(jsonb)',
        'public.upsert_crm_expense_templates(jsonb)',
        'public.upsert_crm_expenses(jsonb)',
        'public.upsert_crm_financial_accounts(jsonb)',
        'public.upsert_crm_sales(jsonb)',
        'public.upsert_crm_vehicles(jsonb)',
        'public.sync_public_dealer_clients_to_crm()',
        'public.sync_crm_dealer_clients_to_public()',
        'public.sync_vehicles_financials()',
        'public.sync_sales_financials()',
        'public.create_vehicle_share_link(uuid, uuid, text, text)',
        'public.get_my_permissions(uuid)',
        'public.get_my_role(uuid)'
    ];
BEGIN
    FOREACH signature IN ARRAY signatures
    LOOP
        IF to_regprocedure(signature) IS NOT NULL THEN
            EXECUTE format(
                'ALTER FUNCTION %s SET search_path TO public, crm, pg_temp',
                signature
            );
        END IF;
    END LOOP;
END $$;
