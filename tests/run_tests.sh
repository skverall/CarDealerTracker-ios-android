#!/bin/bash
# ============================================
# run_tests.sh - Backend Test Runner
# ============================================
# Usage:
#   ./run_tests.sh          # Run all tests
#   ./run_tests.sh rbac     # Run only RBAC tests
#   ./run_tests.sh rls      # Run only RLS tests
#   ./run_tests.sh crud     # Run only CRUD tests
#   ./run_tests.sh security # Run only security tests
#   ./run_tests.sh multi    # Run only multi-org tests
#   ./run_tests.sh invite   # Run only invitation tests
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "============================================"
echo "  Car Dealer Tracker - Backend Tests"
echo "============================================"
echo ""

# Check if supabase CLI is available
if ! command -v supabase &> /dev/null; then
    echo -e "${YELLOW}⚠️  Supabase CLI not found. Using direct SQL execution.${NC}"
fi

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$2
    
    echo ""
    echo -e "${GREEN}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    
    if [ -f "$SCRIPT_DIR/$test_file" ]; then
        # For now, output the SQL file location
        echo "Test file: $SCRIPT_DIR/$test_file"
        echo ""
        echo "To run manually:"
        echo "  psql \"\$DATABASE_URL\" -f $SCRIPT_DIR/$test_file"
        echo ""
        # If you want to run directly against Supabase:
        # supabase db execute -f "$SCRIPT_DIR/$test_file"
    else
        echo -e "${RED}❌ Test file not found: $test_file${NC}"
    fi
}

# Parse command line argument
TEST_TYPE=${1:-all}

case $TEST_TYPE in
    rbac)
        run_test "01_rbac_tests.sql" "RBAC Permission Tests"
        ;;
    rls)
        run_test "02_rls_tests.sql" "RLS Policy Tests"
        ;;
    crud)
        run_test "03_crud_tests.sql" "CRUD Operation Tests"
        ;;
    security)
        run_test "04_security_tests.sql" "Security Penetration Tests"
        ;;
    multi)
        run_test "05_multi_org_tests.sql" "Multi-Organization Tests"
        ;;
    invite)
        run_test "06_invitation_tests.sql" "Invitation System Tests"
        ;;
    all)
        run_test "01_rbac_tests.sql" "RBAC Permission Tests"
        run_test "02_rls_tests.sql" "RLS Policy Tests"
        run_test "03_crud_tests.sql" "CRUD Operation Tests"
        run_test "04_security_tests.sql" "Security Penetration Tests"
        run_test "05_multi_org_tests.sql" "Multi-Organization Tests"
        run_test "06_invitation_tests.sql" "Invitation System Tests"
        ;;
    *)
        echo -e "${RED}Unknown test type: $TEST_TYPE${NC}"
        echo ""
        echo "Usage: ./run_tests.sh [rbac|rls|crud|security|multi|invite|all]"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo "  Tests Completed"
echo "============================================"
echo ""
echo "To execute tests against your database:"
echo "1. Get your database URL from Supabase Dashboard"
echo "2. Run: psql \"\$DATABASE_URL\" -f tests/<test_file>.sql"
echo ""
