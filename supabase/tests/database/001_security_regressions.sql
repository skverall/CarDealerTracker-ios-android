begin;

create schema if not exists extensions;
create extension if not exists pgtap with schema extensions;

select plan(30);

select is(
  (
    select n.nspname
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'moddatetime'
  ),
  'extensions',
  'moddatetime should live in extensions schema'
);

select ok(
  (
    select coalesce(reloptions, array[]::text[]) @> array['security_invoker=true']
    from pg_class
    where oid = 'public.safe_profiles'::regclass
  ),
  'safe_profiles should use security_invoker'
);

select ok(
  (
    select coalesce(reloptions, array[]::text[]) @> array['security_invoker=true']
    from pg_class
    where oid = 'public.public_profiles'::regclass
  ),
  'public_profiles should use security_invoker'
);

select ok(
  (
    select coalesce(reloptions, array[]::text[]) @> array['security_invoker=true']
    from pg_class
    where oid = 'public.vehicle_share_links'::regclass
  ),
  'vehicle_share_links should use security_invoker'
);

select ok(
  has_table_privilege('anon', 'public.vin_checks', 'INSERT'),
  'anon should keep INSERT on vin_checks'
);

select ok(
  not has_table_privilege('anon', 'public.vin_checks', 'SELECT'),
  'anon should not have SELECT on vin_checks'
);

select policies_are(
  'public',
  'vin_checks',
  array['Public can submit vin checks'],
  'vin_checks should expose only the public submit policy'
);

select is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admin_sessions'
      and policyname = 'Allow admin functions access to sessions'
  ),
  0,
  'admin_sessions permissive policy should be removed'
);

select policies_are(
  'public',
  'team_invite_codes',
  array['No direct API access'],
  'team_invite_codes should stay deny-only'
);

select policies_are(
  'public',
  'user_favorites',
  array['No direct API access'],
  'user_favorites should stay deny-only'
);

select ok(
  not has_function_privilege('anon', 'public.get_admin_dashboard_stats()', 'EXECUTE'),
  'anon should not execute old dashboard RPC'
);

select ok(
  has_function_privilege('anon', 'public.get_admin_dashboard_stats(text)', 'EXECUTE'),
  'anon should execute token-gated dashboard RPC'
);

select ok(
  not has_function_privilege('anon', 'public.admin_delete_listing(uuid, uuid, text)', 'EXECUTE'),
  'anon should not execute old admin_delete_listing RPC'
);

select ok(
  has_function_privilege('anon', 'public.admin_delete_listing(text, uuid, uuid, text)', 'EXECUTE'),
  'anon should execute token-gated admin_delete_listing RPC'
);

select ok(
  not has_function_privilege('anon', 'public.delete_user_account(uuid)', 'EXECUTE'),
  'anon should not execute delete_user_account'
);

select ok(
  has_function_privilege('authenticated', 'public.delete_user_account(uuid)', 'EXECUTE'),
  'authenticated should execute delete_user_account'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.get_changes(uuid,text)'::regprocedure
  ),
  'get_changes should run as invoker'
);

select is(
  (
    select array_to_string(proconfig, ',')
    from pg_proc
    where oid = 'public.get_changes(uuid,text)'::regprocedure
  ),
  'search_path=public, crm, pg_temp',
  'get_changes should pin search_path'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.sync_vehicles(jsonb)'::regprocedure
  ),
  'sync_vehicles should run as invoker'
);

select is(
  (
    select array_to_string(proconfig, ',')
    from pg_proc
    where oid = 'public.sync_vehicles(jsonb)'::regprocedure
  ),
  'search_path=public, crm, pg_temp',
  'sync_vehicles should pin search_path'
);

select is(
  (
    select array_to_string(proconfig, ',')
    from pg_proc
    where oid = 'public.require_admin_session(text,uuid)'::regprocedure
  ),
  'search_path=public, auth, extensions, pg_temp',
  'require_admin_session should pin search_path'
);

select is(
  (
    select array_to_string(proconfig, ',')
    from pg_proc
    where oid = 'public.get_users_for_admin(text,integer,integer,text,text,text,text)'::regprocedure
  ),
  'search_path=public, auth, extensions, pg_temp',
  'token-gated admin user listing RPC should pin search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.assert_crm_permission(uuid,text[])', 'EXECUTE'),
  'authenticated should execute assert_crm_permission'
);

select ok(
  pg_get_functiondef('public.get_changes(uuid,text)'::regprocedure) like '%crm_effective_permission%',
  'get_changes should enforce effective permission filters'
);

select ok(
  pg_get_functiondef('public.get_changes(uuid,text)'::regprocedure) like '%CASE WHEN can_view_financials%',
  'get_changes should keep snapshot keys while filtering financial data'
);

select ok(
  pg_get_functiondef('public.create_vehicle_share_link(uuid,uuid,text,text)'::regprocedure) like '%assert_crm_permission%',
  'create_vehicle_share_link should check CRM permissions'
);

select ok(
  pg_get_functiondef('public.create_vehicle_share_link(uuid,uuid,text,text)'::regprocedure) like '%v.dealer_id = p_dealer_id%',
  'create_vehicle_share_link should verify vehicle ownership'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'crm.sales'::regclass
      and tgname = 'trg_crm_sales_permission_guard'
      and not tgisinternal
  ),
  'crm.sales should have a write permission guard trigger'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'crm.vehicles'::regclass
      and tgname = 'trg_crm_vehicles_permission_guard'
      and not tgisinternal
  ),
  'crm.vehicles should have a write permission guard trigger'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.crm_part_sales'::regclass
      and tgname = 'trg_crm_part_sales_permission_guard'
      and not tgisinternal
  ),
  'crm_part_sales should have a write permission guard trigger'
);

select * from finish();
rollback;
