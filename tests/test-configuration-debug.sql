-- Debug test for configuration system
BEGIN;

-- Create test function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Test schemas
CREATE SCHEMA test_track;
CREATE SCHEMA test_ignore;

\echo 'Testing Configuration Debug...'

-- Check initial state
\echo '  Checking trigger state'
SELECT 
    evtname as trigger_name,
    evtenabled as enabled,
    evtfoid::regproc as function_name
FROM pg_event_trigger 
WHERE evtname LIKE 'pggit%'
ORDER BY evtname;

-- Configure tracking
\echo '  Configuring tracking'
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['test_track'],
    ignore_schemas => ARRAY['test_ignore']
);

-- Check configuration
\echo '  Checking configuration'
SELECT * FROM pggit.tracking_config ORDER BY priority DESC, config_id;

-- Test object creation
\echo '  Creating objects'
CREATE TABLE test_track.should_be_tracked (id int);
CREATE TABLE test_ignore.should_not_be_tracked (id int);

-- Check what was tracked
\echo '  Checking tracked objects'
SELECT 
    object_name,
    object_type,
    schema_name
FROM pggit.versioned_objects 
WHERE object_name LIKE 'test_%'
ORDER BY object_name;

-- Test should_track_object function directly
\echo '  Testing should_track_object function'
SELECT 
    'test_track' as schema,
    pggit.should_track_object('test_track', 'table', 'CREATE') as should_track;
    
SELECT 
    'test_ignore' as schema,
    pggit.should_track_object('test_ignore', 'table', 'CREATE') as should_track;

-- Clean up
DROP SCHEMA test_track CASCADE;
DROP SCHEMA test_ignore CASCADE;

COMMIT;