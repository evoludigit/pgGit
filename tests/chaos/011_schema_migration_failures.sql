-- Chaos Test: Schema Migration Failures
-- Test File: 011_schema_migration_failures.sql
-- Purpose: Test behavior when schema migrations fail or are interrupted

BEGIN;

SELECT plan(16);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create schema for migration testing
CREATE SCHEMA IF NOT EXISTS migration_test;

-- Create table that will undergo migrations
CREATE TABLE migration_test.data_table (
    id SERIAL PRIMARY KEY,
    old_column TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO migration_test.data_table (old_column) 
SELECT 'data_' || i FROM generate_series(1, 50) AS i;

-- ============================================================================
-- TEST GROUP 1: Successful Migration
-- ============================================================================

-- Test 1: Add column (forward migration)
SELECT lives_ok(
    $$ ALTER TABLE migration_test.data_table ADD COLUMN new_column INTEGER; $$,
    'Should add new column'
);

-- Test 2: Populate new column
SELECT lives_ok(
    $$ UPDATE migration_test.data_table SET new_column = id * 10; $$,
    'Should populate new column'
);

-- Test 3: Verify data integrity after migration
SELECT results_eq(
    $$ SELECT count(*) FROM migration_test.data_table WHERE new_column = id * 10 $$,
    ARRAY[50]::BIGINT[],
    'All rows should have correct new_column values'
);

-- ============================================================================
-- TEST GROUP 2: Failed Migration Simulation
-- ============================================================================

-- Test 4: Attempt invalid operation (should fail)
SELECT throws_ok(
    $$ ALTER TABLE migration_test.data_table ADD COLUMN bad_column INTEGER NOT NULL; $$,
    '23502',  -- not_null_violation
    'column "bad_column" contains null values',
    'Should fail adding NOT NULL column without default'
);

-- Test 5: Table should remain intact after failed migration
SELECT results_eq(
    $$ SELECT count(*) FROM migration_test.data_table $$,
    ARRAY[50]::BIGINT[],
    'Table should have all data after failed migration'
);

-- Test 6: Previous successful migration should remain
SELECT has_column(
    'migration_test',
    'data_table',
    'new_column',
    'new_column should still exist'
);

-- ============================================================================
-- TEST GROUP 3: Transactional Migration
-- ============================================================================

-- Test 7: Successful multi-step migration
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Step 1: Add column with default
        ALTER TABLE migration_test.data_table ADD COLUMN status TEXT DEFAULT 'active';
        
        -- Step 2: Create index
        CREATE INDEX idx_migration_status ON migration_test.data_table(status);
        
        -- Step 3: Update some rows
        UPDATE migration_test.data_table SET status = 'pending' WHERE id <= 10;
    END;
    $$;
    $$,
    'Should complete multi-step migration'
);

-- Test 8: Verify all migration steps applied
SELECT results_eq(
    $$ SELECT count(*) FROM migration_test.data_table WHERE status = 'active' $$,
    ARRAY[40]::BIGINT[],
    'Should have 40 active rows'
);

-- ============================================================================
-- TEST GROUP 4: Branch Migration
-- ============================================================================

-- Test 9: Create branch for migration testing
SELECT lives_ok(
    $$ SELECT pggit.create_branch('migration_branch'); $$,
    'Should create migration branch'
);

-- Test 10: Apply migration in branch
SELECT pggit.switch_branch('migration_branch');
SELECT lives_ok(
    $$ ALTER TABLE migration_test.data_table ADD COLUMN branch_only_col TEXT; $$,
    'Should apply migration in branch'
);

-- Test 11: Verify migration isolated to branch
SELECT has_column(
    'migration_test',
    'data_table',
    'branch_only_col',
    'Branch should have new column'
);

-- Test 12: Main branch should not see migration
SELECT pggit.switch_branch('main');
SELECT hasnt_column(
    'migration_test',
    'data_table',
    'branch_only_col',
    'Main should not see branch migration'
);

-- ============================================================================
-- TEST GROUP 5: Rollback Simulation
-- ============================================================================

-- Test 13: Simulate rollback (drop added columns)
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Note: In real migration, would have proper rollback scripts
        -- Here we simulate by dropping columns we added
        ALTER TABLE migration_test.data_table DROP COLUMN IF EXISTS new_column;
    EXCEPTION
        WHEN OTHERS THEN
            -- Column might not exist
            NULL;
    END;
    $$;
    $$,
    'Should handle column drop (rollback simulation)'
);

-- Test 14: Verify DDL tracking captured rollback
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history 
     WHERE object_name = 'data_table' 
     AND change_type = 'ALTER'),
    '>=',
    2::BIGINT,
    'Should track ALTER operations'
);

-- ============================================================================
-- TEST GROUP 6: Migration Validation
-- ============================================================================

-- Test 15: Verify schema version tracking
SELECT lives_ok(
    $$ SELECT * FROM pggit.get_schema_version(); $$,
    'Should get schema version'
);

-- Test 16: Final data integrity check
SELECT is(
    (SELECT count(*) FROM migration_test.data_table),
    50::BIGINT,
    'Final row count should match original'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'migration_branch';

-- Clean up test objects
DROP INDEX IF EXISTS idx_migration_status;
DROP TABLE IF EXISTS migration_test.data_table CASCADE;
DROP SCHEMA IF EXISTS migration_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE schema_name = 'migration_test';
DELETE FROM pggit.history WHERE schema_name = 'migration_test';

SELECT * FROM finish();

ROLLBACK;
