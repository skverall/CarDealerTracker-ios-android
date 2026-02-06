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
    
    -- If the dealer_id matches the user's ID (personal organization case), allow access
    -- This is the common pattern where user.id == organization.id for personal accounts
    IF p_dealer_id = v_uid THEN
        RETURN true;
    END IF;
    
    -- Check via the get_my_organizations RPC pattern
    -- User has access if they are a member of the organization
    RETURN EXISTS (
        SELECT 1 
        FROM public.organizations o
        WHERE o.id = p_dealer_id
          AND EXISTS (
              SELECT 1 
              FROM public.organization_members om
              WHERE om.organization_id = o.id 
                AND om.user_id = v_uid
                AND om.status = 'active'
          )
    );
END;
$function$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.crm_can_access(uuid) TO authenticated;
