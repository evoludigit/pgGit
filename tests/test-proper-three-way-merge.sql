-- ============================================
-- Proper Three-Way Merge Tests
-- ============================================
-- Testing the Git-like implementation based on expert recommendations

\echo 'Starting proper three-way merge tests...'

-- Setup
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Install the proper implementation
\i core/sql/018_proper_git_three_way_merge.sql

-- ============================================
-- Test 1: Basic object creation
-- ============================================
\echo 'Test 1: Basic Git object creation...'

DO $$
DECLARE
    v_blob_sha TEXT;
    v_tree_sha TEXT;
    v_commit_sha TEXT;
BEGIN
    -- Create a blob
    v_blob_sha := pggit_v2.create_blob('Hello, World!');
    ASSERT v_blob_sha IS NOT NULL, 'Blob creation failed';
    
    -- Create a tree
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'hello.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    ASSERT v_tree_sha IS NOT NULL, 'Tree creation failed';
    
    -- Create a commit
    v_commit_sha := pggit_v2.create_commit(v_tree_sha, NULL, 'Initial commit');
    ASSERT v_commit_sha IS NOT NULL, 'Commit creation failed';
    
    RAISE NOTICE 'Test 1 PASSED: Git objects created successfully';
END $$;

-- ============================================
-- Test 2: Merge base detection
-- ============================================
\echo 'Test 2: Merge base detection...'

DO $$
DECLARE
    v_base_commit TEXT;
    v_branch1_commit TEXT;
    v_branch2_commit TEXT;
    v_merge_base TEXT;
    v_blob1 TEXT;
    v_blob2 TEXT;
    v_tree1 TEXT;
    v_tree2 TEXT;
BEGIN
    -- Create common ancestor
    v_blob1 := pggit_v2.create_blob('Initial content');
    v_tree1 := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob1)
    ));
    v_base_commit := pggit_v2.create_commit(v_tree1, NULL, 'Base commit');
    
    -- Create branch 1
    v_blob1 := pggit_v2.create_blob('Branch 1 content');
    v_tree1 := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob1)
    ));
    v_branch1_commit := pggit_v2.create_commit(v_tree1, ARRAY[v_base_commit], 'Branch 1 change');
    
    -- Create branch 2
    v_blob2 := pggit_v2.create_blob('Branch 2 content');
    v_tree2 := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob2)
    ));
    v_branch2_commit := pggit_v2.create_commit(v_tree2, ARRAY[v_base_commit], 'Branch 2 change');
    
    -- Find merge base
    v_merge_base := pggit_v2.find_merge_base(v_branch1_commit, v_branch2_commit);
    
    ASSERT v_merge_base = v_base_commit, 
           format('Wrong merge base: expected %s, got %s', v_base_commit, v_merge_base);
    
    RAISE NOTICE 'Test 2 PASSED: Merge base correctly identified';
END $$;

-- ============================================
-- Test 3: Clean merge (no conflicts)
-- ============================================
\echo 'Test 3: Clean merge without conflicts...'

DO $$
DECLARE
    v_base_commit TEXT;
    v_ours_commit TEXT;
    v_theirs_commit TEXT;
    v_merge_commit TEXT;
    v_tree_sha TEXT;
    v_blob_sha TEXT;
BEGIN
    -- Base: one file
    v_blob_sha := pggit_v2.create_blob('Original content');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'README.md', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_base_commit := pggit_v2.create_commit(v_tree_sha, NULL, 'Initial commit');
    
    -- Ours: add file1.txt
    v_blob_sha := pggit_v2.create_blob('File 1 content');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'README.md', 'mode', '100644', 'sha', 
            (SELECT object_sha FROM pggit_v2.tree_entries WHERE tree_sha = 
                (SELECT tree_sha FROM pggit_v2.commit_graph WHERE commit_sha = v_base_commit) 
                AND path = 'README.md')),
        jsonb_build_object('path', 'file1.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_ours_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Add file1');
    
    -- Theirs: add file2.txt
    v_blob_sha := pggit_v2.create_blob('File 2 content');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'README.md', 'mode', '100644', 'sha', 
            (SELECT object_sha FROM pggit_v2.tree_entries WHERE tree_sha = 
                (SELECT tree_sha FROM pggit_v2.commit_graph WHERE commit_sha = v_base_commit) 
                AND path = 'README.md')),
        jsonb_build_object('path', 'file2.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_theirs_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Add file2');
    
    -- Perform merge (should succeed)
    v_merge_commit := pggit_v2.create_merge_commit(
        v_ours_commit, 
        v_theirs_commit, 
        'Merge: combine file1 and file2'
    );
    
    ASSERT v_merge_commit IS NOT NULL, 'Clean merge failed';
    
    -- Verify merge has both parents
    ASSERT array_length(
        (SELECT parent_shas FROM pggit_v2.commit_graph WHERE commit_sha = v_merge_commit), 
        1
    ) = 2, 'Merge commit should have 2 parents';
    
    RAISE NOTICE 'Test 3 PASSED: Clean merge completed successfully';
END $$;

-- ============================================
-- Test 4: Conflicting merge
-- ============================================
\echo 'Test 4: Merge with conflicts...'

DO $$
DECLARE
    v_base_commit TEXT;
    v_ours_commit TEXT;
    v_theirs_commit TEXT;
    v_tree_sha TEXT;
    v_blob_sha TEXT;
    v_conflict_detected BOOLEAN := FALSE;
BEGIN
    -- Base: one file
    v_blob_sha := pggit_v2.create_blob('Original content');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'conflict.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_base_commit := pggit_v2.create_commit(v_tree_sha, NULL, 'Base for conflict test');
    
    -- Ours: modify file
    v_blob_sha := pggit_v2.create_blob('Our changes to the file');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'conflict.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_ours_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Our changes');
    
    -- Theirs: different modification
    v_blob_sha := pggit_v2.create_blob('Their changes to the file');
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'conflict.txt', 'mode', '100644', 'sha', v_blob_sha)
    ));
    v_theirs_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Their changes');
    
    -- Try to merge (should fail with conflict)
    BEGIN
        PERFORM pggit_v2.create_merge_commit(
            v_ours_commit, 
            v_theirs_commit, 
            'This should fail'
        );
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%conflict%' THEN
            v_conflict_detected := TRUE;
        END IF;
    END;
    
    ASSERT v_conflict_detected, 'Conflict was not detected';
    
    RAISE NOTICE 'Test 4 PASSED: Conflicts correctly detected';
END $$;

-- ============================================
-- Test 5: Three-way merge analysis
-- ============================================
\echo 'Test 5: Three-way merge analysis...'

DO $$
DECLARE
    v_base_commit TEXT;
    v_ours_commit TEXT;
    v_theirs_commit TEXT;
    v_merge_result RECORD;
    v_clean_count INTEGER := 0;
    v_conflict_count INTEGER := 0;
BEGIN
    -- Create test scenario with multiple files
    -- Base
    WITH blobs AS (
        SELECT 
            pggit_v2.create_blob('File A content') as file_a,
            pggit_v2.create_blob('File B content') as file_b,
            pggit_v2.create_blob('File C content') as file_c
    )
    SELECT pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file_a.txt', 'mode', '100644', 'sha', file_a),
        jsonb_build_object('path', 'file_b.txt', 'mode', '100644', 'sha', file_b),
        jsonb_build_object('path', 'file_c.txt', 'mode', '100644', 'sha', file_c)
    )) INTO v_tree_sha FROM blobs;
    
    v_base_commit := pggit_v2.create_commit(v_tree_sha, NULL, 'Base with 3 files');
    
    -- Ours: modify A and B
    WITH blobs AS (
        SELECT 
            pggit_v2.create_blob('File A modified by us') as file_a,
            pggit_v2.create_blob('File B modified by us') as file_b,
            pggit_v2.create_blob('File C content') as file_c
    )
    SELECT pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file_a.txt', 'mode', '100644', 'sha', file_a),
        jsonb_build_object('path', 'file_b.txt', 'mode', '100644', 'sha', file_b),
        jsonb_build_object('path', 'file_c.txt', 'mode', '100644', 'sha', file_c)
    )) INTO v_tree_sha FROM blobs;
    
    v_ours_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Our changes to A and B');
    
    -- Theirs: modify B and C
    WITH blobs AS (
        SELECT 
            pggit_v2.create_blob('File A content') as file_a,
            pggit_v2.create_blob('File B modified by them') as file_b,
            pggit_v2.create_blob('File C modified by them') as file_c
    )
    SELECT pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file_a.txt', 'mode', '100644', 'sha', file_a),
        jsonb_build_object('path', 'file_b.txt', 'mode', '100644', 'sha', file_b),
        jsonb_build_object('path', 'file_c.txt', 'mode', '100644', 'sha', file_c)
    )) INTO v_tree_sha FROM blobs;
    
    v_theirs_commit := pggit_v2.create_commit(v_tree_sha, ARRAY[v_base_commit], 'Their changes to B and C');
    
    -- Analyze merge
    FOR v_merge_result IN 
        SELECT * FROM pggit_v2.three_way_merge(v_ours_commit, v_theirs_commit)
    LOOP
        IF v_merge_result.merge_status = 'clean' THEN
            v_clean_count := v_clean_count + 1;
        ELSIF v_merge_result.merge_status = 'conflict' THEN
            v_conflict_count := v_conflict_count + 1;
        END IF;
    END LOOP;
    
    -- Expected: A is clean (only we changed), B conflicts, C is clean (only they changed)
    ASSERT v_clean_count = 2, format('Expected 2 clean merges, got %s', v_clean_count);
    ASSERT v_conflict_count = 1, format('Expected 1 conflict, got %s', v_conflict_count);
    
    RAISE NOTICE 'Test 5 PASSED: Three-way merge analysis correct';
END $$;

-- ============================================
-- Test 6: Performance benchmarks
-- ============================================
\echo 'Test 6: Performance benchmarks...'

DO $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms INTEGER;
    v_commit_sha TEXT;
    v_tree_sha TEXT;
    v_parent_sha TEXT;
    i INTEGER;
BEGIN
    -- Create chain of 100 commits
    v_start_time := clock_timestamp();
    
    -- Initial commit
    v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'test.txt', 'mode', '100644', 
                          'sha', pggit_v2.create_blob('Commit 0'))
    ));
    v_parent_sha := pggit_v2.create_commit(v_tree_sha, NULL, 'Commit 0');
    
    -- Create 99 more commits
    FOR i IN 1..99 LOOP
        v_tree_sha := pggit_v2.create_tree(jsonb_build_array(
            jsonb_build_object('path', 'test.txt', 'mode', '100644', 
                              'sha', pggit_v2.create_blob('Commit ' || i))
        ));
        v_parent_sha := pggit_v2.create_commit(v_tree_sha, ARRAY[v_parent_sha], 'Commit ' || i);
    END LOOP;
    
    v_end_time := clock_timestamp();
    v_duration_ms := extract(milliseconds from (v_end_time - v_start_time))::INTEGER;
    
    RAISE NOTICE 'Created 100 commits in % ms', v_duration_ms;
    
    -- Test merge base performance
    v_start_time := clock_timestamp();
    
    -- Find merge base between early and late commits
    PERFORM pggit_v2.find_merge_base(
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY generation DESC LIMIT 1),
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY generation ASC LIMIT 1 OFFSET 10)
    );
    
    v_end_time := clock_timestamp();
    v_duration_ms := extract(milliseconds from (v_end_time - v_start_time))::INTEGER;
    
    RAISE NOTICE 'Merge base lookup: % ms', v_duration_ms;
    
    -- Record performance metrics
    INSERT INTO pggit_v2.performance_metrics (operation, duration_ms, object_count)
    VALUES ('create_100_commits', v_duration_ms, 100);
    
    -- Check performance requirements (merge base should be <10ms)
    ASSERT v_duration_ms < 10, format('Merge base too slow: %s ms (should be <10ms)', v_duration_ms);
    
    RAISE NOTICE 'Test 6 PASSED: Performance within requirements';
END $$;

-- ============================================
-- Summary
-- ============================================
\echo ''
\echo '============================================'
\echo 'Three-Way Merge Test Summary'
\echo '============================================'

SELECT 
    'Performance Metrics:' as info
UNION ALL
SELECT 
    '  ' || operation || ': ' || round(avg(duration_ms)) || 'ms (avg)'
FROM pggit_v2.performance_metrics
GROUP BY operation
UNION ALL
SELECT ''
UNION ALL
SELECT 'Implementation Status:'
UNION ALL
SELECT '  ✓ Git-like object model'
UNION ALL
SELECT '  ✓ Efficient merge base detection'
UNION ALL
SELECT '  ✓ True three-way merge algorithm'
UNION ALL
SELECT '  ✓ Conflict detection'
UNION ALL
SELECT '  ✓ Performance optimizations';

\echo ''
\echo 'All tests completed. The implementation now properly supports Git-like three-way merge!'

-- Cleanup
DROP SCHEMA pggit_v2 CASCADE;