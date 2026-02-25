-- Chaos Test: Extreme Conditions (Final)
-- Test File: 020_extreme_conditions.sql
-- Purpose: Combined stress test of multiple extreme scenarios

BEGIN;

SELECT plan(16);

-- ============================================================================
-- SETUP: Create extreme test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test table
CREATE TABLE extreme_test (
    id SERIAL PRIMARY KEY,
    name TEXT,
    large_data TEXT,
    numeric_val NUMERIC(20,10),
    json_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Extreme Data
-- ============================================================================

-- Test 1: Insert many rows with large data
SELECT lives_ok(
    $$ 
    INSERT INTO extreme_test (name, large_data, numeric_val, json_data)
    SELECT 
        'extreme_' || i,
        repeat('X', 1000),
        i * 3.1415926535,
        jsonb_build_object('key', i, 'data', repeat('Y', 100))
    FROM generate_series(1, 200) AS i;
    $$,
    'Should insert 200 rows with large data'
);

-- Test 2: Verify extreme data
SELECT is(
    (SELECT count(*) FROM extreme_test),
    200::BIGINT,
    'Should have 200 extreme rows'
);

-- ============================================================================
-- TEST GROUP 2: Rapid DDL with Data
-- ============================================================================

-- Test 3: Add column with data present
SELECT lives_ok(
    $$ ALTER TABLE extreme_test ADD COLUMN new_col TEXT DEFAULT 'extreme_default'; $$,
    'Should add column with 200 rows'
);

-- Test 4: Create index on large data
SELECT lives_ok(
    $$ CREATE INDEX idx_extreme_name ON extreme_test(name); $$,
    'Should create index on large table'
);

-- Test 5: Add constraint
SELECT lives_ok(
    $$ ALTER TABLE extreme_test ADD CONSTRAINT chk_extreme CHECK (numeric_val > 0); $$,
    'Should add CHECK constraint'
);

-- ============================================================================
-- TEST GROUP 3: Extreme Branching
-- ============================================================================

-- Test 6: Create 10 branches rapidly
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 1..10 LOOP
            PERFORM pggit.create_branch('extreme_branch_' || i);
        END LOOP;
    END;
    $$;
    $$,
    'Should create 10 branches rapidly'
);

-- Test 7: Switch to middle branch
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('extreme_branch_5'); $$,
    'Should switch to branch 5'
);

-- Test 8: Modify in branch
SELECT pggit.switch_branch('extreme_branch_5');
SELECT lives_ok(
    $$ 
    UPDATE extreme_test SET name = 'modified_in_branch_5' WHERE id <= 50;
    DELETE FROM extreme_test WHERE id > 150;
    $$,
    'Should modify and delete in branch'
);

-- Test 9: Verify branch state
SELECT is(
    (SELECT count(*) FROM extreme_test),
    150::BIGINT,
    'Branch should have 150 rows after delete'
);

-- ============================================================================
-- TEST GROUP 4: Merge Extreme Changes
-- ============================================================================

-- Test 10: Merge to main
SELECT pggit.switch_branch('main');
SELECT lives_ok(
    $$ SELECT pggit.merge('extreme_branch_5', 'main', 'theirs'); $$,
    'Should merge extreme changes'
);

-- Test 11: Verify merged state
SELECT is(
    (SELECT count(*) FROM extreme_test),
    150::BIGINT,
    'Main should have 150 merged rows'
);

-- ============================================================================
-- TEST GROUP 5: Combined Stress
-- ============================================================================

-- Test 12: DDL during merge aftermath
SELECT lives_ok(
    $$ 
    ALTER TABLE extreme_test ADD COLUMN post_merge TEXT;
    CREATE INDEX idx_extreme_json ON extreme_test USING gin(json_data);
    $$,
    'Should perform DDL after merge'
);

-- Test 13: More branches after merge
SELECT lives_ok(
    $$ SELECT pggit.create_branch('post_extreme_branch'); $$,
    'Should create branch after extreme operations'
);

-- Test 14: Query performance after everything
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_count BIGINT;
    BEGIN
        SELECT count(*) INTO v_count FROM extreme_test 
        WHERE name LIKE '%extreme%' AND numeric_val > 10;
        
        SELECT count(*) INTO v_count FROM extreme_test 
        WHERE json_data->>'key'::int > 100;
    END;
    $$;
    $$,
    'Queries should work after extreme operations'
);

-- ============================================================================
-- TEST GROUP 6: Final Verification
-- ============================================================================

-- Test 15: Health check should pass
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after extreme conditions'
);

-- Test 16: DDL tracking should capture everything
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_name = 'extreme_test'),
    '>=',
    5::BIGINT,
    'DDL tracking should capture extreme operations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name LIKE 'extreme_branch_%';
DELETE FROM pggit.branches WHERE name = 'post_extreme_branch';

-- Clean up test table
DROP TABLE IF EXISTS extreme_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'extreme_test';

SELECT * FROM finish();

ROLLBACK;
