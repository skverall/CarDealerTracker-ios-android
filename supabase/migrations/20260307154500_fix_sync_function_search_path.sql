DO $$
DECLARE
    signature text;
    crm_signatures text[] := ARRAY[
        'crm.sync_expense_description()',
        'crm.sync_sales_amount()',
        'crm.update_updated_at_column()'
    ];
    public_signatures text[] := ARRAY[
        'public.add_sync_columns(text, text)',
        'public.update_crm_dealer_clients()',
        'public.update_crm_dealer_users()',
        'public.update_crm_expense_templates()',
        'public.update_crm_financial_accounts()',
        'public.update_server_updated_at()',
        'public.update_updated_at_column()'
    ];
BEGIN
    FOREACH signature IN ARRAY crm_signatures
    LOOP
        IF to_regprocedure(signature) IS NOT NULL THEN
            EXECUTE format(
                'ALTER FUNCTION %s SET search_path TO crm, public, pg_temp',
                signature
            );
        END IF;
    END LOOP;

    FOREACH signature IN ARRAY public_signatures
    LOOP
        IF to_regprocedure(signature) IS NOT NULL THEN
            EXECUTE format(
                'ALTER FUNCTION %s SET search_path TO public, crm, pg_temp',
                signature
            );
        END IF;
    END LOOP;
END $$;
