-- pgGit v0.3 Phase 9: Schema Diffing Foundation
-- Detailed schema comparison, diff detection, and migration planning
-- Author: stephengibson12

-- ============================================================================
-- STORAGE TABLES FOR SCHEMA ANALYSIS
-- ============================================================================

-- Table: schema_snapshots (already exists from prior work)
-- No need to recreate - using existing table

-- Table: schema_diffs (recreate with proper structure for Phase 9)
-- Drop existing if it has wrong structure
DROP TABLE IF EXISTS pggit.schema_diffs CASCADE;

CREATE TABLE pggit.schema_diffs (
    id bigserial PRIMARY KEY,
    branch_a text NOT NULL,
    branch_b text NOT NULL,
    diff_json jsonb NOT NULL,
    added_count integer DEFAULT 0,
    removed_count integer DEFAULT 0,
    modified_count integer DEFAULT 0,
    breaking_changes integer DEFAULT 0,
    compatible_changes integer DEFAULT 0,
    risky_changes integer DEFAULT 0,
    created_at timestamp NOT NULL DEFAULT NOW()
);

-- Table: schema_changes
-- Stores: Individual change records from diffs
CREATE TABLE IF NOT EXISTS pggit.schema_changes (
    id bigserial PRIMARY KEY,
    diff_id bigint NOT NULL REFERENCES pggit.schema_diffs(id),
    object_type text NOT NULL,
    object_name text NOT NULL,
    schema_name text DEFAULT 'public',
    change_type text NOT NULL,
    category text NOT NULL CHECK(category IN ('BREAKING', 'COMPATIBLE', 'RISKY', 'OPTIONAL')),
    old_definition text,
    new_definition text,
    impact_description text,
    created_at timestamp NOT NULL DEFAULT NOW()
);

-- Table: migration_plans (already exists from prior work)
-- No need to recreate - using existing table

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_schema_snapshots_branch_date
    ON pggit.schema_snapshots(branch_id, snapshot_date DESC);

CREATE INDEX IF NOT EXISTS idx_schema_diffs_branches
    ON pggit.schema_diffs(branch_a, branch_b, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schema_changes_diff_category
    ON pggit.schema_changes(diff_id, category);

CREATE INDEX IF NOT EXISTS idx_migration_plans_branches
    ON pggit.migration_plans(source_branch, target_branch, created_at DESC);

-- ============================================================================
-- FUNCTION: pggit.get_schema_snapshot()
-- ============================================================================
-- Generate a complete schema representation for a branch
-- Captures: All objects, properties, and structure at a point in time

CREATE OR REPLACE FUNCTION pggit.get_schema_snapshot(
    p_branch_name text
)
RETURNS jsonb AS $$
DECLARE
    v_branch_id integer;
    v_snapshot jsonb;
    v_object_count integer;
    v_object record;
BEGIN
    -- Get branch ID
    SELECT id INTO v_branch_id FROM pggit.branches WHERE name = p_branch_name;
    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;

    -- Get object count first
    SELECT COUNT(*) INTO v_object_count
    FROM pggit.objects
    WHERE branch_id = v_branch_id;

    -- Collect all objects from this branch
    v_snapshot := jsonb_build_object(
        'branch', p_branch_name,
        'timestamp', NOW()::text,
        'summary', jsonb_build_object('object_count', v_object_count),
        'objects', COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'type', o.object_type::text,
                    'schema', o.schema_name,
                    'name', o.object_name,
                    'definition', o.ddl_normalized,
                    'content_hash', o.content_hash,
                    'version', o.version
                )
            )
            FROM pggit.objects o
            WHERE o.branch_id = v_branch_id),
            '[]'::jsonb
        )
    );

    -- Store snapshot for caching (if not already cached at exact same timestamp)
    INSERT INTO pggit.schema_snapshots (branch_id, branch_name, schema_json, object_count, snapshot_date)
    VALUES (v_branch_id, p_branch_name, v_snapshot, v_object_count, NOW())
    ON CONFLICT (branch_id, snapshot_date) DO NOTHING;

    RAISE NOTICE 'get_schema_snapshot: Captured % objects from branch %', v_object_count, p_branch_name;

    RETURN v_snapshot;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.compare_schemas()
-- ============================================================================
-- Detailed schema comparison between two branches
-- Detects: Added, removed, modified objects and their changes

CREATE OR REPLACE FUNCTION pggit.compare_schemas(
    p_branch_a text,
    p_branch_b text
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{
        "branch_a": "",
        "branch_b": "",
        "timestamp": "",
        "summary": {"added": 0, "removed": 0, "modified": 0},
        "changes": []
    }'::jsonb;
    v_change record;
    v_added_count integer := 0;
    v_removed_count integer := 0;
    v_modified_count integer := 0;
BEGIN
    v_result := jsonb_set(v_result, '{branch_a}', to_jsonb(p_branch_a));
    v_result := jsonb_set(v_result, '{branch_b}', to_jsonb(p_branch_b));
    v_result := jsonb_set(v_result, '{timestamp}', to_jsonb(NOW()::text));

    -- Find added objects (in B, not in A)
    FOR v_change IN
        SELECT
            'added'::text as change_type,
            ob.object_type,
            ob.schema_name,
            ob.object_name,
            ob.ddl_normalized
        FROM pggit.objects ob
        JOIN pggit.branches bb ON ob.branch_id = bb.id
        WHERE bb.name = p_branch_b
          AND NOT EXISTS (
              SELECT 1 FROM pggit.objects oa
              JOIN pggit.branches ba ON oa.branch_id = ba.id
              WHERE ba.name = p_branch_a
                AND oa.object_type = ob.object_type
                AND oa.schema_name = ob.schema_name
                AND oa.object_name = ob.object_name
          )
    LOOP
        v_added_count := v_added_count + 1;
        v_result := jsonb_set(
            v_result,
            '{changes}',
            v_result->'changes' || jsonb_build_object(
                'type', 'added',
                'object_type', v_change.object_type::text,
                'object_name', v_change.object_name,
                'definition', v_change.ddl_normalized
            )
        );
    END LOOP;

    -- Find removed objects (in A, not in B)
    FOR v_change IN
        SELECT
            'removed'::text as change_type,
            oa.object_type,
            oa.schema_name,
            oa.object_name,
            oa.ddl_normalized
        FROM pggit.objects oa
        JOIN pggit.branches ba ON oa.branch_id = ba.id
        WHERE ba.name = p_branch_a
          AND NOT EXISTS (
              SELECT 1 FROM pggit.objects ob
              JOIN pggit.branches bb ON ob.branch_id = bb.id
              WHERE bb.name = p_branch_b
                AND ob.object_type = oa.object_type
                AND ob.schema_name = oa.schema_name
                AND ob.object_name = oa.object_name
          )
    LOOP
        v_removed_count := v_removed_count + 1;
        v_result := jsonb_set(
            v_result,
            '{changes}',
            v_result->'changes' || jsonb_build_object(
                'type', 'removed',
                'object_type', v_change.object_type::text,
                'object_name', v_change.object_name,
                'definition', v_change.ddl_normalized
            )
        );
    END LOOP;

    -- Find modified objects (same object, different definition)
    FOR v_change IN
        SELECT
            'modified'::text as change_type,
            oa.object_type,
            oa.schema_name,
            oa.object_name,
            oa.ddl_normalized as old_def,
            ob.ddl_normalized as new_def
        FROM pggit.objects oa
        JOIN pggit.branches ba ON oa.branch_id = ba.id
        JOIN pggit.objects ob ON ob.object_type = oa.object_type
                              AND ob.schema_name = oa.schema_name
                              AND ob.object_name = oa.object_name
        JOIN pggit.branches bb ON ob.branch_id = bb.id
        WHERE ba.name = p_branch_a
          AND bb.name = p_branch_b
          AND oa.content_hash IS DISTINCT FROM ob.content_hash
    LOOP
        v_modified_count := v_modified_count + 1;
        v_result := jsonb_set(
            v_result,
            '{changes}',
            v_result->'changes' || jsonb_build_object(
                'type', 'modified',
                'object_type', v_change.object_type::text,
                'object_name', v_change.object_name,
                'old_definition', v_change.old_def,
                'new_definition', v_change.new_def
            )
        );
    END LOOP;

    -- Update summary
    v_result := jsonb_set(v_result, '{summary, added}', to_jsonb(v_added_count));
    v_result := jsonb_set(v_result, '{summary, removed}', to_jsonb(v_removed_count));
    v_result := jsonb_set(v_result, '{summary, modified}', to_jsonb(v_modified_count));

    -- Store diff for caching
    INSERT INTO pggit.schema_diffs (branch_a, branch_b, diff_json, added_count, removed_count, modified_count)
    VALUES (p_branch_a, p_branch_b, v_result, v_added_count, v_removed_count, v_modified_count);

    RAISE NOTICE 'compare_schemas: Found % added, % removed, % modified between % and %',
        v_added_count, v_removed_count, v_modified_count, p_branch_a, p_branch_b;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.categorize_change()
-- ============================================================================
-- Categorize a change as BREAKING, COMPATIBLE, RISKY, or OPTIONAL
-- Uses: Heuristics based on object type and change pattern

CREATE OR REPLACE FUNCTION pggit.categorize_change(
    p_object_type text,
    p_change_type text,
    p_old_def text,
    p_new_def text
)
RETURNS jsonb AS $$
DECLARE
    v_category text;
    v_description text;
BEGIN
    -- Default categorization logic
    v_category := 'OPTIONAL';
    v_description := 'No impact assessment available';

    -- BREAKING CHANGES: Operations that break existing code/data
    IF p_change_type = 'removed' THEN
        v_category := 'BREAKING';
        v_description := 'Removing ' || p_object_type || ' will break dependent code';
    ELSIF p_object_type IN ('CONSTRAINT', 'PRIMARY KEY') AND p_change_type = 'removed' THEN
        v_category := 'BREAKING';
        v_description := 'Removing ' || p_object_type || ' violates data integrity';
    ELSIF p_object_type = 'COLUMN' AND p_change_type = 'removed' THEN
        v_category := 'BREAKING';
        v_description := 'Removing column will break queries and applications';
    ELSIF p_object_type = 'COLUMN' AND p_change_type = 'modified'
          AND (p_old_def LIKE '%NOT NULL%' AND p_new_def NOT LIKE '%NOT NULL%') THEN
        v_category := 'BREAKING';
        v_description := 'Changing column from NOT NULL to nullable changes semantics';

    -- RISKY CHANGES: May cause issues, need careful planning
    ELSIF p_object_type = 'COLUMN' AND p_change_type = 'modified'
          AND p_old_def LIKE '%NOT NULL%' AND p_new_def LIKE '%NOT NULL%' THEN
        v_category := 'RISKY';
        v_description := 'Column type change requires data migration';
    ELSIF p_object_type = 'CONSTRAINT' AND p_change_type = 'modified' THEN
        v_category := 'RISKY';
        v_description := 'Constraint modification may violate existing data';

    -- COMPATIBLE CHANGES: Safe to apply
    ELSIF p_object_type = 'COLUMN' AND p_change_type = 'added' THEN
        v_category := 'COMPATIBLE';
        v_description := 'Adding new column is backwards compatible (unless NOT NULL without default)';
    ELSIF p_object_type = 'INDEX' AND p_change_type IN ('added', 'removed') THEN
        v_category := 'COMPATIBLE';
        v_description := 'Index changes do not affect functionality';
    ELSIF p_object_type = 'VIEW' AND p_change_type = 'modified' THEN
        v_category := 'COMPATIBLE';
        v_description := 'View modifications are generally safe';

    -- OPTIONAL CHANGES: Nice to have, no impact
    ELSIF p_object_type IN ('COMMENT', 'PERMISSION') THEN
        v_category := 'OPTIONAL';
        v_description := 'Change is informational only';
    END IF;

    RETURN jsonb_build_object(
        'category', v_category,
        'description', v_description,
        'object_type', p_object_type,
        'change_type', p_change_type
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.assess_migration_impact()
-- ============================================================================
-- Assess impact of a schema diff result

CREATE OR REPLACE FUNCTION pggit.assess_migration_impact(
    p_diff jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_impact jsonb := '{
        "feasibility": "ready",
        "risk_level": "low",
        "breaking_changes": 0,
        "risky_changes": 0,
        "compatible_changes": 0,
        "optional_changes": 0,
        "estimated_effort": "low"
    }'::jsonb;
    v_change jsonb;
    v_breaking integer := 0;
    v_risky integer := 0;
    v_compatible integer := 0;
    v_optional integer := 0;
BEGIN
    -- Count changes by category
    FOR v_change IN SELECT jsonb_array_elements(p_diff->'changes')
    LOOP
        CASE v_change->>'type'
            WHEN 'removed' THEN v_breaking := v_breaking + 1;
            WHEN 'added' THEN v_compatible := v_compatible + 1;
            WHEN 'modified' THEN v_risky := v_risky + 1;
            ELSE v_optional := v_optional + 1;
        END CASE;
    END LOOP;

    -- Assess feasibility
    IF v_breaking > 0 THEN
        v_impact := jsonb_set(v_impact, '{feasibility}', '"review_required"'::jsonb);
        v_impact := jsonb_set(v_impact, '{risk_level}', '"high"'::jsonb);
    ELSIF v_risky > 0 THEN
        v_impact := jsonb_set(v_impact, '{feasibility}', '"proceed_with_caution"'::jsonb);
        v_impact := jsonb_set(v_impact, '{risk_level}', '"medium"'::jsonb);
    ELSE
        v_impact := jsonb_set(v_impact, '{feasibility}', '"ready"'::jsonb);
        v_impact := jsonb_set(v_impact, '{risk_level}', '"low"'::jsonb);
    END IF;

    -- Estimate effort
    IF v_breaking > 0 THEN
        v_impact := jsonb_set(v_impact, '{estimated_effort}', '"high"'::jsonb);
    ELSIF v_risky > 0 THEN
        v_impact := jsonb_set(v_impact, '{estimated_effort}', '"medium"'::jsonb);
    ELSE
        v_impact := jsonb_set(v_impact, '{estimated_effort}', '"low"'::jsonb);
    END IF;

    -- Update counts
    v_impact := jsonb_set(v_impact, '{breaking_changes}', to_jsonb(v_breaking));
    v_impact := jsonb_set(v_impact, '{risky_changes}', to_jsonb(v_risky));
    v_impact := jsonb_set(v_impact, '{compatible_changes}', to_jsonb(v_compatible));
    v_impact := jsonb_set(v_impact, '{optional_changes}', to_jsonb(v_optional));

    RAISE NOTICE 'assess_migration_impact: Breaking: %, Risky: %, Compatible: %, Optional: %',
        v_breaking, v_risky, v_compatible, v_optional;

    RETURN v_impact;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.plan_migration()
-- ============================================================================
-- Generate migration plan from one branch to another

CREATE OR REPLACE FUNCTION pggit.plan_migration(
    p_source_branch text,
    p_target_branch text
)
RETURNS jsonb AS $$
DECLARE
    v_plan jsonb;
    v_diff jsonb;
    v_impact jsonb;
    v_step_count integer := 0;
    v_change jsonb;
BEGIN
    -- Get schema diff
    v_diff := pggit.compare_schemas(p_source_branch, p_target_branch);

    -- Assess impact
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Build migration plan
    v_plan := jsonb_build_object(
        'plan_id', gen_random_uuid()::text,
        'source_branch', p_source_branch,
        'target_branch', p_target_branch,
        'generated_at', NOW()::text,
        'feasibility', v_impact->>'feasibility',
        'risk_level', v_impact->>'risk_level',
        'estimated_effort', v_impact->>'estimated_effort',
        'steps', jsonb_build_array()
    );

    -- Add steps for each change (in safe order)
    -- Order: removes last, adds first, modifies in middle
    v_step_count := 0;

    -- Step 1: Add new objects
    FOR v_change IN SELECT * FROM jsonb_array_elements(v_diff->'changes') WHERE value->>'type' = 'added'
    LOOP
        v_step_count := v_step_count + 1;
        v_plan := jsonb_set(
            v_plan,
            '{steps}',
            v_plan->'steps' || jsonb_build_object(
                'order', v_step_count,
                'type', 'ADD_OBJECT',
                'object_type', v_change->>'object_type',
                'object_name', v_change->>'object_name',
                'definition', v_change->>'definition',
                'risk_level', 'low'
            )
        );
    END LOOP;

    -- Step 2: Modify objects
    FOR v_change IN SELECT * FROM jsonb_array_elements(v_diff->'changes') WHERE value->>'type' = 'modified'
    LOOP
        v_step_count := v_step_count + 1;
        v_plan := jsonb_set(
            v_plan,
            '{steps}',
            v_plan->'steps' || jsonb_build_object(
                'order', v_step_count,
                'type', 'MODIFY_OBJECT',
                'object_type', v_change->>'object_type',
                'object_name', v_change->>'object_name',
                'old_definition', v_change->>'old_definition',
                'new_definition', v_change->>'new_definition',
                'risk_level', 'medium'
            )
        );
    END LOOP;

    -- Step 3: Remove objects
    FOR v_change IN SELECT * FROM jsonb_array_elements(v_diff->'changes') WHERE value->>'type' = 'removed'
    LOOP
        v_step_count := v_step_count + 1;
        v_plan := jsonb_set(
            v_plan,
            '{steps}',
            v_plan->'steps' || jsonb_build_object(
                'order', v_step_count,
                'type', 'REMOVE_OBJECT',
                'object_type', v_change->>'object_type',
                'object_name', v_change->>'object_name',
                'definition', v_change->>'definition',
                'risk_level', 'high'
            )
        );
    END LOOP;

    v_plan := jsonb_set(v_plan, '{step_count}', to_jsonb(v_step_count));

    -- Store plan
    INSERT INTO pggit.migration_plans (source_branch, target_branch, plan_json, feasibility, estimated_duration_seconds)
    VALUES (p_source_branch, p_target_branch, v_plan, v_impact->>'feasibility', (v_step_count * 5)::integer);

    RAISE NOTICE 'plan_migration: Generated % steps for migrating from % to %',
        v_step_count, p_source_branch, p_target_branch;

    RETURN v_plan;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.detect_schema_dependencies()
-- ============================================================================
-- Detect object dependencies within a branch

CREATE OR REPLACE FUNCTION pggit.detect_schema_dependencies(
    p_branch_name text
)
RETURNS jsonb AS $$
DECLARE
    v_dependencies jsonb := '{"branch": "", "dependencies": [], "dependency_count": 0}'::jsonb;
    v_dep_count integer := 0;
    v_object record;
BEGIN
    v_dependencies := jsonb_set(v_dependencies, '{branch}', to_jsonb(p_branch_name));

    -- For now, simple dependency detection based on object names
    -- In production, would parse DDL to find actual dependencies
    FOR v_object IN
        SELECT DISTINCT
            o1.object_name as from_object,
            o2.object_name as to_object,
            o1.object_type,
            o2.object_type as referenced_type
        FROM pggit.objects o1
        JOIN pggit.branches b1 ON o1.branch_id = b1.id
        JOIN pggit.objects o2 ON o2.branch_id = b1.id
        WHERE b1.name = p_branch_name
          AND o1.object_name != o2.object_name
          AND (o1.ddl_normalized ILIKE '%' || o2.object_name || '%'
               OR o2.ddl_normalized ILIKE '%' || o1.object_name || '%')
        LIMIT 100
    LOOP
        v_dep_count := v_dep_count + 1;
        v_dependencies := jsonb_set(
            v_dependencies,
            '{dependencies}',
            v_dependencies->'dependencies' || jsonb_build_object(
                'from', v_object.from_object,
                'to', v_object.to_object,
                'from_type', v_object.object_type::text,
                'to_type', v_object.referenced_type::text
            )
        );
    END LOOP;

    v_dependencies := jsonb_set(v_dependencies, '{dependency_count}', to_jsonb(v_dep_count));

    RAISE NOTICE 'detect_schema_dependencies: Found % dependencies in %', v_dep_count, p_branch_name;

    RETURN v_dependencies;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.generate_schema_diff_report()
-- ============================================================================
-- Generate human-readable schema diff report

CREATE OR REPLACE FUNCTION pggit.generate_schema_diff_report(
    p_branch_a text,
    p_branch_b text
)
RETURNS text AS $$
DECLARE
    v_report text;
    v_diff jsonb;
    v_impact jsonb;
BEGIN
    -- Get diff
    v_diff := pggit.compare_schemas(p_branch_a, p_branch_b);

    -- Assess impact
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Build report
    v_report := '================================================================================
' || E'\n' ||
'SCHEMA DIFF REPORT
' || E'\n' ||
'================================================================================
' || E'\n' ||
'Branch A: ' || p_branch_a || E'\n' ||
'Branch B: ' || p_branch_b || E'\n' ||
'Generated: ' || NOW()::text || E'\n' ||
'================================================================================
' || E'\n' ||
E'\n' ||
'SUMMARY
' || E'\n' ||
'--------
' || E'\n' ||
'Added Objects:    ' || (v_diff->'summary'->>'added') || E'\n' ||
'Removed Objects:  ' || (v_diff->'summary'->>'removed') || E'\n' ||
'Modified Objects: ' || (v_diff->'summary'->>'modified') || E'\n' ||
E'\n' ||
'IMPACT ASSESSMENT
' || E'\n' ||
'--------
' || E'\n' ||
'Feasibility: ' || (v_impact->>'feasibility') || E'\n' ||
'Risk Level:  ' || (v_impact->>'risk_level') || E'\n' ||
'Effort:      ' || (v_impact->>'estimated_effort') || E'\n' ||
E'\n' ||
'Breaking Changes: ' || (v_impact->>'breaking_changes') || E'\n' ||
'Risky Changes:    ' || (v_impact->>'risky_changes') || E'\n' ||
'Compatible:       ' || (v_impact->>'compatible_changes') || E'\n' ||
'Optional:         ' || (v_impact->>'optional_changes') || E'\n' ||
'================================================================================
';

    RETURN v_report;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.track_schema_lineage()
-- ============================================================================
-- Track schema evolution for a branch

CREATE OR REPLACE FUNCTION pggit.track_schema_lineage(
    p_branch_name text
)
RETURNS jsonb AS $$
DECLARE
    v_lineage jsonb := '{"branch": "", "snapshots": []}'::jsonb;
    v_snapshot record;
BEGIN
    v_lineage := jsonb_set(v_lineage, '{branch}', to_jsonb(p_branch_name));

    -- Get all snapshots for this branch
    FOR v_snapshot IN
        SELECT snapshot_date, object_count FROM pggit.schema_snapshots
        WHERE branch_name = p_branch_name
        ORDER BY snapshot_date DESC
        LIMIT 10
    LOOP
        v_lineage := jsonb_set(
            v_lineage,
            '{snapshots}',
            v_lineage->'snapshots' || jsonb_build_object(
                'date', v_snapshot.snapshot_date::text,
                'object_count', v_snapshot.object_count
            )
        );
    END LOOP;

    RAISE NOTICE 'track_schema_lineage: Tracked % snapshots for %',
        jsonb_array_length(v_lineage->'snapshots'), p_branch_name;

    RETURN v_lineage;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR SCHEMA ANALYSIS
-- ============================================================================

-- View: v_schema_change_summary
-- Shows: Summary of changes by type and category
CREATE OR REPLACE VIEW pggit.v_schema_change_summary AS
SELECT
    branch_a,
    branch_b,
    COUNT(*) as total_changes,
    COUNT(CASE WHEN change_type = 'added' THEN 1 END) as added_count,
    COUNT(CASE WHEN change_type = 'removed' THEN 1 END) as removed_count,
    COUNT(CASE WHEN change_type = 'modified' THEN 1 END) as modified_count,
    COUNT(CASE WHEN category = 'BREAKING' THEN 1 END) as breaking_count,
    COUNT(CASE WHEN category = 'RISKY' THEN 1 END) as risky_count,
    COUNT(CASE WHEN category = 'COMPATIBLE' THEN 1 END) as compatible_count,
    COUNT(CASE WHEN category = 'OPTIONAL' THEN 1 END) as optional_count,
    sd.created_at
FROM pggit.schema_diffs sd
LEFT JOIN pggit.schema_changes sc ON sc.diff_id = sd.id
GROUP BY sd.branch_a, sd.branch_b, sd.created_at
ORDER BY sd.created_at DESC;

-- View: v_schema_impact_analysis
-- Shows: Categorized changes with impact levels
CREATE OR REPLACE VIEW pggit.v_schema_impact_analysis AS
SELECT
    sd.branch_a,
    sd.branch_b,
    sc.object_type,
    sc.object_name,
    sc.change_type,
    sc.category,
    sc.impact_description,
    sd.created_at
FROM pggit.schema_diffs sd
LEFT JOIN pggit.schema_changes sc ON sc.diff_id = sd.id
WHERE sc.category IS NOT NULL
ORDER BY sd.created_at DESC, sc.category DESC;

-- View: v_schema_migration_readiness
-- Shows: Migration readiness assessment
CREATE OR REPLACE VIEW pggit.v_schema_migration_readiness AS
SELECT
    source_branch,
    target_branch,
    (plan_json->>'feasibility') as feasibility,
    (plan_json->>'risk_level') as risk_level,
    (plan_json->>'estimated_effort') as estimated_effort,
    (plan_json->'step_count')::integer as step_count,
    created_at
FROM pggit.migration_plans
ORDER BY created_at DESC;
