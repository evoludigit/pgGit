-- pggit Database Versioning Extension
-- 
-- This creates a complete database versioning system using only PostgreSQL
-- features: tables, functions, triggers, and event triggers.

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create schema for versioning objects
CREATE SCHEMA IF NOT EXISTS pggit;

-- Enum types
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
    'SEQUENCE',
    'PARTITION'
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

-- Main versioning table
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

-- Version history table
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

-- Indexes for performance
CREATE INDEX idx_objects_type ON pggit.objects(object_type);
CREATE INDEX idx_objects_parent ON pggit.objects(parent_id);
CREATE INDEX idx_objects_active ON pggit.objects(is_active) WHERE is_active = true;
CREATE INDEX idx_history_object ON pggit.history(object_id);
CREATE INDEX idx_history_created ON pggit.history(created_at DESC);
CREATE INDEX idx_dependencies_dependent ON pggit.dependencies(dependent_id);
CREATE INDEX idx_dependencies_depends_on ON pggit.dependencies(depends_on_id);

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
    
    -- Record in history
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

-- Function to add dependency
CREATE OR REPLACE FUNCTION pggit.add_dependency(
    p_dependent_name TEXT,
    p_depends_on_name TEXT,
    p_dependency_type TEXT DEFAULT 'generic'
) RETURNS VOID AS $$
DECLARE
    v_dependent_id INTEGER;
    v_depends_on_id INTEGER;
BEGIN
    -- Get object IDs
    SELECT id INTO v_dependent_id
    FROM pggit.objects
    WHERE full_name = p_dependent_name AND is_active = true;
    
    SELECT id INTO v_depends_on_id
    FROM pggit.objects
    WHERE full_name = p_depends_on_name AND is_active = true;
    
    IF v_dependent_id IS NULL OR v_depends_on_id IS NULL THEN
        RAISE EXCEPTION 'One or both objects not found: % -> %', 
            p_dependent_name, p_depends_on_name;
    END IF;
    
    -- Insert dependency
    INSERT INTO pggit.dependencies (
        dependent_id, depends_on_id, dependency_type
    ) VALUES (
        v_dependent_id, v_depends_on_id, p_dependency_type
    ) ON CONFLICT (dependent_id, depends_on_id) DO UPDATE
    SET dependency_type = EXCLUDED.dependency_type;
END;
$$ LANGUAGE plpgsql;

-- Function to get object version
CREATE OR REPLACE FUNCTION pggit.get_version(
    p_object_name TEXT
) RETURNS TABLE (
    object_type pggit.object_type,
    full_name TEXT,
    version INTEGER,
    version_string TEXT,
    metadata JSONB,
    updated_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.object_type,
        o.full_name,
        o.version,
        o.version_major || '.' || o.version_minor || '.' || o.version_patch AS version_string,
        o.metadata,
        o.updated_at
    FROM pggit.objects o
    WHERE o.full_name = p_object_name
    AND o.is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Function to get version history
CREATE OR REPLACE FUNCTION pggit.get_history(
    p_object_name TEXT,
    p_limit INTEGER DEFAULT 10
) RETURNS TABLE (
    change_type pggit.change_type,
    change_severity pggit.change_severity,
    old_version INTEGER,
    new_version INTEGER,
    change_description TEXT,
    created_at TIMESTAMP,
    created_by TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.change_type,
        h.change_severity,
        h.old_version,
        h.new_version,
        h.change_description,
        h.created_at,
        h.created_by
    FROM pggit.history h
    JOIN pggit.objects o ON h.object_id = o.id
    WHERE o.full_name = p_object_name
    ORDER BY h.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to check for circular dependencies
CREATE OR REPLACE FUNCTION pggit.has_circular_dependency(
    p_object_id INTEGER,
    p_visited INTEGER[] DEFAULT ARRAY[]::INTEGER[]
) RETURNS BOOLEAN AS $$
DECLARE
    v_dependency RECORD;
BEGIN
    -- Check if we've already visited this object (circular reference)
    IF p_object_id = ANY(p_visited) THEN
        RETURN TRUE;
    END IF;
    
    -- Add current object to visited array
    p_visited := array_append(p_visited, p_object_id);
    
    -- Check all dependencies recursively
    FOR v_dependency IN 
        SELECT depends_on_id 
        FROM pggit.dependencies 
        WHERE dependent_id = p_object_id
    LOOP
        IF pggit.has_circular_dependency(v_dependency.depends_on_id, p_visited) THEN
            RETURN TRUE;
        END IF;
    END LOOP;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Function to get objects in dependency order (topological sort)
CREATE OR REPLACE FUNCTION pggit.get_dependency_order(
    p_object_ids INTEGER[]
) RETURNS INTEGER[] AS $$
DECLARE
    v_result INTEGER[] := ARRAY[]::INTEGER[];
    v_remaining INTEGER[] := p_object_ids;
    v_added BOOLEAN;
    v_object_id INTEGER;
    v_has_unmet_dep BOOLEAN;
BEGIN
    WHILE array_length(v_remaining, 1) > 0 LOOP
        v_added := FALSE;
        
        -- Try to find an object with no unmet dependencies
        FOR i IN 1..array_length(v_remaining, 1) LOOP
            v_object_id := v_remaining[i];
            
            -- Check if all dependencies are already in result
            SELECT EXISTS (
                SELECT 1 
                FROM pggit.dependencies d
                WHERE d.dependent_id = v_object_id
                AND d.depends_on_id = ANY(p_object_ids)
                AND NOT (d.depends_on_id = ANY(v_result))
            ) INTO v_has_unmet_dep;
            
            IF NOT v_has_unmet_dep THEN
                -- Add to result and remove from remaining
                v_result := array_append(v_result, v_object_id);
                v_remaining := array_remove(v_remaining, v_object_id);
                v_added := TRUE;
                EXIT;
            END IF;
        END LOOP;
        
        -- If no object could be added, there's a circular dependency
        IF NOT v_added THEN
            RAISE EXCEPTION 'Circular dependency detected';
        END IF;
    END LOOP;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;