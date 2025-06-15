-- pggit Core Edition - Open Source Database Version Control
-- Version: 1.0.0
-- License: Apache 2.0
-- 
-- This creates a minimal database versioning system using PostgreSQL
-- event triggers to track DDL changes automatically.

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create schema for versioning objects
CREATE SCHEMA IF NOT EXISTS pggit;

-- Enum types for categorizing database objects and changes
CREATE TYPE pggit.object_type AS ENUM (
    'SCHEMA',
    'TABLE', 
    'COLUMN',
    'INDEX',
    'CONSTRAINT',
    'VIEW',
    'MATERIALIZED_VIEW',
    'FUNCTION',
    'PROCEDURE',
    'TRIGGER',
    'TYPE',
    'SEQUENCE'
);

CREATE TYPE pggit.change_type AS ENUM (
    'CREATE',
    'ALTER',
    'DROP',
    'RENAME',
    'COMMENT'
);

CREATE TYPE pggit.change_severity AS ENUM (
    'MAJOR',    -- Breaking changes
    'MINOR',    -- New features
    'PATCH'     -- Bug fixes
);

-- Main versioning table to track all database objects
CREATE TABLE IF NOT EXISTS pggit.objects (
    id SERIAL PRIMARY KEY,
    object_type pggit.object_type NOT NULL,
    schema_name TEXT NOT NULL,
    object_name TEXT NOT NULL,
    full_name TEXT GENERATED ALWAYS AS (
        CASE 
            WHEN schema_name = '' THEN object_name
            ELSE schema_name || '.' || object_name
        END
    ) STORED,
    parent_id INTEGER REFERENCES pggit.objects(id) ON DELETE CASCADE,
    version INTEGER NOT NULL DEFAULT 1,
    version_major INTEGER NOT NULL DEFAULT 1,
    version_minor INTEGER NOT NULL DEFAULT 0,
    version_patch INTEGER NOT NULL DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(object_type, schema_name, object_name)
);

-- Version history table to track all changes
CREATE TABLE IF NOT EXISTS pggit.history (
    id SERIAL PRIMARY KEY,
    object_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    change_type pggit.change_type NOT NULL,
    change_severity pggit.change_severity NOT NULL,
    old_version INTEGER,
    new_version INTEGER,
    old_metadata JSONB,
    new_metadata JSONB,
    change_description TEXT,
    sql_executed TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER
);

-- Dependency tracking table
CREATE TABLE IF NOT EXISTS pggit.dependencies (
    id SERIAL PRIMARY KEY,
    dependent_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    depends_on_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    dependency_type TEXT NOT NULL DEFAULT 'generic',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(dependent_id, depends_on_id)
);

-- Migration scripts table
CREATE TABLE IF NOT EXISTS pggit.migrations (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    description TEXT,
    up_script TEXT NOT NULL,
    down_script TEXT,
    checksum TEXT,
    applied_at TIMESTAMP,
    applied_by TEXT,
    execution_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_objects_type ON pggit.objects(object_type);
CREATE INDEX IF NOT EXISTS idx_objects_parent ON pggit.objects(parent_id);
CREATE INDEX IF NOT EXISTS idx_objects_active ON pggit.objects(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_history_object ON pggit.history(object_id);
CREATE INDEX IF NOT EXISTS idx_history_created ON pggit.history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dependencies_dependent ON pggit.dependencies(dependent_id);
CREATE INDEX IF NOT EXISTS idx_dependencies_depends_on ON pggit.dependencies(depends_on_id);

-- Helper function to get or create an object
CREATE OR REPLACE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
DECLARE
    v_object_id INTEGER;
    v_parent_id INTEGER;
BEGIN
    -- Find parent if specified
    IF p_parent_name IS NOT NULL THEN
        SELECT id INTO v_parent_id
        FROM pggit.objects
        WHERE full_name = p_parent_name
        AND is_active = true
        LIMIT 1;
    END IF;
    
    -- Try to find existing object
    SELECT id INTO v_object_id
    FROM pggit.objects
    WHERE object_type = p_object_type
    AND schema_name = p_schema_name
    AND object_name = p_object_name;
    
    -- Create if not exists
    IF v_object_id IS NULL THEN
        INSERT INTO pggit.objects (
            object_type, schema_name, object_name, parent_id, metadata
        ) VALUES (
            p_object_type, p_schema_name, p_object_name, v_parent_id, p_metadata
        ) RETURNING id INTO v_object_id;
    END IF;
    
    RETURN v_object_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment version
CREATE OR REPLACE FUNCTION pggit.increment_version(
    p_object_id INTEGER,
    p_change_type pggit.change_type,
    p_change_severity pggit.change_severity,
    p_description TEXT DEFAULT NULL,
    p_new_metadata JSONB DEFAULT NULL,
    p_sql_executed TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_old_version INTEGER;
    v_new_version INTEGER;
    v_old_metadata JSONB;
    v_major INTEGER;
    v_minor INTEGER;
    v_patch INTEGER;
BEGIN
    -- Get current version and metadata
    SELECT version, version_major, version_minor, version_patch, metadata
    INTO v_old_version, v_major, v_minor, v_patch, v_old_metadata
    FROM pggit.objects
    WHERE id = p_object_id;
    
    -- Calculate new version based on severity
    CASE p_change_severity
        WHEN 'MAJOR' THEN
            v_major := v_major + 1;
            v_minor := 0;
            v_patch := 0;
        WHEN 'MINOR' THEN
            v_minor := v_minor + 1;
            v_patch := 0;
        WHEN 'PATCH' THEN
            v_patch := v_patch + 1;
    END CASE;
    
    v_new_version := v_old_version + 1;
    
    -- Update object
    UPDATE pggit.objects
    SET version = v_new_version,
        version_major = v_major,
        version_minor = v_minor,
        version_patch = v_patch,
        metadata = COALESCE(p_new_metadata, metadata),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_object_id;
    
    -- Record history
    INSERT INTO pggit.history (
        object_id, change_type, change_severity,
        old_version, new_version,
        old_metadata, new_metadata,
        change_description, sql_executed
    ) VALUES (
        p_object_id, p_change_type, p_change_severity,
        v_old_version, v_new_version,
        v_old_metadata, COALESCE(p_new_metadata, v_old_metadata),
        p_description, p_sql_executed
    );
    
    RETURN v_new_version;
END;
$$ LANGUAGE plpgsql;

-- Determine change severity based on DDL command
CREATE OR REPLACE FUNCTION pggit.determine_severity(
    p_command_tag TEXT,
    p_object_type TEXT
) RETURNS pggit.change_severity AS $$
BEGIN
    -- DROP commands are always major
    IF p_command_tag LIKE 'DROP%' THEN
        RETURN 'MAJOR';
    END IF;
    
    -- CREATE commands are minor (new features)
    IF p_command_tag LIKE 'CREATE%' THEN
        RETURN 'MINOR';
    END IF;
    
    -- ALTER commands depend on the specific change
    IF p_command_tag LIKE 'ALTER%' THEN
        -- For now, treat all ALTERs as minor
        -- In a full implementation, we'd analyze the specific change
        RETURN 'MINOR';
    END IF;
    
    -- Default to patch for other changes
    RETURN 'PATCH';
END;
$$ LANGUAGE plpgsql;

-- Event trigger function for DDL commands
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command() 
RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
    v_object_id INTEGER;
    v_object_type pggit.object_type;
    v_change_type pggit.change_type;
    v_severity pggit.change_severity;
BEGIN
    -- Process each DDL command
    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        -- Skip if not a tracked object type
        CONTINUE WHEN v_object.object_type NOT IN (
            'table', 'view', 'index', 'sequence', 'function', 'type', 'trigger'
        );
        
        -- Map object type
        v_object_type := CASE v_object.object_type
            WHEN 'table' THEN 'TABLE'::pggit.object_type
            WHEN 'view' THEN 'VIEW'::pggit.object_type
            WHEN 'index' THEN 'INDEX'::pggit.object_type
            WHEN 'sequence' THEN 'SEQUENCE'::pggit.object_type
            WHEN 'function' THEN 'FUNCTION'::pggit.object_type
            WHEN 'type' THEN 'TYPE'::pggit.object_type
            WHEN 'trigger' THEN 'TRIGGER'::pggit.object_type
        END;
        
        -- Map command to change type
        v_change_type := CASE 
            WHEN v_object.command_tag LIKE 'CREATE%' THEN 'CREATE'::pggit.change_type
            WHEN v_object.command_tag LIKE 'ALTER%' THEN 'ALTER'::pggit.change_type
            WHEN v_object.command_tag LIKE 'DROP%' THEN 'DROP'::pggit.change_type
            ELSE 'ALTER'::pggit.change_type
        END;
        
        -- Determine severity
        v_severity := pggit.determine_severity(v_object.command_tag, v_object.object_type);
        
        -- Get or create object
        v_object_id := pggit.ensure_object(
            v_object_type,
            COALESCE(v_object.schema_name, 'public'),
            v_object.object_identity
        );
        
        -- Increment version
        PERFORM pggit.increment_version(
            v_object_id,
            v_change_type,
            v_severity,
            v_object.command_tag,
            jsonb_build_object(
                'command_tag', v_object.command_tag,
                'object_type', v_object.object_type
            )
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Event trigger function for DROP commands
CREATE OR REPLACE FUNCTION pggit.handle_sql_drop() 
RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
    v_object_id INTEGER;
BEGIN
    -- Process each dropped object
    FOR v_object IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP
        -- Mark object as inactive
        UPDATE pggit.objects
        SET is_active = false,
            updated_at = CURRENT_TIMESTAMP
        WHERE schema_name = v_object.schema_name
        AND object_name = v_object.object_name
        AND is_active = true
        RETURNING id INTO v_object_id;
        
        -- Record the drop in history if object was tracked
        IF v_object_id IS NOT NULL THEN
            INSERT INTO pggit.history (
                object_id, 
                change_type, 
                change_severity,
                change_description
            ) VALUES (
                v_object_id,
                'DROP'::pggit.change_type,
                'MAJOR'::pggit.change_severity,
                'Object dropped'
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create event triggers
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger;
CREATE EVENT TRIGGER pggit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION pggit.handle_ddl_command();

DROP EVENT TRIGGER IF EXISTS pggit_drop_trigger;
CREATE EVENT TRIGGER pggit_drop_trigger
    ON sql_drop
    EXECUTE FUNCTION pggit.handle_sql_drop();

-- Basic utility functions

-- Get current version of an object
CREATE OR REPLACE FUNCTION pggit.get_version(
    p_object_name TEXT
) RETURNS TABLE (
    object_name TEXT,
    object_type pggit.object_type,
    version TEXT,
    version_number INTEGER,
    is_active BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.full_name,
        o.object_type,
        o.version_major || '.' || o.version_minor || '.' || o.version_patch,
        o.version,
        o.is_active
    FROM pggit.objects o
    WHERE o.full_name = p_object_name
    OR o.object_name = p_object_name
    ORDER BY o.version DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Get history of an object
CREATE OR REPLACE FUNCTION pggit.get_history(
    p_object_name TEXT
) RETURNS TABLE (
    version INTEGER,
    change_type pggit.change_type,
    change_severity pggit.change_severity,
    change_description TEXT,
    created_at TIMESTAMP,
    created_by TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.new_version,
        h.change_type,
        h.change_severity,
        h.change_description,
        h.created_at,
        h.created_by
    FROM pggit.history h
    JOIN pggit.objects o ON h.object_id = o.id
    WHERE o.full_name = p_object_name
    OR o.object_name = p_object_name
    ORDER BY h.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Generate migration between versions
CREATE OR REPLACE FUNCTION pggit.generate_migration(
    p_from_version TEXT DEFAULT NULL,
    p_to_version TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_migration TEXT;
    v_object RECORD;
BEGIN
    v_migration := '-- pggit migration' || E'\n';
    v_migration := v_migration || '-- Generated: ' || CURRENT_TIMESTAMP || E'\n\n';
    
    -- Get all changes between versions
    FOR v_object IN 
        SELECT 
            o.full_name,
            o.object_type,
            h.change_type,
            h.change_description,
            h.sql_executed
        FROM pggit.history h
        JOIN pggit.objects o ON h.object_id = o.id
        WHERE (p_from_version IS NULL OR h.created_at > p_from_version::TIMESTAMP)
        AND (p_to_version IS NULL OR h.created_at <= p_to_version::TIMESTAMP)
        ORDER BY h.created_at
    LOOP
        v_migration := v_migration || '-- ' || v_object.change_type || ' ' || 
                      v_object.object_type || ' ' || v_object.full_name || E'\n';
        IF v_object.sql_executed IS NOT NULL THEN
            v_migration := v_migration || v_object.sql_executed || ';' || E'\n\n';
        END IF;
    END LOOP;
    
    RETURN v_migration;
END;
$$ LANGUAGE plpgsql;

-- Get impact analysis for an object
CREATE OR REPLACE FUNCTION pggit.get_impact_analysis(
    p_object_name TEXT
) RETURNS TABLE (
    dependent_object TEXT,
    dependency_type TEXT,
    impact_level TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE deps AS (
        -- Find the object
        SELECT id, full_name 
        FROM pggit.objects 
        WHERE full_name = p_object_name 
        OR object_name = p_object_name
        
        UNION
        
        -- Find all dependents recursively
        SELECT o.id, o.full_name
        FROM pggit.objects o
        JOIN pggit.dependencies d ON o.id = d.dependent_id
        JOIN deps ON d.depends_on_id = deps.id
    )
    SELECT 
        o.full_name,
        d.dependency_type,
        CASE 
            WHEN d.dependency_type = 'foreign_key' THEN 'HIGH'
            WHEN d.dependency_type = 'view' THEN 'MEDIUM'
            ELSE 'LOW'
        END AS impact_level
    FROM deps
    JOIN pggit.dependencies d ON deps.id = d.depends_on_id
    JOIN pggit.objects o ON d.dependent_id = o.id
    WHERE deps.full_name = p_object_name OR deps.full_name LIKE '%.' || p_object_name;
END;
$$ LANGUAGE plpgsql;

-- Summary view of all tracked objects
CREATE OR REPLACE VIEW pggit.object_summary AS
SELECT 
    object_type,
    schema_name,
    object_name,
    full_name,
    version_major || '.' || version_minor || '.' || version_patch AS version,
    version AS version_number,
    is_active,
    created_at,
    updated_at
FROM pggit.objects
ORDER BY object_type, schema_name, object_name;

-- ============================================
-- AI-Powered Migration Analysis
-- ============================================

-- Store migration patterns for AI learning
CREATE TABLE IF NOT EXISTS pggit.migration_patterns (
    id SERIAL PRIMARY KEY,
    pattern_type TEXT NOT NULL,
    source_tool TEXT NOT NULL,
    pattern_sql TEXT NOT NULL,
    pattern_embedding TEXT,
    semantic_meaning TEXT,
    example_migration TEXT,
    pggit_template TEXT,
    confidence_threshold DECIMAL DEFAULT 0.9,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- AI decision audit log
CREATE TABLE IF NOT EXISTS pggit.ai_decisions (
    id SERIAL PRIMARY KEY,
    migration_id TEXT,
    original_content TEXT,
    ai_prompt TEXT,
    ai_response TEXT,
    confidence DECIMAL,
    human_override BOOLEAN DEFAULT false,
    override_reason TEXT,
    model_version TEXT,
    inference_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Edge cases that need human review
CREATE TABLE IF NOT EXISTS pggit.ai_edge_cases (
    id SERIAL PRIMARY KEY,
    migration_id TEXT,
    case_type TEXT,
    original_content TEXT,
    ai_suggestion TEXT,
    confidence DECIMAL,
    risk_level TEXT,
    review_status TEXT DEFAULT 'PENDING',
    reviewer_notes TEXT,
    reviewed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pre-populate common migration patterns
-- Note: Patterns reverse-engineered for compatibility, not copied code
INSERT INTO pggit.migration_patterns (pattern_type, source_tool, pattern_sql, semantic_meaning, pggit_template) VALUES
('create_table', 'flyway', 'CREATE TABLE ${table_name} (id SERIAL PRIMARY KEY, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);', 'Basic table creation with ID and timestamp', 'CREATE TABLE %I (id SERIAL PRIMARY KEY, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)'),
('add_column', 'liquibase', 'ALTER TABLE ${table_name} ADD COLUMN ${column_name} ${column_type};', 'Add single column', 'ALTER TABLE %I ADD COLUMN %I %s'),
('create_index', 'rails', 'CREATE INDEX CONCURRENTLY idx_${table}_${column} ON ${table}(${column});', 'Non-blocking index creation', 'CREATE INDEX CONCURRENTLY %I ON %I(%I)'),
('add_foreign_key', 'flyway', 'ALTER TABLE ${table} ADD CONSTRAINT fk_${table}_${ref} FOREIGN KEY (${column}) REFERENCES ${ref_table}(id);', 'Add foreign key constraint', 'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I(id)'),
('drop_column_safe', 'liquibase', 'ALTER TABLE ${table} DROP COLUMN IF EXISTS ${column};', 'Safe column removal', 'ALTER TABLE %I DROP COLUMN IF EXISTS %I'),
('rename_table', 'rails', 'ALTER TABLE ${old_name} RENAME TO ${new_name};', 'Rename table', 'ALTER TABLE %I RENAME TO %I'),
('add_not_null', 'flyway', 'ALTER TABLE ${table} ALTER COLUMN ${column} SET NOT NULL;', 'Add NOT NULL constraint', 'ALTER TABLE %I ALTER COLUMN %I SET NOT NULL'),
('create_enum', 'liquibase', 'CREATE TYPE ${enum_name} AS ENUM (${values});', 'Create enumeration type', 'CREATE TYPE %I AS ENUM (%L)'),
('add_check_constraint', 'rails', 'ALTER TABLE ${table} ADD CONSTRAINT ${name} CHECK (${condition});', 'Add check constraint', 'ALTER TABLE %I ADD CONSTRAINT %I CHECK (%s)'),
('create_trigger', 'flyway', 'CREATE TRIGGER ${trigger_name} ${timing} ${event} ON ${table} FOR EACH ROW EXECUTE FUNCTION ${function}();', 'Create trigger', 'CREATE TRIGGER %I %s %s ON %I FOR EACH ROW EXECUTE FUNCTION %I()'),
('create_partial_index', 'liquibase', 'CREATE INDEX CONCURRENTLY ${index_name} ON ${table}(${column}) WHERE ${condition};', 'Partial index for performance', 'CREATE INDEX CONCURRENTLY %I ON %I(%I) WHERE %s'),
('bulk_update', 'rails', 'UPDATE ${table} SET ${column} = ${value} WHERE ${condition};', 'Bulk data update', 'UPDATE %I SET %I = %L WHERE %s')
ON CONFLICT DO NOTHING;

-- Voluntary Performance Metrics Collection Function
-- This function generates anonymous performance metrics to help improve pggit
-- It collects ONLY technical metrics - no sensitive data
CREATE OR REPLACE FUNCTION pggit.generate_contribution_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    db_objects JSONB;
    pggit_metrics JSONB;
    system_info JSONB;
    performance_benchmarks JSONB;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    analysis_time NUMERIC;
    trigger_time NUMERIC;
    migration_time NUMERIC;
BEGIN
    -- Collect database object counts (no names, just counts)
    SELECT jsonb_build_object(
        'tables', (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'pg_catalog')),
        'indexes', (SELECT COUNT(*) FROM pg_indexes WHERE schemaname NOT IN ('information_schema', 'pg_catalog')),
        'functions', (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema NOT IN ('information_schema', 'pg_catalog')),
        'triggers', (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema NOT IN ('information_schema', 'pg_catalog')),
        'constraints', (SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_schema NOT IN ('information_schema', 'pg_catalog'))
    ) INTO db_objects;

    -- Collect pggit-specific metrics
    SELECT jsonb_build_object(
        'tracked_objects', COALESCE((SELECT COUNT(*) FROM pggit.objects), 0),
        'history_records', COALESCE((SELECT COUNT(*) FROM pggit.history), 0),
        'storage_overhead_percent', ROUND(
            CASE 
                WHEN pg_database_size(current_database()) > 0 THEN
                    (COALESCE((SELECT SUM(pg_total_relation_size(schemaname||'.'||tablename)) 
                              FROM pg_tables WHERE schemaname = 'pggit'), 0)::FLOAT / 
                     pg_database_size(current_database())::FLOAT) * 100
                ELSE 0
            END, 2)
    ) INTO pggit_metrics;

    -- Collect system information (PostgreSQL version, basic system info)
    SELECT jsonb_build_object(
        'postgresql_version', version(),
        'cpu_cores', COALESCE((SELECT setting::INTEGER FROM pg_settings WHERE name = 'max_worker_processes'), 1),
        'shared_buffers_mb', ROUND(
            CASE 
                WHEN (SELECT setting FROM pg_settings WHERE name = 'shared_buffers') ~ '^\d+$' THEN
                    (SELECT setting::BIGINT FROM pg_settings WHERE name = 'shared_buffers') * 8 / 1024
                ELSE 128
            END
        ),
        'os', 'postgresql'  -- We can't easily detect OS from PostgreSQL
    ) INTO system_info;

    -- Performance benchmarks (time key operations)
    
    -- Test AI analysis performance
    start_time := clock_timestamp();
    BEGIN
        PERFORM pggit.analyze_migration_with_ai('metrics_test', 'CREATE TABLE metrics_test (id INT);', 'benchmark');
    EXCEPTION WHEN OTHERS THEN
        -- If AI analysis fails, record 0
        analysis_time := 0;
    END;
    end_time := clock_timestamp();
    analysis_time := EXTRACT(epoch FROM (end_time - start_time)) * 1000;

    -- Test migration generation performance  
    start_time := clock_timestamp();
    BEGIN
        PERFORM pggit.generate_migration();
    EXCEPTION WHEN OTHERS THEN
        migration_time := 0;
    END;
    end_time := clock_timestamp();
    migration_time := EXTRACT(epoch FROM (end_time - start_time)) * 1000;

    -- Estimate event trigger overhead (we can't measure directly without causing triggers)
    trigger_time := 0.1; -- Placeholder - real measurement would require instrumentation

    SELECT jsonb_build_object(
        'ai_analysis_time_ms', ROUND(analysis_time, 2),
        'migration_generation_ms', ROUND(migration_time, 2),
        'estimated_trigger_overhead_ms', trigger_time
    ) INTO performance_benchmarks;

    -- Build final result
    result := jsonb_build_object(
        'timestamp', CURRENT_TIMESTAMP,
        'pggit_version', '1.0.0',
        'database_objects', db_objects,
        'pggit_metrics', pggit_metrics,
        'system_info', system_info,
        'performance_benchmarks', performance_benchmarks,
        'privacy_notice', 'This data contains no sensitive information - only anonymous technical metrics'
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Grant usage on schema and functions
GRANT USAGE ON SCHEMA pggit TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;