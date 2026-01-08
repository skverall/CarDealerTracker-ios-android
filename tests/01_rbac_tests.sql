-- ============================================
-- 01_RBAC_TESTS.sql
-- Role-Based Access Control Tests
-- ============================================
-- Tests: Permissions, Roles, has_permission function
-- ============================================

\echo '============================================'
\echo 'RBAC TESTS - Role-Based Access Control'
\echo '============================================'

-- Setup: Create test data
DO $$
DECLARE
    v_owner_id uuid := gen_random_uuid();
    v_admin_id uuid := gen_random_uuid();
    v_sales_id uuid := gen_random_uuid();
    v_viewer_id uuid := gen_random_uuid();
    v_org_id uuid := gen_random_uuid();
    v_result boolean;
BEGIN
    -- Create test organization (use existing dealer as org)
    -- We'll use the org_id directly in tests

    -- Insert test team members
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES 
        (v_org_id, v_owner_id, 'owner', 'active'),
        (v_org_id, v_admin_id, 'admin', 'active'),
        (v_org_id, v_sales_id, 'sales', 'active'),
        (v_org_id, v_viewer_id, 'viewer', 'active')
    ON CONFLICT DO NOTHING;

    -- ============================================
    -- TEST 1: Owner has ALL permissions
    -- ============================================
    \echo ''
    \echo 'TEST 1: Owner Permissions'
    
    SELECT has_permission(v_owner_id, v_org_id, 'view_financials') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Owner has view_financials';
    ELSE
        RAISE NOTICE '❌ FAIL: Owner should have view_financials';
    END IF;

    SELECT has_permission(v_owner_id, v_org_id, 'view_expenses') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Owner has view_expenses';
    ELSE
        RAISE NOTICE '❌ FAIL: Owner should have view_expenses';
    END IF;

    SELECT has_permission(v_owner_id, v_org_id, 'manage_team') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Owner has manage_team';
    ELSE
        RAISE NOTICE '❌ FAIL: Owner should have manage_team';
    END IF;

    -- ============================================
    -- TEST 2: Admin permissions (similar to owner, no manage_team by default)
    -- ============================================
    \echo ''
    \echo 'TEST 2: Admin Permissions'
    
    SELECT has_permission(v_admin_id, v_org_id, 'view_financials') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Admin has view_financials';
    ELSE
        RAISE NOTICE '❌ FAIL: Admin should have view_financials';
    END IF;

    SELECT has_permission(v_admin_id, v_org_id, 'view_expenses') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Admin has view_expenses';
    ELSE
        RAISE NOTICE '❌ FAIL: Admin should have view_expenses';
    END IF;

    -- ============================================
    -- TEST 3: Sales role - LIMITED permissions
    -- ============================================
    \echo ''
    \echo 'TEST 3: Sales Permissions (Limited)'
    
    SELECT has_permission(v_sales_id, v_org_id, 'view_inventory') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Sales has view_inventory';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales should have view_inventory';
    END IF;

    SELECT has_permission(v_sales_id, v_org_id, 'create_sale') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Sales has create_sale';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales should have create_sale';
    END IF;

    SELECT has_permission(v_sales_id, v_org_id, 'view_financials') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Sales does NOT have view_financials (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales should NOT have view_financials';
    END IF;

    SELECT has_permission(v_sales_id, v_org_id, 'manage_team') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Sales does NOT have manage_team (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Sales should NOT have manage_team';
    END IF;

    -- ============================================
    -- TEST 4: Viewer role - MINIMAL permissions
    -- ============================================
    \echo ''
    \echo 'TEST 4: Viewer Permissions (Minimal)'
    
    SELECT has_permission(v_viewer_id, v_org_id, 'view_inventory') INTO v_result;
    IF v_result THEN
        RAISE NOTICE '✅ PASS: Viewer has view_inventory';
    ELSE
        RAISE NOTICE '❌ FAIL: Viewer should have view_inventory';
    END IF;

    SELECT has_permission(v_viewer_id, v_org_id, 'create_sale') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Viewer does NOT have create_sale (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Viewer should NOT have create_sale';
    END IF;

    SELECT has_permission(v_viewer_id, v_org_id, 'view_financials') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Viewer does NOT have view_financials (correct)';
    ELSE
        RAISE NOTICE '❌ FAIL: Viewer should NOT have view_financials';
    END IF;

    -- ============================================
    -- TEST 5: Random UUID (Hacker) - NO permissions
    -- ============================================
    \echo ''
    \echo 'TEST 5: Hacker (Random UUID) - No Access'
    
    SELECT has_permission(gen_random_uuid(), v_org_id, 'view_financials') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Random user has NO access';
    ELSE
        RAISE NOTICE '❌ FAIL: Random user should have NO access!';
    END IF;

    SELECT has_permission(gen_random_uuid(), v_org_id, 'view_inventory') INTO v_result;
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Random user has NO inventory access';
    ELSE
        RAISE NOTICE '❌ FAIL: Random user should have NO access!';
    END IF;

    -- Cleanup test data
    DELETE FROM public.dealer_team_members 
    WHERE organization_id = v_org_id;

    \echo ''
    \echo '============================================'
    \echo 'RBAC TESTS COMPLETED'
    \echo '============================================'
END $$;
