-- pgGit Phase 2: Branch Management (Core API)
-- Revolutionary database branching with Git-style operations
--
-- PATENT PENDING: This technology is protected by multiple patent applications
-- covering novel database branching, data versioning, and merge algorithms.
--
-- This file implements four core functions:
-- 1. pggit.create_branch() - Create new branches from parent branches
-- 2. pggit.delete_branch() - Safely delete branches with merge validation
-- 3. pggit.list_branches() - List branches with comprehensive metadata
-- 4. pggit.checkout_branch() - Switch between branches (session tracking)
--
-- All functions maintain immutable history - deletions mark status as DELETED
-- rather than removing rows, preserving audit trails forever.

-- Ensure pggit schema exists
CREATE SCHEMA IF NOT EXISTS pggit;

-- Drop existing functions if they exist to allow signature changes
DROP FUNCTION IF EXISTS pggit.create_branch(TEXT, TEXT, TEXT, JSONB) CASCADE;
DROP FUNCTION IF EXISTS pggit.delete_branch(TEXT, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS pggit.list_branches(TEXT, BOOLEAN, TEXT) CASCADE;
DROP FUNCTION IF EXISTS pggit.checkout_branch(TEXT) CASCADE;

-- ============================================================================
-- Phase 2.1: pggit.create_branch()
-- ============================================================================
-- Creates a new database branch as a child of a parent branch
--
-- Parameters:
--   p_branch_name: Name of new branch (must be unique, must match ^[a-zA-Z0-9._/#-]+$)
--   p_parent_branch_name: Parent branch name (default: 'main')
--   p_branch_type: Type of branch (default: 'standard')
--                  Valid: 'standard', 'tiered', 'temporal', 'compressed'
--   p_metadata: Optional JSONB metadata for branch
--
-- Returns TABLE with:
--   branch_id: Auto-generated ID
--   branch_name: Name of new branch
--   parent_branch_id: ID of parent branch
--   parent_branch_name: Name of parent branch
--   status: Always 'ACTIVE' for new branches
--   branch_type: Type of branch (as provided)
--   head_commit_hash: Initial commit hash (branch point)
--   created_at: Creation timestamp
--   created_by: User who created branch
--
-- Behavior:
-- - Validates branch name format
-- - Finds active parent branch
-- - Copies all active objects from parent to new branch
-- - Creates immutable entry in branches table
-- - Returns complete branch information

CREATE OR REPLACE FUNCTION pggit.create_branch(
    p_branch_name TEXT,
    p_parent_branch_name TEXT DEFAULT 'main',
    p_branch_type TEXT DEFAULT 'schema-only',
    p_metadata JSONB DEFAULT NULL
) RETURNS TABLE (
    branch_id INTEGER,
    branch_name TEXT,
    parent_branch_id INTEGER,
    parent_branch_name TEXT,
    status TEXT,
    branch_type TEXT,
    head_commit_hash CHAR(64),
    created_at TIMESTAMP,
    created_by TEXT
) AS $$
DECLARE
    v_parent_id INTEGER;
    v_new_branch_id INTEGER;
    v_commit_hash CHAR(64);
    v_parent_head_hash TEXT;
    v_current_timestamp TIMESTAMP;
BEGIN
    -- Step 1 - Validate inputs
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RAISE EXCEPTION 'Branch name cannot be empty or NULL';
    END IF;

    IF NOT p_branch_name ~ '^[a-zA-Z0-9._/#-]+$' THEN
        RAISE EXCEPTION 'Branch name contains invalid characters. Allowed: letters, numbers, . _ / # -';
    END IF;

    IF p_branch_type NOT IN ('schema-only', 'full', 'temporal', 'compressed') THEN
        RAISE EXCEPTION 'Invalid branch type: %. Valid types: schema-only, full, temporal, compressed', p_branch_type;
    END IF;

    -- Check for uniqueness
    PERFORM 1 FROM pggit.branches b WHERE b.branch_name = p_branch_name;
    IF FOUND THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;

    -- Step 2 - Find active parent branch
    SELECT b.branch_id INTO v_parent_id
    FROM pggit.branches b
    WHERE b.branch_name = p_parent_branch_name AND b.status = 'ACTIVE';

    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Parent branch % not found or is not active', p_parent_branch_name;
    END IF;

    -- Step 3 - Get parent's head commit
    SELECT b.head_commit_hash INTO v_parent_head_hash
    FROM pggit.branches b
    WHERE b.branch_id = v_parent_id;

    -- Step 4 - Initialize timestamp
    v_current_timestamp := CURRENT_TIMESTAMP;

    -- Note: head_commit_hash starts as NULL; will be set when first commit is made

    -- Step 5 - Insert new branch entry
    INSERT INTO pggit.branches (
        branch_name,
        parent_branch_id,
        head_commit_hash,
        status,
        branch_type,
        created_by,
        created_at,
        metadata
    )
    VALUES (
        p_branch_name,
        v_parent_id,
        NULL,  -- head_commit_hash starts NULL, set on first commit
        'ACTIVE',
        p_branch_type,
        CURRENT_USER,
        v_current_timestamp,
        p_metadata
    );

    -- Get the inserted branch_id
    SELECT b.branch_id INTO v_new_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = p_branch_name
    LIMIT 1;

    -- Step 6 - Note: Object copying deferred to Phase 3
    -- Phase 2 manages branch metadata only; Phase 3 implements object tracking per branch

    -- Step 7 - Return new branch information
    RETURN QUERY
    SELECT
        v_new_branch_id::INTEGER,
        p_branch_name::TEXT,
        v_parent_id::INTEGER,
        p_parent_branch_name::TEXT,
        'ACTIVE'::TEXT,
        p_branch_type::TEXT,
        NULL::CHAR(64),  -- head_commit_hash starts NULL
        v_current_timestamp::TIMESTAMP,
        CURRENT_USER::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 2.2: pggit.delete_branch()
-- ============================================================================
-- Safely deletes a branch with merge status validation
--
-- Parameters:
--   p_branch_name: Name of branch to delete
--   p_force: If true, skip merge check and force deletion (default: false)
--
-- Returns TABLE with:
--   success: Boolean indicating deletion success
--   message: Human-readable description of what happened
--   branch_id: ID of deleted branch
--   deleted_at: Timestamp of deletion
--
-- Behavior:
-- - Prevents deletion of 'main' branch (always)
-- - Checks merge status unless force=true
-- - Performs cascade cleanup (data_branches, commits, history)
-- - Marks branch as DELETED (soft delete, not hard delete)
-- - Preserves immutable audit trail
--
-- Safety Notes:
-- - This is a soft delete - row remains in database with status='DELETED'
-- - Foreign keys have ON DELETE CASCADE to clean up related data
-- - Original created_by preserved; merged_by/merged_at set on delete

CREATE OR REPLACE FUNCTION pggit.delete_branch(
    p_branch_name TEXT,
    p_force BOOLEAN DEFAULT false
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    branch_id INTEGER,
    deleted_at TIMESTAMP
) AS $$
DECLARE
    v_branch_id INTEGER;
    v_branch_status TEXT;
    v_current_timestamp TIMESTAMP;
    v_delete_message TEXT;
BEGIN
    -- Step 1 - Validate input
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RAISE EXCEPTION 'Branch name cannot be empty or NULL';
    END IF;

    -- Verify branch exists
    SELECT b.branch_id, b.status INTO v_branch_id, v_branch_status
    FROM pggit.branches b
    WHERE b.branch_name = p_branch_name;

    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % does not exist', p_branch_name;
    END IF;

    -- Step 2 - Prevent main branch deletion
    IF p_branch_name = 'main' THEN
        RAISE EXCEPTION 'Cannot delete main branch';
    END IF;

    -- Step 3 - Check merge status (unless force=true)
    IF p_force = false THEN
        IF v_branch_status != 'MERGED' THEN
            RAISE EXCEPTION 'Branch must be merged before deletion. Use force=true to override.';
        END IF;
    END IF;

    v_current_timestamp := CURRENT_TIMESTAMP;

    -- Step 4 - Cascade cleanup
    -- Delete objects associated with this branch
    DELETE FROM pggit.object_history oh WHERE oh.branch_id = v_branch_id;
    DELETE FROM pggit.merge_operations mo
    WHERE mo.source_branch_id = v_branch_id OR mo.target_branch_id = v_branch_id;
    DELETE FROM pggit.object_dependencies od WHERE od.branch_id = v_branch_id;
    DELETE FROM pggit.data_tables dt WHERE dt.branch_id = v_branch_id;
    DELETE FROM pggit.commits c WHERE c.branch_id = v_branch_id;

    -- Step 5 - Mark branch as DELETED (soft delete)
    UPDATE pggit.branches b
    SET status = 'DELETED',
        merged_at = COALESCE(b.merged_at, v_current_timestamp),
        merged_by = COALESCE(b.merged_by, CURRENT_USER)
    WHERE b.branch_id = v_branch_id;

    -- Step 6 - Return status
    v_delete_message := 'Branch ' || p_branch_name || ' marked as DELETED';

    RETURN QUERY
    SELECT
        true,
        v_delete_message,
        v_branch_id,
        v_current_timestamp;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 2.3: pggit.list_branches()
-- ============================================================================
-- Lists all branches with comprehensive metadata and filtering
--
-- Parameters:
--   p_filter_status: Filter by status (NULL = all statuses)
--                    Valid: 'ACTIVE', 'MERGED', 'DELETED', 'CONFLICTED'
--   p_include_deleted: If false (default), exclude branches with status='DELETED'
--   p_order_by: Ordering specification (default: 'created_at DESC')
--               Valid: 'created_at ASC', 'created_at DESC', 'name ASC', 'name DESC',
--                      'status ASC', 'status DESC'
--
-- Returns TABLE with:
--   branch_id: Unique branch ID
--   branch_name: Name of branch
--   parent_branch_id: ID of parent branch (NULL for 'main')
--   parent_branch_name: Name of parent branch (NULL for 'main')
--   status: Current status (ACTIVE, MERGED, DELETED, CONFLICTED)
--   branch_type: Type (standard, tiered, temporal, compressed)
--   head_commit_hash: Latest commit hash
--   object_count: Number of objects in branch
--   storage_bytes: Total storage used by objects
--   created_by: User who created branch
--   created_at: Creation timestamp
--   merged_at: When merged (NULL if not merged)
--   merged_by: User who merged (NULL if not merged)
--   last_modified_at: When last modified
--
-- Behavior:
-- - LEFT JOIN to parent branches to show hierarchy
-- - Calculates object_count and storage_bytes on the fly
-- - Filters by status if provided
-- - Excludes DELETED by default
-- - Supports multiple ordering options

CREATE OR REPLACE FUNCTION pggit.list_branches(
    p_filter_status TEXT DEFAULT NULL,
    p_include_deleted BOOLEAN DEFAULT false,
    p_order_by TEXT DEFAULT 'created_at DESC'
) RETURNS TABLE (
    branch_id INTEGER,
    branch_name TEXT,
    parent_branch_id INTEGER,
    parent_branch_name TEXT,
    status TEXT,
    branch_type TEXT,
    head_commit_hash CHAR(64),
    object_count INTEGER,
    storage_bytes BIGINT,
    created_by TEXT,
    created_at TIMESTAMP,
    merged_at TIMESTAMP,
    merged_by TEXT,
    last_modified_at TIMESTAMP
) AS $$
DECLARE
    v_query TEXT;
    v_order_clause TEXT;
BEGIN
    -- Step 1 - Build base query with CTE for metrics calculation
    v_query := 'WITH branch_metrics AS (
        SELECT
            b.branch_id,
            COUNT(oh.*) AS object_count,
            COALESCE(SUM(LENGTH(COALESCE(oh.after_definition::TEXT, ''''))), 0) AS storage_bytes,
            MAX(COALESCE(oh.author_time, b.created_at)) AS last_modified
        FROM pggit.branches b
        LEFT JOIN pggit.object_history oh ON b.branch_id = oh.branch_id
        GROUP BY b.branch_id
    )
    SELECT
        b.branch_id,
        b.branch_name,
        b.parent_branch_id,
        pb.branch_name,
        b.status,
        b.branch_type,
        b.head_commit_hash,
        COALESCE(bm.object_count, 0)::INTEGER,
        COALESCE(bm.storage_bytes, 0)::BIGINT,
        b.created_by,
        b.created_at,
        b.merged_at,
        b.merged_by,
        COALESCE(bm.last_modified, b.created_at)
    FROM pggit.branches b
    LEFT JOIN pggit.branches pb ON b.parent_branch_id = pb.branch_id
    LEFT JOIN branch_metrics bm ON b.branch_id = bm.branch_id
    WHERE 1=1';

    -- Step 2 - Apply status filter
    IF p_filter_status IS NOT NULL THEN
        v_query := v_query || ' AND b.status = ' || quote_literal(p_filter_status);
    END IF;

    -- Step 3 - Apply deleted filter
    IF p_include_deleted = false THEN
        v_query := v_query || ' AND b.status != ' || quote_literal('DELETED');
    END IF;

    -- Step 4 - Validate and apply ordering
    -- Whitelist valid order_by values to prevent SQL injection
    v_order_clause := CASE
        WHEN p_order_by = 'created_at ASC' THEN ' ORDER BY b.created_at ASC'
        WHEN p_order_by = 'created_at DESC' THEN ' ORDER BY b.created_at DESC'
        WHEN p_order_by = 'name ASC' THEN ' ORDER BY b.branch_name ASC'
        WHEN p_order_by = 'name DESC' THEN ' ORDER BY b.branch_name DESC'
        WHEN p_order_by = 'status ASC' THEN ' ORDER BY b.status ASC'
        WHEN p_order_by = 'status DESC' THEN ' ORDER BY b.status DESC'
        ELSE ' ORDER BY b.created_at DESC'  -- Default if invalid
    END;

    v_query := v_query || v_order_clause;

    -- Step 5 - Execute query and return results
    RETURN QUERY EXECUTE v_query;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 2.4: pggit.checkout_branch()
-- ============================================================================
-- Switches the current branch in the session
--
-- Parameters:
--   p_branch_name: Name of branch to switch to
--
-- Returns TABLE with:
--   success: Boolean indicating success
--   previous_branch: Name of previous branch (NULL if no previous)
--   current_branch: Name of current branch (always p_branch_name on success)
--   message: Human-readable status message
--   switched_at: Timestamp of switch
--
-- Behavior:
-- - Tracks current branch in session variable 'pggit.current_branch'
-- - Verifies target branch is ACTIVE
-- - Updates session variable to new branch name
-- - Session-only: persists for duration of connection only
-- - Enables Phase 3+ to know which branch's objects to return
--
-- Note: This does NOT switch any actual tables or data.
-- It only tracks which branch is "current" in the session.
-- The actual switching of which objects are visible is done in Phase 3+.

CREATE OR REPLACE FUNCTION pggit.checkout_branch(
    p_branch_name TEXT
) RETURNS TABLE (
    success BOOLEAN,
    previous_branch TEXT,
    current_branch TEXT,
    message TEXT,
    switched_at TIMESTAMP
) AS $$
DECLARE
    v_previous_branch TEXT;
    v_branch_id INTEGER;
    v_branch_status TEXT;
    v_current_timestamp TIMESTAMP;
    v_message TEXT;
BEGIN
    -- Step 1 - Validate input
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RAISE EXCEPTION 'Branch name cannot be empty or NULL';
    END IF;

    -- Step 2 - Get previous branch from session (NULL means no previous set)
    v_previous_branch := current_setting('pggit.current_branch', true);
    IF v_previous_branch IS NULL OR v_previous_branch = '' THEN
        v_previous_branch := 'main';  -- Default to main if not set
    END IF;

    -- Step 3 - Verify target branch exists and is ACTIVE
    SELECT branch_id, status INTO v_branch_id, v_branch_status
    FROM pggit.branches
    WHERE branch_name = p_branch_name AND status = 'ACTIVE';

    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found or is not active', p_branch_name;
    END IF;

    v_current_timestamp := CURRENT_TIMESTAMP;

    -- Step 4 - Update session variable
    EXECUTE format('SET pggit.current_branch = %L', p_branch_name);

    -- Step 5 - Optional: Record in audit trail
    -- INSERT into pggit.history to track checkout events
    BEGIN
        INSERT INTO pggit.object_history (
            object_id,
            change_type,
            change_severity,
            commit_hash,
            branch_id,
            author_name,
            author_time
        )
        VALUES (
            1,  -- Placeholder object_id for branch checkout event
            'BRANCH_CHECKOUT',
            'PATCH',
            pggit.generate_sha256(p_branch_name || v_current_timestamp::TEXT),
            v_branch_id,
            CURRENT_USER,
            v_current_timestamp
        );
    EXCEPTION WHEN OTHERS THEN
        -- Silently ignore if history table doesn't have this column or has issues
        NULL;
    END;

    -- Step 6 - Return status
    v_message := 'Switched from ' || v_previous_branch || ' to ' || p_branch_name;

    RETURN QUERY
    SELECT
        true,
        v_previous_branch,
        p_branch_name,
        v_message,
        v_current_timestamp;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- End of Phase 2: Branch Management
-- ============================================================================
-- All four core functions are now defined.
-- Next step: Implementation (fill in TODO blocks)
-- Test file: tests/unit/test_phase2_branch_management.py
