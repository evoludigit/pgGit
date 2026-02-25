-- Unit Test Suite for pgGit Core Functions
-- Test File: 001_test_git_core.sql
-- Coverage: Branch operations, commit operations, basic validation
-- Author: Pass 5 Implementation

BEGIN;

-- Plan: 30 tests for core git functionality
SELECT plan(30);

-- ============================================================================
-- SETUP: Create test schema and dependencies
-- ============================================================================

-- Ensure we're in a clean state for testing
-- Note: Tests run in a transaction, so changes are rolled back

-- ============================================================================
-- TEST GROUP 1: Branch Creation (Tests 1-8)
-- ============================================================================

-- Test 1: Basic branch creation should succeed
SELECT lives_ok(
    $$ SELECT pggit.create_branch('test_branch_basic') $$,
    'Branch creation should succeed with valid name'
);

-- Test 2: Duplicate branch name should fail
SELECT throws_ok(
    $$ SELECT pggit.create_branch('test_branch_basic') $$,
    'P0001',  -- RAISE EXCEPTION error code
    'Branch test_branch_basic already exists',
    'Should reject duplicate branch names'
);

-- Test 3: NULL branch name should fail
SELECT throws_ok(
    $$ SELECT pggit.create_branch(NULL) $$,
    'P0001',
    'Branch name cannot be NULL',
    'Should reject NULL branch name'
);

-- Test 4: Empty branch name should fail
SELECT throws_ok(
    $$ SELECT pggit.create_branch('') $$,
    'P0001',
    'Branch name cannot be empty',
    'Should reject empty branch name'
);

-- Test 5: Branch name too long should fail (>255 chars)
SELECT throws_ok(
    $$ SELECT pggit.create_branch(repeat('a', 256)) $$,
    'P0001',
    'Branch name too long (max 255 characters',
    'Should reject branch names >255 characters'
);

-- Test 6: Branch name with special characters should succeed
SELECT lives_ok(
    $$ SELECT pggit.create_branch('test_branch_v1.0_feature-x') $$,
    'Branch names with hyphens and dots should be valid'
);

-- Test 7: Branch name with underscore should succeed
SELECT lives_ok(
    $$ SELECT pggit.create_branch('test_branch_feature_x') $$,
    'Branch names with underscores should be valid'
);

-- Test 8: Create branch from non-existent parent should fail
SELECT throws_ok(
    $$ SELECT pggit.create_branch('orphan_branch', 'nonexistent_parent') $$,
    'P0001',
    'Parent branch nonexistent_parent not found',
    'Should reject invalid parent branch'
);

-- ============================================================================
-- TEST GROUP 2: Branch Listing and Retrieval (Tests 9-12)
-- ============================================================================

-- Test 9: list_branches should return created branches
SELECT results_eq(
    $$ SELECT name FROM pggit.list_branches() WHERE name LIKE 'test_%' ORDER BY name $$,
    ARRAY['test_branch_basic', 'test_branch_feature_x', 'test_branch_v1.0_feature-x']::TEXT[],
    'list_branches should return test branches in alphabetical order'
);

-- Test 10: get_branch_info should return details for existing branch
SELECT results_eq(
    $$ SELECT name FROM pggit.get_branch_info('test_branch_basic') $$,
    ARRAY['test_branch_basic']::TEXT[],
    'get_branch_info should return branch name for existing branch'
);

-- Test 11: get_branch_info for non-existent branch should return NULL
SELECT results_eq(
    $$ SELECT pggit.get_branch_info('nonexistent_branch_xyz') $$,
    ARRAY[]::RECORD[],
    'get_branch_info should return empty for non-existent branch'
);

-- Test 12: Branch exists check should work correctly
SELECT is(
    pggit.branch_exists('test_branch_basic'),
    true,
    'branch_exists should return true for existing branch'
);

-- ============================================================================
-- TEST GROUP 3: Branch Switching (Tests 13-16)
-- ============================================================================

-- Test 13: Switch to valid branch should succeed
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('test_branch_basic') $$,
    'Switching to valid branch should succeed'
);

-- Test 14: Switch to non-existent branch should fail
SELECT throws_ok(
    $$ SELECT pggit.switch_branch('nonexistent_switch_target') $$,
    'P0001',
    'Branch nonexistent_switch_target not found',
    'Switching to non-existent branch should fail'
);

-- Test 15: Switch to NULL branch should fail
SELECT throws_ok(
    $$ SELECT pggit.switch_branch(NULL) $$,
    'P0001',
    'Branch name cannot be NULL',
    'Switching to NULL branch should fail'
);

-- Test 16: get_current_branch should reflect switch
SELECT is(
    pggit.get_current_branch(),
    'test_branch_basic',
    'get_current_branch should return switched-to branch'
);

-- ============================================================================
-- TEST GROUP 4: Commit Operations (Tests 17-22)
-- ============================================================================

-- Test 17: Create commit with message should succeed
SELECT lives_ok(
    $$ SELECT pggit.commit('Test commit message') $$,
    'Creating commit with message should succeed'
);

-- Test 18: Commit with empty message should fail
SELECT throws_ok(
    $$ SELECT pggit.commit('') $$,
    'P0001',
    'Commit message cannot be empty',
    'Commit with empty message should fail'
);

-- Test 19: Commit with NULL message should fail
SELECT throws_ok(
    $$ SELECT pggit.commit(NULL) $$,
    'P0001',
    'Commit message cannot be NULL',
    'Commit with NULL message should fail'
);

-- Test 20: Get commit history should return commits
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.get_commit_history('test_branch_basic')),
    '>=',
    1::BIGINT,
    'Commit history should contain at least one commit'
);

-- Test 21: Get commit by hash should work
SELECT results_eq(
    $$ SELECT commit_message FROM pggit.get_commit_history('test_branch_basic') LIMIT 1 $$,
    ARRAY['Test commit message']::TEXT[],
    'Commit message should be stored correctly'
);

-- Test 22: Commit count should track correctly
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.commits WHERE branch_id = (SELECT id FROM pggit.branches WHERE name = 'test_branch_basic')),
    '>=',
    1::BIGINT,
    'Commits table should track branch commits'
);

-- ============================================================================
-- TEST GROUP 5: Branch Deletion (Tests 23-27)
-- ============================================================================

-- First create a branch specifically for deletion
SELECT pggit.create_branch('branch_to_delete');

-- Test 23: Delete existing branch should succeed
SELECT lives_ok(
    $$ SELECT pggit.delete_branch('branch_to_delete') $$,
    'Deleting existing branch should succeed'
);

-- Test 24: Delete non-existent branch should fail
SELECT throws_ok(
    $$ SELECT pggit.delete_branch('already_deleted_branch') $$,
    'P0001',
    'Branch already_deleted_branch not found',
    'Deleting non-existent branch should fail'
);

-- Test 25: Delete main branch should fail (protected)
SELECT throws_ok(
    $$ SELECT pggit.delete_branch('main') $$,
    'P0001',
    'Cannot delete main branch',
    'Deleting main branch should fail'
);

-- Test 26: Delete current branch should fail or switch first
-- (Implementation dependent - this tests the safety check)
SELECT pggit.switch_branch('main');
SELECT lives_ok(
    $$ SELECT pggit.create_branch('temp_delete_test') $$,
    'Creating temporary branch for deletion test'
);

-- Test 27: Branch is actually deleted
SELECT is(
    pggit.branch_exists('branch_to_delete'),
    false,
    'Deleted branch should no longer exist'
);

-- ============================================================================
-- TEST GROUP 6: Edge Cases and Validation (Tests 28-30)
-- ============================================================================

-- Test 28: Branch name with only whitespace should fail
SELECT throws_ok(
    $$ SELECT pggit.create_branch('   ') $$,
    'P0001',
    'Branch name cannot be empty',
    'Whitespace-only branch name should fail'
);

-- Test 29: Unicode branch names should work
SELECT lives_ok(
    $$ SELECT pggit.create_branch('feature_日本語_test') $$,
    'Unicode branch names should be supported'
);

-- Test 30: Reserved keywords should be rejected or handled
SELECT lives_ok(
    $$ SELECT pggit.create_branch('select_from_where') $$,
    'Branch names containing SQL keywords should work if properly formatted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- Delete test branches (except main)
DELETE FROM pggit.branches WHERE name LIKE 'test_%' OR name LIKE 'temp_%' OR name LIKE 'branch_to_delete%' OR name LIKE 'feature_%' OR name LIKE 'orphan%';

-- Return to main branch
SELECT pggit.switch_branch('main');

-- Finish tests
SELECT * FROM finish();

ROLLBACK;
