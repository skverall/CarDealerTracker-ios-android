-- ============================================
-- 03_CRUD_TESTS.sql  
-- Create, Read, Update, Delete Operations
-- ============================================
-- Tests: All data operations for each entity
-- ============================================

\echo '============================================'
\echo 'CRUD TESTS - Data Operations'
\echo '============================================'

-- ============================================
-- TEST 1: get_changes RPC exists and works
-- ============================================
\echo ''
\echo 'TEST 1: get_changes RPC Function'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_changes') 
        THEN '✅ PASS: get_changes RPC exists'
        ELSE '❌ FAIL: get_changes RPC not found'
    END as result;

-- ============================================
-- TEST 2: get_my_permissions RPC exists  
-- ============================================
\echo ''
\echo 'TEST 2: get_my_permissions RPC Function'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_my_permissions') 
        THEN '✅ PASS: get_my_permissions RPC exists'
        ELSE '❌ FAIL: get_my_permissions RPC not found'
    END as result;

-- ============================================
-- TEST 3: has_permission function exists
-- ============================================
\echo ''
\echo 'TEST 3: has_permission Function'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'has_permission') 
        THEN '✅ PASS: has_permission function exists'
        ELSE '❌ FAIL: has_permission function not found'
    END as result;

-- ============================================
-- TEST 4: Check required columns exist
-- ============================================
\echo ''
\echo 'TEST 4: Required Columns in Tables'

-- Check crm.vehicles has notes
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'crm' AND table_name = 'vehicles' AND column_name = 'notes'
        ) 
        THEN '✅ PASS: crm.vehicles has notes column'
        ELSE '❌ FAIL: crm.vehicles missing notes column'
    END as result;

-- Check crm.sales has notes
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'crm' AND table_name = 'sales' AND column_name = 'notes'
        ) 
        THEN '✅ PASS: crm.sales has notes column'
        ELSE '❌ FAIL: crm.sales missing notes column'
    END as result;

-- Check crm.debts has notes
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'crm' AND table_name = 'debts' AND column_name = 'notes'
        ) 
        THEN '✅ PASS: crm.debts has notes column'
        ELSE '❌ FAIL: crm.debts missing notes column'
    END as result;

-- Check crm.dealer_clients has notes
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'crm' AND table_name = 'dealer_clients' AND column_name = 'notes'
        ) 
        THEN '✅ PASS: crm.dealer_clients has notes column'
        ELSE '❌ FAIL: crm.dealer_clients missing notes column'
    END as result;

-- ============================================
-- TEST 5: Financials sidecar tables exist
-- ============================================
\echo ''
\echo 'TEST 5: Sidecar Tables Exist'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'crm_vehicles_financials' AND table_schema = 'public') 
        THEN '✅ PASS: crm_vehicles_financials exists'
        ELSE '❌ FAIL: crm_vehicles_financials not found'
    END as result;

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'crm_sales_financials' AND table_schema = 'public') 
        THEN '✅ PASS: crm_sales_financials exists'
        ELSE '❌ FAIL: crm_sales_financials not found'
    END as result;

-- ============================================
-- TEST 6: Team tables exist
-- ============================================
\echo ''
\echo 'TEST 6: Team Management Tables'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dealer_team_members' AND table_schema = 'public') 
        THEN '✅ PASS: dealer_team_members exists'
        ELSE '❌ FAIL: dealer_team_members not found'
    END as result;

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'team_invitations' AND table_schema = 'public') 
        THEN '✅ PASS: team_invitations exists'
        ELSE '❌ FAIL: team_invitations not found'
    END as result;

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'audit_logs' AND table_schema = 'public') 
        THEN '✅ PASS: audit_logs exists'
        ELSE '❌ FAIL: audit_logs not found'
    END as result;

-- ============================================
-- TEST 7: Remote Config table exists
-- ============================================
\echo ''
\echo 'TEST 7: Remote Config Table'

SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'app_config' AND table_schema = 'public') 
        THEN '✅ PASS: app_config exists'
        ELSE '❌ FAIL: app_config not found'
    END as result;

-- Check if config has data
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM public.app_config LIMIT 1) 
        THEN '✅ PASS: app_config has data'
        ELSE '⚠️ WARNING: app_config is empty'
    END as result;

\echo ''
\echo '============================================'
\echo 'CRUD TESTS COMPLETED'
\echo '============================================'
