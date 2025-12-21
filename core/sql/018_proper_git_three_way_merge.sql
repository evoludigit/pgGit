-- ============================================
-- pgGit Proper Three-Way Merge Implementation
-- ============================================
-- Based on expert team recommendations and Git's actual design

-- Drop existing flawed implementations
DROP SCHEMA IF EXISTS pggit_v2 CASCADE;
CREATE SCHEMA pggit_v2;

-- ============================================
-- CORE GIT-LIKE OBJECT MODEL
-- ============================================

-- Objects table (like Git's object database)
CREATE TABLE pggit_v2.objects (
    sha TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('commit', 'tree', 'blob', 'tag')),
    size INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_objects_type ON pggit_v2.objects(type);

-- Refs table (branches and tags)
CREATE TABLE pggit_v2.refs (
    name TEXT PRIMARY KEY,
    target_sha TEXT NOT NULL REFERENCES pggit_v2.objects(sha),
    type TEXT NOT NULL CHECK (type IN ('branch', 'tag', 'remote'))
);

-- HEAD tracking
CREATE TABLE pggit_v2.HEAD (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    ref_name TEXT NOT NULL,
    direct_sha TEXT
);

-- ============================================
-- PERFORMANCE OPTIMIZATION STRUCTURES
-- ============================================

-- Pre-computed commit graph for fast traversal
CREATE TABLE pggit_v2.commit_graph (
    commit_sha TEXT PRIMARY KEY REFERENCES pggit_v2.objects(sha),
    parent_shas TEXT[] NOT NULL DEFAULT '{}',
    tree_sha TEXT NOT NULL,
    generation INTEGER NOT NULL DEFAULT 0, -- Distance from root
    author TEXT NOT NULL,
    committer TEXT NOT NULL,
    authored_at TIMESTAMP NOT NULL,
    committed_at TIMESTAMP NOT NULL,
    message TEXT NOT NULL
);

CREATE INDEX idx_commit_graph_parents ON pggit_v2.commit_graph USING GIN(parent_shas);
CREATE INDEX idx_commit_graph_generation ON pggit_v2.commit_graph(generation);

-- Merge base cache for O(1) lookups
CREATE TABLE pggit_v2.merge_base_cache (
    commit1_sha TEXT NOT NULL,
    commit2_sha TEXT NOT NULL,
    merge_base_sha TEXT NOT NULL,
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (commit1_sha, commit2_sha)
);

-- Tree entry cache for fast tree comparisons
CREATE TABLE pggit_v2.tree_entries (
    tree_sha TEXT NOT NULL REFERENCES pggit_v2.objects(sha),
    path TEXT NOT NULL,
    mode TEXT NOT NULL, -- File mode (100644, 100755, 040000, etc.)
    object_sha TEXT NOT NULL REFERENCES pggit_v2.objects(sha),
    PRIMARY KEY (tree_sha, path)
);

CREATE INDEX idx_tree_entries_object ON pggit_v2.tree_entries(object_sha);

-- ============================================
-- CORE GIT FUNCTIONS
-- ============================================

-- Create blob object
CREATE OR REPLACE FUNCTION pggit_v2.create_blob(
    p_content TEXT
) RETURNS TEXT AS $$
DECLARE
    v_sha TEXT;
    v_size INTEGER;
BEGIN
    v_size := length(p_content);
    -- Use proper encoding without null bytes for PostgreSQL
    v_sha := encode(sha256(('blob ' || v_size || ':' || p_content)::bytea), 'hex');
    
    INSERT INTO pggit_v2.objects (sha, type, size, content)
    VALUES (v_sha, 'blob', v_size, p_content)
    ON CONFLICT (sha) DO NOTHING;
    
    RETURN v_sha;
END;
$$ LANGUAGE plpgsql;

-- Create tree object
CREATE OR REPLACE FUNCTION pggit_v2.create_tree(
    p_entries JSONB -- Array of {path, mode, sha}
) RETURNS TEXT AS $$
DECLARE
    v_sha TEXT;
    v_content TEXT := '';
    v_entry RECORD;
    v_size INTEGER;
BEGIN
    -- Build tree content (Git format)
    FOR v_entry IN
        SELECT value as entry_data
        FROM jsonb_array_elements(p_entries)
        ORDER BY (value->>'path')::text
    LOOP
        v_content := v_content ||
                    format('%s %s|', v_entry.entry_data->>'mode', v_entry.entry_data->>'path') ||
                    (v_entry.entry_data->>'sha') || '|';
    END LOOP;

    v_size := length(v_content);
    v_sha := encode(sha256(('tree ' || v_size || ':' || v_content)::bytea), 'hex');

    -- Store tree object
    INSERT INTO pggit_v2.objects (sha, type, size, content)
    VALUES (v_sha, 'tree', v_size, encode(v_content::bytea, 'base64'))
    ON CONFLICT (sha) DO NOTHING;

    -- Cache tree entries
    INSERT INTO pggit_v2.tree_entries (tree_sha, path, mode, object_sha)
    SELECT v_sha, value->>'path', value->>'mode', value->>'sha'
    FROM jsonb_array_elements(p_entries)
    ON CONFLICT DO NOTHING;

    RETURN v_sha;
END;
$$ LANGUAGE plpgsql;

-- Create commit object
CREATE OR REPLACE FUNCTION pggit_v2.create_commit(
    p_tree_sha TEXT,
    p_parent_shas TEXT[],
    p_message TEXT,
    p_author TEXT DEFAULT NULL,
    p_committer TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_sha TEXT;
    v_content TEXT;
    v_size INTEGER;
    v_parent_sha TEXT;
    v_author TEXT;
    v_committer TEXT;
    v_timestamp TEXT;
BEGIN
    v_author := COALESCE(p_author, current_user || ' <' || current_user || '@pggit>');
    v_committer := COALESCE(p_committer, v_author);
    v_timestamp := extract(epoch from now())::bigint::TEXT || ' +0000';
    
    -- Build commit content (Git format)
    v_content := 'tree ' || p_tree_sha || E'\n';
    
    -- Add parent references
    FOREACH v_parent_sha IN ARRAY COALESCE(p_parent_shas, '{}')
    LOOP
        v_content := v_content || 'parent ' || v_parent_sha || E'\n';
    END LOOP;
    
    v_content := v_content || 
                'author ' || v_author || ' ' || v_timestamp || E'\n' ||
                'committer ' || v_committer || ' ' || v_timestamp || E'\n\n' ||
                p_message;
    
    v_size := length(v_content);
    v_sha := encode(sha256(('commit ' || v_size || ':' || v_content)::bytea), 'hex');
    
    -- Store commit object
    INSERT INTO pggit_v2.objects (sha, type, size, content)
    VALUES (v_sha, 'commit', v_size, v_content)
    ON CONFLICT (sha) DO NOTHING;
    
    -- Update commit graph
    INSERT INTO pggit_v2.commit_graph (
        commit_sha, parent_shas, tree_sha, generation,
        author, committer, authored_at, committed_at, message
    )
    SELECT 
        v_sha, 
        COALESCE(p_parent_shas, '{}'), 
        p_tree_sha,
        COALESCE((SELECT MAX(generation) + 1 FROM pggit_v2.commit_graph WHERE commit_sha = ANY(p_parent_shas)), 0),
        v_author,
        v_committer,
        now(),
        now(),
        p_message
    ON CONFLICT (commit_sha) DO NOTHING;
    
    RETURN v_sha;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- THREE-WAY MERGE ALGORITHM
-- ============================================

-- Find merge base using generation numbers (optimized)
CREATE OR REPLACE FUNCTION pggit_v2.find_merge_base(
    p_commit1_sha TEXT,
    p_commit2_sha TEXT
) RETURNS TEXT AS $$
DECLARE
    v_merge_base TEXT;
BEGIN
    -- Check cache first
    SELECT merge_base_sha INTO v_merge_base
    FROM pggit_v2.merge_base_cache
    WHERE (commit1_sha = p_commit1_sha AND commit2_sha = p_commit2_sha)
       OR (commit1_sha = p_commit2_sha AND commit2_sha = p_commit1_sha);
    
    IF v_merge_base IS NOT NULL THEN
        RETURN v_merge_base;
    END IF;
    
    -- Use generation numbers for efficient traversal
    WITH RECURSIVE 
    -- Get all ancestors of commit1 with distance
    ancestors1 AS (
        SELECT commit_sha, parent_shas, generation, 0 as distance
        FROM pggit_v2.commit_graph
        WHERE commit_sha = p_commit1_sha
        
        UNION ALL
        
        SELECT g.commit_sha, g.parent_shas, g.generation, a.distance + 1
        FROM pggit_v2.commit_graph g
        JOIN ancestors1 a ON g.commit_sha = ANY(a.parent_shas)
        WHERE a.distance < 1000 -- Prevent infinite recursion
    ),
    -- Get all ancestors of commit2 with distance
    ancestors2 AS (
        SELECT commit_sha, parent_shas, generation, 0 as distance
        FROM pggit_v2.commit_graph
        WHERE commit_sha = p_commit2_sha
        
        UNION ALL
        
        SELECT g.commit_sha, g.parent_shas, g.generation, a.distance + 1
        FROM pggit_v2.commit_graph g
        JOIN ancestors2 a ON g.commit_sha = ANY(a.parent_shas)
        WHERE a.distance < 1000
    )
    -- Find common ancestor with highest generation (most recent)
    SELECT a1.commit_sha INTO v_merge_base
    FROM ancestors1 a1
    JOIN ancestors2 a2 ON a1.commit_sha = a2.commit_sha
    ORDER BY a1.generation DESC
    LIMIT 1;
    
    -- Cache the result
    IF v_merge_base IS NOT NULL THEN
        INSERT INTO pggit_v2.merge_base_cache (commit1_sha, commit2_sha, merge_base_sha)
        VALUES (p_commit1_sha, p_commit2_sha, v_merge_base)
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN v_merge_base;
END;
$$ LANGUAGE plpgsql;

-- Compare two trees
CREATE OR REPLACE FUNCTION pggit_v2.diff_trees(
    p_tree1_sha TEXT,
    p_tree2_sha TEXT
) RETURNS TABLE (
    path TEXT,
    change_type TEXT, -- 'add', 'delete', 'modify'
    old_mode TEXT,
    new_mode TEXT,
    old_sha TEXT,
    new_sha TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH tree1 AS (
        SELECT te.path, te.mode, te.object_sha
        FROM pggit_v2.tree_entries te
        WHERE te.tree_sha = p_tree1_sha
    ),
    tree2 AS (
        SELECT te.path, te.mode, te.object_sha
        FROM pggit_v2.tree_entries te
        WHERE te.tree_sha = p_tree2_sha
    )
    SELECT
        COALESCE(t1.path, t2.path) as path,
        CASE
            WHEN t1.path IS NULL THEN 'add'
            WHEN t2.path IS NULL THEN 'delete'
            WHEN t1.object_sha != t2.object_sha OR t1.mode != t2.mode THEN 'modify'
        END as change_type,
        t1.mode as old_mode,
        t2.mode as new_mode,
        t1.object_sha as old_sha,
        t2.object_sha as new_sha
    FROM tree1 t1
    FULL OUTER JOIN tree2 t2 ON t1.path = t2.path
    WHERE t1.object_sha IS DISTINCT FROM t2.object_sha
       OR t1.mode IS DISTINCT FROM t2.mode;
END;
$$ LANGUAGE plpgsql;

-- Perform three-way merge
CREATE OR REPLACE FUNCTION pggit_v2.three_way_merge(
    p_ours_sha TEXT,
    p_theirs_sha TEXT,
    p_base_sha TEXT DEFAULT NULL
) RETURNS TABLE (
    path TEXT,
    merge_status TEXT, -- 'clean', 'conflict', 'both_added', 'both_deleted'
    base_content TEXT,
    ours_content TEXT,
    theirs_content TEXT,
    merged_content TEXT,
    conflict_markers BOOLEAN
) AS $$
DECLARE
    v_base_sha TEXT;
    v_ours_tree TEXT;
    v_theirs_tree TEXT;
    v_base_tree TEXT;
BEGIN
    -- Get merge base if not provided
    IF p_base_sha IS NULL THEN
        v_base_sha := pggit_v2.find_merge_base(p_ours_sha, p_theirs_sha);
    ELSE
        v_base_sha := p_base_sha;
    END IF;
    
    -- Get tree SHAs from commits
    SELECT tree_sha INTO v_ours_tree FROM pggit_v2.commit_graph WHERE commit_sha = p_ours_sha;
    SELECT tree_sha INTO v_theirs_tree FROM pggit_v2.commit_graph WHERE commit_sha = p_theirs_sha;
    SELECT tree_sha INTO v_base_tree FROM pggit_v2.commit_graph WHERE commit_sha = v_base_sha;
    
    -- Perform three-way diff
    RETURN QUERY
    WITH 
    base_diff_ours AS (
        SELECT * FROM pggit_v2.diff_trees(v_base_tree, v_ours_tree)
    ),
    base_diff_theirs AS (
        SELECT * FROM pggit_v2.diff_trees(v_base_tree, v_theirs_tree)
    ),
    all_paths AS (
        SELECT DISTINCT path FROM (
            SELECT path FROM base_diff_ours
            UNION ALL
            SELECT path FROM base_diff_theirs
        ) combined
    )
    SELECT 
        p.path,
        CASE
            -- No changes in either branch
            WHEN o.path IS NULL AND t.path IS NULL THEN 'clean'
            -- Only one branch changed
            WHEN o.path IS NULL OR t.path IS NULL THEN 'clean'
            -- Both changed the same way
            WHEN o.new_sha = t.new_sha THEN 'clean'
            -- Both added different content
            WHEN o.change_type = 'add' AND t.change_type = 'add' THEN 'both_added'
            -- Both deleted
            WHEN o.change_type = 'delete' AND t.change_type = 'delete' THEN 'both_deleted'
            -- Conflict
            ELSE 'conflict'
        END as merge_status,
        -- Get content for conflict resolution
        (SELECT content FROM pggit_v2.objects WHERE sha = COALESCE(o.old_sha, t.old_sha)) as base_content,
        (SELECT content FROM pggit_v2.objects WHERE sha = o.new_sha) as ours_content,
        (SELECT content FROM pggit_v2.objects WHERE sha = t.new_sha) as theirs_content,
        -- Merged content (null if conflict)
        CASE
            WHEN o.new_sha = t.new_sha THEN (SELECT content FROM pggit_v2.objects WHERE sha = o.new_sha)
            WHEN o.path IS NULL THEN (SELECT content FROM pggit_v2.objects WHERE sha = t.new_sha)
            WHEN t.path IS NULL THEN (SELECT content FROM pggit_v2.objects WHERE sha = o.new_sha)
            ELSE NULL
        END as merged_content,
        -- Conflict markers needed?
        CASE
            WHEN o.path IS NOT NULL AND t.path IS NOT NULL AND o.new_sha != t.new_sha THEN true
            ELSE false
        END as conflict_markers
    FROM all_paths p
    LEFT JOIN base_diff_ours o ON p.path = o.path
    LEFT JOIN base_diff_theirs t ON p.path = t.path;
END;
$$ LANGUAGE plpgsql;

-- Create merge commit
CREATE OR REPLACE FUNCTION pggit_v2.create_merge_commit(
    p_ours_sha TEXT,
    p_theirs_sha TEXT,
    p_message TEXT,
    p_author TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_merge_tree_sha TEXT;
    v_merge_result RECORD;
    v_tree_entries JSONB := '[]'::JSONB;
    v_has_conflicts BOOLEAN := false;
BEGIN
    -- Check for conflicts
    FOR v_merge_result IN 
        SELECT * FROM pggit_v2.three_way_merge(p_ours_sha, p_theirs_sha)
    LOOP
        IF v_merge_result.merge_status = 'conflict' THEN
            v_has_conflicts := true;
            RAISE EXCEPTION 'Merge conflict in file: %', v_merge_result.path;
        END IF;
        
        -- Add to tree if clean merge
        IF v_merge_result.merged_content IS NOT NULL THEN
            v_tree_entries := v_tree_entries || jsonb_build_object(
                'path', v_merge_result.path,
                'mode', '100644',
                'sha', pggit_v2.create_blob(v_merge_result.merged_content)
            );
        END IF;
    END LOOP;
    
    -- Create merged tree
    v_merge_tree_sha := pggit_v2.create_tree(v_tree_entries);
    
    -- Create merge commit with two parents
    RETURN pggit_v2.create_commit(
        v_merge_tree_sha,
        ARRAY[p_ours_sha, p_theirs_sha],
        p_message,
        p_author
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Update ref
CREATE OR REPLACE FUNCTION pggit_v2.update_ref(
    p_ref_name TEXT,
    p_new_sha TEXT,
    p_old_sha TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_current_sha TEXT;
BEGIN
    -- Get current SHA if checking
    IF p_old_sha IS NOT NULL THEN
        SELECT target_sha INTO v_current_sha
        FROM pggit_v2.refs
        WHERE name = p_ref_name;
        
        IF v_current_sha != p_old_sha THEN
            RAISE EXCEPTION 'Ref % has changed (expected %, got %)', 
                            p_ref_name, p_old_sha, v_current_sha;
        END IF;
    END IF;
    
    -- Update or insert ref
    INSERT INTO pggit_v2.refs (name, target_sha, type)
    VALUES (p_ref_name, p_new_sha, 
            CASE 
                WHEN p_ref_name LIKE 'refs/tags/%' THEN 'tag'
                WHEN p_ref_name LIKE 'refs/remotes/%' THEN 'remote'
                ELSE 'branch'
            END)
    ON CONFLICT (name) 
    DO UPDATE SET target_sha = EXCLUDED.target_sha;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PERFORMANCE MONITORING
-- ============================================

CREATE TABLE pggit_v2.performance_metrics (
    operation TEXT,
    duration_ms INTEGER,
    object_count INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON SCHEMA pggit_v2 IS 'Proper Git-like implementation with three-way merge';
COMMENT ON FUNCTION pggit_v2.find_merge_base IS 'Find common ancestor using optimized generation-based algorithm';
COMMENT ON FUNCTION pggit_v2.three_way_merge IS 'Perform true three-way merge with conflict detection';
COMMENT ON FUNCTION pggit_v2.create_merge_commit IS 'Create merge commit with automatic conflict detection';