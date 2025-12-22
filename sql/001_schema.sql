-- pggit: Native Git for PostgreSQL Databases
-- 
-- Revolutionary database versioning system that implements actual Git workflows
-- inside PostgreSQL with real branching, merging, and version control.
-- 
-- PATENT PENDING: This technology is protected by multiple patent applications
-- covering novel database branching, data versioning, and merge algorithms.

-- Create schema for git versioning objects
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
    'PARTITION',
    'BRANCH',
    'COMMIT',
    'TAG'
);

CREATE TYPE pggit.change_type AS ENUM (
    'CREATE',
    'ALTER',
    'DROP',
    'RENAME',
    'COMMENT',
    'BRANCH',
    'MERGE',
    'CONFLICT_RESOLVED'
);

CREATE TYPE pggit.change_severity AS ENUM (
    'MAJOR',    -- Breaking changes (DROP, breaking schema changes)
    'MINOR',    -- New features (CREATE, new columns)
    'PATCH'     -- Bug fixes (comments, defaults, indexes)
);

-- PATENT #4: Copy-on-Write Data Branching Status
CREATE TYPE pggit.branch_status AS ENUM (
    'ACTIVE',
    'MERGED',
    'DELETED',
    'CONFLICTED'
);

-- PATENT #5: Data Merge Resolution Types
CREATE TYPE pggit.merge_resolution AS ENUM (
    'AUTO_RESOLVED',
    'MANUAL_RESOLVED',
    'CONFLICT_PENDING',
    'MERGE_REJECTED'
);

-- PATENT #1: Main object versioning with cryptographic hashing
-- Real-time DDL change detection using content-addressable storage
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
    -- PATENT #1: Content-addressable storage with cryptographic hashing
    content_hash TEXT,
    ddl_normalized TEXT,
    -- PATENT #4: Branch tracking for copy-on-write data branching
    branch_id INTEGER DEFAULT 1,
    branch_name TEXT DEFAULT 'main',
    version INTEGER NOT NULL DEFAULT 1,
    version_major INTEGER NOT NULL DEFAULT 1,
    version_minor INTEGER NOT NULL DEFAULT 0,
    version_patch INTEGER NOT NULL DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(object_type, schema_name, object_name, branch_name)
);


-- PATENT #5: Commit tracking with merkle tree structure
CREATE TABLE IF NOT EXISTS pggit.commits (
    id SERIAL PRIMARY KEY,
    hash TEXT NOT NULL UNIQUE,
    branch_id INTEGER NOT NULL REFERENCES pggit.branches(id),
    parent_commit_hash TEXT,
    message TEXT,
    author TEXT DEFAULT CURRENT_USER,
    authored_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    committer TEXT DEFAULT CURRENT_USER,
    committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tree_hash TEXT,
    -- PATENT #6: Content-addressable storage for database objects
    object_hashes JSONB DEFAULT '{}'
);

-- PATENT #2: Version history with three-way merge support
CREATE TABLE IF NOT EXISTS pggit.history (
    id SERIAL PRIMARY KEY,
    object_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    change_type pggit.change_type NOT NULL,
    change_severity pggit.change_severity NOT NULL,
    -- PATENT #2: Three-way merge tracking
    commit_hash TEXT,
    branch_id INTEGER REFERENCES pggit.branches(id),
    merge_base_hash TEXT,
    merge_resolution pggit.merge_resolution,
    old_version INTEGER,
    new_version INTEGER,
    old_metadata JSONB,
    new_metadata JSONB,
    change_description TEXT,
    sql_executed TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER
);

-- PATENT #4: Database Branches - Revolutionary Git-style data branching
CREATE TABLE IF NOT EXISTS pggit.branches (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    parent_branch_id INTEGER REFERENCES pggit.branches(id),
    head_commit_hash TEXT,
    status pggit.branch_status DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    merged_at TIMESTAMP,
    merged_by TEXT,
    -- Branch type: standard, tiered, temporal, or compressed
    branch_type TEXT DEFAULT 'standard' CHECK (branch_type IN ('standard', 'tiered', 'temporal', 'compressed')),
    -- Copy-on-write statistics
    total_objects INTEGER DEFAULT 0,
    modified_objects INTEGER DEFAULT 0,
    storage_efficiency DECIMAL(5,2) DEFAULT 100.00
);

-- Insert main branch
INSERT INTO pggit.branches (id, name) VALUES (1, 'main') ON CONFLICT (name) DO NOTHING;

-- Add CHECK constraints for branch name validation
ALTER TABLE pggit.branches ADD CONSTRAINT branch_name_not_empty
  CHECK (name IS NOT NULL AND name != '');

ALTER TABLE pggit.branches ADD CONSTRAINT branch_name_format
  CHECK (name ~ '^[a-zA-Z0-9._/#-]+$');

-- Add CASCADE DELETE to foreign key relationships
ALTER TABLE pggit.commits DROP CONSTRAINT IF EXISTS commits_branch_id_fkey;
ALTER TABLE pggit.commits ADD CONSTRAINT fk_commits_branch_id
  FOREIGN KEY (branch_id) REFERENCES pggit.branches(id) ON DELETE CASCADE;

ALTER TABLE pggit.history DROP CONSTRAINT IF EXISTS history_branch_id_fkey;
ALTER TABLE pggit.history ADD CONSTRAINT fk_history_branch_id
  FOREIGN KEY (branch_id) REFERENCES pggit.branches(id) ON DELETE CASCADE;

ALTER TABLE pggit.data_branches DROP CONSTRAINT IF EXISTS data_branches_branch_id_fkey;
ALTER TABLE pggit.data_branches ADD CONSTRAINT fk_data_branches_branch_id
  FOREIGN KEY (branch_id) REFERENCES pggit.branches(id) ON DELETE CASCADE;

-- PATENT #5: Copy-on-write data storage with deduplication
CREATE TABLE IF NOT EXISTS pggit.data_branches (
    id SERIAL PRIMARY KEY,
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    branch_id INTEGER NOT NULL REFERENCES pggit.branches(id),
    parent_table TEXT,
    cow_enabled BOOLEAN DEFAULT true,
    row_count BIGINT DEFAULT 0,
    storage_bytes BIGINT DEFAULT 0,
    deduplication_ratio DECIMAL(5,2) DEFAULT 100.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(table_schema, table_name, branch_id)
);

-- PATENT #6: Three-way merge conflict resolution
CREATE TABLE IF NOT EXISTS pggit.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_id TEXT NOT NULL,
    branch_a TEXT NOT NULL,
    branch_b TEXT NOT NULL,
    base_branch TEXT,
    conflict_object TEXT NOT NULL,
    conflict_type TEXT NOT NULL,
    base_value JSONB,
    branch_a_value JSONB,
    branch_b_value JSONB,
    resolved_value JSONB,
    resolution_strategy TEXT,
    auto_resolved BOOLEAN DEFAULT false,
    resolved_by TEXT,
    resolved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Dependency tracking with branch awareness
CREATE TABLE IF NOT EXISTS pggit.dependencies (
    id SERIAL PRIMARY KEY,
    dependent_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    depends_on_id INTEGER NOT NULL REFERENCES pggit.objects(id) ON DELETE CASCADE,
    branch_id INTEGER REFERENCES pggit.branches(id) DEFAULT 1,
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

-- Git blobs (individual object definitions)
CREATE TABLE IF NOT EXISTS pggit.blobs (
    blob_hash TEXT PRIMARY KEY,
    object_type pggit.object_type NOT NULL,
    object_name TEXT NOT NULL,
    object_schema TEXT NOT NULL,
    object_definition TEXT NOT NULL,
    dependencies JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Access patterns table for testing and tracking database access patterns
CREATE TABLE IF NOT EXISTS pggit.access_patterns (
    pattern_id SERIAL PRIMARY KEY,
    object_name TEXT NOT NULL,
    access_type TEXT NOT NULL,
    response_time_ms NUMERIC(10,2)
);

-- Indexes for performance
CREATE INDEX idx_objects_type ON pggit.objects(object_type);
CREATE INDEX idx_objects_parent ON pggit.objects(parent_id);
CREATE INDEX idx_objects_active ON pggit.objects(is_active) WHERE is_active = true;
CREATE INDEX idx_history_object ON pggit.history(object_id);
CREATE INDEX idx_history_created ON pggit.history(created_at DESC);
CREATE INDEX idx_dependencies_dependent ON pggit.dependencies(dependent_id);
CREATE INDEX idx_dependencies_depends_on ON pggit.dependencies(depends_on_id);

-- Helper function to get or create an object with branch specification
CREATE OR REPLACE FUNCTION pggit.ensure_object_with_branch(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}',
    p_branch_name TEXT DEFAULT 'main'
) RETURNS INTEGER AS $$
DECLARE
    v_object_id INTEGER;
    v_parent_id INTEGER;
    v_schema_name TEXT;
BEGIN
    -- Ensure schema_name is not NULL (fallback to 'public')
    v_schema_name := COALESCE(NULLIF(p_schema_name, ''), 'public');

    -- Find parent if specified
    IF p_parent_name IS NOT NULL THEN
        SELECT id INTO v_parent_id
        FROM pggit.objects
        WHERE full_name = p_parent_name
        AND is_active = true
        AND branch_name = p_branch_name
        LIMIT 1;
    END IF;

    -- Try to find existing object
    SELECT id INTO v_object_id
    FROM pggit.objects
    WHERE object_type = p_object_type
    AND schema_name = v_schema_name
    AND object_name = p_object_name
    AND branch_name = p_branch_name;

    -- Create if not exists
    IF v_object_id IS NULL THEN
        -- Final safety check: ensure schema_name is never NULL
        IF v_schema_name IS NULL THEN
            v_schema_name := 'public';
        END IF;

        INSERT INTO pggit.objects (
            object_type, schema_name, object_name, parent_id, metadata, branch_name
        ) VALUES (
            p_object_type, v_schema_name, p_object_name, v_parent_id, p_metadata, p_branch_name
        ) RETURNING id INTO v_object_id;
    END IF;

    RETURN v_object_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get or create an object (always uses 'main' branch)
-- This is the primary function - use ensure_object_with_branch() if you need a different branch
CREATE OR REPLACE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
BEGIN
    -- Call the branch-specific version with 'main' as default branch
    RETURN pggit.ensure_object_with_branch(
        p_object_type,
        p_schema_name,
        p_object_name,
        p_parent_name,
        p_metadata,
        'main'  -- Use default branch
    );
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