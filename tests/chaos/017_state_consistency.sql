-- Chaos Test: State Consistency Verification
-- Test File: 017_state_consistency.sql
-- Purpose: Verify system state remains consistent after various operations

BEGIN;

SELECT plan(16);

-- ============================================================================
-- SETUP: Create baseline state
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test table with data
CREATE TABLE consistency_test (
    id SERIAL PRIMARY KEY,
    value TEXT,
    checksum TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO consistency_test (value, checksum) 
SELECT 'value_' || i, md5('value_' || i) FROM generate_series(1, 50) AS i;

-- Record baseline counts
SELECT count(*) INTO baseline_objects FROM pggit.objects WHERE is_active = true;
SELECT count(*) INTO baseline_branches FROM pggit.branches WHERE status = 'ACTIVE';

-- ============================================================================
-- TEST GROUP 1: Baseline Verification
-- ============================================================================

-- Test 1: Verify initial data integrity
SELECT is(
    (SELECT count(*) FROM consistency_test),
    50::BIGINT,
    'Should have 50 initial rows'
);

-- Test 2: Verify checksums
SELECT results_eq(
    $$ SELECT count(*) FROM consistency_test WHERE checksum = md5(value) $$,
    ARRAY[50]::BIGINT[],
    'All checksums should match'
);

-- ============================================================================
-- TEST GROUP 2: Modify and Verify Consistency
-- ============================================================================

-- Test 3: Batch update
SELECT lives_ok(
    $$ 
    UPDATE consistency_test 
    SET value = value || '_modified', 
        checksum = md5(value || '_modified'),
        updated_at = CURRENT_TIMESTAMP
    WHERE id <= 25;
    $$,
    'Should batch update 25 rows'
);

-- Test 4: Verify modified rows
SELECT results_eq(
    $$ SELECT count(*) FROM consistency_test WHERE value LIKE '%_modified' $$,
    ARRAY[25]::BIGINT[],
    'Should have 25 modified rows'
);

-- Test 5: Verify checksums after modification
SELECT results_eq(
    $$ SELECT count(*) FROM consistency_test WHERE checksum = md5(value) $$,
    ARRAY[50]::BIGINT[],
    'Checksums should still match after modification'
);

-- ============================================================================
-- TEST GROUP 3: Branch Consistency
-- ============================================================================

-- Test 6: Create branch
SELECT lives_ok(
    $$ SELECT pggit.create_branch('consistency_branch'); $$,
    'Should create branch'
);

-- Test 7: Modify in branch
SELECT pggit.switch_branch('consistency_branch');
UPDATE consistency_test SET value = 'branch_value' WHERE id = 1;

-- Test 8: Verify branch modification isolated
SELECT results_eq(
    $$ SELECT value FROM consistency_test WHERE id = 1 $$,
    ARRAY['branch_value']::TEXT[],
    'Branch should have modified value'
);

-- Test 9: Verify main unchanged
SELECT pggit.switch_branch('main');
SELECT results_eq(
    $$ SELECT value FROM consistency_test WHERE id = 1 $$,
    ARRAY['value_1_modified']::TEXT[],
    'Main should have original modified value'
);

-- ============================================================================
-- TEST GROUP 4: Metadata Consistency
-- ============================================================================

-- Test 10: Object count should match tracked objects
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name = 'consistency_test' AND is_active = true),
    '>=',
    1::BIGINT,
    'Object tracking should be consistent'
);

-- Test 11: History should track changes
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_id IN (SELECT id FROM pggit.objects WHERE object_name = 'consistency_test')),
    '>=',
    1::BIGINT,
    'History should track table changes'
);

-- Test 12: Branch count should be accurate
SELECT is(
    (SELECT count(*) FROM pggit.branches WHERE name = 'consistency_branch'),
    1::BIGINT,
    'Should have exactly 1 consistency branch'
);

-- ============================================================================
-- TEST GROUP 5: Post-Operation Consistency
-- ============================================================================

-- Test 13: Delete some rows and verify count
SELECT lives_ok(
    $$ DELETE FROM consistency_test WHERE id > 40; $$,
    'Should delete 10 rows'
);

-- Test 14: Verify count after delete
SELECT is(
    (SELECT count(*) FROM consistency_test),
    40::BIGINT,
    'Should have 40 rows after delete'
);

-- Test 15: Verify checksums still valid
SELECT results_eq(
    $$ SELECT count(*) FROM consistency_test WHERE checksum = md5(value) $$,
    ARRAY[40]::BIGINT[],
    'Checksums should remain valid'
);

-- Test 16: System health should be consistent
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'System health should be consistent'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'consistency_branch';

-- Clean up test table
DROP TABLE IF EXISTS consistency_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'consistency_test';

SELECT * FROM finish();

ROLLBACK;
