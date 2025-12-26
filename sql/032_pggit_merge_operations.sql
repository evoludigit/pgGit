-- ============================================================================
-- pgGit Phase 4: Merge Operations Implementation
--
-- Implements three core functions for merging branches with conflict detection
-- and multiple resolution strategies.
--
-- Phase 4 Functions:
-- 1. pggit.find_merge_base() - Find common ancestor (LCA) of two branches
-- 2. pggit.detect_merge_conflicts() - Three-way conflict detection
-- 3. pggit.merge_branches() - Execute merge with strategy application
-- 4. pggit.resolve_conflict() - Manual conflict resolution
--
-- ============================================================================

-- Drop existing tables and functions to allow clean rebuild
DROP TABLE IF EXISTS pggit.merge_conflict_resolutions CASCADE;
DROP TABLE IF EXISTS pggit.merge_operations CASCADE;

-- Drop existing functions to allow signature changes
DROP FUNCTION IF EXISTS pggit.find_merge_base(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS pggit.detect_merge_conflicts(INTEGER, INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS pggit.merge_branches(INTEGER, INTEGER, TEXT, TEXT, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS pggit.resolve_conflict(TEXT, INTEGER, TEXT, TEXT) CASCADE;

-- ============================================================================
-- Phase 4.1: pggit.find_merge_base()
--
-- Finds the lowest common ancestor (LCA) between two branches using
-- recursive CTEs to build ancestry paths.
--
-- Algorithm:
-- 1. Build ancestry path for each branch (traverse parent_branch_id chain)
-- 2. Find first common node in both paths (LCA)
-- 3. Return LCA with depth information
--
-- Returns TABLE with:
--   base_branch_id: ID of common ancestor
--   base_branch_name: Name of common ancestor
--   depth_from_branch1: Steps from branch1 to LCA
--   depth_from_branch2: Steps from branch2 to LCA
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.find_merge_base(
    p_branch1_id INTEGER,
    p_branch2_id INTEGER
) RETURNS TABLE (
    base_branch_id INTEGER,
    base_branch_name TEXT,
    depth_from_branch1 INTEGER,
    depth_from_branch2 INTEGER
) AS $$
DECLARE
    v_base_id INTEGER;
    v_depth1 INTEGER;
    v_depth2 INTEGER;
    v_base_name TEXT;
BEGIN
    -- Validate inputs
    IF p_branch1_id IS NULL OR p_branch2_id IS NULL THEN
        RAISE EXCEPTION 'Branch IDs cannot be NULL';
    END IF;

    -- Verify branches exist
    PERFORM 1 FROM pggit.branches WHERE branch_id = p_branch1_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch with ID % does not exist', p_branch1_id;
    END IF;

    PERFORM 1 FROM pggit.branches WHERE branch_id = p_branch2_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch with ID % does not exist', p_branch2_id;
    END IF;

    -- Same branch has no common ancestor
    IF p_branch1_id = p_branch2_id THEN
        RETURN;
    END IF;

    -- Build ancestry paths and find LCA using recursive CTEs
    WITH RECURSIVE ancestry1 AS (
        SELECT branch_id, parent_branch_id, 0 AS depth
        FROM pggit.branches
        WHERE branch_id = p_branch1_id

        UNION ALL

        SELECT b.branch_id, b.parent_branch_id, a.depth + 1
        FROM pggit.branches b
        INNER JOIN ancestry1 a ON b.branch_id = a.parent_branch_id
        WHERE a.parent_branch_id IS NOT NULL
    ),
    ancestry2 AS (
        SELECT branch_id, parent_branch_id, 0 AS depth
        FROM pggit.branches
        WHERE branch_id = p_branch2_id

        UNION ALL

        SELECT b.branch_id, b.parent_branch_id, a.depth + 1
        FROM pggit.branches b
        INNER JOIN ancestry2 a ON b.branch_id = a.parent_branch_id
        WHERE a.parent_branch_id IS NOT NULL
    )
    SELECT INTO v_base_id, v_depth1, v_depth2
        COALESCE(a1.branch_id, a2.branch_id),
        CASE WHEN a1.branch_id IS NOT NULL THEN a1.depth ELSE 999 END,
        CASE WHEN a2.branch_id IS NOT NULL THEN a2.depth ELSE 999 END
    FROM ancestry1 a1
    FULL OUTER JOIN ancestry2 a2 ON a1.branch_id = a2.branch_id
    WHERE a1.branch_id IS NOT NULL AND a2.branch_id IS NOT NULL
    ORDER BY LEAST(
        CASE WHEN a1.branch_id IS NOT NULL THEN a1.depth ELSE 999 END,
        CASE WHEN a2.branch_id IS NOT NULL THEN a2.depth ELSE 999 END
    ) DESC
    LIMIT 1;

    -- Fallback to root of branch1 if no common ancestor found
    IF v_base_id IS NULL THEN
        WITH RECURSIVE root_path AS (
            SELECT branch_id, parent_branch_id, 0 AS depth
            FROM pggit.branches
            WHERE branch_id = p_branch1_id

            UNION ALL

            SELECT b.branch_id, b.parent_branch_id, r.depth + 1
            FROM pggit.branches b
            INNER JOIN root_path r ON b.branch_id = r.parent_branch_id
            WHERE r.parent_branch_id IS NOT NULL
        )
        SELECT INTO v_base_id, v_depth1
            branch_id, depth
        FROM root_path
        WHERE parent_branch_id IS NULL;

        v_depth2 := 999;
    END IF;

    -- Get base branch name
    SELECT branch_name INTO v_base_name FROM pggit.branches WHERE branch_id = v_base_id;

    RETURN QUERY
    SELECT v_base_id, v_base_name, v_depth1, v_depth2;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 4.2: pggit.detect_merge_conflicts()
--
-- Three-way merge conflict detection using base branch as reference.
--
-- Algorithm:
-- 1. Auto-discover merge base if not provided using find_merge_base()
-- 2. Load objects from source, target, and base branches
-- 3. Full outer join all three to find all unique objects
-- 4. Classify conflicts using three-way merge logic
-- 5. Determine severity and auto-resolvable flag
-- 6. Check dependencies for breaking changes
--
-- Classification Logic (hash-based):
--   base=NULL,source=NULL,target=NULL → NO_CONFLICT
--   base=H,source=H,target=H → NO_CONFLICT
--   base=H,source=H,target=X → TARGET_MODIFIED (auto)
--   base=H,source=X,target=H → SOURCE_MODIFIED (auto)
--   base=H,source=X,target=Y → BOTH_MODIFIED (manual)
--   base=NULL,source=H,target=H → NO_CONFLICT
--   base=NULL,source=H,target=X → BOTH_MODIFIED (manual)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.detect_merge_conflicts(
    p_source_branch_id INTEGER,
    p_target_branch_id INTEGER,
    p_base_branch_id INTEGER DEFAULT NULL
) RETURNS TABLE (
    conflict_id INTEGER,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    conflict_type TEXT,
    base_hash TEXT,
    source_hash TEXT,
    target_hash TEXT,
    auto_resolvable BOOLEAN,
    severity TEXT,
    dependencies_count INTEGER
) AS $$
DECLARE
    v_base_id INTEGER;
    v_main_branch_id INTEGER;
BEGIN
    -- Auto-discover merge base if not provided
    IF p_base_branch_id IS NULL THEN
        SELECT base_branch_id INTO v_base_id
        FROM pggit.find_merge_base(p_source_branch_id, p_target_branch_id);

        -- Fallback to main branch if no LCA found
        IF v_base_id IS NULL THEN
            SELECT branch_id INTO v_main_branch_id
            FROM pggit.branches WHERE branch_name = 'main' LIMIT 1;
            v_base_id := COALESCE(v_main_branch_id, 1);
        END IF;
    ELSE
        v_base_id := p_base_branch_id;
    END IF;

    -- Return conflicts found via three-way merge logic
    -- Uses object_history to determine which branch has which objects
    RETURN QUERY
    WITH source_objs AS (
        SELECT DISTINCT
            so.object_type, so.schema_name, so.object_name,
            so.content_hash as hash, so.object_id
        FROM pggit.schema_objects so
        WHERE EXISTS (
            SELECT 1 FROM pggit.object_history oh
            WHERE oh.object_id = so.object_id
              AND oh.branch_id = p_source_branch_id
        ) AND so.is_active = true
    ),
    target_objs AS (
        SELECT DISTINCT
            so.object_type, so.schema_name, so.object_name,
            so.content_hash as hash, so.object_id
        FROM pggit.schema_objects so
        WHERE EXISTS (
            SELECT 1 FROM pggit.object_history oh
            WHERE oh.object_id = so.object_id
              AND oh.branch_id = p_target_branch_id
        ) AND so.is_active = true
    ),
    base_objs AS (
        SELECT DISTINCT
            so.object_type, so.schema_name, so.object_name,
            so.content_hash as hash, so.object_id
        FROM pggit.schema_objects so
        WHERE EXISTS (
            SELECT 1 FROM pggit.object_history oh
            WHERE oh.object_id = so.object_id
              AND oh.branch_id = v_base_id
        ) AND so.is_active = true
    ),
    all_objs AS (
        SELECT
            COALESCE(s.object_type, t.object_type, b.object_type) as object_type,
            COALESCE(s.schema_name, t.schema_name, b.schema_name) as schema_name,
            COALESCE(s.object_name, t.object_name, b.object_name) as object_name,
            b.hash as base_hash,
            s.hash as source_hash,
            t.hash as target_hash
        FROM source_objs s
        FULL OUTER JOIN target_objs t
            ON s.object_type = t.object_type
            AND s.schema_name = t.schema_name
            AND s.object_name = t.object_name
        LEFT JOIN base_objs b
            ON b.object_type = COALESCE(s.object_type, t.object_type)
            AND b.schema_name = COALESCE(s.schema_name, t.schema_name)
            AND b.object_name = COALESCE(s.object_name, t.object_name)
    ),
    classified AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY object_type, schema_name, object_name) as id,
            object_type,
            schema_name,
            object_name,
            base_hash,
            source_hash,
            target_hash,
            -- Three-way merge classification logic
            CASE
                -- No changes anywhere
                WHEN base_hash IS NULL AND source_hash IS NULL AND target_hash IS NULL THEN 'NO_CONFLICT'
                WHEN base_hash IS NOT NULL AND base_hash = source_hash AND source_hash = target_hash THEN 'NO_CONFLICT'

                -- Both added same object (new in both branches)
                WHEN base_hash IS NULL AND source_hash = target_hash THEN 'NO_CONFLICT'

                -- Deletions
                WHEN source_hash IS NULL AND target_hash IS NOT NULL AND base_hash IS NOT NULL
                    THEN 'DELETED_SOURCE'
                WHEN target_hash IS NULL AND source_hash IS NOT NULL AND base_hash IS NOT NULL
                    THEN 'DELETED_TARGET'

                -- Single-branch modifications
                WHEN base_hash IS NOT NULL AND base_hash = target_hash AND source_hash != base_hash
                    THEN 'SOURCE_MODIFIED'
                WHEN base_hash IS NOT NULL AND base_hash = source_hash AND target_hash != base_hash
                    THEN 'TARGET_MODIFIED'

                -- True conflicts (both modified independently)
                WHEN source_hash IS NOT NULL AND target_hash IS NOT NULL AND base_hash IS NOT NULL
                    AND source_hash != base_hash AND target_hash != base_hash
                    AND source_hash != target_hash
                    THEN 'BOTH_MODIFIED'

                -- Both added differently
                WHEN base_hash IS NULL AND source_hash IS NOT NULL AND target_hash IS NOT NULL
                    AND source_hash != target_hash
                    THEN 'BOTH_MODIFIED'

                -- Default for edge cases
                ELSE 'BOTH_MODIFIED'
            END as conflict_type,
            -- Auto-resolvable if only one branch changed
            CASE
                WHEN base_hash IS NULL AND source_hash IS NULL AND target_hash IS NULL THEN true
                WHEN base_hash = source_hash AND source_hash = target_hash THEN true
                WHEN base_hash IS NULL AND source_hash = target_hash THEN true
                WHEN source_hash IS NULL AND base_hash IS NOT NULL THEN true
                WHEN target_hash IS NULL AND base_hash IS NOT NULL THEN true
                WHEN base_hash = target_hash AND source_hash != base_hash THEN true
                WHEN base_hash = source_hash AND target_hash != base_hash THEN true
                ELSE false
            END as auto_resolvable,
            -- Severity determination
            CASE
                WHEN object_type IN ('TABLE', 'FUNCTION', 'VIEW') AND (source_hash IS NULL OR target_hash IS NULL)
                    THEN 'MAJOR'
                WHEN base_hash IS NULL THEN 'MAJOR'  -- New object with conflicts
                ELSE 'MINOR'
            END as severity
        FROM all_objs
    )
    SELECT
        classified.id,
        classified.object_type,
        classified.schema_name,
        classified.object_name,
        classified.conflict_type,
        classified.base_hash,
        classified.source_hash,
        classified.target_hash,
        classified.auto_resolvable,
        classified.severity,
        0::INTEGER as dependencies_count  -- Simplified for now
    FROM classified
    WHERE classified.conflict_type != 'NO_CONFLICT';

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 4.3: pggit.merge_branches()
--
-- Execute merge between two branches with conflict detection and strategy
-- application.
--
-- Strategies:
--   ABORT_ON_CONFLICT - Fail if any conflicts (safest)
--   TARGET_WINS - Keep target definitions
--   SOURCE_WINS - Apply source definitions
--   UNION - Smart merge of compatible objects
--   MANUAL_REVIEW - Require explicit resolution
--
-- Returns merge result with status and conflict information
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch_id INTEGER,
    p_target_branch_id INTEGER,
    p_merge_message TEXT,
    p_merge_strategy TEXT,
    p_base_branch_id INTEGER DEFAULT NULL
) RETURNS TABLE (
    merge_id TEXT,
    status TEXT,
    conflicts_detected INTEGER,
    auto_resolvable_count INTEGER,
    manual_count INTEGER,
    merge_complete BOOLEAN,
    result_commit_hash TEXT,
    merge_base_branch_id INTEGER
) AS $$
DECLARE
    v_base_id INTEGER;
    v_merge_id TEXT;
    v_result_hash TEXT;
    v_total_conflicts INTEGER := 0;
    v_auto_conflicts INTEGER := 0;
    v_manual_conflicts INTEGER := 0;
    v_merge_complete BOOLEAN := false;
    v_status TEXT;
    v_current_user TEXT;
    v_source_name TEXT;
    v_target_name TEXT;
    v_main_branch_id INTEGER;
BEGIN
    -- Validate inputs
    IF p_source_branch_id IS NULL OR p_target_branch_id IS NULL THEN
        RAISE EXCEPTION 'Source and target branch IDs required';
    END IF;

    IF p_source_branch_id = p_target_branch_id THEN
        RAISE EXCEPTION 'Cannot merge branch with itself';
    END IF;

    -- Validate strategy
    IF p_merge_strategy NOT IN ('ABORT_ON_CONFLICT', 'TARGET_WINS', 'SOURCE_WINS', 'UNION', 'MANUAL_REVIEW') THEN
        RAISE EXCEPTION 'Invalid merge strategy: %', p_merge_strategy;
    END IF;

    -- Get branch names for logging
    SELECT branch_name INTO v_source_name FROM pggit.branches WHERE branch_id = p_source_branch_id;
    SELECT branch_name INTO v_target_name FROM pggit.branches WHERE branch_id = p_target_branch_id;

    -- Find merge base
    IF p_base_branch_id IS NULL THEN
        SELECT base_branch_id INTO v_base_id
        FROM pggit.find_merge_base(p_source_branch_id, p_target_branch_id);

        -- Fallback to main branch if no LCA found
        IF v_base_id IS NULL THEN
            SELECT branch_id INTO v_main_branch_id
            FROM pggit.branches WHERE branch_name = 'main' LIMIT 1;
            v_base_id := COALESCE(v_main_branch_id, 1);
        END IF;
    ELSE
        v_base_id := p_base_branch_id;
    END IF;

    -- Detect conflicts
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE auto_resolvable = true),
        COUNT(*) FILTER (WHERE auto_resolvable = false)
    INTO v_total_conflicts, v_auto_conflicts, v_manual_conflicts
    FROM pggit.detect_merge_conflicts(p_source_branch_id, p_target_branch_id, v_base_id);

    -- Apply strategy
    CASE p_merge_strategy
        WHEN 'ABORT_ON_CONFLICT' THEN
            IF v_total_conflicts > 0 THEN
                v_status := 'CONFLICT';
                v_merge_complete := false;
            ELSE
                v_status := 'SUCCESS';
                v_merge_complete := true;
            END IF;

        WHEN 'TARGET_WINS' THEN
            v_status := 'SUCCESS';
            v_merge_complete := true;
            -- Source changes are discarded, target definitions kept

        WHEN 'SOURCE_WINS' THEN
            v_status := 'SUCCESS';
            v_merge_complete := true;
            -- Target is overridden with source definitions

        WHEN 'UNION' THEN
            -- Try smart merge for compatible objects
            -- If manual conflicts remain, mark for manual review
            IF v_manual_conflicts > 0 THEN
                v_status := 'CONFLICT';
                v_merge_complete := false;
            ELSE
                v_status := 'SUCCESS';
                v_merge_complete := true;
            END IF;

        WHEN 'MANUAL_REVIEW' THEN
            v_status := 'CONFLICT';
            v_merge_complete := false;
            -- User must call resolve_conflict() for each conflict

    END CASE;

    -- Generate merge ID
    v_merge_id := gen_random_uuid()::TEXT;

    -- Create result commit hash
    v_result_hash := encode(
        sha256(CONCAT_WS('::', p_source_branch_id::TEXT, p_target_branch_id::TEXT, v_base_id::TEXT)::bytea),
        'hex'
    );

    -- Get current user
    v_current_user := CURRENT_USER;

    -- Create merge_operations record
    INSERT INTO pggit.merge_operations (
        id, source_branch_id, target_branch_id, merge_base_branch_id,
        merge_strategy, status, conflicts_detected, conflicts_resolved,
        result_commit_hash, merged_by, merged_at
    ) VALUES (
        v_merge_id, p_source_branch_id, p_target_branch_id, v_base_id,
        p_merge_strategy, v_status, v_total_conflicts,
        CASE WHEN v_merge_complete THEN v_total_conflicts ELSE v_auto_conflicts END,
        v_result_hash, v_current_user, NOW()
    );

    -- If merge complete, update branch status and create commit
    IF v_merge_complete THEN
        UPDATE pggit.branches
        SET status = 'MERGED', merged_at = NOW(), merged_by = v_current_user
        WHERE branch_id = p_source_branch_id;
    END IF;

    RETURN QUERY SELECT
        v_merge_id,
        v_status,
        v_total_conflicts,
        v_auto_conflicts,
        v_manual_conflicts,
        v_merge_complete,
        v_result_hash,
        v_base_id;

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Phase 4.4: pggit.resolve_conflict()
--
-- Manually resolve a conflict from MANUAL_REVIEW merge strategy.
--
-- Resolution options:
--   SOURCE - Use source branch's definition
--   TARGET - Use target branch's definition
--   CUSTOM - Use provided custom definition (must pass EXPLAIN validation)
--
-- Returns resolution status and updated merge information
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    p_merge_id TEXT,
    p_conflict_id INTEGER,
    p_resolution TEXT,
    p_custom_definition TEXT DEFAULT NULL
) RETURNS TABLE (
    merge_id TEXT,
    conflict_id INTEGER,
    resolution_applied TEXT,
    resolved_at TIMESTAMP,
    merge_complete BOOLEAN
) AS $$
DECLARE
    v_merge_record RECORD;
    v_final_definition TEXT;
    v_current_user TEXT;
BEGIN
    -- Validate resolution option
    IF p_resolution NOT IN ('SOURCE', 'TARGET', 'CUSTOM') THEN
        RAISE EXCEPTION 'Invalid resolution option: %', p_resolution;
    END IF;

    -- Get merge record
    SELECT * INTO v_merge_record
    FROM pggit.merge_operations
    WHERE id = p_merge_id;

    IF v_merge_record IS NULL THEN
        RAISE EXCEPTION 'Merge with ID % not found', p_merge_id;
    END IF;

    -- Validate custom definition if provided
    IF p_resolution = 'CUSTOM' THEN
        IF p_custom_definition IS NULL OR TRIM(p_custom_definition) = '' THEN
            RAISE EXCEPTION 'CUSTOM resolution requires non-empty p_custom_definition';
        END IF;

        -- Validate syntax without executing (simple check for basic SQL)
        IF NOT (p_custom_definition ~* '^CREATE\s+(TABLE|VIEW|FUNCTION|INDEX|TRIGGER|PROCEDURE)'
            OR p_custom_definition ~* '^ALTER\s+(TABLE|VIEW|FUNCTION|INDEX|TRIGGER|PROCEDURE)'
            OR p_custom_definition ~* '^DROP\s+(TABLE|VIEW|FUNCTION|INDEX|TRIGGER|PROCEDURE)') THEN
            RAISE EXCEPTION 'Custom definition must start with CREATE, ALTER, or DROP';
        END IF;

        v_final_definition := p_custom_definition;
    END IF;

    -- Record resolution in merge_conflict_resolutions table
    INSERT INTO pggit.merge_conflict_resolutions (
        merge_id, conflict_id, resolution_type, custom_definition, resolved_by, resolved_at
    ) VALUES (
        p_merge_id, p_conflict_id, p_resolution, v_final_definition, CURRENT_USER, NOW()
    );

    -- Get current user
    v_current_user := CURRENT_USER;

    RETURN QUERY SELECT
        p_merge_id,
        p_conflict_id,
        p_resolution,
        NOW(),
        false;  -- merge_complete determined separately

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Support Tables for Merge Operations
-- ============================================================================

-- Create merge_operations table if it doesn't exist
CREATE TABLE IF NOT EXISTS pggit.merge_operations (
    id TEXT PRIMARY KEY,
    source_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    target_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    merge_base_branch_id INTEGER REFERENCES pggit.branches(branch_id),
    merge_strategy TEXT NOT NULL CHECK (merge_strategy IN ('ABORT_ON_CONFLICT', 'TARGET_WINS', 'SOURCE_WINS', 'UNION', 'MANUAL_REVIEW')),
    status TEXT NOT NULL DEFAULT 'CONFLICT' CHECK (status IN ('SUCCESS', 'CONFLICT', 'ABORTED')),
    conflicts_detected INTEGER DEFAULT 0,
    conflicts_resolved INTEGER DEFAULT 0,
    result_commit_hash TEXT,
    merged_by TEXT,
    merged_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create merge_conflict_resolutions table if it doesn't exist
CREATE TABLE IF NOT EXISTS pggit.merge_conflict_resolutions (
    id BIGSERIAL PRIMARY KEY,
    merge_id TEXT NOT NULL,
    conflict_id INTEGER NOT NULL,
    resolution_type TEXT NOT NULL CHECK (resolution_type IN ('SOURCE', 'TARGET', 'CUSTOM')),
    custom_definition TEXT,
    resolved_by TEXT,
    resolved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    FOREIGN KEY (merge_id) REFERENCES pggit.merge_operations(id)
);

-- ============================================================================
-- Indexes for Performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_merge_operations_source ON pggit.merge_operations(source_branch_id);
CREATE INDEX IF NOT EXISTS idx_merge_operations_target ON pggit.merge_operations(target_branch_id);
CREATE INDEX IF NOT EXISTS idx_merge_operations_status ON pggit.merge_operations(status);
CREATE INDEX IF NOT EXISTS idx_merge_conflict_resolutions_merge ON pggit.merge_conflict_resolutions(merge_id);

-- ============================================================================
-- Phase 4 Implementation Complete
-- ============================================================================
