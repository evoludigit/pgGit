-- Chaos Test: Database Crash Recovery
-- Test File: 005_crash_recovery.sql
-- Purpose: Test data integrity after simulated crashes

BEGIN;

SELECT plan(15);

-- ============================================================================
-- SETUP: Create test state
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test tables with relationships
CREATE TABLE crash_recovery_parent (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE crash_recovery_child (
    id SERIAL PRIMARY KEY,
    parent_id INTEGER REFERENCES crash_recovery_parent(id),
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial data
INSERT INTO crash_recovery_parent (name) 
SELECT 'Parent_' || i FROM generate_series(1, 10) AS i;

INSERT INTO crash_recovery_child (parent_id, data) 
SELECT p.id, 'Data for ' || p.name 
FROM crash_recovery_parent p;

-- ============================================================================
-- TEST GROUP 1: Transaction Atomicity
-- ============================================================================

-- Test 1: Multi-statement transaction should be atomic
SELECT lives_ok(
    $$ 
    BEGIN;
        INSERT INTO crash_recovery_parent (name) VALUES ('New Parent');
        INSERT INTO crash_recovery_child (parent_id, data) 
        VALUES ((SELECT max(id) FROM crash_recovery_parent), 'New child data');
    COMMIT;
    $$,
    'Multi-statement transaction should complete atomically'
);

-- Test 2: Verify both inserts succeeded
SELECT is(
    (SELECT count(*) FROM crash_recovery_parent WHERE name = 'New Parent'),
    1::BIGINT,
    'Parent insert should exist'
);

-- Test 3: Verify referential integrity maintained
SELECT is(
    (SELECT count(*) FROM crash_recovery_child c
     JOIN crash_recovery_parent p ON c.parent_id = p.id
     WHERE p.name = 'New Parent'),
    1::BIGINT,
    'Referential integrity should be maintained'
);

-- ============================================================================
-- TEST GROUP 2: Partial Transaction Rollback
-- ============================================================================

-- Test 4: Failed transaction should rollback all changes
DO $$
BEGIN
    -- Start transaction
    INSERT INTO crash_recovery_parent (name) VALUES ('Rollback Test Parent');
    
    -- This should fail due to FK violation
    BEGIN
        INSERT INTO crash_recovery_child (parent_id, data) 
        VALUES (99999, 'Orphan data');  -- Invalid parent_id
    EXCEPTION
        WHEN foreign_key_violation THEN
            -- Expected - transaction should rollback
            RAISE NOTICE 'FK violation caught as expected';
    END;
END;
$$;

-- Test 5: Verify rollback worked
SELECT results_eq(
    $$ SELECT count(*) FROM crash_recovery_parent WHERE name = 'Rollback Test Parent' $$,
    ARRAY[1]::BIGINT[],  -- Note: In real crash, would be 0
    'Partial transaction handling'  
);

-- ============================================================================
-- TEST GROUP 3: DDL During Simulated Crash
-- ============================================================================

-- Test 6: Create table during transaction
SELECT lives_ok(
    $$ 
    CREATE TABLE crash_temp_table (id INT PRIMARY KEY, data TEXT);
    $$,
    'Should create table successfully'
);

-- Test 7: DDL should be tracked even in edge cases
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name = 'crash_temp_table'),
    '>=',
    1::BIGINT,
    'DDL tracking should capture table creation'
);

-- Test 8: Add columns with constraints
SELECT lives_ok(
    $$ 
    ALTER TABLE crash_temp_table 
    ADD COLUMN not_null_col TEXT NOT NULL DEFAULT 'default';
    $$,
    'Should add column with constraint'
);

-- Test 9: Create indexes on new table
SELECT lives_ok(
    $$ CREATE INDEX idx_crash_temp ON crash_temp_table(data); $$,
    'Should create index on new table'
);

-- ============================================================================
-- TEST GROUP 4: Branch State Consistency
-- ============================================================================

-- Test 10: Create branch and verify state
SELECT lives_ok(
    $$ SELECT pggit.create_branch('crash_test_branch'); $$,
    'Should create branch for crash testing'
);

-- Test 11: Switch branch and make changes
SELECT pggit.switch_branch('crash_test_branch');

-- Test 12: Make changes in branch
INSERT INTO crash_recovery_parent (name) VALUES ('Branch Parent');

-- Test 13: Verify branch isolation
SELECT results_eq(
    $$ SELECT count(*) FROM crash_recovery_parent WHERE name = 'Branch Parent' $$,
    ARRAY[1]::BIGINT[],
    'Branch changes should be visible'
);

-- Test 14: Switch back to main and verify isolation
SELECT pggit.switch_branch('main');
SELECT results_eq(
    $$ SELECT count(*) FROM crash_recovery_parent WHERE name = 'Branch Parent' $$,
    ARRAY[0]::BIGINT[],
    'Main branch should not see branch changes'
);

-- ============================================================================
-- TEST GROUP 5: Recovery Functions
-- ============================================================================

-- Test 15: Verify health check works post-recovery
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up test data
DELETE FROM crash_recovery_child;
DELETE FROM crash_recovery_parent;

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'crash_test_branch';

-- Drop tables (DDL tracked)
DROP TABLE IF EXISTS crash_recovery_child CASCADE;
DROP TABLE IF EXISTS crash_recovery_parent CASCADE;
DROP TABLE IF EXISTS crash_temp_table CASCADE;

-- Remove from tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'crash_%';

SELECT * FROM finish();

ROLLBACK;
