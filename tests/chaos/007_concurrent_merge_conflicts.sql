-- Chaos Test: Concurrent Merge Conflicts
-- Test File: 007_concurrent_merge_conflicts.sql
-- Purpose: Test merge resolution under high concurrency

BEGIN;

SELECT plan(20);

-- ============================================================================
-- SETUP: Create base state and multiple conflict branches
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create base table
CREATE TABLE merge_conflict_test (
    id SERIAL PRIMARY KEY,
    value TEXT,
    version INTEGER DEFAULT 1
);

INSERT INTO merge_conflict_test (value) VALUES 
    ('original_a'), ('original_b'), ('original_c');

-- Create feature branch 1
SELECT pggit.create_branch('feature_1');
SELECT pggit.switch_branch('feature_1');
UPDATE merge_conflict_test SET value = 'modified_by_feature_1', version = 2 WHERE id = 1;
INSERT INTO merge_conflict_test (value) VALUES ('new_from_feature_1');

-- Create feature branch 2
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('feature_2');
SELECT pggit.switch_branch('feature_2');
UPDATE merge_conflict_test SET value = 'modified_by_feature_2', version = 2 WHERE id = 1;
INSERT INTO merge_conflict_test (value) VALUES ('new_from_feature_2');

-- Create feature branch 3
SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('feature_3');
SELECT pggit.switch_branch('feature_3');
UPDATE merge_conflict_test SET value = 'modified_by_feature_3', version = 2 WHERE id = 1;
INSERT INTO merge_conflict_test (value) VALUES ('new_from_feature_3');

-- ============================================================================
-- TEST GROUP 1: Conflict Detection
-- ============================================================================

-- Test 1: Detect conflicts between feature_1 and main
SELECT pggit.switch_branch('main');
SELECT cmp_ok(
    (SELECT (pggit.detect_conflicts('feature_1', 'main')->>'conflict_count')::int),
    '>',
    0::INTEGER,
    'Should detect conflicts between feature_1 and main'
);

-- Test 2: Detect conflicts between feature_2 and main
SELECT cmp_ok(
    (SELECT (pggit.detect_conflicts('feature_2', 'main')->>'conflict_count')::int),
    '>',
    0::INTEGER,
    'Should detect conflicts between feature_2 and main'
);

-- Test 3: Detect conflicts between feature_3 and main
SELECT cmp_ok(
    (SELECT (pggit.detect_conflicts('feature_3', 'main')->>'conflict_count')::int),
    '>',
    0::INTEGER,
    'Should detect conflicts between feature_3 and main'
);

-- Test 4: All features should conflict on same row
SELECT results_eq(
    $$ SELECT count(*) > 0 FROM pggit.detect_conflicts('feature_1', 'main')::TEXT $$,
    ARRAY[true]::BOOLEAN[],
    'Should detect conflict details'
);

-- ============================================================================
-- TEST GROUP 2: Concurrent Merge Initiation
-- ============================================================================

-- Test 5: Initiate merge for feature_1
SELECT pggit.switch_branch('main');
SELECT lives_ok(
    $$ SELECT pggit.merge('feature_1', 'main', 'manual'); $$,
    'Should initiate merge for feature_1'
);

-- Test 6: Merge status should be awaiting_resolution
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history 
       WHERE source_branch = 'feature_1' ORDER BY initiated_at DESC LIMIT 1 $$,
    ARRAY['awaiting_resolution']::TEXT[],
    'Merge should be awaiting resolution'
);

-- Test 7: Get conflict details
SELECT lives_ok(
    $$ 
    SELECT pggit.get_merge_conflicts(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'feature_1' ORDER BY initiated_at DESC LIMIT 1)
    );
    $$,
    'Should get conflict details'
);

-- ============================================================================
-- TEST GROUP 3: Sequential Conflict Resolution
-- ============================================================================

-- Test 8: Resolve first conflict using theirs strategy
SELECT lives_ok(
    $$ 
    SELECT pggit.resolve_conflict(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'feature_1' ORDER BY initiated_at DESC LIMIT 1),
        'merge_conflict_test',
        1,
        'theirs'
    );
    $$,
    'Should resolve conflict with theirs strategy'
);

-- Test 9: Complete the merge
SELECT lives_ok(
    $$ 
    SELECT pggit.complete_merge(
        (SELECT id FROM pggit.merge_history WHERE source_branch = 'feature_1' ORDER BY initiated_at DESC LIMIT 1)
    );
    $$,
    'Should complete merge'
);

-- Test 10: Verify merge completed
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history 
       WHERE source_branch = 'feature_1' AND status = 'completed' $$,
    ARRAY['completed']::TEXT[],
    'Merge should show as completed'
);

-- ============================================================================
-- TEST GROUP 4: Cascading Merges
-- ============================================================================

-- Test 11: Verify feature_1 changes are in main
SELECT results_eq(
    $$ SELECT value FROM merge_conflict_test WHERE id = 1 $$,
    ARRAY['modified_by_feature_1']::TEXT[],
    'Feature 1 changes should be in main'
);

-- Test 12: Merge feature_2 (will have new conflicts)
SELECT lives_ok(
    $$ SELECT pggit.merge('feature_2', 'main', 'manual'); $$,
    'Should initiate merge for feature_2'
);

-- Test 13: Resolve feature_2 conflicts
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_merge_id UUID;
    BEGIN
        SELECT id INTO v_merge_id FROM pggit.merge_history 
        WHERE source_branch = 'feature_2' AND status = 'awaiting_resolution' 
        ORDER BY initiated_at DESC LIMIT 1;
        
        PERFORM pggit.resolve_conflict(v_merge_id, 'merge_conflict_test', 1, 'theirs');
        PERFORM pggit.complete_merge(v_merge_id);
    END;
    $$;
    $$,
    'Should resolve and complete feature_2 merge'
);

-- Test 14: Verify feature_2 changes
SELECT results_eq(
    $$ SELECT value FROM merge_conflict_test WHERE id = 1 $$,
    ARRAY['modified_by_feature_2']::TEXT[],
    'Feature 2 changes should now be in main'
);

-- ============================================================================
-- TEST GROUP 5: Merge History Integrity
-- ============================================================================

-- Test 15: Both merges should be in history
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.merge_history 
     WHERE source_branch IN ('feature_1', 'feature_2') AND status = 'completed'),
    '>=',
    2::BIGINT,
    'Both merges should be in history'
);

-- Test 16: Merge statistics should be accurate
SELECT lives_ok(
    $$ SELECT * FROM pggit.get_merge_stats(); $$,
    'Should get merge statistics'
);

-- Test 17: System should still be healthy
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'merge_operations' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should show healthy merges'
);

-- Test 18: New data from merged branches should exist
SELECT cmp_ok(
    (SELECT count(*) FROM merge_conflict_test),
    '>=',
    4::BIGINT,
    'Should have data from merged branches'
);

-- ============================================================================
-- TEST GROUP 6: Abort and Cleanup
-- ============================================================================

-- Test 19: Clean up incomplete merge (feature_3)
SELECT pggit.switch_branch('main');
DO $$
DECLARE
    v_merge_id UUID;
BEGIN
    SELECT id INTO v_merge_id FROM pggit.merge_history 
    WHERE source_branch = 'feature_3' AND status IN ('in_progress', 'awaiting_resolution')
    ORDER BY initiated_at DESC LIMIT 1;
    
    IF v_merge_id IS NOT NULL THEN
        PERFORM pggit.abort_merge(v_merge_id, 'Test cleanup');
    END IF;
END;
$$;

SELECT pass('Should clean up incomplete merge');

-- Test 20: Final state should be consistent
SELECT is(
    (SELECT count(*) FROM merge_conflict_test WHERE id = 1),
    1::BIGINT,
    'Final state should have single row for id=1'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name LIKE 'feature_%';

-- Clean up test data
DROP TABLE IF EXISTS merge_conflict_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'merge_conflict_test';

SELECT * FROM finish();

ROLLBACK;
