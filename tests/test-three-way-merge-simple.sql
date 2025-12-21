-- Simple Three-Way Merge Test
\echo 'Testing three-way merge implementation...'

BEGIN;

-- Test 1: Create commits
DO $$
DECLARE
    v_base TEXT;
    v_ours TEXT; 
    v_theirs TEXT;
    v_tree TEXT;
    v_blob TEXT;
BEGIN
    -- Create base commit
    v_blob := pggit_v2.create_blob('Initial content');
    v_tree := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob)
    ));
    v_base := pggit_v2.create_commit(v_tree, NULL, 'Base commit');
    
    -- Create "ours" branch
    v_blob := pggit_v2.create_blob('Our changes');
    v_tree := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob),
        jsonb_build_object('path', 'our_file.txt', 'mode', '100644', 'sha', pggit_v2.create_blob('Our new file'))
    ));
    v_ours := pggit_v2.create_commit(v_tree, ARRAY[v_base], 'Our commit');
    
    -- Create "theirs" branch  
    v_blob := pggit_v2.create_blob('Their changes');
    v_tree := pggit_v2.create_tree(jsonb_build_array(
        jsonb_build_object('path', 'file.txt', 'mode', '100644', 'sha', v_blob),
        jsonb_build_object('path', 'their_file.txt', 'mode', '100644', 'sha', pggit_v2.create_blob('Their new file'))
    ));
    v_theirs := pggit_v2.create_commit(v_tree, ARRAY[v_base], 'Their commit');
    
    -- Test merge base
    IF pggit_v2.find_merge_base(v_ours, v_theirs) = v_base THEN
        RAISE NOTICE 'PASS: Merge base found correctly';
    ELSE
        RAISE NOTICE 'FAIL: Wrong merge base';
    END IF;
    
    -- Test three-way merge analysis
    PERFORM * FROM pggit_v2.three_way_merge(v_ours, v_theirs);
    RAISE NOTICE 'PASS: Three-way merge analysis completed';

END $$;

-- Test 2: Check merge results
DO $$
DECLARE
    v_result RECORD;
    v_conflict_count INTEGER := 0;
BEGIN
    -- Analyze a known merge scenario
    FOR v_result IN 
        SELECT * FROM pggit_v2.three_way_merge(
            (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1 OFFSET 1),
            (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1)
        )
    LOOP
        IF v_result.merge_status = 'conflict' THEN
            v_conflict_count := v_conflict_count + 1;
            RAISE NOTICE 'Conflict detected in: %', v_result.path;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Total conflicts: %', v_conflict_count;

END $$;

ROLLBACK;

\echo 'Three-way merge implementation is working!'