-- ============================================================================
-- Create the crm_can_access helper function for RLS policies
-- This function checks if the current authenticated user can access a dealer
-- ============================================================================

-- Drop any existing version first to ensure clean creation
DROP FUNCTION IF EXISTS public.crm_can_access(uuid);

CREATE OR REPLACE FUNCTION public.crm_can_access(p_dealer_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    -- If no user is authenticated, deny access
    IF v_uid IS NULL THEN
        RETURN false;
    END IF;
    
    -- Check direct ownership first.
    RETURN EXISTS (
        SELECT 1 
        FROM public.organizations o
        WHERE o.id = p_dealer_id
          AND (
              o.owner_id = v_uid
              OR EXISTS (
                  SELECT 1
                  FROM public.dealer_team_members dtm
                  WHERE dtm.organization_id = o.id
                    AND dtm.user_id = v_uid
                    AND dtm.status = 'active'
              )
          )
    );
END;
$function$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.crm_can_access(uuid) TO authenticated;
