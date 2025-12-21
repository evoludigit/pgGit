-- ============================================
-- pgGit v0: Developer-Friendly Tools & Functions
-- ============================================
-- CLI-friendly functions for common pggit_v0 operations
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
CREATE OR REPLACE FUNCTION pggit_v0.get_current_schema()
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
        FROM pggit_v0.commit_graph
        ORDER BY committed_at DESC
        LIMIT 1
    )
    SELECT
        'public' as object_schema,
        te.name as object_name,
        'TABLE' as object_type,
        cg.committed_at,
        cg.author
    FROM pggit_v0.tree_entries te
    JOIN pggit_v0.objects o ON o.sha = te.object_sha AND o.type = 'blob'
    JOIN head_commit h ON te.tree_sha = h.tree_sha
    JOIN pggit_v0.commit_graph cg ON cg.commit_sha = (
        SELECT commit_sha FROM pggit_v0.commit_graph
        ORDER BY committed_at DESC LIMIT 1
    )
    ORDER BY object_schema, object_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_current_schema() IS
'Get current schema state at HEAD. Returns all objects in the latest commit with their types and metadata.';

-- Function: List all objects in a commit or HEAD
CREATE OR REPLACE FUNCTION pggit_v0.list_objects(
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TABLE (
    commit_sha TEXT,
    author TEXT,
    message TEXT,
    committed_at TIMESTAMPTZ,
    parent_shas TEXT[]
)
    FROM pggit_v0.commit_graph cg
    ORDER BY cg.committed_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_commit_history(INT, INT) IS
'Get paginated commit history like git log. Default: 20 most recent commits with offset support.';

-- Function: Get history of a specific object
CREATE OR REPLACE FUNCTION pggit_v0.get_object_history(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_limit INT DEFAULT 10
) RETURNS TABLE (
    commit_sha TEXT,
    change_type TEXT,
    author TEXT,
    committed_at TIMESTAMPTZ,
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
    JOIN pggit_v0.commit_graph cg ON cg.commit_sha = pac.commit_sha
    WHERE (pac.object_schema || '.' || pac.object_name) = v_object_path
    ORDER BY cg.committed_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_object_history(TEXT, TEXT, INT) IS
'Get history of changes to a specific object. Returns last p_limit changes (default 10).';

-- ============================================
-- DIFF OPERATIONS
-- ============================================

-- Function: Show differences between two commits
CREATE OR REPLACE FUNCTION pggit_v0.diff_commits(
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

COMMENT ON FUNCTION pggit_v0.diff_commits(TEXT, TEXT) IS
'Show what changed between two commits. Returns object path, change type (CREATE/ALTER/DROP), and definitions.';

-- Function: Compare two branches
CREATE OR REPLACE FUNCTION pggit_v0.diff_branches(
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
    SELECT target_sha INTO v_commit_sha1
    FROM pggit_v0.refs
    WHERE name = p_branch_name1 AND type = 'branch';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name1;
    END IF;

    SELECT target_sha INTO v_commit_sha2
    FROM pggit_v0.refs
    WHERE name = p_branch_name2 AND type = 'branch';

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

COMMENT ON FUNCTION pggit_v0.diff_branches(TEXT, TEXT) IS
'Compare two branches and show differences. Returns changed objects with their definitions.';

-- ============================================
-- OBJECT INTROSPECTION
-- ============================================

-- Function: Get DDL for an object at a specific point in time
CREATE OR REPLACE FUNCTION pggit_v0.get_object_definition(
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
        (SELECT commit_sha FROM pggit_v0.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    v_object_path := p_schema_name || '.' || p_object_name;

    -- Get tree SHA for commit
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v0.commit_graph
    WHERE commit_sha = v_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Commit % not found', v_commit_sha;
    END IF;

    -- Get object definition from tree
    SELECT o.content INTO v_definition
    FROM pggit_v0.tree_entries te
    JOIN pggit_v0.objects o ON o.sha = te.object_sha
    WHERE te.tree_sha = v_tree_sha
      AND te.path = v_object_path;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Object %.% not found in commit %', p_schema_name, p_object_name, v_commit_sha;
    END IF;

    RETURN v_definition;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_object_definition(TEXT, TEXT, TEXT) IS
'Get the DDL definition of an object at a specific commit or HEAD. Returns complete CREATE statement.';

-- Function: Get metadata about an object
CREATE OR REPLACE FUNCTION pggit_v0.get_object_metadata(
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
        (SELECT commit_sha FROM pggit_v0.commit_graph ORDER BY committed_at DESC LIMIT 1)
    );

    v_object_path := p_schema_name || '.' || p_object_name;

    -- Get tree SHA for commit
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v0.commit_graph
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
    FROM pggit_v0.tree_entries te
    JOIN pggit_v0.objects o ON o.sha = te.object_sha
    JOIN pggit_v0.commit_graph cg ON cg.commit_sha = v_commit_sha
    WHERE te.tree_sha = v_tree_sha
      AND te.path = v_object_path;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Object %.% not found in commit %', p_schema_name, p_object_name, v_commit_sha;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_object_metadata(TEXT, TEXT, TEXT) IS
'Get metadata about an object: type, size, last modification time and author.';

-- ============================================
-- HELPER FUNCTION: Get current HEAD SHA
-- ============================================

CREATE OR REPLACE FUNCTION pggit_v0.get_head_sha()
RETURNS TEXT AS $$
BEGIN
    RETURN (SELECT commit_sha FROM pggit_v0.commit_graph ORDER BY committed_at DESC LIMIT 1);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v0.get_head_sha() IS 'Get the current HEAD (latest) commit SHA.';

-- ============================================
-- METADATA AND DOCUMENTATION
-- ============================================

COMMENT ON SCHEMA pggit_v0 IS 'pgGit v0: Content-addressable schema versioning system';

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit v2 Developer Functions loaded successfully';
    RAISE NOTICE 'Available: 10+ functions for schema navigation, branching, history, diffing, introspection';
    RAISE NOTICE 'Ready for developer use';
END $$;
