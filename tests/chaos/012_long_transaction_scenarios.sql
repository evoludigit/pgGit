-- Chaos Test: Long Transaction Scenarios
-- Test File: 012_long_transaction_scenarios.sql
-- Purpose: Test behavior with long-running transactions and timeouts

BEGIN;

SELECT plan(15);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test table
CREATE TABLE long_tx_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Insert initial data
INSERT INTO long_tx_test (data) 
SELECT 'initial_' || i FROM generate_series(1, 30) AS i;

-- ============================================================================
-- TEST GROUP 1: Basic Long Transaction
-- ============================================================================

-- Test 1: Simulate long transaction with multiple operations
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Long transaction simulation
        UPDATE long_tx_test SET data = 'modified_1' WHERE id = 1;
        PERFORM pg_sleep(0.1);  -- 100ms delay
        
        UPDATE long_tx_test SET data = 'modified_2' WHERE id = 2;
        PERFORM pg_sleep(0.1);
        
        UPDATE long_tx_test SET data = 'modified_3' WHERE id = 3;
    END;
    $$;
    $$,
    'Should complete long transaction'
);

-- Test 2: Verify all updates applied
SELECT results_eq(
    $$ SELECT count(*) FROM long_tx_test WHERE data LIKE 'modified_%' $$,
    ARRAY[3]::BIGINT[],
    'Should have 3 modified rows'
);

-- ============================================================================
-- TEST GROUP 2: DDL During Active Transaction
-- ============================================================================

-- Test 3: DDL should work during long transaction
SELECT lives_ok(
    $$ ALTER TABLE long_tx_test ADD COLUMN new_field TEXT; $$,
    'Should add column during active operations'
);

-- Test 4: DDL tracking should work
SELECT results_eq(
    $$ SELECT count(*) > 0 FROM pggit.objects WHERE object_name = 'long_tx_test' AND object_type = 'TABLE' $$,
    ARRAY[true]::BOOLEAN[],
    'DDL tracking should capture table'
);

-- Test 5: Can still modify data after DDL
SELECT lives_ok(
    $$ UPDATE long_tx_test SET new_field = 'populated' WHERE id <= 5; $$,
    'Should update data after DDL'
);

-- ============================================================================
-- TEST GROUP 3: Branch Operations with Long Transactions
-- ============================================================================

-- Test 6: Create branch during "long" operation
SELECT lives_ok(
    $$ SELECT pggit.create_branch('long_tx_branch'); $$,
    'Should create branch during operations'
);

-- Test 7: Switch to branch
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('long_tx_branch'); $$,
    'Should switch to new branch'
);

-- Test 8: Modify in branch
SELECT pggit.switch_branch('long_tx_branch');
SELECT lives_ok(
    $$ 
    UPDATE long_tx_test SET data = 'branch_modified' WHERE id = 10;
    INSERT INTO long_tx_test (data) VALUES ('branch_new');
    $$,
    'Should modify data in branch'
);

-- Test 9: Verify isolation
SELECT results_eq(
    $$ SELECT count(*) FROM long_tx_test WHERE data = 'branch_modified' $$,
    ARRAY[1]::BIGINT[],
    'Branch modification should be visible'
);

-- Test 10: Main branch should not see changes
SELECT pggit.switch_branch('main');
SELECT results_eq(
    $$ SELECT count(*) FROM long_tx_test WHERE data = 'branch_modified' $$,
    ARRAY[0]::BIGINT[],
    'Main should not see branch changes'
);

-- ============================================================================
-- TEST GROUP 4: Transaction Boundaries
-- ============================================================================

-- Test 11: Multiple small transactions vs one large
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Multiple small transactions
        FOR i IN 4..6 LOOP
            UPDATE long_tx_test SET data = 'small_tx_' || i WHERE id = i;
        END LOOP;
    END;
    $$;
    $$,
    'Should handle multiple small transactions'
);

-- Test 12: Verify all updates
SELECT results_eq(
    $$ SELECT count(*) FROM long_tx_test WHERE data LIKE 'small_tx_%' $$,
    ARRAY[3]::BIGINT[],
    'Should have 3 small_tx rows'
);

-- ============================================================================
-- TEST GROUP 5: Commit and History
-- ============================================================================

-- Test 13: Commit long transaction work
SELECT lives_ok(
    $$ SELECT pggit.commit('Long transaction test commit'); $$,
    'Should commit long transaction work'
);

-- Test 14: History should capture all changes
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.get_commit_history('main') 
     WHERE commit_message LIKE '%Long transaction%'),
    '>=',
    1::BIGINT,
    'Should capture long transaction commit'
);

-- Test 15: System health after long transaction
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after long transactions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'long_tx_branch';

-- Clean up test data
DROP TABLE IF EXISTS long_tx_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'long_tx_test';

SELECT * FROM finish();

ROLLBACK;
