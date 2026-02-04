-- pgGit v0.2 Phase 7: Advanced Merge Operations
-- Three-way merge algorithm, semantic conflict detection, automatic heuristics
-- Author: stephengibson12
-- Phase: v0.2 Extended (Advanced Conflict Resolution)

-- ============================================================================
-- ENHANCE MERGE_CONFLICTS TABLE FOR ADVANCED FEATURES
-- ============================================================================
-- Add columns for semantic analysis and automatic resolution

ALTER TABLE IF EXISTS pggit.merge_conflicts
ADD COLUMN IF NOT EXISTS conflict_severity text DEFAULT 'WARNING'
CHECK (conflict_severity IN ('CRITICAL', 'WARNING', 'INFO'));

ALTER TABLE IF EXISTS pggit.merge_conflicts
ADD COLUMN IF NOT EXISTS is_auto_resolvable boolean DEFAULT false;

ALTER TABLE IF EXISTS pggit.merge_conflicts
ADD COLUMN IF NOT EXISTS auto_resolution_suggestion text DEFAULT NULL;

ALTER TABLE IF EXISTS pggit.merge_conflicts
ADD COLUMN IF NOT EXISTS conflict_reason text DEFAULT NULL;

-- ============================================================================
-- FUNCTION: pggit.classify_conflict_severity()
-- ============================================================================
-- Determine severity level based on conflict type and schema changes
-- CRITICAL: Breaks data integrity (FK violations, constraint incompatibility)
-- WARNING: May cause issues (column modifications, type changes)
-- INFO: Informational only (index changes, comments)

CREATE OR REPLACE FUNCTION pggit.classify_conflict_severity(
    p_conflict_type text,
    p_source_def text,
    p_target_def text
)
RETURNS text AS $$
BEGIN
    -- CRITICAL: Foreign key, primary key, unique constraint violations
    IF p_conflict_type IN ('constraint_modified', 'constraint_removed') THEN
        IF p_source_def LIKE '%FOREIGN KEY%' OR
           p_source_def LIKE '%PRIMARY KEY%' OR
           p_source_def LIKE '%UNIQUE%' THEN
            RETURN 'CRITICAL';
        END IF;
    END IF;

    -- WARNING: Column and table modifications (may affect data)
    IF p_conflict_type IN ('column_modified', 'table_modified', 'constraint_modified') THEN
        RETURN 'WARNING';
    END IF;

    -- WARNING: Table additions/removals (structural impact)
    IF p_conflict_type IN ('table_added', 'table_removed') THEN
        RETURN 'WARNING';
    END IF;

    -- INFO: Column additions (usually safe), index changes (minor impact)
    IF p_conflict_type IN ('column_added', 'index_added', 'index_removed') THEN
        RETURN 'INFO';
    END IF;

    -- Column removal is WARNING (potential data loss)
    IF p_conflict_type = 'column_removed' THEN
        RETURN 'WARNING';
    END IF;

    -- Default to WARNING for unknown types
    RETURN 'WARNING';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: pggit.suggest_auto_resolution()
-- ============================================================================
-- Suggest automatic resolution for conflicts that are safe to auto-merge
-- Returns 'ours', 'theirs', or NULL (manual required)

CREATE OR REPLACE FUNCTION pggit.suggest_auto_resolution(
    p_conflict_type text,
    p_severity text,
    p_source_def text,
    p_target_def text
)
RETURNS text AS $$
BEGIN
    -- Auto-resolve INFO level conflicts with 'theirs' (accept source changes)
    IF p_severity = 'INFO' THEN
        IF p_conflict_type IN ('index_added', 'column_added') THEN
            RETURN 'theirs'; -- Accept source additions
        ELSIF p_conflict_type IN ('index_removed') THEN
            RETURN 'theirs'; -- Accept source removals
        END IF;
    END IF;

    -- Column additions are typically safe (non-breaking)
    IF p_conflict_type = 'column_added' AND p_severity IN ('INFO', 'WARNING') THEN
        -- Check if column has NOT NULL without default (breaking change)
        IF p_source_def NOT LIKE '%NOT NULL%' OR p_source_def LIKE '%DEFAULT%' THEN
            RETURN 'theirs'; -- Safe to add
        END IF;
    END IF;

    -- No auto-resolution suggestion (manual review required)
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: pggit.detect_semantic_conflicts()
-- ============================================================================
-- Identify semantic conflicts beyond syntactic differences
-- Detects renamed objects, compatible changes, and data-dependent conflicts

CREATE OR REPLACE FUNCTION pggit.detect_semantic_conflicts(
    p_source_branch text,
    p_target_branch text
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{"semantic_conflicts": [], "compatible_changes": [], "safe_auto_merges": []}'::jsonb;
    v_source_id integer;
    v_target_id integer;
    v_objects record;
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

    -- Detect objects that appear to be renames (same type, similar name, both exist)
    FOR v_objects IN
        SELECT
            s.object_name as source_name,
            t.object_name as target_name,
            s.object_type,
            CASE
                WHEN levenshtein(s.object_name, t.object_name) <= 3 THEN 'likely_rename'
                ELSE 'different_objects'
            END as relationship
        FROM pggit.objects s
        CROSS JOIN pggit.objects t
        WHERE s.branch_id = v_source_id
          AND t.branch_id = v_target_id
          AND s.object_type = t.object_type
          AND s.object_name != t.object_name
          AND levenshtein(s.object_name, t.object_name) <= 3
    LOOP
        v_result := jsonb_set(
            v_result,
            '{semantic_conflicts}',
            v_result->'semantic_conflicts' || jsonb_build_object(
                'source_name', v_objects.source_name,
                'target_name', v_objects.target_name,
                'type', v_objects.object_type,
                'relationship', v_objects.relationship
            )
        );
    END LOOP;

    RAISE NOTICE 'detect_semantic_conflicts: Found % semantic conflicts',
        jsonb_array_length(v_result->'semantic_conflicts');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.three_way_merge()
-- ============================================================================
-- Implement three-way merge algorithm to reduce false conflicts
-- Compares: base (common ancestor), source, target
-- Only flags conflicts where both sides changed differently

CREATE OR REPLACE FUNCTION pggit.three_way_merge(
    p_source_branch text,
    p_target_branch text,
    p_base_branch text DEFAULT 'main'
)
RETURNS jsonb AS $$
DECLARE
    v_base_id integer;
    v_source_id integer;
    v_target_id integer;
    v_result jsonb := '{"conflicts": [], "auto_merges": [], "conflict_count": 0}'::jsonb;
    v_object record;
    v_true_conflict boolean;
    v_base_hash text;
    v_source_hash text;
    v_target_hash text;
    v_conflict_type text;
BEGIN
    -- Get branch IDs
    SELECT id INTO v_base_id FROM pggit.branches WHERE name = p_base_branch;
    SELECT id INTO v_source_id FROM pggit.branches WHERE name = p_source_branch;
    SELECT id INTO v_target_id FROM pggit.branches WHERE name = p_target_branch;

    -- Validate branches exist
    IF v_base_id IS NULL THEN
        RAISE EXCEPTION 'Base branch % not found', p_base_branch;
    END IF;
    IF v_source_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;
    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'Target branch % not found', p_target_branch;
    END IF;

    -- Three-way merge algorithm:
    -- Only flag conflict if both sides changed from base
    FOR v_object IN
        SELECT
            COALESCE(b.object_name, s.object_name, t.object_name) as object_name,
            COALESCE(b.object_type, s.object_type, t.object_type) as object_type,
            b.content_hash as base_hash,
            s.content_hash as source_hash,
            t.content_hash as target_hash
        FROM (
            SELECT * FROM pggit.objects WHERE branch_id = v_base_id
        ) b
        FULL OUTER JOIN (
            SELECT * FROM pggit.objects WHERE branch_id = v_source_id
        ) s ON b.object_type = s.object_type
            AND b.schema_name = s.schema_name
            AND b.object_name = s.object_name
        FULL OUTER JOIN (
            SELECT * FROM pggit.objects WHERE branch_id = v_target_id
        ) t ON COALESCE(b.object_type, s.object_type) = t.object_type
            AND COALESCE(b.schema_name, s.schema_name) = t.schema_name
            AND COALESCE(b.object_name, s.object_name) = t.object_name
    LOOP
        v_true_conflict := false;
        v_base_hash := v_object.base_hash;
        v_source_hash := v_object.source_hash;
        v_target_hash := v_object.target_hash;

        -- Only a true conflict if both source and target changed from base
        IF (v_source_hash IS NOT NULL AND v_target_hash IS NOT NULL) THEN
            -- Both sides exist - check if they differ from base
            IF v_base_hash IS NULL THEN
                -- Both added (only conflict if they differ)
                v_true_conflict := (v_source_hash IS DISTINCT FROM v_target_hash);
                IF v_true_conflict THEN
                    v_conflict_type := 'both_added_different';
                ELSE
                    v_conflict_type := 'both_added_same'; -- Auto-merge
                END IF;
            ELSIF v_source_hash IS DISTINCT FROM v_base_hash AND
                  v_target_hash IS DISTINCT FROM v_base_hash THEN
                -- Both changed - only conflict if changed differently
                v_true_conflict := (v_source_hash IS DISTINCT FROM v_target_hash);
                IF v_true_conflict THEN
                    v_conflict_type := 'both_modified_different';
                ELSE
                    v_conflict_type := 'both_modified_same'; -- Auto-merge
                END IF;
            END IF;
        ELSIF (v_source_hash IS NOT NULL AND v_target_hash IS NULL) THEN
            -- Only source changed - no conflict (source added/modified, target didn't change)
            v_true_conflict := false;
            v_conflict_type := 'source_only_changed'; -- Auto-merge
        ELSIF (v_target_hash IS NOT NULL AND v_source_hash IS NULL) THEN
            -- Only target changed - no conflict (target added/modified, source didn't change)
            v_true_conflict := false;
            v_conflict_type := 'target_only_changed'; -- Keep target
        ELSIF (v_source_hash IS NULL AND v_target_hash IS NULL) THEN
            -- Both removed - no conflict
            v_true_conflict := false;
            v_conflict_type := 'both_removed'; -- Auto-merge
        END IF;

        -- Record result
        IF v_true_conflict THEN
            v_result := jsonb_set(
                v_result,
                '{conflicts}',
                v_result->'conflicts' || jsonb_build_object(
                    'object_name', v_object.object_name,
                    'type', v_conflict_type,
                    'base_hash', v_base_hash,
                    'source_hash', v_source_hash,
                    'target_hash', v_target_hash
                )
            );
        ELSE
            v_result := jsonb_set(
                v_result,
                '{auto_merges}',
                v_result->'auto_merges' || jsonb_build_object(
                    'object_name', v_object.object_name,
                    'type', v_conflict_type,
                    'resolution', CASE
                        WHEN v_conflict_type LIKE 'both_added%' THEN 'theirs'
                        WHEN v_conflict_type LIKE 'source_only%' THEN 'theirs'
                        WHEN v_conflict_type LIKE 'target_only%' THEN 'ours'
                        ELSE 'theirs'
                    END
                )
            );
        END IF;
    END LOOP;

    -- Update conflict count
    v_result := jsonb_set(
        v_result,
        '{conflict_count}',
        to_jsonb((jsonb_array_length(v_result->'conflicts'))::integer)
    );

    RAISE NOTICE 'three_way_merge: Found % true conflicts, % auto-merges',
        v_result->>'conflict_count',
        jsonb_array_length(v_result->'auto_merges');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.auto_resolve_safe_conflicts()
-- ============================================================================
-- Automatically resolve conflicts marked as safe to auto-merge

CREATE OR REPLACE FUNCTION pggit.auto_resolve_safe_conflicts(
    p_merge_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_resolved integer := 0;
    v_failed integer := 0;
    v_conflict record;
    v_result jsonb := '{"resolved": 0, "failed": 0, "details": []}'::jsonb;
BEGIN
    -- Find all resolvable conflicts
    FOR v_conflict IN
        SELECT id, conflict_object, is_auto_resolvable, auto_resolution_suggestion
        FROM pggit.merge_conflicts
        WHERE merge_id = p_merge_id::text
          AND is_auto_resolvable = true
          AND resolution_strategy IS NULL
    LOOP
        BEGIN
            -- Apply auto-resolution
            UPDATE pggit.merge_conflicts
            SET resolution_strategy = v_conflict.auto_resolution_suggestion,
                resolved_at = NOW(),
                resolved_by = 'auto_merge'
            WHERE id = v_conflict.id;

            v_resolved := v_resolved + 1;

            v_result := jsonb_set(
                v_result,
                '{details}',
                v_result->'details' || jsonb_build_object(
                    'object', v_conflict.conflict_object,
                    'resolution', v_conflict.auto_resolution_suggestion,
                    'status', 'success'
                )
            );
        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
            v_result := jsonb_set(
                v_result,
                '{details}',
                v_result->'details' || jsonb_build_object(
                    'object', v_conflict.conflict_object,
                    'status', 'failed',
                    'error', SQLERRM
                )
            );
        END;
    END LOOP;

    v_result := jsonb_set(v_result, '{resolved}', to_jsonb(v_resolved));
    v_result := jsonb_set(v_result, '{failed}', to_jsonb(v_failed));

    RAISE NOTICE 'auto_resolve_safe_conflicts: Resolved %, Failed %', v_resolved, v_failed;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.merge_with_heuristics()
-- ============================================================================
-- Enhanced merge that uses three-way algorithm and automatic heuristics

CREATE OR REPLACE FUNCTION pggit.merge_with_heuristics(
    p_source_branch text,
    p_target_branch text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_merge_result jsonb;
    v_merge_id uuid;
    v_three_way jsonb;
    v_auto_resolved jsonb;
    v_three_way_conflicts jsonb;
    v_conflict jsonb;
BEGIN
    -- If target is NULL, use current branch
    IF p_target_branch IS NULL THEN
        SELECT current_branch INTO p_target_branch FROM pggit.branches LIMIT 1;
    END IF;

    -- Start merge operation
    INSERT INTO pggit.merge_history (source_branch, target_branch, status, merge_strategy)
    VALUES (p_source_branch, p_target_branch, 'in_progress', 'heuristic')
    RETURNING id INTO v_merge_id;

    -- Run three-way merge algorithm
    v_three_way := pggit.three_way_merge(p_source_branch, p_target_branch, 'main');

    -- Apply auto-resolutions from three-way algorithm
    IF jsonb_array_length(v_three_way->'auto_merges') > 0 THEN
        FOR v_conflict IN
            SELECT * FROM jsonb_array_elements(v_three_way->'auto_merges')
        LOOP
            INSERT INTO pggit.merge_conflicts (
                merge_id, branch_a, branch_b, conflict_object, conflict_type,
                is_auto_resolvable, auto_resolution_suggestion, resolution_strategy
            ) VALUES (
                v_merge_id,
                p_source_branch,
                p_target_branch,
                v_conflict->>'object_name',
                v_conflict->>'type',
                true,
                v_conflict->>'resolution',
                v_conflict->>'resolution'
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    -- Record true conflicts with severity and suggestions
    IF jsonb_array_length(v_three_way->'conflicts') > 0 THEN
        FOR v_conflict IN
            SELECT * FROM jsonb_array_elements(v_three_way->'conflicts')
        LOOP
            INSERT INTO pggit.merge_conflicts (
                merge_id, branch_a, branch_b, conflict_object, conflict_type,
                conflict_severity, is_auto_resolvable,
                auto_resolution_suggestion
            ) VALUES (
                v_merge_id,
                p_source_branch,
                p_target_branch,
                v_conflict->>'object_name',
                v_conflict->>'type',
                pggit.classify_conflict_severity(
                    v_conflict->>'type',
                    v_conflict->>'source_hash',
                    v_conflict->>'target_hash'
                ),
                pggit.suggest_auto_resolution(
                    v_conflict->>'type',
                    pggit.classify_conflict_severity(
                        v_conflict->>'type',
                        v_conflict->>'source_hash',
                        v_conflict->>'target_hash'
                    ),
                    v_conflict->>'source_hash',
                    v_conflict->>'target_hash'
                ) IS NOT NULL,
                pggit.suggest_auto_resolution(
                    v_conflict->>'type',
                    pggit.classify_conflict_severity(
                        v_conflict->>'type',
                        v_conflict->>'source_hash',
                        v_conflict->>'target_hash'
                    ),
                    v_conflict->>'source_hash',
                    v_conflict->>'target_hash'
                )
            ) ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    -- Auto-resolve safe conflicts
    v_auto_resolved := pggit.auto_resolve_safe_conflicts(v_merge_id);

    -- Update merge status
    UPDATE pggit.merge_history
    SET conflict_count = (SELECT COUNT(*) FROM pggit.merge_conflicts WHERE merge_id = v_merge_id),
        resolved_conflicts = (SELECT COUNT(*) FROM pggit.merge_conflicts WHERE merge_id = v_merge_id AND resolution_strategy IS NOT NULL),
        unresolved_conflicts = (SELECT COUNT(*) FROM pggit.merge_conflicts WHERE merge_id = v_merge_id AND resolution_strategy IS NULL),
        status = CASE
            WHEN (SELECT COUNT(*) FROM pggit.merge_conflicts WHERE merge_id = v_merge_id AND resolution_strategy IS NULL) = 0
            THEN 'completed'
            ELSE 'awaiting_resolution'
        END
    WHERE id = v_merge_id;

    -- Build result
    SELECT row_to_json(row) INTO v_merge_result FROM (
        SELECT
            v_merge_id as merge_id,
            (SELECT status FROM pggit.merge_history WHERE id = v_merge_id) as status,
            (SELECT conflict_count FROM pggit.merge_history WHERE id = v_merge_id) as conflict_count,
            (SELECT resolved_conflicts FROM pggit.merge_history WHERE id = v_merge_id) as resolved_conflicts,
            (SELECT unresolved_conflicts FROM pggit.merge_history WHERE id = v_merge_id) as unresolved_conflicts,
            v_auto_resolved->>'resolved' as auto_resolved_count,
            (v_auto_resolved->>'failed')::integer as auto_resolution_failures
    ) row;

    RAISE NOTICE 'merge_with_heuristics: Merge % completed with % auto-resolutions',
        v_merge_id,
        v_auto_resolved->>'resolved';

    RETURN v_merge_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CREATE FUNCTION: pggit.get_merge_metrics()
-- ============================================================================
-- Return detailed metrics about merge operations

CREATE OR REPLACE FUNCTION pggit.get_merge_metrics(
    p_time_range interval DEFAULT '7 days'::interval
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'total_merges', COUNT(*),
        'completed', COUNT(*) FILTER (WHERE status = 'completed'),
        'failed', COUNT(*) FILTER (WHERE status = 'failed'),
        'awaiting_resolution', COUNT(*) FILTER (WHERE status = 'awaiting_resolution'),
        'avg_conflicts_per_merge', ROUND(AVG(conflict_count)::numeric, 2),
        'total_conflicts', SUM(conflict_count),
        'total_resolved', SUM(resolved_conflicts),
        'conflict_types', (
            SELECT jsonb_object_agg(conflict_type, cnt)
            FROM (
                SELECT conflict_type, COUNT(*) as cnt
                FROM pggit.merge_conflicts
                WHERE merge_id IN (
                    SELECT id FROM pggit.merge_history
                    WHERE initiated_at > NOW() - p_time_range
                )
                GROUP BY conflict_type
            ) subq
        ),
        'avg_resolution_time_minutes', ROUND(
            AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)) / 60)::numeric,
            2
        )
    )
    INTO v_result
    FROM pggit.merge_history
    WHERE initiated_at > NOW() - p_time_range;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- INDEXES FOR PERFORMANCE

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_severity
    ON pggit.merge_conflicts(conflict_severity)
    WHERE is_auto_resolvable = true;

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_auto_resolvable
    ON pggit.merge_conflicts(merge_id, is_auto_resolvable)
    WHERE is_auto_resolvable = true AND resolution_strategy IS NULL;

-- VIEWS FOR REPORTING

CREATE OR REPLACE VIEW pggit.v_merge_summary AS
SELECT
    mh.id,
    mh.source_branch,
    mh.target_branch,
    mh.status,
    mh.conflict_count,
    mh.resolved_conflicts,
    mh.unresolved_conflicts,
    mh.merge_strategy,
    ROUND(EXTRACT(EPOCH FROM (mh.completed_at - mh.initiated_at)) / 1000, 2) as duration_ms,
    mh.initiated_at,
    mh.completed_at
FROM pggit.merge_history mh
ORDER BY mh.initiated_at DESC;

CREATE OR REPLACE VIEW pggit.v_conflict_summary AS
SELECT
    COUNT(*) as total_conflicts,
    SUM(CASE WHEN conflict_severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical_count,
    SUM(CASE WHEN conflict_severity = 'WARNING' THEN 1 ELSE 0 END) as warning_count,
    SUM(CASE WHEN conflict_severity = 'INFO' THEN 1 ELSE 0 END) as info_count,
    SUM(CASE WHEN is_auto_resolvable = true THEN 1 ELSE 0 END) as auto_resolvable_count,
    SUM(CASE WHEN resolution_strategy IS NOT NULL THEN 1 ELSE 0 END) as resolved_count
FROM pggit.merge_conflicts;
