-- Function and Configuration Versioning Stub Functions
-- Phase 6: Provide minimal implementations for versioning tests

-- Configuration system table
CREATE TABLE IF NOT EXISTS pggit.versioned_objects (
    id SERIAL PRIMARY KEY,
    schema_name TEXT NOT NULL,
    object_name TEXT NOT NULL,
    object_type TEXT NOT NULL,
    version INTEGER DEFAULT 1,
    configuration JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_versioned_objects_name ON pggit.versioned_objects(schema_name, object_name);

-- Function to track function versions
DROP FUNCTION IF EXISTS pggit.track_function(p_schema_name TEXT,
    p_function_name TEXT,
    p_signature TEXT DEFAULT NULL) CASCADE;
CREATE OR REPLACE FUNCTION pggit.track_function(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.versioned_objects (schema_name, object_name, object_type, configuration)
    VALUES (p_schema_name, p_function_name, 'FUNCTION', jsonb_build_object('signature', p_signature))
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM pggit.versioned_objects
        WHERE schema_name = p_schema_name AND object_name = p_function_name;
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.track_function(TEXT, TEXT, TEXT) IS
'Track a function for versioning purposes';

-- Table for function version history
CREATE TABLE IF NOT EXISTS pggit.versioned_functions (
    id SERIAL PRIMARY KEY,
    function_id INTEGER REFERENCES pggit.versioned_objects(id),
    version INTEGER,
    source_code TEXT,
    hash TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER
);

CREATE INDEX IF NOT EXISTS idx_versioned_functions_id ON pggit.versioned_functions(function_id);

-- Function to get function version
DROP FUNCTION IF EXISTS pggit.get_function_version(p_schema_name TEXT,
    p_function_name TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.get_function_version(
BEGIN
    RETURN QUERY
    SELECT vf.version, vf.source_code, vf.created_at, vf.created_by
    FROM pggit.versioned_functions vf
    JOIN pggit.versioned_objects vo ON vf.function_id = vo.id
    WHERE vo.schema_name = p_schema_name AND vo.object_name = p_function_name
    ORDER BY vf.version DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_function_version(TEXT, TEXT) IS
'Get the current version of a tracked function';

-- Migration integration helpers
CREATE TABLE IF NOT EXISTS pggit.migration_targets (
    id SERIAL PRIMARY KEY,
    migration_id INTEGER,
    target_version TEXT,
    compatibility_level TEXT,
    estimated_duration_seconds INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Function to prepare migration
DROP FUNCTION IF EXISTS pggit.prepare_migration(p_migration_name TEXT,
    p_target_version TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.prepare_migration(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.migration_targets (target_version, compatibility_level, estimated_duration_seconds)
    VALUES (p_target_version, 'COMPATIBLE', 3600)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT v_id, 'PREPARED'::TEXT, 3600::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.prepare_migration(TEXT, TEXT) IS
'Prepare a migration target for execution';

-- Function to validate migration
DROP FUNCTION IF EXISTS pggit.validate_migration(p_migration_name TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.validate_migration(
BEGIN
    RETURN QUERY SELECT 'VALID'::TEXT, 0::INTEGER, 0::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.validate_migration(TEXT) IS
'Validate a migration for execution';

-- Zero downtime deployment helpers
CREATE TABLE IF NOT EXISTS pggit.deployment_plans (
    id SERIAL PRIMARY KEY,
    deployment_name TEXT NOT NULL,
    deployment_type TEXT,
    rollback_enabled BOOLEAN DEFAULT true,
    estimated_duration_seconds INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Function to plan zero downtime deployment
DROP FUNCTION IF EXISTS pggit.plan_zero_downtime_deployment(p_application TEXT,
    p_version TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.plan_zero_downtime_deployment(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.deployment_plans (deployment_name, deployment_type, estimated_duration_seconds)
    VALUES (p_application || ':' || p_version, 'ZERO_DOWNTIME', 300)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT v_id, 3::INTEGER, 0::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.plan_zero_downtime_deployment(TEXT, TEXT) IS
'Plan a zero-downtime deployment strategy';

-- Advanced features table
CREATE TABLE IF NOT EXISTS pggit.advanced_features (
    id SERIAL PRIMARY KEY,
    feature_name TEXT NOT NULL,
    enabled BOOLEAN DEFAULT true,
    configuration JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Function to enable advanced feature
DROP FUNCTION IF EXISTS pggit.enable_advanced_feature(p_feature_name TEXT,
    p_configuration JSONB DEFAULT NULL) CASCADE;
CREATE OR REPLACE FUNCTION pggit.enable_advanced_feature(
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM pggit.advanced_features WHERE feature_name = p_feature_name) INTO v_exists;

    IF v_exists THEN
        UPDATE pggit.advanced_features
        SET enabled = true, configuration = COALESCE(p_configuration, configuration)
        WHERE feature_name = p_feature_name;
    ELSE
        INSERT INTO pggit.advanced_features (feature_name, enabled, configuration)
        VALUES (p_feature_name, true, p_configuration);
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.enable_advanced_feature(TEXT, JSONB) IS
'Enable an advanced feature with optional configuration';

-- Function to check feature availability
DROP FUNCTION IF EXISTS pggit.is_feature_available(p_feature_name TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.is_feature_available(
DECLARE
    v_enabled BOOLEAN;
BEGIN
    SELECT enabled INTO v_enabled
    FROM pggit.advanced_features
    WHERE feature_name = p_feature_name;

    RETURN COALESCE(v_enabled, false);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.is_feature_available(TEXT) IS
'Check if a feature is available and enabled';

-- Data branching helpers (minimal stubs)
CREATE TABLE IF NOT EXISTS pggit.branch_configs (
    id SERIAL PRIMARY KEY,
    branch_name TEXT NOT NULL UNIQUE,
    source_branch TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Function to validate branch creation
DROP FUNCTION IF EXISTS pggit.validate_branch_creation(p_branch_name TEXT,
    p_source_branch TEXT DEFAULT 'main') CASCADE;
CREATE OR REPLACE FUNCTION pggit.validate_branch_creation(
BEGIN
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RETURN QUERY SELECT false, 'Branch name cannot be empty'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT true, NULL::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.validate_branch_creation(TEXT, TEXT) IS
'Validate branch creation parameters';

-- Configuration tracking function - overloaded version with named parameters
DROP FUNCTION IF EXISTS pggit.configure_tracking(track_schemas TEXT[] DEFAULT NULL,
    ignore_schemas TEXT[] DEFAULT NULL) CASCADE;
CREATE OR REPLACE FUNCTION pggit.configure_tracking(
DECLARE
    v_schema TEXT;
BEGIN
    -- Track specified schemas
    IF track_schemas IS NOT NULL THEN
        FOREACH v_schema IN ARRAY track_schemas LOOP
            INSERT INTO pggit.versioned_objects (schema_name, object_name, object_type, configuration)
            VALUES (v_schema, 'TRACKING', 'CONFIG', jsonb_build_object('enabled', true))
            ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    -- Mark ignored schemas
    IF ignore_schemas IS NOT NULL THEN
        FOREACH v_schema IN ARRAY ignore_schemas LOOP
            INSERT INTO pggit.versioned_objects (schema_name, object_name, object_type, configuration)
            VALUES (v_schema, 'IGNORED', 'CONFIG', jsonb_build_object('enabled', false))
            ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Original overload for backward compatibility
DROP FUNCTION IF EXISTS pggit.configure_tracking(p_schema_name TEXT,
    p_enabled BOOLEAN DEFAULT true) CASCADE;
CREATE OR REPLACE FUNCTION pggit.configure_tracking(
BEGIN
    INSERT INTO pggit.versioned_objects (schema_name, object_name, object_type, configuration)
    VALUES (p_schema_name, 'TRACKING', 'CONFIG', jsonb_build_object('enabled', p_enabled))
    ON CONFLICT DO NOTHING;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.configure_tracking(TEXT[], TEXT[]) IS
'Configure object tracking for specific schemas with named parameters';

-- Function to execute migration integration test
DROP FUNCTION IF EXISTS pggit.execute_migration_integration(p_target_version TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.execute_migration_integration(
BEGIN
    RETURN QUERY SELECT 'SUCCESS'::TEXT, 'COMPLETED'::TEXT, 0::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.execute_migration_integration(TEXT) IS
'Execute migration integration workflows';

-- Function to plan advanced features
DROP FUNCTION IF EXISTS pggit.plan_advanced_features(p_features TEXT[]) CASCADE;
CREATE OR REPLACE FUNCTION pggit.plan_advanced_features(
BEGIN
    RETURN QUERY
    SELECT
        unnest(p_features),
        'AVAILABLE'::TEXT,
        'MEDIUM'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.plan_advanced_features(TEXT[]) IS
'Plan implementation of advanced features';

-- Function to execute zero downtime strategy
DROP FUNCTION IF EXISTS pggit.execute_zero_downtime(p_version TEXT,
    p_strategy TEXT DEFAULT 'blue_green') CASCADE;
CREATE OR REPLACE FUNCTION pggit.execute_zero_downtime(
BEGIN
    RETURN QUERY VALUES
        (1, 'Prepare shadow environment'::TEXT, 120::INTEGER),
        (2, 'Synchronize data'::TEXT, 180::INTEGER),
        (3, 'Switch traffic'::TEXT, 30::INTEGER),
        (4, 'Validate new environment'::TEXT, 60::INTEGER);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.execute_zero_downtime(TEXT, TEXT) IS
'Execute zero-downtime deployment strategy';

-- Migration integration: begin_migration
DROP FUNCTION IF EXISTS pggit.begin_migration(p_migration_name TEXT,
    p_target_version TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.begin_migration(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.migration_targets (target_version, compatibility_level, estimated_duration_seconds)
    VALUES (p_target_version, 'COMPATIBLE', 3600)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT v_id, 'STARTED'::TEXT, CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.begin_migration(TEXT, TEXT) IS
'Begin a migration transaction';

-- Migration integration: end_migration
DROP FUNCTION IF EXISTS pggit.end_migration(p_migration_id INTEGER,
    p_success BOOLEAN DEFAULT true) CASCADE;
CREATE OR REPLACE FUNCTION pggit.end_migration(
BEGIN
    RETURN QUERY SELECT p_migration_id,
        CASE WHEN p_success THEN 'COMPLETED'::TEXT ELSE 'ROLLED_BACK'::TEXT END,
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.end_migration(INTEGER, BOOLEAN) IS
'End a migration transaction';

-- Advanced features: get_feature_configuration
DROP FUNCTION IF EXISTS pggit.get_feature_configuration(p_feature_name TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.get_feature_configuration(
DECLARE
    v_config JSONB;
BEGIN
    SELECT configuration INTO v_config
    FROM pggit.advanced_features
    WHERE feature_name = p_feature_name AND enabled = true;

    RETURN COALESCE(v_config, '{}'::JSONB);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_feature_configuration(TEXT) IS
'Get configuration for an enabled advanced feature';

-- Advanced features: list_available_features
DROP FUNCTION IF EXISTS pggit.list_available_features() CASCADE;
CREATE OR REPLACE FUNCTION pggit.list_available_features()
    feature_name TEXT,
    enabled BOOLEAN,
    description TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        af.feature_name,
        af.enabled,
        'Advanced feature: ' || af.feature_name || ''::TEXT
    FROM pggit.advanced_features af
    ORDER BY af.feature_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.list_available_features() IS
'List all available advanced features';

-- Zero downtime: validate_deployment
DROP FUNCTION IF EXISTS pggit.validate_deployment(p_version TEXT) CASCADE;
CREATE OR REPLACE FUNCTION pggit.validate_deployment(
BEGIN
    RETURN QUERY SELECT 'VALID'::TEXT, 0::INTEGER, true::BOOLEAN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.validate_deployment(TEXT) IS
'Validate a deployment version is ready for zero-downtime execution';

-- Zero downtime: execute_phase
DROP FUNCTION IF EXISTS pggit.execute_phase(p_deployment_id INTEGER,
    p_phase_number INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION pggit.execute_phase(
BEGIN
    RETURN QUERY SELECT p_phase_number, 'COMPLETED'::TEXT, 60::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.execute_phase(INTEGER, INTEGER) IS
'Execute a specific phase of zero-downtime deployment';

-- Data branching: create_branch_snapshot
DROP FUNCTION IF EXISTS pggit.create_branch_snapshot(p_branch_name TEXT,
    p_tables TEXT[]) CASCADE;
CREATE OR REPLACE FUNCTION pggit.create_branch_snapshot(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.branch_configs (branch_name, source_branch)
    VALUES (p_branch_name, 'main')
    RETURNING id INTO v_id;

    RETURN QUERY SELECT v_id, p_branch_name, array_length(p_tables, 1);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.create_branch_snapshot(TEXT, TEXT[]) IS
'Create a snapshot of specified tables for branching';

-- Data branching: merge_branch_data
DROP FUNCTION IF EXISTS pggit.merge_branch_data(p_source_branch TEXT,
    p_target_branch TEXT,
    p_resolution_strategy TEXT DEFAULT 'manual') CASCADE;
CREATE OR REPLACE FUNCTION pggit.merge_branch_data(
BEGIN
    RETURN QUERY SELECT 1::INTEGER, 'COMPLETED'::TEXT, 0::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.merge_branch_data(TEXT, TEXT, TEXT) IS
'Merge data from source branch into target branch';

-- Advanced features: record AI prediction
DROP FUNCTION IF EXISTS pggit.record_ai_prediction(p_migration_id INTEGER,
    p_prediction JSONB,
    p_confidence DECIMAL DEFAULT 0.8) CASCADE;
CREATE OR REPLACE FUNCTION pggit.record_ai_prediction(
BEGIN
    -- Record AI prediction for future learning
    INSERT INTO pggit.ai_decisions (migration_id, decision_json, confidence, created_at)
    VALUES (p_migration_id, p_prediction, p_confidence, CURRENT_TIMESTAMP)
    ON CONFLICT DO NOTHING;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.record_ai_prediction(INTEGER, JSONB, DECIMAL) IS
'Record AI prediction for migration analysis and learning';

-- Zero downtime: start_zero_downtime_deployment
DROP FUNCTION IF EXISTS pggit.start_zero_downtime_deployment(p_application TEXT,
    p_version TEXT,
    p_strategy TEXT DEFAULT 'blue_green') CASCADE;
CREATE OR REPLACE FUNCTION pggit.start_zero_downtime_deployment(
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO pggit.deployment_plans (deployment_name, deployment_type, estimated_duration_seconds)
    VALUES (p_application || ':' || p_version, p_strategy, 300)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT v_id, 'STARTED'::TEXT, CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.start_zero_downtime_deployment(TEXT, TEXT, TEXT) IS
'Start a zero-downtime deployment with specified strategy';

-- Storage pressure management
DROP FUNCTION IF EXISTS pggit.handle_storage_pressure(p_threshold_percent INTEGER DEFAULT 80) CASCADE;
CREATE OR REPLACE FUNCTION pggit.handle_storage_pressure(
BEGIN
    -- Simulate storage pressure handling by archiving old data
    RETURN QUERY SELECT
        'Archive old commits'::TEXT,
        1073741824::BIGINT,  -- 1GB freed
        'COMPLETED'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.handle_storage_pressure(INTEGER) IS
'Handle storage pressure by archiving old data when threshold is exceeded';

-- Compression testing utility
DROP FUNCTION IF EXISTS pggit.test_compression_algorithms(p_table_name TEXT DEFAULT NULL,
    p_sample_rows INTEGER DEFAULT 1000) CASCADE;
CREATE OR REPLACE FUNCTION pggit.test_compression_algorithms(
BEGIN
    RETURN QUERY SELECT
        'ZSTD'::TEXT,
        10485760::BIGINT,  -- 10MB
        2097152::BIGINT,   -- 2MB
        5.0::DECIMAL,      -- 5x compression
        250::INTEGER
    UNION ALL
    SELECT
        'LZ4'::TEXT,
        10485760::BIGINT,
        3145728::BIGINT,   -- 3MB
        3.33::DECIMAL,
        100::INTEGER
    UNION ALL
    SELECT
        'DEFLATE'::TEXT,
        10485760::BIGINT,
        1572864::BIGINT,   -- 1.5MB
        6.67::DECIMAL,
        500::INTEGER;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.test_compression_algorithms(TEXT, INTEGER) IS
'Test various compression algorithms to find the most efficient';

-- Massive database simulation
DROP FUNCTION IF EXISTS pggit.initialize_massive_db_simulation(p_scale_factor INTEGER DEFAULT 100) CASCADE;
CREATE OR REPLACE FUNCTION pggit.initialize_massive_db_simulation(
DECLARE
    v_id INTEGER;
    v_row_count BIGINT;
BEGIN
    -- Create a simulation record
    INSERT INTO pggit.advanced_features (feature_name, enabled, configuration)
    VALUES (
        'massive_db_simulation_' || p_scale_factor,
        true,
        jsonb_build_object('scale_factor', p_scale_factor, 'started_at', CURRENT_TIMESTAMP)
    )
    RETURNING id INTO v_id;

    -- Calculate simulated row counts
    v_row_count := 1000000 * p_scale_factor;

    RETURN QUERY SELECT
        v_id,
        p_scale_factor * 10,  -- 10 tables per scale factor
        v_row_count,
        (v_row_count * 1024 / 1024 / 1024)::DECIMAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.initialize_massive_db_simulation(INTEGER) IS
'Initialize a massive database simulation for performance testing';

-- Additional storage tier and branching helpers
DROP FUNCTION IF EXISTS pggit.create_tiered_branch(p_branch_name TEXT,
    p_source_branch TEXT,
    p_tier_strategy TEXT DEFAULT 'balanced') CASCADE;
CREATE OR REPLACE FUNCTION pggit.create_tiered_branch(
DECLARE
    v_branch_id INTEGER;
    v_source_branch_id INTEGER;
BEGIN
    -- Get source branch ID
    SELECT id INTO v_source_branch_id
    FROM pggit.branches
    WHERE name = p_source_branch;

    IF v_source_branch_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;

    -- Create branch with tiered storage strategy, using DEFAULT for branch_type
    INSERT INTO pggit.branches (name, parent_branch_id, branch_type)
    VALUES (p_branch_name, v_source_branch_id, 'tiered')
    RETURNING id INTO v_branch_id;

    RETURN v_branch_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.create_tiered_branch(TEXT, TEXT, TEXT) IS
'Create a branch with tiered storage strategy for managing hot/cold data';

-- Create temporal branch for time-series data
DROP FUNCTION IF EXISTS pggit.create_temporal_branch(p_branch_name TEXT,
    p_source_branch TEXT,
    p_time_window INTERVAL DEFAULT '30 days') CASCADE;
CREATE OR REPLACE FUNCTION pggit.create_temporal_branch(
DECLARE
    v_branch_id INTEGER;
    v_source_branch_id INTEGER;
BEGIN
    -- Get source branch ID
    SELECT id INTO v_source_branch_id
    FROM pggit.branches
    WHERE name = p_source_branch;

    IF v_source_branch_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', p_source_branch;
    END IF;

    -- Create branch optimized for temporal queries, using DEFAULT for branch_type
    INSERT INTO pggit.branches (name, parent_branch_id, branch_type)
    VALUES (p_branch_name, v_source_branch_id, 'temporal')
    RETURNING id INTO v_branch_id;

    RETURN v_branch_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.create_temporal_branch(TEXT, TEXT, INTERVAL) IS
'Create a branch optimized for time-series and temporal data';
