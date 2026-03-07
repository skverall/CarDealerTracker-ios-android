ALTER FUNCTION crm.sync_expense_description()
    SET search_path TO crm, public, pg_temp;

ALTER FUNCTION crm.sync_sales_amount()
    SET search_path TO crm, public, pg_temp;

ALTER FUNCTION crm.update_updated_at_column()
    SET search_path TO crm, public, pg_temp;

ALTER FUNCTION public.add_sync_columns(text, text)
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_crm_dealer_clients()
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_crm_dealer_users()
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_crm_expense_templates()
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_crm_financial_accounts()
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_server_updated_at()
    SET search_path TO public, crm, pg_temp;

ALTER FUNCTION public.update_updated_at_column()
    SET search_path TO public, crm, pg_temp;
