-- ============================================
-- 05_MULTI_ORG_TESTS.sql
-- Multi-Organization Support Tests
-- ============================================
-- Tests: Same user in multiple orgs with different roles
-- ============================================

\echo '============================================'
\echo 'MULTI-ORG TESTS - Same User, Multiple Orgs'
\echo '============================================'

-- ============================================
-- TEST 1: User can be in multiple organizations
-- ============================================
\echo ''
\echo 'TEST 1: Multi-Org Membership'

DO $$
DECLARE
    v_user_id uuid := gen_random_uuid();
    v_org_a uuid := gen_random_uuid();
    v_org_b uuid := gen_random_uuid();
    v_count int;
BEGIN
    -- Add user to Org A as Owner
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_a, v_user_id, 'owner', 'active');
    
    -- Add SAME user to Org B as Sales
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_b, v_user_id, 'sales', 'active');
    
    -- Verify user is in both orgs
    SELECT COUNT(*) INTO v_count
    FROM public.dealer_team_members
    WHERE user_id = v_user_id;
    
    IF v_count = 2 THEN
        RAISE NOTICE '✅ PASS: User successfully added to 2 organizations';
    ELSE
        RAISE NOTICE '❌ FAIL: Expected 2 memberships, found %', v_count;
    END IF;
    
    -- Cleanup
    DELETE FROM public.dealer_team_members WHERE user_id = v_user_id;
END $$;

-- ============================================
-- TEST 2: Different permissions per organization
-- ============================================
\echo ''
\echo 'TEST 2: Per-Org Permission Isolation'

DO $$
DECLARE
    v_user_id uuid := gen_random_uuid();
    v_org_owner uuid := gen_random_uuid();
    v_org_employee uuid := gen_random_uuid();
    v_result boolean;
BEGIN
    -- User is OWNER in org_owner
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_owner, v_user_id, 'owner', 'active');
    
    -- User is SALES in org_employee
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_employee, v_user_id, 'sales', 'active');
    
    -- Should have full access in owned org
    SELECT has_permission(v_user_id, v_org_owner, 'view_financials') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: User has view_financials in OWNED org';
    ELSE
        RAISE NOTICE '❌ FAIL: User should have full access in owned org';
    END IF;
    
    SELECT has_permission(v_user_id, v_org_owner, 'manage_team') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: User has manage_team in OWNED org';
    ELSE
        RAISE NOTICE '❌ FAIL: User should have manage_team in owned org';
    END IF;
    
    -- Should have LIMITED access in employee org
    SELECT has_permission(v_user_id, v_org_employee, 'view_financials') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: User does NOT have view_financials in EMPLOYEE org (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales role should not have view_financials!';
    END IF;
    
    SELECT has_permission(v_user_id, v_org_employee, 'manage_team') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: User does NOT have manage_team in EMPLOYEE org (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales role should not have manage_team!';
    END IF;
    
    SELECT has_permission(v_user_id, v_org_employee, 'view_inventory') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: User HAS view_inventory in EMPLOYEE org';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales role should have view_inventory';
    END IF;
    
    -- Cleanup
    DELETE FROM public.dealer_team_members WHERE user_id = v_user_id;
END $$;

-- ============================================  
-- TEST 3: UNIQUE constraint prevents duplicate membership
-- ============================================
\echo ''
\echo 'TEST 3: Duplicate Membership Prevention'

DO $$
DECLARE
    v_user_id uuid := gen_random_uuid();
    v_org_id uuid := gen_random_uuid();
BEGIN
    -- Add user first time
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_id, v_user_id, 'owner', 'active');
    
    -- Try to add same user to same org again
    BEGIN
        INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
        VALUES (v_org_id, v_user_id, 'sales', 'active');
        
        -- If we get here, constraint failed
        RAISE NOTICE '❌ FAIL: Duplicate membership allowed!';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE '✅ PASS: Duplicate membership correctly prevented';
    END;
    
    -- Cleanup
    DELETE FROM public.dealer_team_members WHERE user_id = v_user_id;
END $$;

-- ============================================
-- TEST 4: Verify constraint exists
-- ============================================
\echo ''
\echo 'TEST 4: UNIQUE Constraint Verification'

SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE table_name = 'dealer_team_members' 
            AND constraint_type = 'UNIQUE'
            AND constraint_name LIKE '%organization_id_user_id%'
        ) 
        THEN '✅ PASS: UNIQUE constraint on (org_id, user_id) exists'
        ELSE '⚠️ WARNING: UNIQUE constraint may be named differently'
    END as result;

\echo ''
\echo '============================================'
\echo 'MULTI-ORG TESTS COMPLETED'
\echo '============================================'
