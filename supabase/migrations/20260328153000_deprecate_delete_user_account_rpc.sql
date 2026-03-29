CREATE OR REPLACE FUNCTION public.delete_user_account(user_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path TO public, pg_temp
AS $function$
BEGIN
    RAISE EXCEPTION 'delete_user_account RPC is deprecated. Use the delete_account edge function.';
END;
$function$;
