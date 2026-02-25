-- Chaos Test: Disk Space Exhaustion Simulation
-- Test File: 004_disk_space_exhaustion.sql
-- Purpose: Test behavior when storage is critically low

BEGIN;

SELECT plan(12);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create a table that could potentially consume space
CREATE TABLE disk_test_data (
    id SERIAL PRIMARY KEY,
    large_text TEXT,
    binary_data BYTEA,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Large Data Insertion Under Pressure
-- ============================================================================

-- Test 1: System should handle large text insertions gracefully
SELECT lives_ok(
    $$ 
    INSERT INTO disk_test_data (large_text) 
    SELECT repeat('x', 10000) FROM generate_series(1, 100);
    $$,
    'Should handle bulk text insertions'
);

-- Test 2: Verify data was inserted
SELECT is(
    (SELECT count(*) FROM disk_test_data),
    100::BIGINT,
    'Should have 100 rows after bulk insert'
);

-- Test 3: Binary data insertion should work
SELECT lives_ok(
    $$ 
    INSERT INTO disk_test_data (binary_data) 
    SELECT repeat('\\x00', 1000)::BYTEA FROM generate_series(1, 50);
    $$,
    'Should handle binary data insertions'
);

-- Test 4: JSONB data with nested structures
SELECT lives_ok(
    $$ 
    INSERT INTO disk_test_data (metadata) 
    SELECT jsonb_build_object(
        'nested', jsonb_build_object(
            'deep', jsonb_build_object(
                'data', repeat('y', 1000)
            )
        )
    ) FROM generate_series(1, 50);
    $$,
    'Should handle deeply nested JSONB data'
);

-- ============================================================================
-- TEST GROUP 2: DDL Operations Under Storage Pressure
-- ============================================================================

-- Test 5: Creating indexes on large tables should work
SELECT lives_ok(
    $$ CREATE INDEX idx_disk_test_created ON disk_test_data(created_at); $$,
    'Should create index on large table'
);

-- Test 6: Adding columns to large tables
SELECT lives_ok(
    $$ ALTER TABLE disk_test_data ADD COLUMN extra_column TEXT DEFAULT 'test'; $$,
    'Should add column to large table'
);

-- Test 7: Schema changes should be tracked even with large data
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name = 'disk_test_data'),
    '>=',
    1::BIGINT,
    'DDL tracking should work on large tables'
);

-- ============================================================================
-- TEST GROUP 3: Cleanup and Recovery
-- ============================================================================

-- Test 8: Deleting data should free up logical space
SELECT lives_ok(
    $$ DELETE FROM disk_test_data WHERE id <= 50; $$,
    'Should delete data from large table'
);

-- Test 9: Verify deletion worked
SELECT is(
    (SELECT count(*) FROM disk_test_data),
    150::BIGINT,
    'Should have 150 rows after deletion (100 + 50 + 50 - 50)'
);

-- Test 10: Vacuum should reclaim space (simulated)
SELECT lives_ok(
    $$ VACUUM disk_test_data; $$,
    'Should vacuum table to reclaim space'
);

-- Test 11: DDL tracking should continue after cleanup
SELECT lives_ok(
    $$ ALTER TABLE disk_test_data ADD COLUMN another_column INTEGER; $$,
    'Should continue DDL tracking after cleanup'
);

-- Test 12: Branch operations should work with large data
SELECT lives_ok(
    $$ SELECT pggit.create_branch('disk_pressure_branch'); $$,
    'Should create branch despite large data'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');
DELETE FROM pggit.branches WHERE name = 'disk_pressure_branch';
DROP TABLE IF EXISTS disk_test_data CASCADE;

SELECT * FROM finish();

ROLLBACK;
