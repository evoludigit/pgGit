-- pgGit v0.0.1 - Phase 1: Bootstrap Data
-- Initialize main branch and system state
-- Date: 2025-12-24

-- This script initializes the pgGit system after schema is created
-- It should be run once per installation

-- 1. Ensure main branch exists and is active
INSERT INTO pggit.branches (
    branch_name,
    status,
    branch_type,
    created_by,
    parent_branch_id,
    head_commit_hash,
    object_count,
    modified_objects
) VALUES (
    'main',
    'ACTIVE',
    'schema-only',
    'system',
    NULL,
    NULL,
    0,
    0
)
ON CONFLICT (branch_name) DO UPDATE
SET status = 'ACTIVE'
WHERE pggit.branches.status IN ('DELETED', 'MERGED');

-- 2. Create initial system commit (root commit for main branch)
-- This represents the initial state before any changes
INSERT INTO pggit.commits (
    commit_hash,
    parent_commit_hash,
    branch_id,
    object_changes,
    tree_hash,
    author_name,
    author_time,
    commit_message,
    created_at
) SELECT
    pggit.generate_sha256('initial_commit_main_branch'),
    NULL,
    b.branch_id,
    '{}'::jsonb,
    pggit.generate_sha256(''),
    'system',
    CURRENT_TIMESTAMP,
    'Initial commit - system bootstrap',
    CURRENT_TIMESTAMP
FROM pggit.branches b
WHERE b.branch_name = 'main'
  AND NOT EXISTS (
    SELECT 1 FROM pggit.commits c WHERE c.branch_id = b.branch_id
  );

-- 3. Update main branch to point to initial commit
UPDATE pggit.branches
SET head_commit_hash = (
    SELECT commit_hash FROM pggit.commits
    WHERE branch_id = (SELECT branch_id FROM pggit.branches WHERE branch_name = 'main')
    AND commit_message = 'Initial commit - system bootstrap'
    LIMIT 1
)
WHERE branch_name = 'main'
  AND head_commit_hash IS NULL;

-- 4. Configuration defaults (already set in schema creation, but ensure they exist)
INSERT INTO pggit.configuration (config_key, config_value, description)
VALUES
    ('track_ddl', '{"enabled": true}'::jsonb, 'Track DDL changes'),
    ('track_data', '{"enabled": false}'::jsonb, 'Track data changes'),
    ('ignore_schemas', '["pg_catalog", "information_schema"]'::jsonb, 'Schemas to ignore'),
    ('ignore_objects', '[]'::jsonb, 'Object name patterns to ignore'),
    ('cqrs_enabled', '{"enabled": false}'::jsonb, 'CQRS mode'),
    ('auto_version_tracking', '"auto"'::jsonb, 'Auto or manual versioning')
ON CONFLICT (config_key) DO NOTHING;

-- 5. Initialize schema_objects with pggit system tables themselves
-- This captures the bootstrap state
INSERT INTO pggit.schema_objects (
    object_type,
    schema_name,
    object_name,
    current_definition,
    content_hash,
    version_major,
    version_minor,
    version_patch,
    is_active,
    first_seen_commit_hash,
    last_modified_commit_hash,
    created_at,
    last_modified_at
) VALUES
    ('TABLE', 'pggit', 'schema_objects',
     'Core table tracking schema objects', pggit.generate_sha256('pggit.schema_objects'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'commits',
     'Git-like commit history', pggit.generate_sha256('pggit.commits'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'branches',
     'Development branches', pggit.generate_sha256('pggit.branches'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'object_history',
     'Audit trail of changes', pggit.generate_sha256('pggit.object_history'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'merge_operations',
     'Merge tracking', pggit.generate_sha256('pggit.merge_operations'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'object_dependencies',
     'Dependency graph', pggit.generate_sha256('pggit.object_dependencies'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'data_tables',
     'Copy-on-write table tracking', pggit.generate_sha256('pggit.data_tables'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('TABLE', 'pggit', 'configuration',
     'System configuration', pggit.generate_sha256('pggit.configuration'),
     1, 0, 0, true, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (object_type, schema_name, object_name) DO NOTHING;

-- 6. Set default session variable for current branch
-- Note: This needs to be set per session, typically in application startup
-- SET pggit.current_branch = 'main';

-- 7. Verify bootstrap was successful
SELECT 'Bootstrap verification:' as status;
SELECT format('  Main branch exists: %s', EXISTS(SELECT 1 FROM pggit.branches WHERE branch_name = 'main')) as result;
SELECT format('  Initial commit exists: %s', EXISTS(SELECT 1 FROM pggit.commits WHERE parent_commit_hash IS NULL)) as result;
SELECT format('  Configuration initialized: %s', (SELECT count(*) FROM pggit.configuration) >= 6) as result;
SELECT format('  pggit tables registered: %s', (SELECT count(*) FROM pggit.schema_objects WHERE schema_name = 'pggit') = 8) as result;
SELECT format('  Total objects tracked: %s', (SELECT count(*) FROM pggit.schema_objects)) as result;
