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
    p_branch_type TEXT DEFAULT 'standard',
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
    v_parent_head_commit TEXT;
BEGIN
    -- TODO: Step 1 - Validate inputs
    -- - Check p_branch_name not empty/NULL
    -- - Check matches regex ^[a-zA-Z0-9._/#-]+$
    -- - Check p_branch_type is valid
    -- - Check p_branch_name is unique

    -- TODO: Step 2 - Find active parent branch
    -- - Query pggit.branches for p_parent_branch_name
    -- - Filter where status = 'ACTIVE'
    -- - Raise exception if not found

    -- TODO: Step 3 - Get parent's head commit
    -- - Query head_commit_hash from parent branch

    -- TODO: Step 4 - Generate commit hash for branch point
    -- - Use sha256(CURRENT_TIMESTAMP || p_branch_name || p_parent_branch_name)

    -- TODO: Step 5 - Insert new branch entry
    -- - INSERT into pggit.branches with all fields
    -- - Use INSERT RETURNING to get v_new_branch_id

    -- TODO: Step 6 - Copy parent's objects to new branch
    -- - INSERT into pggit.objects from parent branch
    -- - Filter where branch_name = p_parent_branch_name AND is_active = true

    -- TODO: Step 7 - Return new branch information
    -- - RETURN QUERY with all fields

    RAISE EXCEPTION 'pggit.create_branch() not yet implemented';
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
    v_branch_status pggit.branch_status;
    v_merge_message TEXT;
BEGIN
    -- TODO: Step 1 - Validate input
    -- - Check p_branch_name not NULL/empty
    -- - Verify branch exists in pggit.branches

    -- TODO: Step 2 - Prevent main branch deletion
    -- - If p_branch_name = 'main', raise exception

    -- TODO: Step 3 - Check merge status (unless force=true)
    -- - If p_force = false:
    --   - Check if status = 'MERGED'
    --   - If not MERGED, raise exception with message about force flag

    -- TODO: Step 4 - Cascade cleanup
    -- - DELETE from pggit.data_branches (has CASCADE FK)
    -- - DELETE from pggit.commits (has CASCADE FK)
    -- - DELETE from pggit.history (has CASCADE FK)
    -- - DELETE from pggit.objects for this branch

    -- TODO: Step 5 - Mark branch as DELETED
    -- - UPDATE pggit.branches SET status='DELETED', merged_at=CURRENT_TIMESTAMP

    -- TODO: Step 6 - Return status
    -- - RETURN QUERY with success, message, branch_id, deleted_at

    RAISE EXCEPTION 'pggit.delete_branch() not yet implemented';
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
    p_filter_status pggit.branch_status DEFAULT NULL,
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
BEGIN
    -- TODO: Step 1 - Build base query
    -- - SELECT from pggit.branches b
    -- - LEFT JOIN pggit.branches pb ON b.parent_branch_id = pb.id

    -- TODO: Step 2 - Apply status filter
    -- - If p_filter_status IS NOT NULL: WHERE b.status = p_filter_status

    -- TODO: Step 3 - Apply deleted filter
    -- - If p_include_deleted = false: WHERE b.status != 'DELETED'

    -- TODO: Step 4 - Calculate metrics
    -- - object_count: COUNT(*) from pggit.objects where branch_id = b.id
    -- - storage_bytes: SUM(LENGTH(ddl_normalized::text)) for branch objects
    -- - last_modified_at: MAX(updated_at) from pggit.objects for branch

    -- TODO: Step 5 - Apply ordering
    -- - Validate p_order_by against whitelist
    -- - Apply ORDER BY clause

    -- TODO: Step 6 - Return results
    -- - RETURN QUERY with all calculated columns

    RAISE EXCEPTION 'pggit.list_branches() not yet implemented';
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
    v_branch_status pggit.branch_status;
BEGIN
    -- TODO: Step 1 - Validate input
    -- - Check p_branch_name not NULL/empty

    -- TODO: Step 2 - Get previous branch from session
    -- - Query current_setting('pggit.current_branch', true)
    -- - Default to 'main' if not set

    -- TODO: Step 3 - Verify target branch exists and is ACTIVE
    -- - Query pggit.branches for p_branch_name
    -- - Filter where status = 'ACTIVE'
    -- - Raise exception if not found/not active

    -- TODO: Step 4 - Update session variable
    -- - EXECUTE: SET pggit.current_branch = p_branch_name

    -- TODO: Step 5 - Optional: Record in audit trail
    -- - Could INSERT into pggit.history with BRANCH_CHECKOUT change_type

    -- TODO: Step 6 - Return status
    -- - RETURN with success=true, both branches, timestamp

    RAISE EXCEPTION 'pggit.checkout_branch() not yet implemented';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- End of Phase 2: Branch Management
-- ============================================================================
-- All four core functions are now defined.
-- Next step: Implementation (fill in TODO blocks)
-- Test file: tests/unit/test_phase2_branch_management.py
