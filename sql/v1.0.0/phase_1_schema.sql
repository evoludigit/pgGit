-- pgGit v0.0.1 - Phase 1: Foundation Schema
-- Complete DDL for all 8 core tables with indexes
-- Date: 2025-12-24

-- Create pggit schema
CREATE SCHEMA IF NOT EXISTS pggit;

-- 1. Schema Objects
-- Core table tracking individual schema objects (tables, views, functions, etc.)
CREATE TABLE pggit.schema_objects (
    object_id BIGSERIAL PRIMARY KEY,
    object_type TEXT NOT NULL,
    schema_name TEXT NOT NULL,
    object_name TEXT NOT NULL,
    current_definition TEXT NOT NULL,
    content_hash CHAR(64) NOT NULL,
    version_major INT DEFAULT 1,
    version_minor INT DEFAULT 0,
    version_patch INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    first_seen_commit_hash CHAR(64),
    last_modified_commit_hash CHAR(64),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_modified_at TIMESTAMP,
    UNIQUE (object_type, schema_name, object_name),
    CHECK (object_type IN (
        'TABLE', 'VIEW', 'FUNCTION', 'PROCEDURE',
        'INDEX', 'CONSTRAINT', 'TRIGGER', 'SEQUENCE',
        'DOMAIN', 'TYPE', 'OPERATOR', 'CAST',
        'EXTENSION', 'SCHEMA', 'AGGREGATE'
    ))
);

CREATE INDEX idx_schema_objects_content_hash ON pggit.schema_objects(content_hash);
CREATE INDEX idx_schema_objects_type_name ON pggit.schema_objects(object_type, schema_name, object_name);
CREATE INDEX idx_schema_objects_is_active ON pggit.schema_objects(is_active);

-- 2. Commits
-- Git-like commit history - immutable record of all state changes
CREATE TABLE pggit.commits (
    commit_id BIGSERIAL PRIMARY KEY,
    commit_hash CHAR(64) UNIQUE NOT NULL,
    parent_commit_hash CHAR(64),
    branch_id INTEGER,
    object_changes JSONB NOT NULL,
    tree_hash CHAR(64),
    author_name TEXT NOT NULL,
    author_time TIMESTAMP NOT NULL,
    commit_message TEXT NOT NULL,
    committer_name TEXT,
    committer_time TIMESTAMP,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (commit_hash),
    CHECK (commit_hash IS NOT NULL)
);

CREATE INDEX idx_commits_parent_hash ON pggit.commits(parent_commit_hash);
CREATE INDEX idx_commits_branch_time ON pggit.commits(branch_id, author_time DESC);
CREATE INDEX idx_commits_author ON pggit.commits(author_name, author_time);

-- 3. Branches
-- Development branches - isolated development environments
CREATE TABLE pggit.branches (
    branch_id SERIAL PRIMARY KEY,
    branch_name TEXT UNIQUE NOT NULL,
    parent_branch_id INTEGER REFERENCES pggit.branches(branch_id),
    head_commit_hash CHAR(64),
    status TEXT DEFAULT 'ACTIVE',
    branch_type TEXT DEFAULT 'schema-only',
    description TEXT,
    metadata JSONB,
    object_count INTEGER DEFAULT 0,
    modified_objects INTEGER DEFAULT 0,
    storage_bytes BIGINT DEFAULT 0,
    deduplication_ratio NUMERIC(5,2) DEFAULT 100.00,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    merged_by TEXT,
    merged_at TIMESTAMP,
    UNIQUE (branch_name),
    CHECK (status IN ('ACTIVE', 'MERGED', 'DELETED', 'CONFLICTED', 'STALE')),
    CHECK (branch_type IN ('schema-only', 'full', 'temporal', 'compressed'))
);

CREATE INDEX idx_branches_parent_id ON pggit.branches(parent_branch_id);
CREATE INDEX idx_branches_status ON pggit.branches(status);
CREATE INDEX idx_branches_created_at ON pggit.branches(created_at DESC);

-- Add FK from commits to branches now
ALTER TABLE pggit.commits
    ADD FOREIGN KEY (branch_id) REFERENCES pggit.branches(branch_id),
    ADD FOREIGN KEY (parent_commit_hash) REFERENCES pggit.commits(commit_hash)
        DEFERRABLE INITIALLY DEFERRED;

-- Add FK from branches to commits
ALTER TABLE pggit.branches
    ADD FOREIGN KEY (head_commit_hash) REFERENCES pggit.commits(commit_hash);

-- 4. Object History
-- Complete immutable audit trail of all changes to any object
CREATE TABLE pggit.object_history (
    history_id BIGSERIAL PRIMARY KEY,
    object_id BIGINT NOT NULL REFERENCES pggit.schema_objects(object_id),
    change_type TEXT NOT NULL,
    change_severity TEXT,
    before_hash CHAR(64),
    after_hash CHAR(64),
    before_version TEXT,
    after_version TEXT,
    before_definition TEXT,
    after_definition TEXT,
    commit_hash CHAR(64) NOT NULL REFERENCES pggit.commits(commit_hash),
    branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    change_reason TEXT,
    change_metadata JSONB,
    author_name TEXT NOT NULL,
    author_time TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (change_type IN ('CREATE', 'ALTER', 'DROP', 'RENAME', 'REBUILD')),
    CHECK (change_severity IN ('MAJOR', 'MINOR', 'PATCH'))
);

CREATE INDEX idx_object_history_object_time ON pggit.object_history(object_id, author_time DESC);
CREATE INDEX idx_object_history_author ON pggit.object_history(author_name, author_time DESC);
CREATE INDEX idx_object_history_change_type ON pggit.object_history(change_type);
CREATE INDEX idx_object_history_branch ON pggit.object_history(branch_id, author_time DESC);

-- 5. Merge Operations
-- Tracks all merge attempts and outcomes
CREATE TABLE pggit.merge_operations (
    merge_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    target_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    merge_base_branch_id INTEGER REFERENCES pggit.branches(branch_id),
    merge_strategy TEXT NOT NULL,
    status TEXT NOT NULL,
    conflicts_detected INTEGER DEFAULT 0,
    conflicts_resolved INTEGER DEFAULT 0,
    objects_merged INTEGER DEFAULT 0,
    conflict_details JSONB,
    resolution_summary JSONB,
    result_commit_hash CHAR(64) REFERENCES pggit.commits(commit_hash),
    merge_message TEXT,
    merged_by TEXT NOT NULL,
    merged_at TIMESTAMP NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (status IN ('SUCCESS', 'CONFLICT', 'ABORTED', 'ERROR')),
    CHECK (source_branch_id != target_branch_id),
    CHECK (merge_strategy IN ('TARGET_WINS', 'SOURCE_WINS', 'UNION', 'MANUAL_REVIEW', 'ABORT_ON_CONFLICT'))
);

CREATE INDEX idx_merge_operations_status ON pggit.merge_operations(status);
CREATE INDEX idx_merge_operations_branches ON pggit.merge_operations(source_branch_id, target_branch_id);
CREATE INDEX idx_merge_operations_merged_at ON pggit.merge_operations(merged_at DESC);

-- 6. Object Dependencies
-- Dependency graph for detecting breaking changes
CREATE TABLE pggit.object_dependencies (
    dependency_id SERIAL PRIMARY KEY,
    dependent_object_id BIGINT NOT NULL REFERENCES pggit.schema_objects(object_id),
    depends_on_object_id BIGINT NOT NULL REFERENCES pggit.schema_objects(object_id),
    dependency_type TEXT NOT NULL,
    branch_id INTEGER REFERENCES pggit.branches(branch_id),
    discovered_at_commit CHAR(64) REFERENCES pggit.commits(commit_hash),
    metadata JSONB,
    UNIQUE (dependent_object_id, depends_on_object_id, dependency_type),
    CHECK (dependent_object_id != depends_on_object_id),
    CHECK (dependency_type IN (
        'FOREIGN_KEY', 'REFERENCES', 'CALLS', 'INHERITS',
        'USES', 'COMPOSED_OF', 'INDEXES', 'TRIGGERS_ON'
    ))
);

CREATE INDEX idx_dependencies_dependent ON pggit.object_dependencies(dependent_object_id);
CREATE INDEX idx_dependencies_depends_on ON pggit.object_dependencies(depends_on_object_id);
CREATE INDEX idx_dependencies_type ON pggit.object_dependencies(dependency_type);

-- 7. Data Tables
-- Tracks tables that have copy-on-write data branching enabled
CREATE TABLE pggit.data_tables (
    data_table_id SERIAL PRIMARY KEY,
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id),
    parent_branch_id INTEGER REFERENCES pggit.branches(branch_id),
    uses_cow BOOLEAN DEFAULT true,
    row_count BIGINT DEFAULT 0,
    storage_bytes BIGINT DEFAULT 0,
    storage_efficiency_percent NUMERIC(5,2) DEFAULT 100.00,
    shared_rows BIGINT DEFAULT 0,
    unique_rows BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_synced_at TIMESTAMP,
    UNIQUE (table_schema, table_name, branch_id)
);

CREATE INDEX idx_data_tables_branch ON pggit.data_tables(branch_id);
CREATE INDEX idx_data_tables_storage ON pggit.data_tables(storage_bytes DESC);

-- 8. Configuration
-- System configuration for tracking behavior
CREATE TABLE pggit.configuration (
    config_id SERIAL PRIMARY KEY,
    config_key TEXT UNIQUE NOT NULL,
    config_value JSONB NOT NULL,
    description TEXT,
    modified_by TEXT,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Bootstrap configuration
INSERT INTO pggit.configuration (config_key, config_value, description) VALUES
    ('track_ddl', '{"enabled": true}'::jsonb, 'Track DDL changes'),
    ('track_data', '{"enabled": false}'::jsonb, 'Track data changes'),
    ('ignore_schemas', '["pg_catalog", "information_schema"]'::jsonb, 'Schemas to ignore'),
    ('ignore_objects', '[]'::jsonb, 'Object name patterns to ignore'),
    ('cqrs_enabled', '{"enabled": false}'::jsonb, 'CQRS mode'),
    ('auto_version_tracking', '"auto"'::jsonb, 'Auto or manual versioning');

-- Bootstrap main branch
INSERT INTO pggit.branches (branch_name, status, branch_type, created_by, parent_branch_id, head_commit_hash)
VALUES ('main', 'ACTIVE', 'schema-only', 'system', NULL, NULL)
ON CONFLICT DO NOTHING;

-- Grant permissions
GRANT USAGE ON SCHEMA pggit TO public;
GRANT SELECT ON ALL TABLES IN SCHEMA pggit TO public;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO public;
