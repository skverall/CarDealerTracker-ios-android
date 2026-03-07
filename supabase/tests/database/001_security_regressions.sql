begin;

create schema if not exists extensions;
create extension if not exists pgtap with schema extensions;

select plan(22);

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

select * from finish();
rollback;
