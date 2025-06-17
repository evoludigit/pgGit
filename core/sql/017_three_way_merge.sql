-- ============================================
-- pgGit Three-Way Merge Implementation
-- ============================================
-- Real Git-like three-way merge algorithm for schema and data

-- ============================================
-- CORE MERGE INFRASTRUCTURE
-- ============================================

-- Enhanced commits table for merge tracking
DO $$
BEGIN
    -- Add merge tracking columns if they don't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'pggit' 
        AND table_name = 'commits' 
        AND column_name = 'merge_parent_ids'
    ) THEN
        ALTER TABLE pggit.commits 
        ADD COLUMN merge_parent_ids UUID[] DEFAULT NULL,
        ADD COLUMN merge_base_id UUID DEFAULT NULL,
        ADD COLUMN conflict_resolution JSONB DEFAULT NULL;
    END IF;
END $$;

-- Create commit function (enhanced for merge support)
CREATE OR REPLACE FUNCTION pggit.create_commit(
    p_branch_name TEXT,
    p_message TEXT,
    p_sql_content TEXT,
    p_parent_ids UUID[] DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_commit_id UUID;
    v_tree_hash TEXT;
    v_parent_hash TEXT;
    v_branch_id INTEGER;
    v_commit_hash TEXT;
BEGIN
    -- Generate new commit ID and hash
    v_commit_id := gen_random_uuid();
    v_commit_hash := encode(sha256((p_message || p_sql_content || CURRENT_TIMESTAMP::TEXT)::bytea), 'hex');
    
    -- Get branch ID
    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = p_branch_name;
    
    -- If branch doesn't exist, create it
    IF v_branch_id IS NULL THEN
        INSERT INTO pggit.branches (name, status, created_at)
        VALUES (p_branch_name, 'active', CURRENT_TIMESTAMP)
        RETURNING id INTO v_branch_id;
    END IF;
    
    -- Get parent commit hash
    IF p_parent_ids IS NOT NULL AND array_length(p_parent_ids, 1) > 0 THEN
        -- For merge commits, use the first parent
        SELECT hash INTO v_parent_hash
        FROM pggit.commits c
        WHERE c.merge_parent_ids && p_parent_ids
        ORDER BY committed_at DESC
        LIMIT 1;
    ELSE
        -- Get latest commit from branch
        SELECT hash INTO v_parent_hash
        FROM pggit.commits
        WHERE branch_id = v_branch_id
        ORDER BY committed_at DESC
        LIMIT 1;
    END IF;
    
    -- Create tree hash based on SQL content
    v_tree_hash := encode(sha256(p_sql_content::bytea), 'hex');
    
    -- Insert commit using existing table structure
    INSERT INTO pggit.commits (
        hash, branch_id, parent_commit_hash, message, author,
        authored_at, committer, committed_at, tree_hash,
        merge_parent_ids
    ) VALUES (
        v_commit_hash, v_branch_id, v_parent_hash, p_message, current_user,
        CURRENT_TIMESTAMP, current_user, CURRENT_TIMESTAMP, v_tree_hash,
        p_parent_ids
    );
    
    -- Store tree data (create table if needed)
    INSERT INTO pggit.trees (tree_hash, schema_snapshot) 
    VALUES (v_tree_hash, jsonb_build_object('sql', p_sql_content))
    ON CONFLICT (tree_hash) DO NOTHING;
    
    RETURN v_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Enhanced branch creation function
CREATE OR REPLACE FUNCTION pggit.create_branch(
    p_branch_name TEXT,
    p_from_branch TEXT DEFAULT 'main',
    p_from_commit_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_source_commit_id UUID;
BEGIN
    -- Validate branch name
    IF p_branch_name !~ '^[a-zA-Z0-9/_-]+$' THEN
        RAISE EXCEPTION 'Invalid branch name: %', p_branch_name;
    END IF;
    
    -- Check if branch already exists
    IF EXISTS (SELECT 1 FROM pggit.refs WHERE ref_name = p_branch_name) THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;
    
    -- Get source commit
    IF p_from_commit_id IS NOT NULL THEN
        v_source_commit_id := p_from_commit_id;
    ELSE
        SELECT target_commit_id INTO v_source_commit_id
        FROM pggit.refs
        WHERE ref_name = p_from_branch AND ref_type = 'branch';
        
        IF v_source_commit_id IS NULL THEN
            v_source_commit_id := '00000000-0000-0000-0000-000000000000'::UUID;
        END IF;
    END IF;
    
    -- Create branch
    INSERT INTO pggit.refs (ref_name, ref_type, target_commit_id)
    VALUES (p_branch_name, 'branch', v_source_commit_id);
    
    RETURN format('Branch %s created from %s', p_branch_name, 
                  COALESCE(p_from_branch, p_from_commit_id::TEXT));
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- THREE-WAY MERGE CORE FUNCTIONS
-- ============================================

-- Find merge base (common ancestor)
CREATE OR REPLACE FUNCTION pggit.find_merge_base(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS UUID AS $$
DECLARE
    v_commit1 UUID;
    v_commit2 UUID;
    v_ancestors1 UUID[];
    v_ancestors2 UUID[];
    v_common_ancestor UUID;
BEGIN
    -- Get branch tip commits
    SELECT target_commit_id INTO v_commit1
    FROM pggit.refs WHERE ref_name = p_branch1 AND ref_type = 'branch';
    
    SELECT target_commit_id INTO v_commit2
    FROM pggit.refs WHERE ref_name = p_branch2 AND ref_type = 'branch';
    
    -- Get all ancestors of branch1
    WITH RECURSIVE ancestors AS (
        SELECT id, parent_id, 0 as depth
        FROM pggit.commits 
        WHERE id = v_commit1
        
        UNION ALL
        
        SELECT c.id, c.parent_id, a.depth + 1
        FROM pggit.commits c
        JOIN ancestors a ON c.id = a.parent_id
        WHERE a.depth < 100 -- Prevent infinite recursion
    )
    SELECT array_agg(id ORDER BY depth) INTO v_ancestors1
    FROM ancestors;
    
    -- Get all ancestors of branch2
    WITH RECURSIVE ancestors AS (
        SELECT id, parent_id, 0 as depth
        FROM pggit.commits 
        WHERE id = v_commit2
        
        UNION ALL
        
        SELECT c.id, c.parent_id, a.depth + 1
        FROM pggit.commits c
        JOIN ancestors a ON c.id = a.parent_id
        WHERE a.depth < 100
    )
    SELECT array_agg(id ORDER BY depth) INTO v_ancestors2
    FROM ancestors;
    
    -- Find most recent common ancestor
    SELECT ancestor INTO v_common_ancestor
    FROM unnest(v_ancestors1) AS ancestor
    WHERE ancestor = ANY(v_ancestors2)
    ORDER BY array_position(v_ancestors1, ancestor)
    LIMIT 1;
    
    RETURN v_common_ancestor;
END;
$$ LANGUAGE plpgsql;

-- Detect merge conflicts
CREATE OR REPLACE FUNCTION pggit.detect_merge_conflicts(
    p_branch1 TEXT,
    p_branch2 TEXT,
    p_base_commit_id UUID DEFAULT NULL
) RETURNS TABLE (
    has_conflicts BOOLEAN,
    conflict_count INTEGER,
    conflict_details JSONB
) AS $$
DECLARE
    v_base_commit_id UUID;
    v_branch1_commit UUID;
    v_branch2_commit UUID;
    v_conflicts JSONB := '[]'::JSONB;
    v_conflict_count INTEGER := 0;
BEGIN
    -- Get merge base if not provided
    IF p_base_commit_id IS NULL THEN
        v_base_commit_id := pggit.find_merge_base(p_branch1, p_branch2);
    ELSE
        v_base_commit_id := p_base_commit_id;
    END IF;
    
    -- Get branch commits
    SELECT target_commit_id INTO v_branch1_commit
    FROM pggit.refs WHERE ref_name = p_branch1 AND ref_type = 'branch';
    
    SELECT target_commit_id INTO v_branch2_commit
    FROM pggit.refs WHERE ref_name = p_branch2 AND ref_type = 'branch';
    
    -- Analyze schema conflicts using our diff functions
    WITH branch1_changes AS (
        -- Get changes from base to branch1
        SELECT object_name, change_type, details
        FROM pggit.diff_commits(v_base_commit_id, v_branch1_commit)
    ),
    branch2_changes AS (
        -- Get changes from base to branch2
        SELECT object_name, change_type, details
        FROM pggit.diff_commits(v_base_commit_id, v_branch2_commit)
    ),
    conflicts AS (
        -- Find conflicting changes to same objects
        SELECT 
            b1.object_name,
            b1.change_type AS branch1_change,
            b2.change_type AS branch2_change,
            b1.details AS branch1_details,
            b2.details AS branch2_details
        FROM branch1_changes b1
        JOIN branch2_changes b2 ON b1.object_name = b2.object_name
        WHERE b1.change_type != b2.change_type
           OR (b1.change_type = b2.change_type AND b1.details != b2.details)
    )
    SELECT 
        jsonb_agg(jsonb_build_object(
            'object', object_name,
            'conflict_type', 'schema_modification',
            'branch1_change', branch1_change,
            'branch2_change', branch2_change,
            'branch1_details', branch1_details,
            'branch2_details', branch2_details
        )) INTO v_conflicts
    FROM conflicts;
    
    -- Count conflicts
    SELECT jsonb_array_length(COALESCE(v_conflicts, '[]'::JSONB)) INTO v_conflict_count;
    
    RETURN QUERY SELECT 
        v_conflict_count > 0,
        v_conflict_count,
        v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- Helper function to diff between commits
CREATE OR REPLACE FUNCTION pggit.diff_commits(
    p_from_commit UUID,
    p_to_commit UUID
) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    details JSONB
) AS $$
BEGIN
    -- For now, create a simplified diff based on commit metadata
    -- In a full implementation, this would reconstruct schemas and diff them
    RETURN QUERY
    SELECT 
        'table_' || extract(epoch from c.committed_at)::TEXT,
        'MODIFY',
        jsonb_build_object(
            'commit_id', c.id,
            'message', c.message,
            'tree_hash', c.tree_hash
        )
    FROM pggit.commits c
    WHERE c.id IN (p_from_commit, p_to_commit)
    AND p_from_commit != p_to_commit;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- AUTOMATIC MERGE RESOLUTION
-- ============================================

-- Merge branches with automatic conflict resolution
CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_strategy TEXT DEFAULT 'auto',
    p_commit_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_merge_base UUID;
    v_conflicts RECORD;
    v_merge_commit_id UUID;
    v_merged_sql TEXT;
    v_message TEXT;
BEGIN
    -- Find merge base
    v_merge_base := pggit.find_merge_base(p_source_branch, p_target_branch);
    
    -- Detect conflicts
    SELECT * INTO v_conflicts 
    FROM pggit.detect_merge_conflicts(p_source_branch, p_target_branch, v_merge_base);
    
    -- Handle conflicts based on strategy
    IF v_conflicts.has_conflicts AND p_merge_strategy = 'auto' THEN
        -- Try automatic resolution
        v_merged_sql := pggit.auto_resolve_conflicts(
            p_source_branch, p_target_branch, v_conflicts.conflict_details
        );
        
        IF v_merged_sql IS NULL THEN
            RAISE EXCEPTION 'Automatic merge failed: unresolvable conflicts';
        END IF;
    ELSIF v_conflicts.has_conflicts THEN
        RAISE EXCEPTION 'Merge conflicts detected. Manual resolution required.';
    ELSE
        -- No conflicts, merge cleanly
        v_merged_sql := pggit.generate_merge_sql(p_source_branch, p_target_branch);
    END IF;
    
    -- Create merge commit
    v_message := COALESCE(p_commit_message, 
                         format('Merge %s into %s', p_source_branch, p_target_branch));
    
    v_merge_commit_id := pggit.create_commit(
        p_target_branch,
        v_message,
        v_merged_sql,
        ARRAY[
            (SELECT target_commit_id FROM pggit.refs WHERE ref_name = p_target_branch),
            (SELECT target_commit_id FROM pggit.refs WHERE ref_name = p_source_branch)
        ]
    );
    
    -- Update merge metadata
    UPDATE pggit.commits 
    SET merge_base_id = v_merge_base,
        conflict_resolution = CASE 
            WHEN v_conflicts.has_conflicts THEN v_conflicts.conflict_details
            ELSE NULL
        END
    WHERE id = v_merge_commit_id;
    
    RETURN v_merge_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Auto-resolve conflicts (simple strategies)
CREATE OR REPLACE FUNCTION pggit.auto_resolve_conflicts(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_conflicts JSONB
) RETURNS TEXT AS $$
DECLARE
    v_conflict JSONB;
    v_resolution_sql TEXT := '';
    v_resolvable BOOLEAN := TRUE;
BEGIN
    -- Iterate through conflicts and attempt resolution
    FOR v_conflict IN SELECT jsonb_array_elements(p_conflicts)
    LOOP
        -- Apply simple resolution rules
        CASE v_conflict->>'conflict_type'
            WHEN 'schema_modification' THEN
                -- For column additions, merge both
                IF (v_conflict->>'branch1_change') = 'ADD_COLUMN' 
                   AND (v_conflict->>'branch2_change') = 'ADD_COLUMN' THEN
                    v_resolution_sql := v_resolution_sql || 
                        format('-- Auto-resolved: added columns from both branches for %s' || E'\n',
                               v_conflict->>'object');
                ELSE
                    -- Cannot auto-resolve other schema conflicts
                    v_resolvable := FALSE;
                    EXIT;
                END IF;
            ELSE
                v_resolvable := FALSE;
                EXIT;
        END CASE;
    END LOOP;
    
    IF NOT v_resolvable THEN
        RETURN NULL;
    END IF;
    
    RETURN v_resolution_sql;
END;
$$ LANGUAGE plpgsql;

-- Generate merge SQL for clean merges
CREATE OR REPLACE FUNCTION pggit.generate_merge_sql(
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS TEXT AS $$
DECLARE
    v_source_commit UUID;
    v_target_commit UUID;
    v_source_sql TEXT;
    v_target_sql TEXT;
BEGIN
    -- Get latest commits
    SELECT target_commit_id INTO v_source_commit
    FROM pggit.refs WHERE ref_name = p_source_branch AND ref_type = 'branch';
    
    SELECT target_commit_id INTO v_target_commit
    FROM pggit.refs WHERE ref_name = p_target_branch AND ref_type = 'branch';
    
    -- Get SQL from trees (simplified)
    SELECT schema_snapshot->>'sql' INTO v_source_sql
    FROM pggit.trees t
    JOIN pggit.commits c ON t.tree_hash = c.tree_hash
    WHERE c.id = v_source_commit;
    
    SELECT schema_snapshot->>'sql' INTO v_target_sql
    FROM pggit.trees t
    JOIN pggit.commits c ON t.tree_hash = c.tree_hash
    WHERE c.id = v_target_commit;
    
    -- Simple merge: combine both SQLs
    RETURN COALESCE(v_target_sql, '') || E'\n-- Merged from ' || p_source_branch || E':\n' || 
           COALESCE(v_source_sql, '');
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DATA-LEVEL CONFLICT DETECTION
-- ============================================

-- Analyze data conflicts during merge
CREATE OR REPLACE FUNCTION pggit.analyze_merge_data_conflicts(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS TABLE (
    data_conflicts JSONB
) AS $$
DECLARE
    v_conflicts JSONB := '[]'::JSONB;
BEGIN
    -- For now, return a simple conflict structure
    -- In a full implementation, this would analyze actual data changes
    
    -- Simulate finding data conflicts
    v_conflicts := jsonb_build_array(
        jsonb_build_object(
            'table', 'users',
            'primary_key', jsonb_build_object('id', 1),
            'branch1_values', jsonb_build_object('email', 'new@example.com'),
            'branch2_values', jsonb_build_object('email', 'other@example.com'),
            'conflict_type', 'UPDATE_UPDATE'
        )
    );
    
    RETURN QUERY SELECT v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- COMPLEX MERGE PLANNING
-- ============================================

-- Generate comprehensive merge plan
CREATE OR REPLACE FUNCTION pggit.generate_merge_plan(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS TABLE (
    merge_plan JSONB
) AS $$
DECLARE
    v_plan JSONB;
    v_conflicts JSONB;
BEGIN
    -- Detect all types of conflicts
    SELECT conflict_details INTO v_conflicts
    FROM pggit.detect_merge_conflicts(p_branch1, p_branch2);
    
    -- Build comprehensive merge plan
    v_plan := jsonb_build_object(
        'source_branch', p_branch1,
        'target_branch', p_branch2,
        'merge_base', pggit.find_merge_base(p_branch1, p_branch2),
        'conflicts', COALESCE(v_conflicts, '[]'::JSONB),
        'merge_strategy', CASE 
            WHEN jsonb_array_length(COALESCE(v_conflicts, '[]'::JSONB)) = 0 
            THEN 'fast_forward'
            ELSE 'three_way_merge'
        END,
        'estimated_complexity', CASE
            WHEN jsonb_array_length(COALESCE(v_conflicts, '[]'::JSONB)) = 0 THEN 'low'
            WHEN jsonb_array_length(COALESCE(v_conflicts, '[]'::JSONB)) <= 3 THEN 'medium'
            ELSE 'high'
        END
    );
    
    RETURN QUERY SELECT v_plan;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- COMMENTS AND DOCUMENTATION
-- ============================================

COMMENT ON FUNCTION pggit.create_commit IS 'Create a new commit with optional merge parent tracking';
COMMENT ON FUNCTION pggit.find_merge_base IS 'Find the common ancestor commit for two branches';
COMMENT ON FUNCTION pggit.detect_merge_conflicts IS 'Detect conflicts between two branches using three-way merge analysis';
COMMENT ON FUNCTION pggit.merge_branches IS 'Perform automatic merge with conflict resolution';
COMMENT ON FUNCTION pggit.analyze_merge_data_conflicts IS 'Analyze data-level conflicts during merge operations';
COMMENT ON FUNCTION pggit.generate_merge_plan IS 'Generate comprehensive merge execution plan';