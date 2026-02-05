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

-- NOTE: pggit.merge_conflicts table is defined in 001_schema.sql
-- Do not redefine it here to avoid conflicts.

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
    v_source_id integer;
    v_target_id integer;
    v_source_hash text;
    v_target_hash text;
    v_conflict_type text;
BEGIN
    -- Get branch IDs
    SELECT id INTO v_source_id FROM pggit.branches WHERE name = p_source_branch;
    IF v_source_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;

    SELECT id INTO v_target_id FROM pggit.branches WHERE name = p_target_branch;
    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'Target branch % not found', p_target_branch;
    END IF;

    -- Compare objects between branches using full outer join
    -- Branch filters in ON clause ensure we only join matching objects across these two branches
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
            AND s.branch_id = v_source_id
            AND t.branch_id = v_target_id
        WHERE (s.branch_id = v_source_id OR s.id IS NULL)
          AND (t.branch_id = v_target_id OR t.id IS NULL)
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
    v_target_branch text;
    v_conflicts jsonb;
    v_conflict_count integer;
    v_conflict_obj record;
    v_conflict_array jsonb[] := '{}';
BEGIN
    -- Validate branches exist
    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_source_branch) THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;

    -- Use provided target or default to main
    v_target_branch := COALESCE(p_target_branch, 'main');

    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = v_target_branch) THEN
        RAISE EXCEPTION 'Target branch % not found', v_target_branch;
    END IF;

    -- Generate merge ID
    v_merge_id := gen_random_uuid();

    -- Detect conflicts
    v_conflicts := pggit.detect_conflicts(p_source_branch, v_target_branch);
    v_conflict_count := (v_conflicts->>'conflict_count')::integer;

    -- Create merge_history record
    INSERT INTO pggit.merge_history (
        id, source_branch, target_branch, initiated_by,
        status, conflict_count
    ) VALUES (
        v_merge_id, p_source_branch, v_target_branch, current_user,
        CASE
            WHEN v_conflict_count = 0 AND p_merge_strategy = 'auto' THEN 'completed'
            ELSE 'awaiting_resolution'
        END,
        v_conflict_count
    );

    -- Create merge_conflicts records for each detected conflict
    IF v_conflict_count > 0 THEN
        FOR v_conflict_obj IN
            SELECT *
            FROM jsonb_to_recordset(v_conflicts->'conflicts') AS x(
                "table" text,
                "type" text,
                "source_hash" text,
                "target_hash" text
            )
        LOOP
            INSERT INTO pggit.merge_conflicts (
                merge_id, branch_a, branch_b, conflict_object, conflict_type
            ) VALUES (
                v_merge_id::text,
                p_source_branch,
                v_target_branch,
                v_conflict_obj.table,
                v_conflict_obj.type
            )
            ON CONFLICT DO NOTHING;

            v_conflict_array := array_append(
                v_conflict_array,
                jsonb_build_object(
                    'table', v_conflict_obj.table,
                    'type', v_conflict_obj.type
                )
            );
        END LOOP;
    END IF;

    -- Build result
    v_result := jsonb_build_object(
        'merge_id', v_merge_id,
        'status', CASE
            WHEN v_conflict_count = 0 AND p_merge_strategy = 'auto' THEN 'completed'
            ELSE 'awaiting_resolution'
        END,
        'conflicts', v_conflict_array,
        'tables_merged', 0,
        'conflict_count', v_conflict_count
    );

    RAISE NOTICE 'merge: Merging %s into %s (conflicts: %)',
        p_source_branch, v_target_branch, v_conflict_count;

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
    p_conflict_id integer,
    p_resolution text,
    p_custom_definition text DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_merge_record record;
    v_unresolved_count integer;
BEGIN
    -- Validate merge exists and is awaiting resolution
    SELECT * INTO v_merge_record
    FROM pggit.merge_history
    WHERE id = p_merge_id;

    IF v_merge_record IS NULL THEN
        RAISE EXCEPTION 'Merge % not found', p_merge_id;
    END IF;

    IF v_merge_record.status != 'awaiting_resolution' THEN
        RAISE EXCEPTION 'Merge % is not awaiting resolution (status: %)',
            p_merge_id, v_merge_record.status;
    END IF;

    -- Validate resolution type
    IF p_resolution NOT IN ('ours', 'theirs', 'custom') THEN
        RAISE EXCEPTION 'Invalid resolution type: %. Use ours, theirs, or custom', p_resolution;
    END IF;

    -- Update conflict record with resolution
    UPDATE pggit.merge_conflicts
    SET
        resolution_strategy = p_resolution,
        resolved_value = CASE
            WHEN p_resolution = 'ours' THEN COALESCE(branch_b_value, '"ours"'::jsonb)
            WHEN p_resolution = 'theirs' THEN COALESCE(branch_a_value, '"theirs"'::jsonb)
            WHEN p_resolution = 'custom' THEN to_jsonb(p_custom_definition)
            ELSE '"unresolved"'::jsonb
        END,
        auto_resolved = false,
        resolved_by = current_user,
        resolved_at = now()
    WHERE id = p_conflict_id
      AND merge_id = p_merge_id::text;

    -- Check if all conflicts are now resolved
    SELECT COUNT(*) INTO v_unresolved_count
    FROM pggit.merge_conflicts
    WHERE merge_id = p_merge_id::text
      AND resolved_value IS NULL;

    -- If all resolved, mark merge as completed
    IF v_unresolved_count = 0 THEN
        PERFORM pggit._complete_merge_after_resolution(p_merge_id);
    END IF;

    RAISE NOTICE 'resolve_conflict: Conflict % resolved with %', p_conflict_id, p_resolution;
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
DECLARE
    v_merge_record record;
    v_conflict record;
BEGIN
    -- Get merge record
    SELECT * INTO v_merge_record
    FROM pggit.merge_history
    WHERE id = p_merge_id;

    IF v_merge_record IS NULL THEN
        RAISE EXCEPTION 'Merge % not found', p_merge_id;
    END IF;

    -- Apply all resolved conflicts (for now, just mark them as applied)
    -- In a full implementation, this would apply DDL changes to the target branch
    FOR v_conflict IN
        SELECT * FROM pggit.merge_conflicts
        WHERE merge_id = p_merge_id::text
          AND resolved_value IS NOT NULL
    LOOP
        -- TODO: Apply the resolved conflict to the target schema
        -- This would involve executing DDL statements based on the resolution
        RAISE NOTICE 'Applying resolved conflict: %', v_conflict.conflict_object;
    END LOOP;

    -- Update merge_history status to completed
    UPDATE pggit.merge_history
    SET
        status = 'completed',
        completed_at = now(),
        resolved_conflicts = (
            SELECT COUNT(*) FROM pggit.merge_conflicts
            WHERE merge_id = p_merge_id::text
              AND resolved_value IS NOT NULL
        )
    WHERE id = p_merge_id;

    RAISE NOTICE '_complete_merge_after_resolution: Merge % completed', p_merge_id;
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
DECLARE
    v_merge record;
    v_conflicts jsonb := '[]'::jsonb;
    v_conflict_record record;
BEGIN
    -- Get merge_history record
    SELECT * INTO v_merge
    FROM pggit.merge_history
    WHERE id = p_merge_id;

    IF v_merge IS NULL THEN
        RAISE EXCEPTION 'Merge % not found', p_merge_id;
    END IF;

    -- Get associated conflicts
    FOR v_conflict_record IN
        SELECT id, conflict_object, conflict_type, resolution_strategy
        FROM pggit.merge_conflicts
        WHERE merge_id = p_merge_id::text
    LOOP
        v_conflicts := v_conflicts || jsonb_build_object(
            'conflict_id', v_conflict_record.id,
            'object', v_conflict_record.conflict_object,
            'type', v_conflict_record.conflict_type,
            'resolution', v_conflict_record.resolution_strategy
        );
    END LOOP;

    -- Build status response
    RETURN jsonb_build_object(
        'merge_id', p_merge_id,
        'source_branch', v_merge.source_branch,
        'target_branch', v_merge.target_branch,
        'status', v_merge.status,
        'initiated_by', v_merge.initiated_by,
        'initiated_at', v_merge.initiated_at,
        'completed_at', v_merge.completed_at,
        'conflict_count', v_merge.conflict_count,
        'resolved_conflicts', v_merge.resolved_conflicts,
        'unresolved_conflicts', v_merge.unresolved_conflicts,
        'merge_strategy', v_merge.merge_strategy,
        'conflicts', v_conflicts
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
DECLARE
    v_merge record;
BEGIN
    -- Get merge record
    SELECT * INTO v_merge
    FROM pggit.merge_history
    WHERE id = p_merge_id;

    IF v_merge IS NULL THEN
        RAISE EXCEPTION 'Merge % not found', p_merge_id;
    END IF;

    -- Update merge_history status to 'aborted'
    UPDATE pggit.merge_history
    SET
        status = 'aborted',
        error_message = p_reason,
        completed_at = now()
    WHERE id = p_merge_id;

    -- Clean up any partial changes (conflicts are left as-is for audit)
    -- The conflicts remain in the database for reference

    RAISE NOTICE 'abort_merge: Merge %s aborted - %s', p_merge_id, p_reason;
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
    mc.branch_a as source_branch,
    mc.branch_b as target_branch,
    mc.conflict_object as table_name,
    mc.conflict_type,
    mc.resolved_value as resolution,
    'pending' as merge_status,
    mc.created_at as initiated_at,
    mc.resolved_by as initiated_by
FROM pggit.merge_conflicts mc
WHERE mc.resolved_value IS NULL
ORDER BY mc.created_at DESC, mc.conflict_object;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT ON pggit.merge_history TO PUBLIC;
GRANT SELECT, INSERT ON pggit.merge_conflicts TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.detect_conflicts(text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.merge(text, text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.resolve_conflict(uuid, integer, text, text) TO PUBLIC;
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
