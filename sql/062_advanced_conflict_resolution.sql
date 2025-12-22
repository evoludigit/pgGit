-- pgGit Advanced Conflict Resolution
-- Phase 4: 3-way merge with intelligent heuristics and semantic conflict detection
-- Enables sophisticated conflict resolution for complex schema and data changes

-- =====================================================
-- Conflict Resolution Strategy Infrastructure
-- =====================================================

-- Extended conflict metadata with resolution strategies
CREATE TABLE IF NOT EXISTS pggit.conflict_resolution_strategies (
    strategy_id SERIAL PRIMARY KEY,
    conflict_id INTEGER NOT NULL,
    strategy_type TEXT NOT NULL, -- 'automatic', 'heuristic', 'manual', 'semantic'
    resolution_method TEXT NOT NULL, -- 'theirs', 'ours', 'merged', 'custom'
    heuristic_rule TEXT,
    confidence_score NUMERIC(4, 3) DEFAULT 0.5,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_by TEXT DEFAULT CURRENT_USER,
    result_data JSONB,
    is_successful BOOLEAN DEFAULT false
);

-- Semantic conflict analysis (DDL vs data)
CREATE TABLE IF NOT EXISTS pggit.semantic_conflicts (
    semantic_conflict_id SERIAL PRIMARY KEY,
    conflict_id INTEGER NOT NULL,
    conflict_type TEXT NOT NULL, -- 'type_change', 'constraint_violation', 'schema_mismatch', 'referential_integrity'
    affected_tables TEXT[],
    affected_columns TEXT[],
    severity TEXT DEFAULT 'medium', -- 'critical', 'high', 'medium', 'low'
    resolution_options TEXT[],
    recommended_resolution TEXT,
    analysis_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Resolution recommendation engine state
CREATE TABLE IF NOT EXISTS pggit.conflict_resolution_history (
    resolution_id SERIAL PRIMARY KEY,
    source_branch_id INTEGER,
    target_branch_id INTEGER,
    source_commit_id INTEGER,
    target_commit_id INTEGER,
    base_commit_id INTEGER,
    total_conflicts INT,
    auto_resolved INT,
    manual_resolved INT,
    unresolved INT,
    merge_status TEXT, -- 'success', 'partial', 'failed'
    resolution_log JSONB,
    resolved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_by TEXT DEFAULT CURRENT_USER
);

-- =====================================================
-- Advanced 3-Way Merge Engine
-- =====================================================

-- Perform semantic analysis of conflicts for intelligent resolution
CREATE OR REPLACE FUNCTION pggit.analyze_semantic_conflict(
    p_conflict_id INTEGER,
    p_base_data JSONB,
    p_source_data JSONB,
    p_target_data JSONB
) RETURNS TABLE (
    conflict_type TEXT,
    severity TEXT,
    resolution_recommended TEXT,
    confidence NUMERIC,
    analysis_details JSONB
) AS $$
DECLARE
    v_base_keys TEXT[];
    v_source_keys TEXT[];
    v_target_keys TEXT[];
    v_base_values JSONB;
    v_source_values JSONB;
    v_target_values JSONB;
    v_conflict_type TEXT;
    v_severity TEXT;
    v_resolution TEXT;
    v_confidence NUMERIC := 0.5;
    v_analysis JSONB;
    v_key TEXT;
BEGIN
    -- Extract keys and values
    v_base_keys := ARRAY(SELECT jsonb_object_keys(COALESCE(p_base_data, '{}'::JSONB)));
    v_source_keys := ARRAY(SELECT jsonb_object_keys(COALESCE(p_source_data, '{}'::JSONB)));
    v_target_keys := ARRAY(SELECT jsonb_object_keys(COALESCE(p_target_data, '{}'::JSONB)));

    v_base_values := COALESCE(p_base_data, '{}'::JSONB);
    v_source_values := COALESCE(p_source_data, '{}'::JSONB);
    v_target_values := COALESCE(p_target_data, '{}'::JSONB);

    -- Analyze conflict type
    IF array_length(v_source_keys, 1) IS NULL THEN
        -- Source deleted the record
        v_conflict_type := 'deletion_conflict';
        IF p_target_data IS NOT NULL AND p_target_data != v_base_values THEN
            v_severity := 'high';
            v_resolution := 'keep_target_with_modifications';
            v_confidence := 0.7;
        ELSE
            v_severity := 'medium';
            v_resolution := 'accept_deletion';
            v_confidence := 0.9;
        END IF;
    ELSIF array_length(v_target_keys, 1) IS NULL THEN
        -- Target deleted the record
        v_conflict_type := 'deletion_conflict';
        IF p_source_data IS NOT NULL AND p_source_data != v_base_values THEN
            v_severity := 'high';
            v_resolution := 'keep_source_with_modifications';
            v_confidence := 0.7;
        ELSE
            v_severity := 'medium';
            v_resolution := 'accept_deletion';
            v_confidence := 0.9;
        END IF;
    ELSE
        -- Both sides modified - analyze semantic compatibility
        v_conflict_type := 'modification_conflict';

        -- Check if modifications are complementary (different fields)
        IF NOT EXISTS (
            SELECT 1
            FROM jsonb_each_text(p_source_data) se
            WHERE se.key IN (
                SELECT key
                FROM jsonb_each_text(p_target_data)
                WHERE value != se.value
            )
        ) THEN
            v_conflict_type := 'non_overlapping_modification';
            v_severity := 'low';
            v_resolution := 'merge_changes';
            v_confidence := 0.95;
        ELSE
            -- Overlapping modifications - check if compatible
            v_severity := 'high';

            -- If one side only updated metadata and other updated data, merge
            IF (p_source_data::TEXT LIKE '%updated%' OR p_source_data::TEXT LIKE '%timestamp%') THEN
                v_resolution := 'merge_data_keep_source_metadata';
                v_confidence := 0.8;
            ELSIF (p_target_data::TEXT LIKE '%updated%' OR p_target_data::TEXT LIKE '%timestamp%') THEN
                v_resolution := 'merge_data_keep_target_metadata';
                v_confidence := 0.8;
            ELSE
                v_resolution := 'require_manual_resolution';
                v_confidence := 0.3;
            END IF;
        END IF;
    END IF;

    -- Build analysis details
    v_analysis := jsonb_build_object(
        'base_keys_count', array_length(v_base_keys, 1),
        'source_keys_count', array_length(v_source_keys, 1),
        'target_keys_count', array_length(v_target_keys, 1),
        'conflict_type', v_conflict_type,
        'modification_path', jsonb_build_object(
            'source_changed', p_source_data != v_base_values,
            'target_changed', p_target_data != v_base_values
        )
    );

    RETURN QUERY SELECT
        v_conflict_type,
        v_severity,
        v_resolution,
        v_confidence,
        v_analysis;
END;
$$ LANGUAGE plpgsql;

-- Attempt automatic conflict resolution using heuristics
CREATE OR REPLACE FUNCTION pggit.attempt_auto_resolution(
    p_conflict_id INTEGER,
    p_resolution_strategy TEXT DEFAULT 'heuristic'
) RETURNS TABLE (
    resolved BOOLEAN,
    resolution_method TEXT,
    merged_data JSONB,
    confidence NUMERIC,
    resolution_details TEXT
) AS $$
DECLARE
    v_conflict RECORD;
    v_analysis RECORD;
    v_base_data JSONB;
    v_source_data JSONB;
    v_target_data JSONB;
    v_merged_data JSONB;
    v_resolved BOOLEAN := false;
    v_method TEXT := 'none';
    v_confidence NUMERIC := 0.0;
    v_details TEXT := 'No automatic resolution found';
BEGIN
    -- Get conflict details
    SELECT
        dc.source_data as base_data,
        dc.source_data as source_data,
        dc.target_data as target_data
    INTO
        v_base_data,
        v_source_data,
        v_target_data
    FROM pggit.data_conflicts dc
    WHERE dc.conflict_id = p_conflict_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'not_found', NULL::JSONB, 0.0, 'Conflict not found';
        RETURN;
    END IF;

    -- Perform semantic analysis
    FOR v_analysis IN
        SELECT * FROM pggit.analyze_semantic_conflict(
            p_conflict_id,
            v_base_data,
            v_source_data,
            v_target_data
        )
    LOOP
        -- Apply heuristics based on conflict type
        CASE v_analysis.conflict_type
            WHEN 'non_overlapping_modification' THEN
                -- Merge changes from both sides
                v_merged_data := v_source_data || v_target_data;
                v_resolved := true;
                v_method := 'automatic_merge';
                v_confidence := v_analysis.confidence;
                v_details := 'Non-overlapping changes merged automatically';

            WHEN 'deletion_conflict' THEN
                -- Keep the non-deleted version
                IF v_source_data IS NULL THEN
                    v_merged_data := v_target_data;
                    v_method := 'keep_target';
                ELSE
                    v_merged_data := v_source_data;
                    v_method := 'keep_source';
                END IF;
                v_resolved := true;
                v_confidence := v_analysis.confidence;
                v_details := 'Deletion conflict resolved: kept non-deleted version';

            WHEN 'modification_conflict' THEN
                -- Check if resolution strategy is safe
                IF v_analysis.resolution_recommended LIKE '%merge%' THEN
                    v_merged_data := v_source_data || v_target_data;
                    v_method := 'metadata_merge';
                    v_resolved := true;
                    v_confidence := v_analysis.confidence;
                    v_details := 'Metadata conflict resolved by merging';
                END IF;

            ELSE
                v_details := 'Unable to automatically resolve: ' || v_analysis.conflict_type;
        END CASE;
    END LOOP;

    RETURN QUERY SELECT
        v_resolved,
        v_method,
        v_merged_data,
        v_confidence,
        v_details;
END;
$$ LANGUAGE plpgsql;

-- Three-way merge with intelligent heuristic-based resolution
CREATE OR REPLACE FUNCTION pggit.three_way_merge_advanced(
    p_source_branch_id INTEGER,
    p_target_branch_id INTEGER,
    p_base_commit_id INTEGER,
    p_auto_resolve BOOLEAN DEFAULT true
) RETURNS TABLE (
    merge_success BOOLEAN,
    total_conflicts INT,
    auto_resolved INT,
    manual_required INT,
    merge_result JSONB,
    resolution_history TEXT
) AS $$
DECLARE
    v_conflicts RECORD;
    v_auto_res RECORD;
    v_total_conflicts INT := 0;
    v_auto_resolved INT := 0;
    v_manual_required INT := 0;
    v_merge_result JSONB := '{}'::JSONB;
    v_history TEXT := '';
    v_resolution_log JSONB := '[]'::JSONB;
    v_merge_success BOOLEAN := true;
    v_source_commit_id INT;
    v_target_commit_id INT;
BEGIN
    -- Get the latest commits from each branch
    SELECT commit_id INTO v_source_commit_id
    FROM pggit.commits
    WHERE branch_id = p_source_branch_id
    ORDER BY created_at DESC
    LIMIT 1;

    SELECT commit_id INTO v_target_commit_id
    FROM pggit.commits
    WHERE branch_id = p_target_branch_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Find all conflicts
    FOR v_conflicts IN
        SELECT
            conflict_id,
            table_name,
            primary_key_value,
            source_data,
            target_data
        FROM pggit.data_conflicts
        WHERE target_branch = p_target_branch_id
        AND resolved_at IS NULL
    LOOP
        v_total_conflicts := v_total_conflicts + 1;

        -- Attempt automatic resolution
        IF p_auto_resolve THEN
            FOR v_auto_res IN
                SELECT * FROM pggit.attempt_auto_resolution(v_conflicts.conflict_id)
            LOOP
                IF v_auto_res.resolved THEN
                    v_auto_resolved := v_auto_resolved + 1;

                    -- Update conflict with resolution
                    UPDATE pggit.data_conflicts
                    SET
                        resolved_at = CURRENT_TIMESTAMP,
                        resolution = v_auto_res.resolution_method,
                        resolved_data = v_auto_res.merged_data
                    WHERE conflict_id = v_conflicts.conflict_id;

                    -- Log resolution
                    v_resolution_log := v_resolution_log || jsonb_build_object(
                        'conflict_id', v_conflicts.conflict_id,
                        'method', v_auto_res.resolution_method,
                        'confidence', v_auto_res.confidence,
                        'details', v_auto_res.resolution_details
                    );

                    v_history := v_history || format(
                        'Auto-resolved conflict %s: %s (confidence: %s)%n',
                        v_conflicts.id,
                        v_auto_res.resolution_method,
                        v_auto_res.confidence
                    );
                ELSE
                    v_manual_required := v_manual_required + 1;
                    v_merge_success := false;
                    v_history := v_history || format(
                        'Manual resolution required for conflict %s: %s%n',
                        v_conflicts.id,
                        v_auto_res.resolution_details
                    );
                END IF;
            END LOOP;
        ELSE
            v_manual_required := v_total_conflicts;
            v_merge_success := false;
        END IF;
    END LOOP;

    -- Record merge history
    INSERT INTO pggit.conflict_resolution_history (
        source_branch_id,
        target_branch_id,
        source_commit_id,
        target_commit_id,
        base_commit_id,
        total_conflicts,
        auto_resolved,
        manual_resolved,
        unresolved,
        merge_status,
        resolution_log
    ) VALUES (
        p_source_branch_id,
        p_target_branch_id,
        v_source_commit_id,
        v_target_commit_id,
        p_base_commit_id,
        v_total_conflicts,
        v_auto_resolved,
        0,
        v_manual_required,
        CASE WHEN v_merge_success THEN 'success' ELSE 'partial' END,
        v_resolution_log
    );

    RETURN QUERY SELECT
        v_merge_success,
        v_total_conflicts,
        v_auto_resolved,
        v_manual_required,
        jsonb_build_object(
            'auto_resolved', v_auto_resolved,
            'manual_required', v_manual_required,
            'total', v_total_conflicts
        ),
        v_history;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Conflict Pattern Recognition
-- =====================================================

-- Identify common conflict patterns to predict future conflicts
CREATE OR REPLACE FUNCTION pggit.identify_conflict_patterns(
    p_lookback_days INTEGER DEFAULT 30
) RETURNS TABLE (
    pattern_id INT,
    affected_table TEXT,
    affected_column TEXT,
    conflict_count INT,
    resolution_success_rate NUMERIC,
    common_causes TEXT[],
    recommendation TEXT
) AS $$
DECLARE
    v_pattern_record RECORD;
    v_cutoff_date TIMESTAMP;
BEGIN
    v_cutoff_date := CURRENT_TIMESTAMP - (p_lookback_days || ' days')::INTERVAL;

    -- Identify patterns in conflict data
    FOR v_pattern_record IN
        WITH conflict_stats AS (
            SELECT
                dc.table_schema,
                dc.table_name,
                COUNT(*) as total_conflicts,
                COUNT(CASE WHEN dc.resolved_at IS NOT NULL THEN 1 END) as resolved_count,
                CASE
                    WHEN COUNT(*) > 0 THEN
                        (COUNT(CASE WHEN dc.resolved_at IS NOT NULL THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC)
                    ELSE 0
                END as success_rate,
                jsonb_agg(DISTINCT dc.conflict_type) as conflict_types
            FROM pggit.data_conflicts dc
            WHERE dc.created_at >= v_cutoff_date
            GROUP BY dc.table_schema, dc.table_name
            HAVING COUNT(*) > 1
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY total_conflicts DESC) as pattern_num,
            table_schema || '.' || table_name as table_name,
            NULL::TEXT as column_name,
            total_conflicts,
            success_rate,
            conflict_types
        FROM conflict_stats
        WHERE success_rate < 0.8
    LOOP
        -- Return pattern with recommendation
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Suggest conflict prevention strategies
CREATE OR REPLACE FUNCTION pggit.suggest_conflict_prevention(
    p_table_schema TEXT,
    p_table_name TEXT
) RETURNS TABLE (
    prevention_strategy TEXT,
    implementation_effort TEXT,
    expected_impact NUMERIC,
    details TEXT
) AS $$
BEGIN
    -- Suggest strategies based on table characteristics
    RETURN QUERY
    SELECT
        'Add optimistic locking with version columns'::TEXT,
        'low'::TEXT,
        0.85::NUMERIC,
        'Adds version column to detect concurrent modifications'::TEXT
    UNION ALL
    SELECT
        'Implement field-level access control'::TEXT,
        'medium'::TEXT,
        0.90::NUMERIC,
        'Prevents conflicting writes to critical fields'::TEXT
    UNION ALL
    SELECT
        'Use structured branch naming conventions'::TEXT,
        'low'::TEXT,
        0.70::NUMERIC,
        'Clarifies branch purpose to reduce accidental conflicts'::TEXT
    UNION ALL
    SELECT
        'Establish merge review process'::TEXT,
        'medium'::TEXT,
        0.75::NUMERIC,
        'Human review catches semantic conflicts before merge'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Conflict Resolution Validation
-- =====================================================

-- Validate that a proposed resolution maintains data integrity
CREATE OR REPLACE FUNCTION pggit.validate_resolution(
    p_conflict_id INTEGER,
    p_proposed_resolution JSONB
) RETURNS TABLE (
    is_valid BOOLEAN,
    validation_errors TEXT[],
    warnings TEXT[],
    integrity_score NUMERIC
) AS $$
DECLARE
    v_conflict RECORD;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_warnings TEXT[] := ARRAY[]::TEXT[];
    v_score NUMERIC := 1.0;
    v_error TEXT;
BEGIN
    -- Get conflict details
    SELECT * INTO v_conflict
    FROM pggit.data_conflicts
    WHERE conflict_id = p_conflict_id;

    IF NOT FOUND THEN
        v_errors := v_errors || 'Conflict not found';
        RETURN QUERY SELECT false, v_errors, v_warnings, 0.0::NUMERIC;
        RETURN;
    END IF;

    -- Validate proposed resolution
    -- Check 1: Proposed resolution has required fields
    IF p_proposed_resolution IS NULL THEN
        v_errors := v_errors || 'Proposed resolution cannot be null';
        v_score := v_score - 0.5;
    END IF;

    -- Check 2: Not just accepting one side without review of changes
    IF p_proposed_resolution = v_conflict.source_data THEN
        v_warnings := v_warnings || 'Resolution matches source: ensure target changes were reviewed';
        v_score := v_score - 0.1;
    ELSIF p_proposed_resolution = v_conflict.target_data THEN
        v_warnings := v_warnings || 'Resolution matches target: ensure source changes were reviewed';
        v_score := v_score - 0.1;
    END IF;

    -- Check 3: Proposed resolution is non-empty (not a deletion without approval)
    IF p_proposed_resolution = '{}'::JSONB AND v_conflict.source_data IS NOT NULL THEN
        v_warnings := v_warnings || 'Warning: proposed resolution is empty; this will delete data';
        v_score := v_score - 0.2;
    END IF;

    RETURN QUERY SELECT
        array_length(v_errors, 1) IS NULL,
        CASE WHEN array_length(v_errors, 1) > 0 THEN v_errors ELSE NULL::TEXT[] END,
        CASE WHEN array_length(v_warnings, 1) > 0 THEN v_warnings ELSE NULL::TEXT[] END,
        GREATEST(0.0::NUMERIC, v_score);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Indexes for Conflict Resolution
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_conflict_strategies_conflict
ON pggit.conflict_resolution_strategies(conflict_id, confidence_score DESC);

CREATE INDEX IF NOT EXISTS idx_semantic_conflicts_severity
ON pggit.semantic_conflicts(conflict_id, severity);

CREATE INDEX IF NOT EXISTS idx_resolution_history_branches
ON pggit.conflict_resolution_history(source_branch_id, target_branch_id);

CREATE INDEX IF NOT EXISTS idx_resolution_history_status
ON pggit.conflict_resolution_history(merge_status, resolved_at DESC);

-- =====================================================
-- Grant Permissions
-- =====================================================

GRANT SELECT, INSERT, UPDATE ON pggit.conflict_resolution_strategies TO PUBLIC;
GRANT SELECT, INSERT ON pggit.semantic_conflicts TO PUBLIC;
GRANT SELECT, INSERT ON pggit.conflict_resolution_history TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;
