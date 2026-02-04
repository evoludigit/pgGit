-- pgGit v0.2: Merge Operations
-- Schema branch merging with conflict detection and resolution
-- Author: stephengibson12
-- Phase: v0.2 (Merge Operations)

-- ============================================================================
-- CREATE MERGE HISTORY TABLE
-- ============================================================================
-- Tracks all merge operations across branches

CREATE TABLE IF NOT EXISTS pggit.merge_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_branch text NOT NULL,
    target_branch text NOT NULL,
    initiated_by text NOT NULL DEFAULT current_user,
    initiated_at timestamp NOT NULL DEFAULT now(),
    completed_at timestamp,
    status text NOT NULL DEFAULT 'in_progress' CHECK (status IN (
        'in_progress',
        'completed',
        'failed',
        'aborted',
        'awaiting_resolution'
    )),
    conflict_count integer DEFAULT 0,
    resolved_conflicts integer DEFAULT 0,
    unresolved_conflicts integer DEFAULT 0,
    merge_strategy text DEFAULT 'auto',
    error_message text,
    notes jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_merge_history_status
    ON pggit.merge_history(status);
CREATE INDEX IF NOT EXISTS idx_merge_history_branches
    ON pggit.merge_history(source_branch, target_branch);
CREATE INDEX IF NOT EXISTS idx_merge_history_time
    ON pggit.merge_history(initiated_at DESC);

-- ============================================================================
-- CREATE MERGE CONFLICTS TABLE
-- ============================================================================
-- Tracks individual conflicts identified during merge operations

CREATE TABLE IF NOT EXISTS pggit.merge_conflicts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merge_id uuid NOT NULL REFERENCES pggit.merge_history(id) ON DELETE CASCADE,
    table_name text NOT NULL,
    conflict_type text NOT NULL,
    source_definition text,
    target_definition text,
    resolution text DEFAULT NULL,
    resolved_at timestamp,
    resolved_by text,
    resolution_notes text,

    UNIQUE(merge_id, table_name, conflict_type)
);

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_merge
    ON pggit.merge_conflicts(merge_id);
CREATE INDEX IF NOT EXISTS idx_merge_conflicts_unresolved
    ON pggit.merge_conflicts(merge_id, resolution)
    WHERE resolution IS NULL;

-- ============================================================================
-- FUNCTION: pggit.detect_conflicts()
-- ============================================================================
-- Identifies schema conflicts between two branches
--
-- RETURNS: jsonb with structure:
-- {
--   "conflict_count": <integer>,
--   "conflicts": [
--     {"table": <name>, "type": <type>, ...},
--     ...
--   ]
-- }

CREATE OR REPLACE FUNCTION pggit.detect_conflicts(
    p_source_branch text,
    p_target_branch text
)
RETURNS jsonb AS $$
DECLARE
    v_conflicts jsonb := '{"conflict_count": 0, "conflicts": []}'::jsonb;
    v_conflict_count integer := 0;
    v_conflict_array jsonb[] := '{}';
    v_object record;
    v_source_hash text;
    v_target_hash text;
    v_conflict_type text;
BEGIN
    -- Validate branches exist
    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_source_branch) THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_target_branch) THEN
        RAISE EXCEPTION 'Target branch % not found', p_target_branch;
    END IF;

    -- Compare objects between branches using full outer join
    FOR v_object IN
        SELECT
            COALESCE(s.object_type, t.object_type) as object_type,
            COALESCE(s.schema_name, t.schema_name) as schema_name,
            COALESCE(s.object_name, t.object_name) as object_name,
            s.content_hash as source_hash,
            t.content_hash as target_hash,
            (s.id IS NOT NULL) as in_source,
            (t.id IS NOT NULL) as in_target
        FROM pggit.objects s
        FULL OUTER JOIN pggit.objects t
            ON s.object_type = t.object_type
            AND s.schema_name = t.schema_name
            AND s.object_name = t.object_name
            AND t.branch_name = p_target_branch
        WHERE s.branch_name = p_source_branch
          OR t.branch_name = p_target_branch
    LOOP
        v_conflict_type := NULL;
        v_source_hash := v_object.source_hash;
        v_target_hash := v_object.target_hash;

        -- Detect conflict types
        IF v_object.in_source AND NOT v_object.in_target THEN
            v_conflict_type := 'table_added';
        ELSIF NOT v_object.in_source AND v_object.in_target THEN
            v_conflict_type := 'table_removed';
        ELSIF v_object.in_source AND v_object.in_target AND v_source_hash IS DISTINCT FROM v_target_hash THEN
            v_conflict_type := 'table_modified';
        END IF;

        -- Add to conflict list if conflict detected
        IF v_conflict_type IS NOT NULL THEN
            v_conflict_count := v_conflict_count + 1;
            v_conflict_array := array_append(
                v_conflict_array,
                jsonb_build_object(
                    'table', v_object.schema_name || '.' || v_object.object_name,
                    'type', v_conflict_type,
                    'source_hash', v_source_hash,
                    'target_hash', v_target_hash
                )
            );
        END IF;
    END LOOP;

    -- Build result
    v_conflicts := jsonb_build_object(
        'conflict_count', v_conflict_count,
        'conflicts', v_conflict_array
    );

    RAISE NOTICE 'detect_conflicts: Found % conflicts between %s and %s',
        v_conflict_count, p_source_branch, p_target_branch;

    RETURN v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.merge()
-- ============================================================================
-- Merge source branch into target branch
--
-- PARAMETERS:
--   p_source_branch: Branch to merge from
--   p_target_branch: Branch to merge into (NULL = current branch)
--   p_merge_strategy: 'auto' (default) or 'manual'
--
-- RETURNS: jsonb with merge result:
-- {
--   "merge_id": <uuid>,
--   "status": "completed" | "awaiting_resolution",
--   "conflicts": [...],
--   "tables_merged": <integer>,
--   "conflict_count": <integer>
-- }

CREATE OR REPLACE FUNCTION pggit.merge(
    p_source_branch text,
    p_target_branch text DEFAULT NULL,
    p_merge_strategy text DEFAULT 'auto'
)
RETURNS jsonb AS $$
DECLARE
    v_merge_id uuid;
    v_result jsonb;
    v_current_branch text;
    v_conflicts jsonb;
    v_conflict_count integer;
BEGIN
    -- TODO: Implement merge logic
    -- 1. Get current branch if target is NULL
    -- 2. Validate both branches exist
    -- 3. Create merge_history record
    -- 4. Detect conflicts
    -- 5. If auto and no conflicts: perform merge
    -- 6. If manual or conflicts: return awaiting_resolution status
    -- 7. Return merge result

    v_merge_id := gen_random_uuid();
    v_result := jsonb_build_object(
        'merge_id', v_merge_id,
        'status', 'in_progress',
        'conflicts', '[]'::jsonb,
        'tables_merged', 0,
        'conflict_count', 0
    );

    RAISE NOTICE 'merge: Merging %s into %s', p_source_branch, COALESCE(p_target_branch, 'current');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.resolve_conflict()
-- ============================================================================
-- Resolve a single conflict in a merge operation
--
-- PARAMETERS:
--   p_merge_id: ID of the merge operation
--   p_table_name: Name of conflicted table
--   p_resolution: 'ours' (keep target) | 'theirs' (use source) | 'custom'
--   p_custom_definition: Custom definition if p_resolution='custom'

CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    p_merge_id uuid,
    p_table_name text,
    p_resolution text,
    p_custom_definition text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
    -- TODO: Implement conflict resolution logic
    -- 1. Validate merge exists and status
    -- 2. Find conflict record
    -- 3. Apply resolution based on choice
    -- 4. Update conflict record
    -- 5. Check if all conflicts resolved
    -- 6. If all resolved: call _complete_merge_after_resolution()

    RAISE NOTICE 'resolve_conflict: Merge % - Table % - Resolution %s',
        p_merge_id, p_table_name, p_resolution;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit._complete_merge_after_resolution()
-- ============================================================================
-- Internal function to complete merge after all conflicts are resolved

CREATE OR REPLACE FUNCTION pggit._complete_merge_after_resolution(
    p_merge_id uuid
)
RETURNS void AS $$
BEGIN
    -- TODO: Implement merge completion logic
    -- 1. Get merge record
    -- 2. Apply all resolved conflicts
    -- 3. Create merge commit
    -- 4. Update merge_history status to completed
    -- 5. Handle errors and rollback if needed

    RAISE NOTICE '_complete_merge_after_resolution: Completing merge %s', p_merge_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_merge_status()
-- ============================================================================
-- Get current status of a merge operation

CREATE OR REPLACE FUNCTION pggit.get_merge_status(
    p_merge_id uuid
)
RETURNS jsonb AS $$
BEGIN
    -- TODO: Implement status query
    -- 1. Get merge_history record
    -- 2. Get associated conflicts
    -- 3. Build status response

    RETURN jsonb_build_object(
        'merge_id', p_merge_id,
        'status', 'in_progress'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.abort_merge()
-- ============================================================================
-- Abort a merge operation in progress

CREATE OR REPLACE FUNCTION pggit.abort_merge(
    p_merge_id uuid,
    p_reason text DEFAULT 'User aborted'
)
RETURNS void AS $$
BEGIN
    -- TODO: Implement merge abort logic
    -- 1. Update merge_history status to 'aborted'
    -- 2. Clean up any partial changes
    -- 3. Record reason

    RAISE NOTICE 'abort_merge: Aborting merge %s - %s', p_merge_id, p_reason;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: pggit.v_merge_conflicts
-- ============================================================================
-- View for easy access to unresolved conflicts

CREATE OR REPLACE VIEW pggit.v_merge_conflicts AS
SELECT
    mc.id,
    mc.merge_id,
    mh.source_branch,
    mh.target_branch,
    mc.table_name,
    mc.conflict_type,
    mc.resolution,
    mh.status as merge_status,
    mh.initiated_at,
    mh.initiated_by
FROM pggit.merge_conflicts mc
JOIN pggit.merge_history mh ON mh.id = mc.merge_id
WHERE mc.resolution IS NULL
ORDER BY mh.initiated_at DESC, mc.table_name;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT ON pggit.merge_history TO PUBLIC;
GRANT SELECT, INSERT ON pggit.merge_conflicts TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.detect_conflicts(text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.merge(text, text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.resolve_conflict(uuid, text, text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_merge_status(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.abort_merge(uuid, text) TO PUBLIC;

-- ============================================================================
-- TODO MARKERS
-- ============================================================================
-- Phase 1 Implementation Checklist:
-- TODO: Implement detect_conflicts() logic
-- TODO: Implement merge() logic
-- TODO: Implement resolve_conflict() logic
-- TODO: Implement _complete_merge_after_resolution() logic
-- TODO: Implement get_merge_status() logic
-- TODO: Implement abort_merge() logic
-- TODO: Add comprehensive error handling
-- TODO: Add transaction safety with savepoints
-- TODO: Add idempotency checks
-- TODO: Performance testing and optimization

-- End of v0.2 Merge Operations SQL
