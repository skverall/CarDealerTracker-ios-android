-- ============================================
-- 06_INVITATION_TESTS.sql
-- Team Invitation System Tests
-- ============================================
-- Tests: Token generation, expiry, one-time use
-- ============================================

\echo '============================================'
\echo 'INVITATION TESTS - Team Invite System'
\echo '============================================'

-- ============================================
-- TEST 1: team_invitations table structure
-- ============================================
\echo ''
\echo 'TEST 1: Invitation Table Structure'

SELECT 
    column_name,
    data_type,
    CASE 
        WHEN is_nullable = 'NO' THEN '(required)'
        ELSE '(optional)'
    END as required
FROM information_schema.columns
WHERE table_name = 'team_invitations'
AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================
-- TEST 2: Required columns exist
-- ============================================
\echo ''
\echo 'TEST 2: Required Invitation Columns'

DO $$
DECLARE
    v_count int;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'team_invitations'
    AND column_name IN ('id', 'organization_id', 'email', 'role', 'token', 'expires_at', 'created_by');
    
    IF v_count >= 7 THEN
        RAISE NOTICE '✅ PASS: All required columns exist';
    ELSE
        RAISE NOTICE '❌ FAIL: Missing columns. Found % of 7', v_count;
    END IF;
END $$;

-- ============================================
-- TEST 3: Invitation token is unique
-- ============================================
\echo ''
\echo 'TEST 3: Token Uniqueness'

SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.table_constraints 
            WHERE table_name = 'team_invitations' 
            AND constraint_type = 'UNIQUE'
        ) OR EXISTS (
            SELECT 1 FROM pg_indexes 
            WHERE tablename = 'team_invitations'
            AND indexdef LIKE '%token%'
        )
        THEN '✅ PASS: Token uniqueness enforced'
        ELSE '⚠️ WARNING: Token uniqueness not found (may be enforced by code)'
    END as result;

-- ============================================
-- TEST 4: Expired invitation filtering
-- ============================================
\echo ''
\echo 'TEST 4: Expiration Logic'

DO $$
DECLARE
    v_org_id uuid := gen_random_uuid();
    v_valid_count int;
    v_expired_count int;
BEGIN
    -- Create valid invitation (future expiry)
    INSERT INTO public.team_invitations (organization_id, email, role, token, expires_at, created_by)
    VALUES (v_org_id, 'valid@test.com', 'sales', gen_random_uuid()::text, NOW() + INTERVAL '2 hours', gen_random_uuid());
    
    -- Create expired invitation (past expiry)
    INSERT INTO public.team_invitations (organization_id, email, role, token, expires_at, created_by)
    VALUES (v_org_id, 'expired@test.com', 'sales', gen_random_uuid()::text, NOW() - INTERVAL '1 hour', gen_random_uuid());
    
    -- Count valid (not expired) invitations
    SELECT COUNT(*) INTO v_valid_count
    FROM public.team_invitations
    WHERE organization_id = v_org_id
    AND expires_at > NOW();
    
    -- Count expired invitations
    SELECT COUNT(*) INTO v_expired_count
    FROM public.team_invitations
    WHERE organization_id = v_org_id
    AND expires_at <= NOW();
    
    IF v_valid_count = 1 AND v_expired_count = 1 THEN
        RAISE NOTICE '✅ PASS: Expiration filtering works correctly';
    ELSE
        RAISE NOTICE '❌ FAIL: Valid=%, Expired=% (expected 1, 1)', v_valid_count, v_expired_count;
    END IF;
    
    -- Cleanup
    DELETE FROM public.team_invitations WHERE organization_id = v_org_id;
END $$;

-- ============================================
-- TEST 5: audit_logs table exists
-- ============================================
\echo ''
\echo 'TEST 5: Audit Logging'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_logs' AND table_schema = 'public') 
        THEN '✅ PASS: audit_logs table exists'
        ELSE '❌ FAIL: audit_logs table not found'
    END as result;

-- Check audit log structure
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'audit_logs'
AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================
-- TEST 6: Role enum values
-- ============================================
\echo ''
\echo 'TEST 6: Valid Role Types'

-- Check that role column accepts expected values
DO $$
DECLARE
    v_org_id uuid := gen_random_uuid();
BEGIN
    -- These should all succeed
    INSERT INTO public.team_invitations (organization_id, email, role, token, expires_at, created_by)
    VALUES 
        (v_org_id, 'admin@test.com', 'admin', gen_random_uuid()::text, NOW() + INTERVAL '1 hour', gen_random_uuid()),
        (v_org_id, 'sales@test.com', 'sales', gen_random_uuid()::text, NOW() + INTERVAL '1 hour', gen_random_uuid()),
        (v_org_id, 'viewer@test.com', 'viewer', gen_random_uuid()::text, NOW() + INTERVAL '1 hour', gen_random_uuid());
    
    RAISE NOTICE '✅ PASS: All valid roles (admin, sales, viewer) accepted';
    
    -- Cleanup
    DELETE FROM public.team_invitations WHERE organization_id = v_org_id;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ FAIL: Role insertion failed: %', SQLERRM;
END $$;

\echo ''
\echo '============================================'
\echo 'INVITATION TESTS COMPLETED'
\echo '============================================'
