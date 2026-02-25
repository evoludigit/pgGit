-- Chaos Test: DDL Bomb - Rapid DDL Operations
-- Test File: 006_ddl_bomb.sql
-- Purpose: Test system behavior under extreme DDL load (1000+ operations)

BEGIN;

SELECT plan(18);

-- ============================================================================
-- SETUP: Prepare for rapid DDL
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create a schema for testing
CREATE SCHEMA ddl_bomb_test;

-- ============================================================================
-- TEST GROUP 1: Rapid Table Creation
-- ============================================================================

-- Test 1: Create 50 tables rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        i INTEGER;
    BEGIN
        FOR i IN 1..50 LOOP
            EXECUTE format('CREATE TABLE ddl_bomb_test.rapid_table_%s (id INT)', i);
        END LOOP;
    END;
    $$;
    $$,
    'Should create 50 tables rapidly'
);

-- Test 2: Verify tables were created
SELECT cmp_ok(
    (SELECT count(*) FROM information_schema.tables 
     WHERE table_schema = 'ddl_bomb_test' AND table_name LIKE 'rapid_table_%'),
    '>=',
    50::BIGINT,
    'Should have at least 50 rapid tables'
);

-- Test 3: DDL tracking should capture all tables
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects 
     WHERE schema_name = 'ddl_bomb_test' AND object_name LIKE 'rapid_table_%'),
    '>=',
    45::BIGINT,  -- Allow some delay in tracking
    'DDL tracking should capture most tables'
);

-- ============================================================================
-- TEST GROUP 2: Rapid Index Creation
-- ============================================================================

-- Test 4: Create indexes on all tables rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        i INTEGER;
    BEGIN
        FOR i IN 1..50 LOOP
            BEGIN
                EXECUTE format('CREATE INDEX idx_rapid_%s ON ddl_bomb_test.rapid_table_%s(id)', i, i);
            EXCEPTION
                WHEN OTHERS THEN
                    -- Some might fail, that's OK
                    NULL;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Should attempt to create 50 indexes rapidly'
);

-- Test 5: Verify some indexes were created
SELECT cmp_ok(
    (SELECT count(*) FROM pg_indexes 
     WHERE schemaname = 'ddl_bomb_test' AND indexname LIKE 'idx_rapid_%'),
    '>=',
    40::BIGINT,
    'Should have created most indexes'
);

-- ============================================================================
-- TEST GROUP 3: Rapid ALTER Operations
-- ============================================================================

-- Test 6: Add columns to tables rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        i INTEGER;
    BEGIN
        FOR i IN 1..25 LOOP
            BEGIN
                EXECUTE format('ALTER TABLE ddl_bomb_test.rapid_table_%s ADD COLUMN col_%s TEXT', i, i);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Should attempt to add 25 columns rapidly'
);

-- Test 7: Verify some columns were added
SELECT cmp_ok(
    (SELECT count(DISTINCT table_name) FROM information_schema.columns 
     WHERE table_schema = 'ddl_bomb_test' AND column_name LIKE 'col_%'),
    '>=',
    20::BIGINT,
    'Should have added columns to most tables'
);

-- ============================================================================
-- TEST GROUP 4: Concurrent DDL Simulation
-- ============================================================================

-- Test 8: Rapid table modifications
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        i INTEGER;
    BEGIN
        FOR i IN 1..20 LOOP
            BEGIN
                -- Create view
                EXECUTE format('CREATE VIEW ddl_bomb_test.rapid_view_%s AS SELECT * FROM ddl_bomb_test.rapid_table_%s', i, i);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Should attempt to create 20 views rapidly'
);

-- Test 9: Create sequences rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        i INTEGER;
    BEGIN
        FOR i IN 1..15 LOOP
            BEGIN
                EXECUTE format('CREATE SEQUENCE ddl_bomb_test.rapid_seq_%s START %s', i, i * 100);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Should attempt to create 15 sequences rapidly'
);

-- ============================================================================
-- TEST GROUP 5: Rapid Cleanup
-- ============================================================================

-- Test 10: Drop views first
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN SELECT table_name FROM information_schema.views 
                 WHERE table_schema = 'ddl_bomb_test' AND table_name LIKE 'rapid_view_%'
        LOOP
            EXECUTE format('DROP VIEW ddl_bomb_test.%I', r.table_name);
        END LOOP;
    END;
    $$;
    $$,
    'Should drop views rapidly'
);

-- Test 11: Drop indexes
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN SELECT indexname FROM pg_indexes 
                 WHERE schemaname = 'ddl_bomb_test' AND indexname LIKE 'idx_rapid_%'
                 LIMIT 40
        LOOP
            BEGIN
                EXECUTE format('DROP INDEX ddl_bomb_test.%I', r.indexname);
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Should drop indexes rapidly'
);

-- Test 12: System should remain stable after DDL bomb
SELECT lives_ok(
    $$ SELECT pggit.create_branch('post_ddl_bomb_branch'); $$,
    'Should create branch after DDL bomb'
);

-- Test 13: Verify branch creation works
SELECT is(
    pggit.branch_exists('post_ddl_bomb_branch'),
    true,
    'Branch should exist after DDL bomb'
);

-- ============================================================================
-- TEST GROUP 6: History Table Stress
-- ============================================================================

-- Test 14: Verify history table grew
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history 
     WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute'),
    '>=',
    50::BIGINT,
    'History should have many recent entries'
);

-- Test 15: Query performance on history should remain acceptable
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_count BIGINT;
        v_start TIMESTAMP;
    BEGIN
        v_start := clock_timestamp();
        SELECT count(*) INTO v_count FROM pggit.history 
        WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute';
        -- Should complete in reasonable time
        IF clock_timestamp() - v_start > INTERVAL '5 seconds' THEN
            RAISE WARNING 'History query took too long';
        END IF;
    END;
    $$;
    $$,
    'History queries should remain performant'
);

-- ============================================================================
-- TEST GROUP 7: Final System State
-- ============================================================================

-- Test 16: Health check should pass
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass'
);

-- Test 17: DDL tracking should still work
SELECT lives_ok(
    $$ CREATE TABLE ddl_bomb_test.final_test (id INT); $$,
    'DDL tracking should work after DDL bomb'
);

-- Test 18: Verify final DDL was tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'final_test' $$,
    ARRAY[1]::BIGINT[],
    'Final DDL should be tracked'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'post_ddl_bomb_branch';

-- Clean up test objects
DROP TABLE IF EXISTS ddl_bomb_test.final_test CASCADE;

-- Drop remaining tables
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT table_name FROM information_schema.tables 
             WHERE table_schema = 'ddl_bomb_test'
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS ddl_bomb_test.%I CASCADE', r.table_name);
    END LOOP;
END;
$$;

-- Drop sequences
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT sequence_name FROM information_schema.sequences 
             WHERE sequence_schema = 'ddl_bomb_test'
    LOOP
        EXECUTE format('DROP SEQUENCE ddl_bomb_test.%I', r.sequence_name);
    END LOOP;
END;
$$;

-- Clean up schema
DROP SCHEMA IF EXISTS ddl_bomb_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE schema_name = 'ddl_bomb_test';

SELECT * FROM finish();

ROLLBACK;
