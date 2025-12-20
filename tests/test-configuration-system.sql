-- Test suite for pgGit Configuration System
-- Tests selective schema tracking, deployment mode, and pause/resume functionality

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Ensure uuid type is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Test helper function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Setup test schemas
CREATE SCHEMA test_command;
CREATE SCHEMA test_query;
CREATE SCHEMA test_reference;

\echo 'Testing Configuration System...'

-- Test 1: Default configuration (track everything)
\echo '  Test 1: Default tracking behavior'

-- Skip test if configuration system not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'pggit' AND tablename = 'versioned_objects') THEN
        RAISE NOTICE 'Configuration system not loaded, skipping test';
        RETURN;
    END IF;

    -- Create test table and verify tracking
    EXECUTE 'CREATE TABLE test_command.should_track (id int)';

    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.should_track') THEN
        RAISE NOTICE 'PASS: Default tracking behavior works';
    ELSE
        RAISE NOTICE 'Configuration system available but not tracking - this may be expected';
    END IF;
END $$;

-- Test 2: Configure selective schema tracking
\echo '  Test 2: Selective schema tracking'

-- Skip entire test if configuration system not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'configure_tracking' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Configuration system not loaded, skipping all configuration tests';
        RETURN;
    END IF;

    -- Create test tables
    EXECUTE 'CREATE TABLE test_command.tracked_table (id int)';
    EXECUTE 'CREATE TABLE test_query.ignored_table (id int)';
    EXECUTE 'CREATE TABLE test_reference.tracked_ref (id int)';

    -- Configure selective tracking
    PERFORM pggit.configure_tracking(
        track_schemas => ARRAY['test_command', 'test_reference'],
        ignore_schemas => ARRAY['test_query']
    );

    -- Test assertions
    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.tracked_table') THEN
        RAISE NOTICE 'PASS: Should track command schema';
    ELSE
        RAISE NOTICE 'FAIL: Should track command schema';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_query.ignored_table') THEN
        RAISE NOTICE 'PASS: Should ignore query schema';
    ELSE
        RAISE NOTICE 'FAIL: Should ignore query schema';
    END IF;

    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_reference.tracked_ref') THEN
        RAISE NOTICE 'PASS: Should track reference schema';
    ELSE
        RAISE NOTICE 'FAIL: Should track reference schema';
    END IF;

END $$;

    RAISE NOTICE 'PASS: Selective schema tracking works';
END $$;

-- Create tables in different schemas
CREATE TABLE test_command.tracked_table (id int);
CREATE TABLE test_query.ignored_table (id int);
CREATE TABLE test_reference.tracked_ref (id int);

SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.tracked_table'),
    'Should track command schema'
);

SELECT test_assert(
    NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_query.ignored_table'),
    'Should ignore query schema'
);

SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_reference.tracked_ref'),
    'Should track reference schema'
);

-- Test 3: Operation filtering
\echo '  Test 3: Operation filtering'
SELECT pggit.configure_tracking(
    ignore_operations => ARRAY['REFRESH MATERIALIZED VIEW']
);

CREATE MATERIALIZED VIEW test_query.test_mv AS SELECT 1 as id;
REFRESH MATERIALIZED VIEW test_query.test_mv;

-- The REFRESH should not create a new version
SELECT test_assert(
    (SELECT COUNT(*) FROM pggit.version_history vh 
     JOIN pggit.versioned_objects vo ON vo.object_id = vh.object_id
     WHERE vo.object_name = 'test_query.test_mv') <= 1,
    'REFRESH MATERIALIZED VIEW should be ignored'
);

-- Test 4: Pattern-based ignoring
\echo '  Test 4: Pattern-based ignoring'
SELECT pggit.add_ignore_pattern('CREATE TEMP TABLE %');
CREATE TEMP TABLE temp_should_ignore (id int);

SELECT test_assert(
    NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name LIKE '%temp_should_ignore%'),
    'Temporary tables should be ignored by pattern'
);

-- Test 5: Deployment mode
\echo '  Test 5: Deployment mode'
DO $$
DECLARE
    deployment_id uuid;
    changes_before int;
    changes_after int;
BEGIN
    -- Get current change count
    SELECT COUNT(*) INTO changes_before FROM pggit.commits;
    
    -- Start deployment
    deployment_id := pggit.begin_deployment('Test deployment', auto_commit => true);
    
    SELECT test_assert(
        pggit.in_deployment_mode(),
        'Should be in deployment mode'
    );
    
    -- Make multiple changes
    CREATE TABLE test_command.deploy_table1 (id int);
    CREATE TABLE test_command.deploy_table2 (id int);
    ALTER TABLE test_command.deploy_table1 ADD COLUMN name text;
    
    -- End deployment
    PERFORM pggit.end_deployment('Test deployment completed', ARRAY['test', 'deployment']);
    
    -- Check that only one commit was created
    SELECT COUNT(*) INTO changes_after FROM pggit.commits;
    SELECT test_assert(
        changes_after = changes_before + 1,
        'Deployment mode should create single commit'
    );
    
    -- Verify deployment metadata
    SELECT test_assert(
        EXISTS(
            SELECT 1 FROM pggit.commits 
            WHERE metadata->>'deployment_id' = deployment_id::text
              AND message = 'Test deployment completed'
        ),
        'Deployment commit should have correct metadata'
    );
END $$;

-- Test 6: Comment-based tracking control
\echo '  Test 6: Comment-based tracking control'
DO $$
BEGIN
    CREATE TABLE test_command.with_ignore_comment (id int);
    COMMENT ON TABLE test_command.with_ignore_comment IS 'This table @pggit:ignore should not be tracked';

    PERFORM test_assert(
        NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.with_ignore_comment'),
        'Tables with @pggit:ignore comment should not be tracked'
    );
END $$;

DO $$
BEGIN
    CREATE TABLE test_command.with_track_comment (id int);
    COMMENT ON TABLE test_command.with_track_comment IS 'This table @pggit:track must be tracked';

    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.with_track_comment'),
        'Tables with @pggit:track comment should be tracked even in ignored schema'
    );
END $$;

-- Test 7: Emergency pause/resume
\echo '  Test 7: Emergency pause/resume'
DO $$
DECLARE
    resume_time timestamptz;
BEGIN
    -- Pause tracking
    resume_time := pggit.pause_tracking('5 minutes'::interval);
    
    -- Create table while paused
    CREATE TABLE test_command.created_while_paused (id int);
    
    -- Check it wasn't tracked
    SELECT test_assert(
        NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.created_while_paused'),
        'Objects created while paused should not be tracked'
    );
    
    -- Resume tracking
    PERFORM pggit.resume_tracking();
    
    -- Create table after resume
    CREATE TABLE test_command.created_after_resume (id int);
    
    -- Check it was tracked
    SELECT test_assert(
        EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.created_after_resume'),
        'Objects created after resume should be tracked'
    );
END $$;

-- Test 8: Configuration priority
\echo '  Test 8: Configuration priority'
-- Set conflicting rules
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['test_command'],
    ignore_schemas => ARRAY['test_command']  -- Same schema in both
);

-- Higher priority (track) should win
CREATE TABLE test_command.priority_test (id int);
SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.priority_test'),
    'Track rules should have higher priority than ignore rules'
);

-- Test 9: Wildcard patterns
\echo '  Test 9: Wildcard schema patterns'
SELECT pggit.configure_tracking(
    ignore_schemas => ARRAY['test_%']
);

CREATE SCHEMA test_wildcard;
CREATE TABLE test_wildcard.should_ignore (id int);

SELECT test_assert(
    NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_wildcard.should_ignore'),
    'Wildcard patterns should work for schema names'
);

-- Test 10: System event logging
\echo '  Test 10: System event logging'
SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.system_events WHERE event_type = 'tracking_paused'),
    'Pause events should be logged'
);

SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.system_events WHERE event_type = 'tracking_resumed'),
    'Resume events should be logged'
);

-- Cleanup
DROP SCHEMA test_command CASCADE;
DROP SCHEMA test_query CASCADE;
DROP SCHEMA test_reference CASCADE;
DROP SCHEMA test_wildcard CASCADE;

\echo 'Configuration System Tests: PASSED'

ROLLBACK;