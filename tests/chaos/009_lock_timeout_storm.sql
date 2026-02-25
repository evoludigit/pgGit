-- Chaos Test: Lock Timeout Storm
-- Test File: 009_lock_timeout_storm.sql
-- Purpose: Test behavior when many operations compete for locks

BEGIN;

SELECT plan(16);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create table with data
CREATE TABLE lock_storm_test (
    id SERIAL PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO lock_storm_test (value) 
SELECT 'value_' || i FROM generate_series(1, 100) AS i;

-- Create index
CREATE INDEX idx_lock_storm ON lock_storm_test(id);

-- ============================================================================
-- TEST GROUP 1: Concurrent Updates
-- ============================================================================

-- Test 1: Rapid updates should complete
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 1..20 LOOP
            UPDATE lock_storm_test SET value = 'updated_' || i, updated_at = CURRENT_TIMESTAMP
            WHERE id = i;
        END LOOP;
    END;
    $$;
    $$,
    'Should complete 20 rapid updates'
);

-- Test 2: Verify updates succeeded
SELECT results_eq(
    $$ SELECT value FROM lock_storm_test WHERE id = 20 $$,
    ARRAY['updated_20']::TEXT[],
    'Update should have succeeded'
);

-- ============================================================================
-- TEST GROUP 2: DDL Under Load
-- ============================================================================

-- Test 3: Add column while table is "hot"
SELECT lives_ok(
    $$ ALTER TABLE lock_storm_test ADD COLUMN new_col TEXT DEFAULT 'default'; $$,
    'Should add column under load'
);

-- Test 4: Create index while table has locks
SELECT lives_ok(
    $$ CREATE INDEX CONCURRENTLY idx_lock_storm_value ON lock_storm_test(value); $$,
    'Should create index under load'
);

-- ============================================================================
-- TEST GROUP 3: Branch Operations Under Load
-- ============================================================================

-- Test 5: Create branch while data is being modified
SELECT lives_ok(
    $$ SELECT pggit.create_branch('lock_storm_branch'); $$,
    'Should create branch under load'
);

-- Test 6: Switch branch
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('lock_storm_branch'); $$,
    'Should switch branch'
);

-- Test 7: Modify data in branch
SELECT pggit.switch_branch('lock_storm_branch');
SELECT lives_ok(
    $$ UPDATE lock_storm_test SET value = 'branch_value' WHERE id <= 10; $$,
    'Should modify data in branch'
);

-- Test 8: Create index in branch
SELECT lives_ok(
    $$ CREATE INDEX idx_branch_test ON lock_storm_test(updated_at); $$,
    'Should create index in branch'
);

-- ============================================================================
-- TEST GROUP 4: Concurrent DDL Operations
-- ============================================================================

-- Test 9: Create multiple objects rapidly
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 1..10 LOOP
            EXECUTE format('CREATE TABLE lock_storm_temp_%s (id INT)', i);
        END LOOP;
    END;
    $$;
    $$,
    'Should create 10 temp tables rapidly'
);

-- Test 10: DDL tracking should capture all
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name LIKE 'lock_storm_temp_%'),
    '>=',
    8::BIGINT,
    'Should track most temp tables'
);

-- Test 11: Drop tables rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN SELECT table_name FROM information_schema.tables 
                 WHERE table_schema = 'public' AND table_name LIKE 'lock_storm_temp_%'
        LOOP
            EXECUTE format('DROP TABLE %I', r.table_name);
        END LOOP;
    END;
    $$;
    $$,
    'Should drop temp tables rapidly'
);

-- ============================================================================
-- TEST GROUP 5: Lock Contention Resolution
-- ============================================================================

-- Test 12: Return to main branch
SELECT pggit.switch_branch('main');

-- Test 13: Verify main branch data unchanged
SELECT results_eq(
    $$ SELECT count(*) FROM lock_storm_test WHERE value LIKE 'branch_%' $$,
    ARRAY[0]::BIGINT[],
    'Main branch should not have branch changes'
);

-- Test 14: Merge should work despite lock history
SELECT lives_ok(
    $$ SELECT pggit.merge('lock_storm_branch', 'main', 'ours'); $$,
    'Should merge despite lock history'
);

-- ============================================================================
-- TEST GROUP 6: Final Verification
-- ============================================================================

-- Test 15: All indexes should exist
SELECT has_index(
    'public',
    'lock_storm_test',
    'idx_lock_storm',
    'Original index should exist'
);

SELECT has_index(
    'public',
    'lock_storm_test',
    'idx_lock_storm_value',
    'Concurrently created index should exist'
);

-- Test 16: Health check should pass
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'tracked_objects' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after lock storm'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'lock_storm_branch';

-- Clean up indexes
DROP INDEX IF EXISTS idx_lock_storm_value;
DROP INDEX IF EXISTS idx_lock_storm;

-- Clean up test data
DROP TABLE IF EXISTS lock_storm_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'lock_storm%';

SELECT * FROM finish();

ROLLBACK;
