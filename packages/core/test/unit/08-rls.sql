-- pgTAP unit tests: Row-Level Security (Phase 1)
-- Cycle 1: Tenant column infrastructure
-- Cycle 2: Tenant isolation with RLS policies

BEGIN;
SELECT plan(14);

-- ---------------------------------------------------------------------------
-- Cycle 1: Verify tenant_id column exists on all tables
-- ---------------------------------------------------------------------------

SELECT has_column(
    'pggit',
    'branches',
    'tenant_id',
    'branches table has tenant_id column'
);

SELECT has_column(
    'pggit',
    'commits',
    'tenant_id',
    'commits table has tenant_id column'
);

SELECT has_column(
    'pggit',
    'objects',
    'tenant_id',
    'objects table has tenant_id column'
);

SELECT has_column(
    'pggit',
    'history',
    'tenant_id',
    'history table has tenant_id column'
);

SELECT col_type_is(
    'pggit', 'branches', 'tenant_id',
    'uuid',
    'branches.tenant_id is UUID type'
);

SELECT col_type_is(
    'pggit', 'commits', 'tenant_id',
    'uuid',
    'commits.tenant_id is UUID type'
);

SELECT col_type_is(
    'pggit', 'objects', 'tenant_id',
    'uuid',
    'objects.tenant_id is UUID type'
);

SELECT col_type_is(
    'pggit', 'history', 'tenant_id',
    'uuid',
    'history.tenant_id is UUID type'
);

-- ---------------------------------------------------------------------------
-- Cycle 2: Verify RLS is enabled on tables
-- ---------------------------------------------------------------------------

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'pggit' 
        AND tablename = 'branches' 
        AND rowsecurity = true
    ),
    'branches has RLS enabled'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'pggit' 
        AND tablename = 'commits' 
        AND rowsecurity = true
    ),
    'commits has RLS enabled'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'pggit' 
        AND tablename = 'objects' 
        AND rowsecurity = true
    ),
    'objects has RLS enabled'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'pggit' 
        AND tablename = 'history' 
        AND rowsecurity = true
    ),
    'history has RLS enabled'
);

-- ---------------------------------------------------------------------------
-- Cycle 2: Verify tenant isolation policies exist
-- ---------------------------------------------------------------------------

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'pggit' 
        AND tablename = 'branches' 
        AND policyname = 'tenant_isolation'
    ),
    'branches has tenant_isolation policy'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'pggit' 
        AND tablename = 'commits' 
        AND policyname = 'tenant_isolation'
    ),
    'commits has tenant_isolation policy'
);

SELECT finish();
ROLLBACK;
