CREATE OR REPLACE FUNCTION public.get_my_role(_org_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO public, auth, pg_temp
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_role text;
BEGIN
    IF v_uid IS NULL OR _org_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.organizations
        WHERE id = _org_id
          AND owner_id = v_uid
    ) THEN
        RETURN 'owner';
    END IF;

    SELECT dtm.role::text
    INTO v_role
    FROM public.dealer_team_members dtm
    WHERE dtm.organization_id = _org_id
      AND dtm.user_id = v_uid
      AND COALESCE(dtm.status, 'active') = 'active'
    ORDER BY dtm.created_at ASC
    LIMIT 1;

    RETURN v_role;
END;
$function$;
