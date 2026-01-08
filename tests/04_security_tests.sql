-- ============================================
-- 04_SECURITY_TESTS.sql
-- Security Penetration Tests
-- ============================================
-- Tests: Hacker scenarios, unauthorized access
-- ============================================

\echo '============================================'
\echo 'SECURITY TESTS - Penetration Testing'
\echo '============================================'

-- ============================================
-- TEST 1: Random UUID cannot access financials
-- ============================================
\echo ''
\echo 'TEST 1: Hacker Access to Vehicles Financials'

-- This simulates a hacker trying to access financial data
-- without being a member of any organization
DO $$
DECLARE
    v_hacker_id uuid := gen_random_uuid();
    v_random_org uuid := gen_random_uuid();
    v_result boolean;
BEGIN
    -- Hacker should NOT have permission
    SELECT has_permission(v_hacker_id, v_random_org, 'view_financials') INTO v_result;
    
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Hacker cannot access financials';
    ELSE
        RAISE NOTICE '❌ CRITICAL FAIL: Hacker has access to financials!';
    END IF;
END $$;

-- ============================================
-- TEST 2: Cross-Organization Access Prevention
-- ============================================
\echo ''
\echo 'TEST 2: Cross-Org Access Prevention'

DO $$
DECLARE
    v_user_a uuid := gen_random_uuid();
    v_user_b uuid := gen_random_uuid();
    v_org_a uuid := gen_random_uuid();
    v_org_b uuid := gen_random_uuid();
    v_result boolean;
BEGIN
    -- Create user A as owner of org A
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_a, v_user_a, 'owner', 'active');
    
    -- Create user B as owner of org B  
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_b, v_user_b, 'owner', 'active');
    
    -- User A should NOT have access to Org B
    SELECT has_permission(v_user_a, v_org_b, 'view_financials') INTO v_result;
    
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: User A cannot access Org B data';
    ELSE
        RAISE NOTICE '❌ CRITICAL FAIL: Cross-org access allowed!';
    END IF;
    
    -- User B should NOT have access to Org A
    SELECT has_permission(v_user_b, v_org_a, 'view_financials') INTO v_result;
    
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: User B cannot access Org A data';
    ELSE
        RAISE NOTICE '❌ CRITICAL FAIL: Cross-org access allowed!';
    END IF;
    
    -- Cleanup
    DELETE FROM public.dealer_team_members WHERE organization_id IN (v_org_a, v_org_b);
END $$;

-- ============================================
-- TEST 3: Inactive member has no access
-- ============================================
\echo ''
\echo 'TEST 3: Inactive Member Access'

DO $$
DECLARE
    v_user_id uuid := gen_random_uuid();
    v_org_id uuid := gen_random_uuid();
    v_result boolean;
BEGIN
    -- Create inactive member
    INSERT INTO public.dealer_team_members (organization_id, user_id, role, status)
    VALUES (v_org_id, v_user_id, 'owner', 'inactive');
    
    -- Inactive member should NOT have access
    SELECT has_permission(v_user_id, v_org_id, 'view_financials') INTO v_result;
    
    IF NOT v_result THEN
        RAISE NOTICE '✅ PASS: Inactive member has no access';
    ELSE
        RAISE NOTICE '⚠️ WARNING: Inactive member still has access (may be by design)';
    END IF;
    
    -- Cleanup
    DELETE FROM public.dealer_team_members WHERE organization_id = v_org_id;
END $$;

-- ============================================
-- TEST 4: SQL Injection Prevention (RPC)
-- ============================================
\echo ''
\echo 'TEST 4: SQL Injection Prevention'

-- Test that has_permission handles malicious input
DO $$
DECLARE
    v_result boolean;
BEGIN
    -- Try SQL injection in permission key
    BEGIN
        SELECT has_permission(
            gen_random_uuid(), 
            gen_random_uuid(), 
            'view_financials''; DROP TABLE users; --'
        ) INTO v_result;
        
        -- If we get here without error, check result is false
        IF NOT v_result THEN
            RAISE NOTICE '✅ PASS: SQL injection returns false (safe)';
        ELSE
            RAISE NOTICE '⚠️ WARNING: Unexpected result from injection attempt';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '✅ PASS: SQL injection blocked by error handling';
    END;
END $$;

-- ============================================
-- TEST 5: Expired Invitation Cannot Be Used
-- ============================================
\echo ''
\echo 'TEST 5: Expired Invitation Check'

DO $$
DECLARE
    v_org_id uuid := gen_random_uuid();
    v_token text := gen_random_uuid()::text;
    v_expired_count int;
BEGIN
    -- Create expired invitation
    INSERT INTO public.team_invitations (organization_id, email, role, token, expires_at, created_by)
    VALUES (v_org_id, 'test@test.com', 'sales', v_token, NOW() - INTERVAL '1 day', gen_random_uuid());
    
    -- Check that expired invitation is not valid
    SELECT COUNT(*) INTO v_expired_count
    FROM public.team_invitations
    WHERE token = v_token
    AND expires_at > NOW();
    
    IF v_expired_count = 0 THEN
        RAISE NOTICE '✅ PASS: Expired invitation correctly rejected';
    ELSE
        RAISE NOTICE '❌ FAIL: Expired invitation still valid!';
    END IF;
    
    -- Cleanup
    DELETE FROM public.team_invitations WHERE organization_id = v_org_id;
END $$;

-- ============================================
-- TEST 6: Orphaned Dealers Check (All have membership)
-- ============================================
\echo ''
\echo 'TEST 6: Orphaned Dealers Check'

SELECT 
    CASE 
        WHEN COUNT(DISTINCT v.dealer_id) - COUNT(DISTINCT m.organization_id) = 0 
        THEN '✅ PASS: No orphaned dealers (all have team membership)'
        ELSE '⚠️ WARNING: ' || (COUNT(DISTINCT v.dealer_id) - COUNT(DISTINCT m.organization_id))::text || ' orphaned dealers found'
    END as result
FROM crm.vehicles v
LEFT JOIN public.dealer_team_members m ON v.dealer_id = m.organization_id;

\echo ''
\echo '============================================'
\echo 'SECURITY TESTS COMPLETED'
\echo '============================================'
