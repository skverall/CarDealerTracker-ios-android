CREATE TABLE IF NOT EXISTS public.team_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
    email text,
    role public.app_role DEFAULT 'viewer'::public.app_role,
    token text,
    status text DEFAULT 'pending',
    permissions jsonb DEFAULT '{}'::jsonb,
    created_by uuid,
    created_at timestamptz DEFAULT now(),
    expires_at timestamptz,
    accepted_at timestamptz,
    updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS email text;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS role public.app_role DEFAULT 'viewer'::public.app_role;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS token text;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS permissions jsonb DEFAULT '{}'::jsonb;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS created_by uuid;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS accepted_at timestamptz;

ALTER TABLE public.team_invitations
    ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'team_invitations'
          AND column_name = 'permissions'
          AND udt_name = 'jsonb'
    ) THEN
        ALTER TABLE public.team_invitations
            ALTER COLUMN permissions SET DEFAULT '{}'::jsonb;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'team_invitations'
          AND column_name = 'status'
    ) THEN
        ALTER TABLE public.team_invitations
            ALTER COLUMN status SET DEFAULT 'pending';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'team_invitations'
          AND column_name = 'updated_at'
          AND udt_name = 'timestamptz'
    ) THEN
        ALTER TABLE public.team_invitations
            ALTER COLUMN updated_at SET DEFAULT now();
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS team_invitations_token_key
    ON public.team_invitations (token)
    WHERE token IS NOT NULL;

CREATE INDEX IF NOT EXISTS team_invitations_org_email_idx
    ON public.team_invitations (organization_id, lower(email));

CREATE INDEX IF NOT EXISTS team_invitations_expires_idx
    ON public.team_invitations (expires_at);

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'has_permission'
          AND pg_get_function_identity_arguments(p.oid) = '_user_id uuid, _org_id uuid, _perm_key text'
    ) THEN
        EXECUTE $create_function$
CREATE FUNCTION public.has_permission(
    _user_id uuid,
    _org_id uuid,
    _perm_key text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO public
AS $function$
DECLARE
    _role public.app_role;
    _permissions jsonb;
    _perm text := lower(_perm_key);
BEGIN
    SELECT role, permissions
    INTO _role, _permissions
    FROM public.dealer_team_members
    WHERE user_id = _user_id
      AND organization_id = _org_id;

    IF _role IS NULL THEN
        RETURN false;
    END IF;

    IF _role = 'owner' THEN
        RETURN true;
    END IF;

    _permissions := COALESCE(_permissions, '{}'::jsonb);

    IF _perm IN ('view_financials', 'view_vehicle_cost', 'view_vehicle_profit') THEN
        RETURN false;
    END IF;

    IF _permissions ? _perm THEN
        RETURN (_permissions ->> _perm)::boolean;
    END IF;

    IF _role = 'admin' THEN
        RETURN _perm IN ('view_inventory', 'create_sale', 'view_leads', 'view_expenses', 'manage_team', 'delete_records');
    END IF;

    IF _role = 'sales' THEN
        RETURN _perm IN ('view_inventory', 'create_sale', 'view_leads', 'view_expenses');
    END IF;

    IF _role = 'viewer' THEN
        RETURN _perm IN ('view_inventory');
    END IF;

    RETURN false;
END;
$function$;
$create_function$;
    END IF;
END;
$migration$;

REVOKE ALL ON FUNCTION public.has_permission(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_permission(uuid, uuid, text) TO authenticated, service_role;
