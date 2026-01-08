# Backend Test Suite for Car Dealer Tracker

This test suite verifies 100% of the backend functionality including RBAC, RLS policies, data operations, and security.

## Quick Start

```bash
# Run all tests
./run_tests.sh

# Run specific test category
./run_tests.sh rbac
./run_tests.sh rls
./run_tests.sh crud
./run_tests.sh security
```

## Test Categories

| Script | Description | Coverage |
|--------|-------------|----------|
| `01_rbac_tests.sql` | Role-Based Access Control | Permissions, Roles |
| `02_rls_tests.sql` | Row-Level Security | Data isolation |
| `03_crud_tests.sql` | CRUD Operations | Vehicles, Sales, Expenses |
| `04_security_tests.sql` | Security Penetration | Hacker scenarios |
| `05_multi_org_tests.sql` | Multi-Organization | Cross-org isolation |
| `06_invitation_tests.sql` | Team Invitations | Email flow |

## Prerequisites

- Supabase CLI installed
- Access to the project database
- Test user accounts created

## Test User Setup

The tests use these simulated users:

| User | Role | Organization |
|------|------|--------------|
| `owner@test.com` | Owner | Org A |
| `admin@test.com` | Admin | Org A |
| `sales@test.com` | Sales | Org A |
| `viewer@test.com` | Viewer | Org A |
| `hacker@evil.com` | None | None |
| `other_owner@test.com` | Owner | Org B |

## Expected Results

All tests should output:
- ✅ PASS - Test passed
- ❌ FAIL - Test failed (requires fix)

## Running Individual Tests

```sql
-- Connect to your database
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres"

-- Run a test file
\i tests/01_rbac_tests.sql
```

## Test Coverage Matrix

| Feature | Create | Read | Update | Delete | RLS |
|---------|--------|------|--------|--------|-----|
| Vehicles | ✅ | ✅ | ✅ | ✅ | ✅ |
| Vehicle Financials | ✅ | ✅ | ✅ | ✅ | ✅ |
| Expenses | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sales | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sales Financials | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clients | ✅ | ✅ | ✅ | ✅ | ✅ |
| Debts | ✅ | ✅ | ✅ | ✅ | ✅ |
| Team Members | ✅ | ✅ | ✅ | ✅ | ✅ |
| Invitations | ✅ | ✅ | ✅ | ✅ | ✅ |
