-- Test suite for pgGit Migration Tool Integration
-- Tests integration with Flyway, Liquibase, and generic migration tools

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Test helper function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Setup test schema
CREATE SCHEMA test_migrations;

\echo 'Testing Migration Integration...'

-- Test 1: Basic migration tracking
\echo '  Test 1: Basic migration tracking'
DO $$
DECLARE
    deployment_id uuid;
    migration_id bigint := 20250620001;
BEGIN
    -- Start migration
    deployment_id := pggit.begin_migration(migration_id, 'flyway', 'Add user table');
    
    -- Simulate migration DDL
    CREATE TABLE test_migrations.users (
        id serial PRIMARY KEY,
        email text UNIQUE NOT NULL,
        created_at timestamptz DEFAULT now()
    );
    
    -- End migration
    PERFORM pggit.end_migration(migration_id, 'abc123'::text, true);
    
    -- Verify migration was tracked
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations WHERE migration_id = migration_id),
        'Migration should be tracked'
    );
    
    -- Verify pgGit commit was created
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations 
               WHERE migration_id = migration_id 
               AND pggit_commit_id IS NOT NULL),
        'Migration should have associated pgGit commit'
    );
END $$;

-- Test 2: Failed migration handling
\echo '  Test 2: Failed migration handling'
DO $$
DECLARE
    deployment_id uuid;
    migration_id bigint := 20250620002;
    error_caught boolean := false;
BEGIN
    -- Start migration
    deployment_id := pggit.begin_migration(migration_id, 'flyway', 'Failed migration');
    
    -- Simulate partial migration
    CREATE TABLE test_migrations.partial_table (id int);
    
    -- Simulate failure
    BEGIN
        -- This will fail
        ALTER TABLE test_migrations.nonexistent ADD COLUMN fail text;
    EXCEPTION WHEN OTHERS THEN
        error_caught := true;
        -- End migration with failure
        PERFORM pggit.end_migration(migration_id, NULL, false, SQLERRM);
    END;
    
    PERFORM test_assert(error_caught, 'Should catch migration error');
    
    -- Verify failure was recorded
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations 
               WHERE migration_id = migration_id 
               AND success = false
               AND error_message IS NOT NULL),
        'Failed migration should be recorded with error'
    );
END $$;

-- Test 3: Link existing migration
\echo '  Test 3: Link existing migration'
DO $$
DECLARE
    migration_id bigint := 20250620003;
BEGIN
    -- Simulate existing migration that wasn't tracked
    CREATE TABLE test_migrations.legacy_table (id int);
    
    -- Link it after the fact
    PERFORM pggit.link_migration(migration_id, 'Legacy migration import', 'liquibase');
    
    -- Verify it was linked
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations 
               WHERE migration_id = migration_id
               AND tool_name = 'liquibase'
               AND pggit_commit_id IS NOT NULL),
        'Should be able to link migrations retroactively'
    );
END $$;

-- Test 4: Flyway integration simulation
\echo '  Test 4: Flyway integration simulation'
DO $$
BEGIN
    -- Create mock Flyway schema_version table
    CREATE TABLE test_migrations.flyway_schema_history (
        installed_rank integer PRIMARY KEY,
        version text,
        description text,
        type text,
        script text,
        checksum integer,
        installed_by text,
        installed_on timestamp DEFAULT now(),
        execution_time integer,
        success boolean
    );
    
    -- Enable Flyway integration
    PERFORM pggit.integrate_flyway('test_migrations');
    
    -- Simulate Flyway migration
    INSERT INTO test_migrations.flyway_schema_history 
    (installed_rank, version, description, type, script, checksum, success)
    VALUES 
    (1, '1.0', 'Create products table', 'SQL', 'V1__Create_products.sql', 12345, true);
    
    -- The trigger should have tracked this
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations 
               WHERE migration_id = 1 
               AND tool_name = 'flyway'),
        'Flyway integration should auto-track migrations'
    );
END $$;

-- Test 5: Migration validation
\echo '  Test 5: Migration validation'
DO $$
DECLARE
    validation_count int;
BEGIN
    -- Add some migrations with gaps
    INSERT INTO pggit.external_migrations 
    (migration_id, tool_name, migration_name, success, pggit_commit_id)
    VALUES 
    (100, 'test', 'Migration 100', true, gen_random_uuid()),
    (102, 'test', 'Migration 102', true, gen_random_uuid()),
    (103, 'test', 'Migration 103', false, NULL),
    (105, 'test', 'Migration 105', true, NULL);
    
    -- Validate migrations
    SELECT COUNT(*) INTO validation_count
    FROM pggit.validate_migrations('test');
    
    PERFORM test_assert(
        validation_count >= 3, -- Gap, failed, and unlinked
        'Should detect migration issues'
    );
    
    -- Check specific validations
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.validate_migrations('test') WHERE status = 'gap'),
        'Should detect gaps in migration sequence'
    );
    
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.validate_migrations('test') WHERE status = 'failed'),
        'Should detect failed migrations'
    );
    
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.validate_migrations('test') WHERE status = 'unlinked'),
        'Should detect unlinked migrations'
    );
END $$;

-- Test 6: Migration history view
\echo '  Test 6: Migration history view'
DO $$
DECLARE
    history_count int;
BEGIN
    -- Check history
    SELECT COUNT(*) INTO history_count
    FROM pggit.migration_history
    WHERE tool_name IN ('flyway', 'liquibase', 'test');
    
    PERFORM test_assert(
        history_count > 0,
        'Migration history should show all tracked migrations'
    );
    
    -- Verify history includes pgGit correlation
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.migration_history 
               WHERE commit_id IS NOT NULL),
        'History should show pgGit commits'
    );
END $$;

-- Test 7: Migration impact analysis
\echo '  Test 7: Migration impact analysis'
DO $$
DECLARE
    impact_count int;
    test_migration_id bigint := 20250620001;
BEGIN
    -- Analyze impact of first migration
    SELECT COUNT(*) INTO impact_count
    FROM pggit.analyze_migration_impact(test_migration_id);
    
    PERFORM test_assert(
        impact_count > 0,
        'Should analyze migration impact on objects'
    );
    
    -- Verify impact includes table creation
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.analyze_migration_impact(test_migration_id)
               WHERE object_type = 'table' 
               AND operation = 'CREATE'),
        'Should detect table creation in migration'
    );
END $$;

-- Test 8: Liquibase integration simulation  
\echo '  Test 8: Liquibase integration simulation'
DO $$
BEGIN
    -- Create mock Liquibase databasechangelog table
    CREATE TABLE test_migrations.databasechangelog (
        id text NOT NULL,
        author text NOT NULL,
        filename text NOT NULL,
        dateexecuted timestamp NOT NULL,
        orderexecuted integer NOT NULL,
        exectype text,
        md5sum text,
        description text,
        comments text,
        tag text,
        liquibase text,
        contexts text,
        labels text,
        deployment_id text
    );
    
    -- Enable Liquibase integration
    PERFORM pggit.integrate_liquibase('test_migrations');
    
    -- Simulate Liquibase changeset
    INSERT INTO test_migrations.databasechangelog
    (id, author, filename, dateexecuted, orderexecuted)
    VALUES
    ('create-orders', 'developer', 'changelog.xml', now(), 1);
    
    -- Verify auto-tracking
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.external_migrations 
               WHERE migration_id = 1 
               AND tool_name = 'liquibase'),
        'Liquibase integration should auto-track changesets'
    );
END $$;

-- Test 9: Migration with deployment mode
\echo '  Test 9: Migration with deployment mode'
DO $$
DECLARE
    migration_id bigint := 20250620009;
    commit_count_before int;
    commit_count_after int;
BEGIN
    -- Get baseline
    SELECT COUNT(*) INTO commit_count_before FROM pggit.commits;
    
    -- Start migration (which uses deployment mode internally)
    PERFORM pggit.begin_migration(migration_id, 'test', 'Multi-step migration');
    
    -- Multiple DDL operations
    CREATE TABLE test_migrations.step1 (id int);
    CREATE TABLE test_migrations.step2 (id int);
    CREATE TABLE test_migrations.step3 (id int);
    ALTER TABLE test_migrations.step1 ADD COLUMN name text;
    ALTER TABLE test_migrations.step2 ADD COLUMN name text;
    
    -- End migration
    PERFORM pggit.end_migration(migration_id);
    
    -- Should create only one commit
    SELECT COUNT(*) INTO commit_count_after FROM pggit.commits;
    
    PERFORM test_assert(
        commit_count_after = commit_count_before + 1,
        'Migration should batch all changes into single commit'
    );
END $$;

-- Test 10: Migration execution time tracking
\echo '  Test 10: Migration execution time tracking'
DO $$
DECLARE
    migration_id bigint := 20250620010;
    exec_time interval;
BEGIN
    -- Start migration
    PERFORM pggit.begin_migration(migration_id, 'test', 'Timed migration');
    
    -- Simulate some work
    PERFORM pg_sleep(0.1);
    CREATE TABLE test_migrations.timed_table (id int);
    
    -- End migration
    PERFORM pggit.end_migration(migration_id);
    
    -- Check execution time was recorded
    SELECT execution_time INTO exec_time
    FROM pggit.external_migrations
    WHERE migration_id = migration_id;
    
    PERFORM test_assert(
        exec_time IS NOT NULL AND exec_time > '0'::interval,
        'Migration execution time should be tracked'
    );
END $$;

-- Test 11: Duplicate migration prevention
\echo '  Test 11: Duplicate migration prevention'
DO $$
DECLARE
    migration_id bigint := 20250620011;
    error_caught boolean := false;
BEGIN
    -- First migration
    PERFORM pggit.begin_migration(migration_id, 'test', 'Original');
    PERFORM pggit.end_migration(migration_id);
    
    -- Try duplicate
    BEGIN
        PERFORM pggit.begin_migration(migration_id, 'test', 'Duplicate');
    EXCEPTION WHEN OTHERS THEN
        error_caught := true;
    END;
    
    PERFORM test_assert(
        error_caught,
        'Should prevent duplicate migration IDs'
    );
END $$;

-- Cleanup
DROP SCHEMA test_migrations CASCADE;

\echo 'Migration Integration Tests: PASSED'

ROLLBACK;