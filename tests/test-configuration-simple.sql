-- Simplified test for configuration system
\set ON_ERROR_STOP on

BEGIN;

-- Test helper
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

\echo 'Testing Configuration System...'

-- Test 1: Configure selective schema tracking
\echo '  Test 1: Selective schema tracking'
CREATE SCHEMA test_tracked;
CREATE SCHEMA test_ignored;

SELECT pggit.configure_tracking(
    track_schemas => ARRAY['test_tracked'],
    ignore_schemas => ARRAY['test_ignored']
);

-- Create tables
CREATE TABLE test_tracked.should_track (id int);
CREATE TABLE test_ignored.should_ignore (id int);

-- Verify tracking
SELECT test_assert(
    EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_tracked.should_track'),
    'Should track test_tracked schema'
);

SELECT test_assert(
    NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_ignored.should_ignore'),
    'Should ignore test_ignored schema'
);

-- Test 2: Deployment mode
\echo '  Test 2: Deployment mode'
DO $$
DECLARE
    deployment_id uuid;
    commit_count_before int;
    commit_count_after int;
BEGIN
    SELECT COUNT(*) INTO commit_count_before FROM pggit.commits;
    
    deployment_id := pggit.begin_deployment('Test deployment');
    
    -- Make changes
    CREATE TABLE test_tracked.deploy1 (id int);
    CREATE TABLE test_tracked.deploy2 (id int);
    
    PERFORM pggit.end_deployment();
    
    SELECT COUNT(*) INTO commit_count_after FROM pggit.commits;
    
    PERFORM test_assert(
        commit_count_after <= commit_count_before + 1,
        'Deployment should batch changes'
    );
END $$;

\echo 'Configuration tests PASSED!'

ROLLBACK;