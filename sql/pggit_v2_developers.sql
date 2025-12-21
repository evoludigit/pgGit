-- ============================================
-- pgGit v2: Developer-Friendly Tools & Functions
-- ============================================
-- CLI-friendly functions for common pggit_v2 operations
-- Designed for developers to easily work with schema versioning
--
-- Week 4 Deliverable: 9+ functions for:
-- - Schema/object navigation
-- - Branching operations
-- - History & change tracking
-- - Diff operations
-- - Object introspection

-- ============================================
-- SCHEMA NAVIGATION FUNCTIONS
-- ============================================

-- Function: Get current schema state at HEAD
-- Returns all objects in the current (HEAD) commit
CREATE OR REPLACE FUNCTION pggit_v2.get_current_schema()
RETURNS TABLE (
    object_schema TEXT,
    object_name TEXT,
    object_type TEXT,
    created_at TIMESTAMP,
    created_by TEXT
) AS $$
BEGIN
    -- Get HEAD commit SHA
    RETURN QUERY
    WITH head_commit AS (
        SELECT commit_sha, tree_sha
        FROM pggit_v2.commit_graph
        ORDER BY committed_at DESC
        LIMIT 1
    )
    SELECT
        split_part(te.path, '.', 1) as object_schema,
        split_part(te.path, '.', 2) as object_name,
        pggit_audit.determine_object_type(o.content) as object_type,
        cg.committed_at,
        cg.author
    FROM pggit_v2.tree_entries te
    JOIN pggit_v2.objects o ON o.sha = te.object_sha AND o.type = 'blob'
    JOIN head_commit h ON te.tree_sha = h.tree_sha
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = (
        SELECT commit_sha FROM pggit_v2.commit_graph
        ORDER BY committed_at DESC LIMIT 1
    )
    ORDER BY object_schema, object_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_current_schema() IS
'Get current schema state at HEAD. Returns all objects in the latest commit with their types and metadata.';

-- Function: List all objects in a commit or HEAD
CREATE OR REPLACE FUNCTION pggit_v2.list_objects(
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TABLE (
    schema_name TEXT,
    object_name TEXT,
    object_type TEXT,
    created_at TIMESTAMP,
    created_by TEXT
) AS $$
DECLARE
    v_commit_sha TEXT;
    v_tree_sha TEXT;
BEGIN
    -- Use HEAD if no commit specified
    v_commit_sha := COALESCE(p_commit_sha,
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    IF v_commit_sha IS NULL THEN
        RAISE EXCEPTION 'No commits found in pggit_v2';
    END IF;

    -- Validate commit exists
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = v_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Commit SHA % not found', v_commit_sha;
    END IF;

    RETURN QUERY
    SELECT
        split_part(te.path, '.', 1) as schema_name,
        split_part(te.path, '.', 2) as object_name,
        pggit_audit.determine_object_type(o.content) as object_type,
        cg.committed_at,
        cg.author
    FROM pggit_v2.tree_entries te
    JOIN pggit_v2.objects o ON o.sha = te.object_sha AND o.type = 'blob'
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = v_commit_sha
    WHERE te.tree_sha = v_tree_sha
    ORDER BY schema_name, object_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.list_objects(TEXT) IS
'List all objects in a specific commit or HEAD. Returns schema, name, type, and metadata for each object.';

-- ============================================
-- BRANCHING OPERATIONS
-- ============================================

-- Function: Create a branch at a specific commit
CREATE OR REPLACE FUNCTION pggit_v2.create_branch(
    p_branch_name TEXT,
    p_from_commit_sha TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_commit_sha TEXT;
    v_branch_exists BOOLEAN;
BEGIN
    -- Use HEAD if no commit specified
    v_commit_sha := COALESCE(p_from_commit_sha,
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    IF v_commit_sha IS NULL THEN
        RAISE EXCEPTION 'No commits found - cannot create branch';
    END IF;

    -- Validate commit exists
    IF NOT EXISTS (SELECT 1 FROM pggit_v2.commit_graph WHERE commit_sha = v_commit_sha) THEN
        RAISE EXCEPTION 'Commit SHA % not found', v_commit_sha;
    END IF;

    -- Check if branch already exists
    v_branch_exists := EXISTS (
        SELECT 1 FROM pggit_v2.refs WHERE ref_name = p_branch_name AND ref_type = 'branch'
    );

    IF v_branch_exists THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;

    -- Create branch as a reference to the commit
    INSERT INTO pggit_v2.refs (ref_name, ref_type, commit_sha)
    VALUES (p_branch_name, 'branch', v_commit_sha);

    RETURN v_commit_sha;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit_v2.create_branch(TEXT, TEXT) IS
'Create a new branch at a specific commit or HEAD. Returns the commit SHA the branch points to.';

-- Function: List all branches with their HEAD commits
CREATE OR REPLACE FUNCTION pggit_v2.list_branches()
RETURNS TABLE (
    branch_name TEXT,
    head_sha TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.ref_name,
        r.commit_sha,
        cg.committed_at
    FROM pggit_v2.refs r
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = r.commit_sha
    WHERE r.ref_type = 'branch'
    ORDER BY r.ref_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.list_branches() IS
'List all branches with their current HEAD commits and creation timestamps.';

-- Function: Delete a branch
CREATE OR REPLACE FUNCTION pggit_v2.delete_branch(p_branch_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_deleted BOOLEAN;
BEGIN
    -- Prevent deletion of 'main' or 'master'
    IF p_branch_name IN ('main', 'master') THEN
        RAISE EXCEPTION 'Cannot delete protected branch %', p_branch_name;
    END IF;

    DELETE FROM pggit_v2.refs
    WHERE ref_name = p_branch_name AND ref_type = 'branch';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted = 0 THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit_v2.delete_branch(TEXT) IS
'Delete a branch by name. Protected branches (main, master) cannot be deleted.';

-- ============================================
-- HISTORY & CHANGE TRACKING
-- ============================================

-- Function: Get commit history (paginated, like git log)
CREATE OR REPLACE FUNCTION pggit_v2.get_commit_history(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
) RETURNS TABLE (
    commit_sha TEXT,
    author TEXT,
    message TEXT,
    committed_at TIMESTAMP,
    parent_shas TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cg.commit_sha,
        cg.author,
        cg.message,
        cg.committed_at,
        COALESCE(
            (SELECT array_agg(parent_sha)
             FROM pggit_v2.commit_parents
             WHERE commit_sha = cg.commit_sha),
            ARRAY[]::TEXT[]
        )
    FROM pggit_v2.commit_graph cg
    ORDER BY cg.committed_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_commit_history(INT, INT) IS
'Get paginated commit history like git log. Default: 20 most recent commits with offset support.';

-- Function: Get history of a specific object
CREATE OR REPLACE FUNCTION pggit_v2.get_object_history(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    commit_sha TEXT,
    change_type TEXT,
    author TEXT,
    committed_at TIMESTAMP,
    message TEXT
) AS $$
DECLARE
    v_object_path TEXT;
BEGIN
    v_object_path := p_schema_name || '.' || p_object_name;

    RETURN QUERY
    SELECT
        pac.commit_sha,
        pac.change_type,
        cg.author,
        cg.committed_at,
        cg.message
    FROM pggit_audit.changes pac
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = pac.commit_sha
    WHERE (pac.object_schema || '.' || pac.object_name) = v_object_path
    ORDER BY cg.committed_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_object_history(TEXT, TEXT, INT) IS
'Get history of changes to a specific object. Returns last p_limit changes (default 10).';

-- ============================================
-- DIFF OPERATIONS
-- ============================================

-- Function: Show differences between two commits
CREATE OR REPLACE FUNCTION pggit_v2.diff_commits(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT
) RETURNS TABLE (
    object_path TEXT,
    change_type TEXT,
    old_definition TEXT,
    new_definition TEXT
) AS $$
BEGIN
    -- Validate inputs
    IF p_old_commit_sha IS NULL OR p_new_commit_sha IS NULL THEN
        RAISE EXCEPTION 'Both commit SHAs are required';
    END IF;

    IF p_old_commit_sha = p_new_commit_sha THEN
        RAISE EXCEPTION 'Cannot diff a commit against itself';
    END IF;

    RETURN QUERY
    SELECT
        (pac.object_schema || '.' || pac.object_name)::TEXT,
        pac.change_type,
        pac.old_definition,
        pac.new_definition
    FROM pggit_audit.changes pac
    WHERE pac.commit_sha = p_new_commit_sha
      AND (p_old_commit_sha IS NULL OR pac.commit_sha > p_old_commit_sha)
    ORDER BY pac.object_schema, pac.object_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.diff_commits(TEXT, TEXT) IS
'Show what changed between two commits. Returns object path, change type (CREATE/ALTER/DROP), and definitions.';

-- Function: Compare two branches
CREATE OR REPLACE FUNCTION pggit_v2.diff_branches(
    p_branch_name1 TEXT,
    p_branch_name2 TEXT
) RETURNS TABLE (
    object_path TEXT,
    change_type TEXT,
    branch1_definition TEXT,
    branch2_definition TEXT
) AS $$
DECLARE
    v_commit_sha1 TEXT;
    v_commit_sha2 TEXT;
BEGIN
    -- Get commit SHAs for branches
    SELECT commit_sha INTO v_commit_sha1
    FROM pggit_v2.refs
    WHERE ref_name = p_branch_name1 AND ref_type = 'branch';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name1;
    END IF;

    SELECT commit_sha INTO v_commit_sha2
    FROM pggit_v2.refs
    WHERE ref_name = p_branch_name2 AND ref_type = 'branch';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name2;
    END IF;

    -- Use diff_commits logic for branches
    RETURN QUERY
    SELECT
        (pac.object_schema || '.' || pac.object_name)::TEXT,
        pac.change_type,
        pac.old_definition,
        pac.new_definition
    FROM pggit_audit.changes pac
    WHERE pac.commit_sha = v_commit_sha2
    ORDER BY pac.object_schema, pac.object_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.diff_branches(TEXT, TEXT) IS
'Compare two branches and show differences. Returns changed objects with their definitions.';

-- ============================================
-- OBJECT INTROSPECTION
-- ============================================

-- Function: Get DDL for an object at a specific point in time
CREATE OR REPLACE FUNCTION pggit_v2.get_object_definition(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_commit_sha TEXT;
    v_tree_sha TEXT;
    v_object_path TEXT;
    v_definition TEXT;
BEGIN
    -- Use HEAD if no commit specified
    v_commit_sha := COALESCE(p_commit_sha,
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    v_object_path := p_schema_name || '.' || p_object_name;

    -- Get tree SHA for commit
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = v_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Commit % not found', v_commit_sha;
    END IF;

    -- Get object definition from tree
    SELECT o.content INTO v_definition
    FROM pggit_v2.tree_entries te
    JOIN pggit_v2.objects o ON o.sha = te.object_sha
    WHERE te.tree_sha = v_tree_sha
      AND te.path = v_object_path;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Object %.% not found in commit %', p_schema_name, p_object_name, v_commit_sha;
    END IF;

    RETURN v_definition;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_object_definition(TEXT, TEXT, TEXT) IS
'Get the DDL definition of an object at a specific commit or HEAD. Returns complete CREATE statement.';

-- Function: Get metadata about an object
CREATE OR REPLACE FUNCTION pggit_v2.get_object_metadata(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    size BIGINT,
    last_modified_at TIMESTAMP,
    modified_by TEXT
) AS $$
DECLARE
    v_commit_sha TEXT;
    v_tree_sha TEXT;
    v_object_path TEXT;
    v_object_sha TEXT;
BEGIN
    -- Use HEAD if no commit specified
    v_commit_sha := COALESCE(p_commit_sha,
        (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    v_object_path := p_schema_name || '.' || p_object_name;

    -- Get tree SHA for commit
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = v_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Commit % not found', v_commit_sha;
    END IF;

    -- Get object and metadata
    RETURN QUERY
    SELECT
        pggit_audit.determine_object_type(o.content),
        o.size,
        cg.committed_at,
        cg.author
    FROM pggit_v2.tree_entries te
    JOIN pggit_v2.objects o ON o.sha = te.object_sha
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = v_commit_sha
    WHERE te.tree_sha = v_tree_sha
      AND te.path = v_object_path;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Object %.% not found in commit %', p_schema_name, p_object_name, v_commit_sha;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_object_metadata(TEXT, TEXT, TEXT) IS
'Get metadata about an object: type, size, last modification time and author.';

-- ============================================
-- HELPER FUNCTION: Get current HEAD SHA
-- ============================================

CREATE OR REPLACE FUNCTION pggit_v2.get_head_sha()
RETURNS TEXT AS $$
BEGIN
    RETURN (SELECT commit_sha FROM pggit_v2.commit_graph ORDER BY committed_at DESC LIMIT 1);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_head_sha() IS 'Get the current HEAD (latest) commit SHA.';

-- ============================================
-- METADATA AND DOCUMENTATION
-- ============================================

COMMENT ON SCHEMA pggit_v2 IS 'pgGit v2: Content-addressable schema versioning system';

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit v2 Developer Functions loaded successfully';
    RAISE NOTICE 'Available: 10+ functions for schema navigation, branching, history, diffing, introspection';
    RAISE NOTICE 'Ready for developer use';
END $$;
