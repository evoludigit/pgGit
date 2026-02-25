-- Unit Test Suite for pgGit Merge Operations
-- Test File: 003_test_merge_operations.sql
-- Coverage: Conflict detection, merge execution, resolution strategies

BEGIN;

-- Plan: 40 tests for merge operations
SELECT plan(40);

-- ============================================================================
-- SETUP: Create test branches with conflicts
-- ============================================================================

-- Create source branch for merge testing
SELECT pggit.create_branch('merge_source_branch');
SELECT pggit.switch_branch('merge_source_branch');

-- Create test table and add data in source
CREATE TABLE IF NOT EXISTS test_products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price DECIMAL(10,2),
    category TEXT
);

INSERT INTO test_products (name, price, category) VALUES 
    ('Product A', 100.00, 'Electronics'),
    ('Product B', 50.00, 'Clothing');

SELECT pggit.commit('Initial products in source branch');

-- Create target branch from main
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('merge_target_branch');
SELECT pggit.switch_branch('merge_target_branch');

-- Create same table with different data in target
CREATE TABLE IF NOT EXISTS test_products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price DECIMAL(10,2),
    category TEXT
);

INSERT INTO test_products (name, price, category) VALUES 
    ('Product A', 120.00, 'Electronics'),  -- Price conflict
    ('Product C', 75.00, 'Books');          -- Different product

SELECT pggit.commit('Initial products in target branch');

-- ============================================================================
-- TEST GROUP 1: Conflict Detection (Tests 1-10)
-- ============================================================================

-- Test 1: Detect conflicts between branches should work
SELECT lives_ok(
    $$ SELECT pggit.detect_conflicts('merge_source_branch', 'merge_target_branch') $$,
    'Conflict detection should execute without error'
);

-- Test 2: Conflict detection returns valid JSON structure
SELECT results_eq(
    $$ SELECT (pggit.detect_conflicts('merge_source_branch', 'merge_target_branch')->>'conflict_count')::int >= 0 $$,
    ARRAY[true]::BOOLEAN[],
    'Conflict detection should return conflict count >= 0'
);

-- Test 3: Non-existent source branch should fail
SELECT throws_ok(
    $$ SELECT pggit.detect_conflicts('nonexistent_source', 'merge_target_branch') $$,
    'P0001',
    'Source branch nonexistent_source not found',
    'Should reject invalid source branch'
);

-- Test 4: Non-existent target branch should fail
SELECT throws_ok(
    $$ SELECT pggit.detect_conflicts('merge_source_branch', 'nonexistent_target') $$,
    'P0001',
    'Target branch nonexistent_target not found',
    'Should reject invalid target branch'
);

-- Test 5: Same branch merge should fail or warn
SELECT results_eq(
    $$ SELECT (pggit.detect_conflicts('main', 'main')->>'conflict_count')::int $$,
    ARRAY[0]::INTEGER[],
    'Merging same branch should have 0 conflicts'
);

-- Test 6: Detect schema conflicts
SELECT pggit.switch_branch('merge_source_branch');
ALTER TABLE test_products ADD COLUMN description TEXT;

SELECT pggit.switch_branch('merge_target_branch');
ALTER TABLE test_products ADD COLUMN stock_count INTEGER;

SELECT cmp_ok(
    (SELECT (pggit.detect_conflicts('merge_source_branch', 'merge_target_branch')->>'conflict_count')::int),
    '>',
    0::INTEGER,
    'Schema conflicts should be detected'
);

-- Test 7: Detect data conflicts
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('data_conflict_test_a');
SELECT pggit.switch_branch('data_conflict_test_a');
UPDATE test_products SET price = 150.00 WHERE name = 'Product A';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('data_conflict_test_b');
SELECT pggit.switch_branch('data_conflict_test_b');
UPDATE test_products SET price = 200.00 WHERE name = 'Product A';

SELECT cmp_ok(
    (SELECT (pggit.detect_conflicts('data_conflict_test_a', 'data_conflict_test_b')->>'conflict_count')::int),
    '>',
    0::INTEGER,
    'Data conflicts should be detected'
);

-- Test 8: Conflict types should be identified
SELECT like(
    (pggit.detect_conflicts('merge_source_branch', 'merge_target_branch')::TEXT),
    '%conflict_type%',
    'Conflict detection should identify conflict types'
);

-- Test 9: Conflicts should include object names
SELECT like(
    (pggit.detect_conflicts('merge_source_branch', 'merge_target_branch')::TEXT),
    '%test_products%',
    'Conflict detection should include table names'
);

-- Test 10: Empty branches should have no conflicts
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('empty_branch_1');
SELECT pggit.create_branch('empty_branch_2');

SELECT results_eq(
    $$ SELECT (pggit.detect_conflicts('empty_branch_1', 'empty_branch_2')->>'conflict_count')::int $$,
    ARRAY[0]::INTEGER[],
    'Empty branches should have no conflicts'
);

-- ============================================================================
-- TEST GROUP 2: Merge Execution (Tests 11-20)
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create clean merge scenario
SELECT pggit.create_branch('merge_clean_source');
SELECT pggit.switch_branch('merge_clean_source');
INSERT INTO test_products (name, price, category) VALUES ('Clean Product', 99.99, 'Test');
SELECT pggit.commit('Add clean product');

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('merge_clean_target');
SELECT pggit.switch_branch('merge_clean_target');

-- Test 11: Clean merge should succeed
SELECT lives_ok(
    $$ SELECT pggit.merge('merge_clean_source', 'merge_clean_target', 'auto') $$,
    'Clean merge with no conflicts should succeed'
);

-- Test 12: Merge should create merge history entry
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.merge_history WHERE source_branch = 'merge_clean_source'),
    '>=',
    1::BIGINT,
    'Merge should create history entry'
);

-- Test 13: Merge with conflicts and strategy 'manual' should wait
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('merge_conflict_source');
SELECT pggit.switch_branch('merge_conflict_source');
UPDATE test_products SET price = 111.11 WHERE name = 'Product A';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('merge_conflict_target');
SELECT pggit.switch_branch('merge_conflict_target');
UPDATE test_products SET price = 222.22 WHERE name = 'Product A';

SELECT lives_ok(
    $$ SELECT pggit.merge('merge_conflict_source', 'merge_conflict_target', 'manual') $$,
    'Merge with conflicts and manual strategy should initiate'
);

-- Test 14: Merge status should be queryable
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history WHERE source_branch = 'merge_conflict_source' ORDER BY initiated_at DESC LIMIT 1 $$,
    ARRAY['awaiting_resolution']::TEXT[],
    'Manual merge with conflicts should have awaiting_resolution status'
);

-- Test 15: Merge with invalid strategy should fail
SELECT throws_ok(
    $$ SELECT pggit.merge('merge_conflict_source', 'merge_conflict_target', 'invalid_strategy') $$,
    'P0001',
    'Invalid merge strategy',
    'Should reject invalid merge strategy'
);

-- Test 16: Merge from non-existent branch should fail
SELECT throws_ok(
    $$ SELECT pggit.merge('nonexistent', 'merge_clean_target', 'auto') $$,
    'P0001',
    'Source branch nonexistent not found',
    'Should reject non-existent source branch'
);

-- Test 17: Merge to non-existent branch should fail
SELECT throws_ok(
    $$ SELECT pggit.merge('merge_clean_source', 'nonexistent', 'auto') $$,
    'P0001',
    'Target branch nonexistent not found',
    'Should reject non-existent target branch'
);

-- Test 18: Merge should track conflicts
SELECT cmp_ok(
    (SELECT coalesce(conflict_count, 0) FROM pggit.merge_history WHERE source_branch = 'merge_conflict_source' ORDER BY initiated_at DESC LIMIT 1),
    '>',
    0::INTEGER,
    'Merge should track conflict count'
);

-- Test 19: Merge should be abortable
SELECT lives_ok(
    $$ SELECT pggit.abort_merge((SELECT id FROM pggit.merge_history WHERE source_branch = 'merge_conflict_source' ORDER BY initiated_at DESC LIMIT 1)) $$,
    'Merge should be abortable'
);

-- Test 20: Aborted merge should have correct status
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history WHERE source_branch = 'merge_conflict_source' AND status = 'aborted' ORDER BY initiated_at DESC LIMIT 1 $$,
    ARRAY['aborted']::TEXT[],
    'Aborted merge should have aborted status'
);

-- ============================================================================
-- TEST GROUP 3: Conflict Resolution (Tests 21-30)
-- ============================================================================

-- Create new conflict scenario for resolution testing
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('resolution_test_source');
SELECT pggit.switch_branch('resolution_test_source');
UPDATE test_products SET price = 333.33 WHERE name = 'Product A';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('resolution_test_target');
SELECT pggit.switch_branch('resolution_test_target');
UPDATE test_products SET price = 444.44 WHERE name = 'Product A';

-- Initiate merge
SELECT pggit.merge('resolution_test_source', 'resolution_test_target', 'manual');

-- Test 21: Get conflict details should work
SELECT lives_ok(
    $$ SELECT pggit.get_merge_conflicts((SELECT id FROM pggit.merge_history WHERE source_branch = 'resolution_test_source' ORDER BY initiated_at DESC LIMIT 1)) $$,
    'Getting conflict details should work'
);

-- Test 22: Conflict resolution should work
SELECT lives_ok(
    $$ SELECT pggit.resolve_conflict(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'resolution_test_source' ORDER BY initiated_at DESC LIMIT 1),
        'test_products',
        1,
        'source'
    ) $$,
    'Resolving conflict should work'
);

-- Test 23: Resolve with invalid resolution type should fail
SELECT throws_ok(
    $$ SELECT pggit.resolve_conflict(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'resolution_test_source' ORDER BY initiated_at DESC LIMIT 1),
        'test_products',
        1,
        'invalid_resolution'
    ) $$,
    'P0001',
    'Invalid resolution type',
    'Should reject invalid resolution type'
);

-- Test 24: Resolve non-existent conflict should fail
SELECT throws_ok(
    $$ SELECT pggit.resolve_conflict(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'resolution_test_source' ORDER BY initiated_at DESC LIMIT 1),
        'nonexistent_table',
        99999,
        'source'
    ) $$,
    'P0001',
    'Conflict not found',
    'Should reject non-existent conflict'
);

-- Test 25: Multiple conflicts can be resolved
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('multi_conflict_source');
SELECT pggit.switch_branch('multi_conflict_source');
UPDATE test_products SET price = 100.00 WHERE name = 'Product A';
UPDATE test_products SET price = 200.00 WHERE name = 'Product B';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('multi_conflict_target');
SELECT pggit.switch_branch('multi_conflict_target');
UPDATE test_products SET price = 300.00 WHERE name = 'Product A';
UPDATE test_products SET price = 400.00 WHERE name = 'Product B';

SELECT pggit.merge('multi_conflict_source', 'multi_conflict_target', 'manual');

SELECT cmp_ok(
    (SELECT count(*) FROM pggit.merge_conflicts WHERE merge_id = (SELECT id FROM pggit.merge_history WHERE source_branch = 'multi_conflict_source' ORDER BY initiated_at DESC LIMIT 1)),
    '>=',
    2::BIGINT,
    'Multiple conflicts should be tracked'
);

-- Test 26: Resolution with custom data
SELECT lives_ok(
    $$ SELECT pggit.resolve_conflict_with_data(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'multi_conflict_source' ORDER BY initiated_at DESC LIMIT 1),
        'test_products',
        1,
        '{"price": 250.00}'::jsonb
    ) $$,
    'Custom data resolution should work'
);

-- Test 27: Resolved conflicts should be marked
SELECT results_eq(
    $$ SELECT resolution FROM pggit.merge_conflicts WHERE merge_id = (SELECT id FROM pggit.merge_history WHERE source_branch = 'multi_conflict_source' ORDER BY initiated_at DESC LIMIT 1) AND resolution IS NOT NULL LIMIT 1 $$,
    ARRAY['MANUAL_RESOLVED']::pggit.merge_resolution[],
    'Resolved conflicts should have MANUAL_RESOLVED status'
);

-- Test 28: Complete merge after resolution
SELECT lives_ok(
    $$ SELECT pggit.complete_merge((SELECT id FROM pggit.merge_history WHERE source_branch = 'multi_conflict_source' ORDER BY initiated_at DESC LIMIT 1)) $$,
    'Completing merge should work'
);

-- Test 29: Completed merge should have correct status
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history WHERE source_branch = 'multi_conflict_source' AND status = 'completed' ORDER BY initiated_at DESC LIMIT 1 $$,
    ARRAY['completed']::TEXT[],
    'Completed merge should have completed status'
);

-- Test 30: Resolved data should be applied
SELECT pggit.switch_branch('multi_conflict_target');
SELECT results_eq(
    $$ SELECT price FROM test_products WHERE name = 'Product A' $$,
    ARRAY[250.00]::DECIMAL[],
    'Resolved data should be applied to target'
);

-- ============================================================================
-- TEST GROUP 4: Auto-Resolution Strategies (Tests 31-35)
-- ============================================================================

-- Test 31: Auto resolution with 'ours' strategy
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_ours_source');
SELECT pggit.switch_branch('auto_ours_source');
UPDATE test_products SET price = 555.55 WHERE name = 'Product A';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_ours_target');
SELECT pggit.switch_branch('auto_ours_target');
UPDATE test_products SET price = 666.66 WHERE name = 'Product A';

SELECT lives_ok(
    $$ SELECT pggit.merge('auto_ours_source', 'auto_ours_target', 'ours') $$,
    'Auto resolution with ours strategy should work'
);

-- Test 32: Auto resolution with 'theirs' strategy
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_theirs_source');
SELECT pggit.switch_branch('auto_theirs_source');
UPDATE test_products SET price = 777.77 WHERE name = 'Product A';

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_theirs_target');
SELECT pggit.switch_branch('auto_theirs_target');
UPDATE test_products SET price = 888.88 WHERE name = 'Product A';

SELECT lives_ok(
    $$ SELECT pggit.merge('auto_theirs_source', 'auto_theirs_target', 'theirs') $$,
    'Auto resolution with theirs strategy should work'
);

-- Test 33: Auto resolution with 'union' strategy for additive changes
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_union_source');
SELECT pggit.switch_branch('auto_union_source');
INSERT INTO test_products (name, price, category) VALUES ('Union Product A', 50.00, 'Test');

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_union_target');
SELECT pggit.switch_branch('auto_union_target');
INSERT INTO test_products (name, price, category) VALUES ('Union Product B', 60.00, 'Test');

SELECT lives_ok(
    $$ SELECT pggit.merge('auto_union_source', 'auto_union_target', 'union') $$,
    'Auto resolution with union strategy should work'
);

-- Test 34: Union merge should combine data
SELECT pggit.switch_branch('auto_union_target');
SELECT cmp_ok(
    (SELECT count(*) FROM test_products WHERE name LIKE 'Union%'),
    '>=',
    2::BIGINT,
    'Union merge should combine both sets of data'
);

-- Test 35: Failed auto resolution should fallback
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_fail_source');
SELECT pggit.switch_branch('auto_fail_source');
DROP TABLE test_products;

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('auto_fail_target');
SELECT pggit.switch_branch('auto_fail_target');

SELECT lives_ok(
    $$ SELECT pggit.merge('auto_fail_source', 'auto_fail_target', 'auto') $$,
    'Failed auto resolution should handle gracefully'
);

-- ============================================================================
-- TEST GROUP 5: Merge History and Audit (Tests 36-40)
-- ============================================================================

-- Test 36: Merge history should include all fields
SELECT results_eq(
    $$ SELECT source_branch, target_branch, status FROM pggit.merge_history WHERE source_branch = 'merge_clean_source' LIMIT 1 $$,
    $$ VALUES ('merge_clean_source', 'merge_clean_target', 'completed') $$,
    'Merge history should track source, target, and status'
);

-- Test 37: Merge history should track timestamps
SELECT results_eq(
    $$ SELECT initiated_at IS NOT NULL, completed_at IS NOT NULL FROM pggit.merge_history WHERE source_branch = 'merge_clean_source' LIMIT 1 $$,
    ARRAY[true, true]::BOOLEAN[],
    'Merge history should track initiation and completion times'
);

-- Test 38: Merge history should track who initiated
SELECT results_eq(
    $$ SELECT initiated_by IS NOT NULL FROM pggit.merge_history WHERE source_branch = 'merge_clean_source' LIMIT 1 $$,
    ARRAY[true]::BOOLEAN[],
    'Merge history should track initiator'
);

-- Test 39: Get merge status should return comprehensive info
SELECT lives_ok(
    $$ SELECT pggit.get_merge_status((SELECT id FROM pggit.merge_history WHERE source_branch = 'merge_clean_source' LIMIT 1)) $$,
    'Getting merge status should work'
);

-- Test 40: List recent merges should work
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.get_recent_merges(10)),
    '>=',
    1::BIGINT,
    'Listing recent merges should return results'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up test branches
DELETE FROM pggit.branches WHERE name LIKE 'merge_%' OR name LIKE '%_source' OR name LIKE '%_target' OR name LIKE 'empty_branch_%' OR name LIKE 'resolution_test%' OR name LIKE 'multi_conflict%' OR name LIKE 'auto_%';

-- Drop test table
DROP TABLE IF EXISTS test_products;

SELECT * FROM finish();

ROLLBACK;
