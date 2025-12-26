-- ============================================================================
-- pgGit Phase 3: Object Tracking & Visibility Implementation
--
-- Implements the Object Tracking & Visibility API for schema objects
-- Enables querying schema objects from specific branches with change tracking
--
-- Phase 3 Functions:
-- 1. pggit.get_branch_objects() - Query objects on a specific branch
-- 2. pggit.get_object_history() - View change history for an object
-- 3. pggit.diff_branches() - Compare objects between two branches
--
-- ============================================================================

-- Drop existing functions to allow signature changes
DROP FUNCTION IF EXISTS pggit.get_branch_objects(TEXT, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS pggit.get_object_history(TEXT, TEXT, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS pggit.diff_branches(TEXT, TEXT) CASCADE;

-- ============================================================================
-- Phase 3.1: pggit.get_branch_objects()
--
-- Query all schema objects on a specific branch with optional filtering
--
-- Parameters:
--   p_branch_name      - Branch to query (NULL = current session branch, default = main)
--   p_object_type      - Filter by object type: TABLE, VIEW, FUNCTION, INDEX, etc. (NULL = all)
--   p_schema_filter    - Filter by schema name (case-insensitive LIKE, NULL = all)
--   p_order_by         - Order results: 'object_name ASC|DESC', 'object_type ASC|DESC', etc.
--
-- Returns:
--   object_id          - Unique object identifier
--   object_type        - Type of schema object (TABLE, VIEW, FUNCTION, etc.)
--   schema_name        - Schema containing the object
--   object_name        - Name of the object
--   full_name          - Fully qualified name (schema.object)
--   version_major      - Major version number
--   version_minor      - Minor version number
--   version_patch      - Patch version number
--   content_hash       - SHA256 hash of object definition
--   is_active          - Whether object is currently active
--   created_at         - When object was created
--   updated_at         - When object was last modified
--   created_by         - User who created/modified object
--
-- ============================================================================
CREATE OR REPLACE FUNCTION pggit.get_branch_objects(
    p_branch_name TEXT DEFAULT NULL,
    p_object_type TEXT DEFAULT NULL,
    p_schema_filter TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'object_name ASC'
) RETURNS TABLE (
    object_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    version_major INTEGER,
    version_minor INTEGER,
    version_patch INTEGER,
    content_hash CHAR(64),
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    created_by TEXT
) AS $$
DECLARE
    v_branch_id INTEGER;
    v_branch_name TEXT;
    v_order_clause TEXT;
BEGIN
    -- Step 1: Determine target branch
    v_branch_name := COALESCE(
        p_branch_name,
        current_setting('pggit.current_branch', true),
        'main'
    );

    -- Query pggit.branches to get branch_id
    SELECT b.branch_id INTO v_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = v_branch_name
    LIMIT 1;

    -- Return empty set if branch not found
    IF v_branch_id IS NULL THEN
        RETURN;
    END IF;

    -- Step 3-6: Get latest objects per branch and apply filters with ordering
    -- Support: 'object_name ASC|DESC', 'object_type ASC|DESC', 'schema_name ASC|DESC', 'created_at ASC|DESC'
    IF p_order_by ILIKE 'object_type%' THEN
        RETURN QUERY
        WITH latest_history AS (
            SELECT
                oh.object_id,
                oh.branch_id,
                oh.author_name,
                oh.author_time,
                ROW_NUMBER() OVER (PARTITION BY oh.object_id ORDER BY oh.author_time DESC) as rn
            FROM pggit.object_history oh
            WHERE oh.branch_id = v_branch_id
        )
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name,
            so.version_major,
            so.version_minor,
            so.version_patch,
            so.content_hash,
            so.is_active,
            so.created_at,
            so.last_modified_at,
            lh.author_name
        FROM pggit.schema_objects so
        JOIN latest_history lh ON so.object_id = lh.object_id AND lh.rn = 1
        WHERE so.is_active = true
          AND (p_object_type IS NULL OR so.object_type = p_object_type)
          AND (p_schema_filter IS NULL OR so.schema_name ILIKE p_schema_filter)
        ORDER BY so.object_type, so.object_name;
    ELSIF p_order_by ILIKE 'schema_name%' THEN
        RETURN QUERY
        WITH latest_history AS (
            SELECT
                oh.object_id,
                oh.branch_id,
                oh.author_name,
                oh.author_time,
                ROW_NUMBER() OVER (PARTITION BY oh.object_id ORDER BY oh.author_time DESC) as rn
            FROM pggit.object_history oh
            WHERE oh.branch_id = v_branch_id
        )
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name,
            so.version_major,
            so.version_minor,
            so.version_patch,
            so.content_hash,
            so.is_active,
            so.created_at,
            so.last_modified_at,
            lh.author_name
        FROM pggit.schema_objects so
        JOIN latest_history lh ON so.object_id = lh.object_id AND lh.rn = 1
        WHERE so.is_active = true
          AND (p_object_type IS NULL OR so.object_type = p_object_type)
          AND (p_schema_filter IS NULL OR so.schema_name ILIKE p_schema_filter)
        ORDER BY so.schema_name, so.object_name;
    ELSIF p_order_by ILIKE 'created_at%' THEN
        RETURN QUERY
        WITH latest_history AS (
            SELECT
                oh.object_id,
                oh.branch_id,
                oh.author_name,
                oh.author_time,
                ROW_NUMBER() OVER (PARTITION BY oh.object_id ORDER BY oh.author_time DESC) as rn
            FROM pggit.object_history oh
            WHERE oh.branch_id = v_branch_id
        )
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name,
            so.version_major,
            so.version_minor,
            so.version_patch,
            so.content_hash,
            so.is_active,
            so.created_at,
            so.last_modified_at,
            lh.author_name
        FROM pggit.schema_objects so
        JOIN latest_history lh ON so.object_id = lh.object_id AND lh.rn = 1
        WHERE so.is_active = true
          AND (p_object_type IS NULL OR so.object_type = p_object_type)
          AND (p_schema_filter IS NULL OR so.schema_name ILIKE p_schema_filter)
        ORDER BY so.created_at DESC, so.object_name;
    ELSE
        -- Default: object_name ASC
        RETURN QUERY
        WITH latest_history AS (
            SELECT
                oh.object_id,
                oh.branch_id,
                oh.author_name,
                oh.author_time,
                ROW_NUMBER() OVER (PARTITION BY oh.object_id ORDER BY oh.author_time DESC) as rn
            FROM pggit.object_history oh
            WHERE oh.branch_id = v_branch_id
        )
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name,
            so.version_major,
            so.version_minor,
            so.version_patch,
            so.content_hash,
            so.is_active,
            so.created_at,
            so.last_modified_at,
            lh.author_name
        FROM pggit.schema_objects so
        JOIN latest_history lh ON so.object_id = lh.object_id AND lh.rn = 1
        WHERE so.is_active = true
          AND (p_object_type IS NULL OR so.object_type = p_object_type)
          AND (p_schema_filter IS NULL OR so.schema_name ILIKE p_schema_filter)
        ORDER BY so.object_name ASC;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;

-- ============================================================================
-- Phase 3.2: pggit.get_object_history()
--
-- View the change history of a specific schema object on a branch
--
-- Parameters:
--   p_object_name      - Name of object to query (can be 'schema.object' format)
--   p_branch_name      - Branch to query history on (NULL = current session branch, default = main)
--   p_limit            - Maximum number of history records to return (default = 100)
--
-- Returns:
--   history_id         - Unique history record identifier
--   object_type        - Type of schema object
--   change_type        - Type of change (CREATE, ALTER, DROP, etc.)
--   change_severity    - Severity of change (BREAKING, MAJOR, MINOR, PATCH)
--   before_hash        - Content hash before change
--   after_hash         - Content hash after change
--   changed_by         - User who made the change
--   changed_at         - When the change was made
--   description        - Human-readable description of the change
--
-- ============================================================================
CREATE OR REPLACE FUNCTION pggit.get_object_history(
    p_object_name TEXT,
    p_branch_name TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 100
) RETURNS TABLE (
    history_id BIGINT,
    object_type TEXT,
    change_type TEXT,
    change_severity TEXT,
    before_hash CHAR(64),
    after_hash CHAR(64),
    changed_by TEXT,
    changed_at TIMESTAMP,
    description TEXT
) AS $$
DECLARE
    v_object_id BIGINT;
    v_branch_id INTEGER;
    v_branch_name TEXT;
    v_schema_name TEXT;
    v_object_name TEXT;
BEGIN
    -- Step 1: Validate input
    IF p_object_name IS NULL OR TRIM(p_object_name) = '' THEN
        RETURN;
    END IF;

    -- Handle both 'schema.object' and 'object' formats
    IF p_object_name LIKE '%.%' THEN
        -- Schema-qualified name
        v_schema_name := SUBSTRING(p_object_name FROM 1 FOR POSITION('.' IN p_object_name) - 1);
        v_object_name := SUBSTRING(p_object_name FROM POSITION('.' IN p_object_name) + 1);
    ELSE
        -- Just object name
        v_schema_name := NULL;
        v_object_name := p_object_name;
    END IF;

    -- Step 2: Determine target branch
    v_branch_name := COALESCE(
        p_branch_name,
        current_setting('pggit.current_branch', true),
        'main'
    );

    -- Query pggit.branches to get branch_id
    SELECT b.branch_id INTO v_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = v_branch_name
    LIMIT 1;

    -- Return empty if branch not found
    IF v_branch_id IS NULL THEN
        RETURN;
    END IF;

    -- Step 3: Find object ID
    IF v_schema_name IS NOT NULL THEN
        -- Schema-qualified lookup
        SELECT so.object_id INTO v_object_id
        FROM pggit.schema_objects so
        WHERE so.object_name = v_object_name
          AND so.schema_name = v_schema_name
        LIMIT 1;
    ELSE
        -- Object name only - find first match
        SELECT so.object_id INTO v_object_id
        FROM pggit.schema_objects so
        WHERE so.object_name = v_object_name
        LIMIT 1;
    END IF;

    -- Return empty if object not found
    IF v_object_id IS NULL THEN
        RETURN;
    END IF;

    -- Step 4-6: Query history and return results
    RETURN QUERY
    SELECT
        oh.history_id,
        so.object_type,
        oh.change_type,
        oh.change_severity,
        oh.before_hash,
        oh.after_hash,
        oh.author_name,
        oh.author_time,
        oh.change_type || ' on ' || p_object_name
    FROM pggit.object_history oh
    JOIN pggit.schema_objects so ON oh.object_id = so.object_id
    WHERE oh.object_id = v_object_id
      AND oh.branch_id = v_branch_id
    ORDER BY oh.author_time DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;

-- ============================================================================
-- Phase 3.3: pggit.diff_branches()
--
-- Compare schema objects between two branches to identify differences
--
-- Parameters:
--   p_source_branch    - Source branch for comparison
--   p_target_branch    - Target branch for comparison (NULL = current session branch, default = main)
--
-- Returns:
--   object_type        - Type of schema object
--   schema_name        - Schema containing the object
--   object_name        - Name of the object
--   full_name          - Fully qualified name (schema.object)
--   change_type        - Type of change (ADDED, REMOVED, MODIFIED, UNCHANGED, CONFLICT)
--   source_version     - Version number on source branch
--   target_version     - Version number on target branch
--   source_hash        - Content hash on source branch
--   target_hash        - Content hash on target branch
--   is_conflict        - Whether there is a conflict between branches
--   description        - Human-readable description of the difference
--
-- ============================================================================
CREATE OR REPLACE FUNCTION pggit.diff_branches(
    p_source_branch TEXT,
    p_target_branch TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    change_type TEXT,
    source_version INTEGER,
    target_version INTEGER,
    source_hash CHAR(64),
    target_hash CHAR(64),
    is_conflict BOOLEAN,
    description TEXT
) AS $$
DECLARE
    v_source_branch_id INTEGER;
    v_target_branch_id INTEGER;
    v_source_branch_name TEXT;
    v_target_branch_name TEXT;
BEGIN
    -- Step 1: Validate inputs
    IF p_source_branch IS NULL OR TRIM(p_source_branch) = '' THEN
        RAISE EXCEPTION 'p_source_branch cannot be NULL or empty';
    END IF;

    -- Step 2: Determine target branch
    v_target_branch_name := COALESCE(
        p_target_branch,
        current_setting('pggit.current_branch', true),
        'main'
    );

    v_source_branch_name := p_source_branch;

    -- Get branch IDs
    SELECT b.branch_id INTO v_source_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = v_source_branch_name
    LIMIT 1;

    IF v_source_branch_id IS NULL THEN
        RAISE EXCEPTION 'Source branch "%" does not exist', v_source_branch_name;
    END IF;

    SELECT b.branch_id INTO v_target_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = v_target_branch_name
    LIMIT 1;

    IF v_target_branch_id IS NULL THEN
        RAISE EXCEPTION 'Target branch "%" does not exist', v_target_branch_name;
    END IF;

    -- Step 3-6: Compare branches
    RETURN QUERY
    WITH source_objects AS (
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.version_major,
            so.content_hash
        FROM pggit.schema_objects so
        WHERE EXISTS (
            SELECT 1 FROM pggit.object_history oh
            WHERE oh.object_id = so.object_id
              AND oh.branch_id = v_source_branch_id
        )
    ),
    target_objects AS (
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.version_major,
            so.content_hash
        FROM pggit.schema_objects so
        WHERE EXISTS (
            SELECT 1 FROM pggit.object_history oh
            WHERE oh.object_id = so.object_id
              AND oh.branch_id = v_target_branch_id
        )
    ),
    diff_results AS (
        SELECT
            COALESCE(s.object_type, t.object_type) as object_type,
            COALESCE(s.schema_name, t.schema_name) as schema_name,
            COALESCE(s.object_name, t.object_name) as object_name,
            COALESCE(s.schema_name, t.schema_name) || '.' || COALESCE(s.object_name, t.object_name) as full_name,
            CASE
                WHEN s.object_id IS NULL THEN 'ADDED'
                WHEN t.object_id IS NULL THEN 'REMOVED'
                WHEN s.content_hash = t.content_hash THEN 'UNCHANGED'
                ELSE 'MODIFIED'
            END as change_type,
            COALESCE(s.version_major, 0) as source_version,
            COALESCE(t.version_major, 0) as target_version,
            s.content_hash as source_hash,
            t.content_hash as target_hash,
            (s.content_hash IS NOT NULL AND t.content_hash IS NOT NULL AND s.content_hash != t.content_hash) as is_conflict
        FROM source_objects s
        FULL OUTER JOIN target_objects t ON s.object_id = t.object_id
    )
    SELECT
        dr.object_type,
        dr.schema_name,
        dr.object_name,
        dr.full_name,
        dr.change_type,
        dr.source_version,
        dr.target_version,
        dr.source_hash,
        dr.target_hash,
        dr.is_conflict,
        dr.change_type || ' - ' || dr.full_name
    FROM diff_results dr
    WHERE dr.change_type != 'UNCHANGED'
    ORDER BY dr.schema_name, dr.object_name;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;
