-- Unit Test Suite for pgGit Branch Operations
-- Test File: 002_test_branch_operations.sql
-- Coverage: Advanced branching, data branching, conflict scenarios

BEGIN;

-- Plan: 25 tests for branch operations
SELECT plan(25);

-- ============================================================================
-- SETUP: Create test data and branches
-- ============================================================================

-- Create base test tables for data branching tests
CREATE TABLE IF NOT EXISTS test_customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO test_customers (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com'),
    ('Charlie', 'charlie@example.com');

-- Create base branch for testing
SELECT pggit.create_branch('base_test_branch');

-- ============================================================================
-- TEST GROUP 1: Branch with Data Copy (Tests 1-5)
-- ============================================================================

-- Test 1: Create branch with data copy should succeed
SELECT lives_ok(
    $$ SELECT pggit.create_branch('data_branch_test', 'base_test_branch', true) $$,
    'Creating branch with data copy should succeed'
);

-- Test 2: Branch without data copy should create empty branch
SELECT lives_ok(
    $$ SELECT pggit.create_branch('schema_only_branch', 'base_test_branch', false) $$,
    'Creating schema-only branch should succeed'
);

-- Test 3: Verify data exists in data branch
SELECT pggit.switch_branch('data_branch_test');
SELECT is(
    (SELECT count(*) FROM test_customers),
    3::BIGINT,
    'Data branch should have copied data'
);

-- Test 4: Verify schema-only branch has structure but no data
SELECT pggit.switch_branch('schema_only_branch');
SELECT is(
    (SELECT count(*) FROM test_customers),
    0::BIGINT,
    'Schema-only branch should have no data'
);

-- Test 5: Verify table exists in schema-only branch
SELECT has_table(
    'public',
    'test_customers',
    'Schema-only branch should have table structure'
);

-- ============================================================================
-- TEST GROUP 2: Branch Metadata and Statistics (Tests 6-10)
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Test 6: Get branch statistics should return valid data
SELECT results_eq(
    $$ SELECT branch_name, row_count > 0 as has_data FROM pggit.branch_storage_stats WHERE branch_name = 'data_branch_test' $$,
    $$ VALUES ('data_branch_test', true) $$,
    'Branch storage stats should track data copy'
);

-- Test 7: Branch should track parent relationship
SELECT is(
    (SELECT parent_branch_id IS NOT NULL FROM pggit.branches WHERE name = 'data_branch_test'),
    true,
    'Data branch should track parent relationship'
);

-- Test 8: Branch creation time should be recent
SELECT results_eq(
    $$ SELECT created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute' FROM pggit.branches WHERE name = 'data_branch_test' $$,
    ARRAY[true]::BOOLEAN[],
    'Branch creation time should be recent'
);

-- Test 9: Branch has unique ID
SELECT is(
    (SELECT count(DISTINCT id) FROM pggit.branches WHERE name IN ('data_branch_test', 'schema_only_branch')),
    2::BIGINT,
    'Each branch should have unique ID'
);

-- Test 10: Branch status should be ACTIVE by default
SELECT results_eq(
    $$ SELECT status FROM pggit.branches WHERE name = 'data_branch_test' $$,
    ARRAY['ACTIVE']::pggit.branch_status[],
    'New branch should have ACTIVE status'
);

-- ============================================================================
-- TEST GROUP 3: Branch Isolation (Tests 11-15)
-- ============================================================================

-- Test 11: Changes in one branch don't affect others
SELECT pggit.switch_branch('data_branch_test');
INSERT INTO test_customers (name, email) VALUES ('David', 'david@example.com');

SELECT pggit.switch_branch('base_test_branch');
SELECT is(
    (SELECT count(*) FROM test_customers),
    3::BIGINT,
    'Changes in data_branch_test should not affect base_test_branch'
);

-- Test 12: Main branch data unchanged
SELECT pggit.switch_branch('main');
SELECT is(
    (SELECT count(*) FROM test_customers),
    3::BIGINT,
    'Changes in data_branch_test should not affect main'
);

-- Test 13: Schema changes are isolated
SELECT pggit.switch_branch('data_branch_test');
ALTER TABLE test_customers ADD COLUMN phone TEXT;

SELECT has_column(
    'public',
    'test_customers',
    'phone',
    'Schema change should exist in data_branch_test'
);

-- Test 14: Schema changes don't propagate to other branches
SELECT pggit.switch_branch('base_test_branch');
SELECT hasnt_column(
    'public',
    'test_customers',
    'phone',
    'Schema change should not exist in base_test_branch'
);

-- Test 15: Verify phone column not in main
SELECT pggit.switch_branch('main');
SELECT hasnt_column(
    'public',
    'test_customers',
    'phone',
    'Schema change should not exist in main'
);

-- ============================================================================
-- TEST GROUP 4: Branch Protection and Permissions (Tests 16-20)
-- ============================================================================

-- Test 16: Create protected branch should work
SELECT lives_ok(
    $$ SELECT pggit.create_branch('protected_branch') $$,
    'Creating branch for protection test should succeed'
);

-- Test 17: Set branch protection should succeed
SELECT lives_ok(
    $$ SELECT pggit.set_branch_protection('protected_branch', true) $$,
    'Setting branch protection should succeed'
);

-- Test 18: Protected branch should not be deletable
SELECT pggit.switch_branch('main');
SELECT throws_ok(
    $$ SELECT pggit.delete_branch('protected_branch') $$,
    'P0001',
    'Cannot delete protected branch',
    'Deleting protected branch should fail'
);

-- Test 19: Remove protection should work
SELECT lives_ok(
    $$ SELECT pggit.set_branch_protection('protected_branch', false) $$,
    'Removing branch protection should succeed'
);

-- Test 20: Unprotected branch should be deletable
SELECT lives_ok(
    $$ SELECT pggit.delete_branch('protected_branch') $$,
    'Deleting unprotected branch should succeed'
);

-- ============================================================================
-- TEST GROUP 5: Branch Listing and Filtering (Tests 21-25)
-- ============================================================================

-- Test 21: List all branches should include test branches
SELECT results_eq(
    $$ SELECT name FROM pggit.list_branches() WHERE name LIKE '%test%' OR name LIKE '%branch%' ORDER BY name $$,
    ARRAY['base_test_branch', 'data_branch_test', 'schema_only_branch']::TEXT[],
    'list_branches should return all test branches'
);

-- Test 22: List active branches only
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.list_branches() WHERE status = 'ACTIVE' $$,
    ARRAY[(SELECT count(*) FROM pggit.branches WHERE status = 'ACTIVE')]::BIGINT[],
    'list_branches with status filter should work'
);

-- Test 23: Get branch ancestry
SELECT results_eq(
    $$ SELECT count(*) > 0 as has_parent FROM pggit.branches WHERE name = 'data_branch_test' AND parent_branch_id IS NOT NULL $$,
    ARRAY[true]::BOOLEAN[],
    'Branch should have ancestry information'
);

-- Test 24: Branch depth calculation
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.get_branch_ancestry('data_branch_test')),
    '>=',
    1::INTEGER,
    'Branch ancestry should include at least parent'
);

-- Test 25: Branch statistics should be accurate
SELECT is(
    (SELECT coalesce(row_count, 0) FROM pggit.branch_storage_stats WHERE branch_name = 'data_branch_test'),
    4::BIGINT,  -- 3 original + 1 added
    'Branch row count should be accurate'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up test branches
DELETE FROM pggit.branches WHERE name IN (
    'base_test_branch', 
    'data_branch_test', 
    'schema_only_branch'
);

-- Drop test table
DROP TABLE IF EXISTS test_customers;

SELECT * FROM finish();

ROLLBACK;
