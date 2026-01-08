-- ============================================
-- 02_RLS_TESTS.sql
-- Row-Level Security Policy Tests
-- ============================================
-- Tests: Data isolation between organizations
-- ============================================

\echo '============================================'
\echo 'RLS TESTS - Row-Level Security'
\echo '============================================'

-- ============================================
-- TEST 1: crm_vehicles_financials RLS
-- ============================================
\echo ''
\echo 'TEST 1: Vehicles Financials RLS Policies'

SELECT 
    CASE 
        WHEN COUNT(*) = 4 THEN '✅ PASS: crm_vehicles_financials has all 4 policies (SELECT, INSERT, UPDATE, DELETE)'
        ELSE '❌ FAIL: crm_vehicles_financials missing policies. Found: ' || COUNT(*)::text
    END as result
FROM pg_policies 
WHERE tablename = 'crm_vehicles_financials';

-- ============================================
-- TEST 2: crm_sales_financials RLS
-- ============================================
\echo ''
\echo 'TEST 2: Sales Financials RLS Policies'

SELECT 
    CASE 
        WHEN COUNT(*) = 4 THEN '✅ PASS: crm_sales_financials has all 4 policies'
        ELSE '❌ FAIL: crm_sales_financials missing policies. Found: ' || COUNT(*)::text
    END as result
FROM pg_policies 
WHERE tablename = 'crm_sales_financials';

-- ============================================
-- TEST 3: RLS is enabled on financial tables
-- ============================================
\echo ''
\echo 'TEST 3: RLS Enabled Check'

SELECT 
    tablename,
    CASE 
        WHEN rowsecurity THEN '✅ RLS Enabled'
        ELSE '❌ RLS DISABLED - SECURITY RISK!'
    END as status
FROM pg_tables 
WHERE tablename IN ('crm_vehicles_financials', 'crm_sales_financials')
AND schemaname = 'public';

-- ============================================
-- TEST 4: Verify policy commands coverage
-- ============================================
\echo ''
\echo 'TEST 4: Policy Command Coverage'

SELECT 
    tablename,
    string_agg(cmd, ', ' ORDER BY cmd) as commands,
    CASE 
        WHEN COUNT(DISTINCT cmd) = 4 THEN '✅ Full Coverage'
        ELSE '❌ Missing Commands'
    END as status
FROM pg_policies 
WHERE tablename IN ('crm_vehicles_financials', 'crm_sales_financials')
GROUP BY tablename;

-- ============================================
-- TEST 5: CRM schema tables RLS check
-- ============================================
\echo ''
\echo 'TEST 5: CRM Schema RLS Status'

SELECT 
    c.relname as table_name,
    CASE 
        WHEN c.relrowsecurity THEN '✅ RLS Enabled'
        ELSE '⚠️ RLS Disabled'
    END as rls_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'crm' 
AND c.relkind = 'r'
ORDER BY c.relname;

\echo ''
\echo '============================================'
\echo 'RLS TESTS COMPLETED'
\echo '============================================'
