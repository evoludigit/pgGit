-- pgTAP unit tests: data model (Phase 1)
-- Tests: schemas, enum types, tables, indexes, bootstrap

BEGIN;
SELECT plan(47);

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------

SELECT has_schema('pggit',          'pggit schema exists');
SELECT has_schema('pggit_internal', 'pggit_internal schema exists');

-- ---------------------------------------------------------------------------
-- Enum types
-- ---------------------------------------------------------------------------

SELECT has_type('pggit', 'branch_status',   'branch_status type exists');
SELECT has_type('pggit', 'object_type',     'object_type type exists');
SELECT has_type('pggit', 'merge_status',    'merge_status type exists');
SELECT has_type('pggit', 'conflict_status', 'conflict_status type exists');

-- branch_status values (pgTAP lacks has_enum_label; query pg_enum directly)
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='branch_status' AND e.enumlabel='active'),
    'branch_status has active');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='branch_status' AND e.enumlabel='merged'),
    'branch_status has merged');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='branch_status' AND e.enumlabel='deleted'),
    'branch_status has deleted');

-- object_type values
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='table'),
    'object_type has table');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='view'),
    'object_type has view');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='materialized_view'),
    'object_type has materialized_view');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='function'),
    'object_type has function');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='procedure'),
    'object_type has procedure');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='trigger'),
    'object_type has trigger');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='index'),
    'object_type has index');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='sequence'),
    'object_type has sequence');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='type'),
    'object_type has type');
SELECT ok(EXISTS(SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='pggit' AND t.typname='object_type' AND e.enumlabel='domain'),
    'object_type has domain');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

SELECT has_table('pggit', 'branches',        'branches table exists');
SELECT has_table('pggit', 'commits',         'commits table exists');
SELECT has_table('pggit', 'objects',         'objects table exists');
SELECT has_table('pggit', 'history',         'history table exists');
SELECT has_table('pggit', 'merge_history',   'merge_history table exists');
SELECT has_table('pggit', 'merge_conflicts', 'merge_conflicts table exists');

-- Key columns NOT NULL
SELECT col_not_null('pggit', 'branches',        'name',         'branches.name NOT NULL');
SELECT col_not_null('pggit', 'branches',        'status',       'branches.status NOT NULL');
SELECT col_not_null('pggit', 'commits',         'branch_id',    'commits.branch_id NOT NULL');
SELECT col_not_null('pggit', 'commits',         'message',      'commits.message NOT NULL');
SELECT col_not_null('pggit', 'commits',         'tree_hash',    'commits.tree_hash NOT NULL');
SELECT col_not_null('pggit', 'objects',         'branch_id',    'objects.branch_id NOT NULL');
SELECT col_not_null('pggit', 'objects',         'content_hash', 'objects.content_hash NOT NULL');
SELECT col_not_null('pggit', 'objects',         'ddl_text',     'objects.ddl_text NOT NULL');
SELECT col_not_null('pggit', 'history',         'branch_id',    'history.branch_id NOT NULL');
SELECT col_not_null('pggit', 'history',         'content_hash', 'history.content_hash NOT NULL');
SELECT col_not_null('pggit', 'history',         'operation',    'history.operation NOT NULL');

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

SELECT has_index('pggit', 'objects',         'objects_branch_schema_name_idx', 'objects branch+schema+name index exists');
SELECT has_index('pggit', 'objects',         'objects_branch_oid_idx',         'objects branch+oid index exists');
SELECT has_index('pggit', 'history',         'history_changed_at_brin_idx',    'history BRIN index exists');
SELECT has_index('pggit', 'history',         'history_object_id_idx',          'history object_id index exists');
SELECT has_index('pggit', 'commits',         'commits_branch_parent_idx',      'commits branch+parent index exists');
SELECT has_index('pggit', 'commits',         'commits_branch_committed_at_idx','commits branch+committed_at index exists');
SELECT has_index('pggit', 'merge_conflicts', 'merge_conflicts_open_idx',       'merge_conflicts open index exists');

-- ---------------------------------------------------------------------------
-- Bootstrap
-- ---------------------------------------------------------------------------

SELECT is(
    (SELECT COUNT(*) FROM pggit.branches),
    1::BIGINT,
    'exactly one branch after bootstrap'
);

SELECT is(
    (SELECT name FROM pggit.branches LIMIT 1),
    'main',
    'bootstrap branch is named main'
);

SELECT is(
    (SELECT status FROM pggit.branches WHERE name = 'main'),
    'active'::pggit.branch_status,
    'main branch is active'
);

SELECT is(
    (SELECT parent_id FROM pggit.branches WHERE name = 'main'),
    NULL::BIGINT,
    'main branch has no parent'
);

SELECT finish();
ROLLBACK;
