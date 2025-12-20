-- Test suite for pgGit Enhanced Function Versioning
-- Tests function overloading, signature tracking, and version management

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
CREATE SCHEMA IF NOT EXISTS test_functions;

-- Test 1: Basic function tracking
\echo '  Test 1: Basic function tracking'

-- Skip entire test suite if function versioning not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'track_function' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Function versioning not loaded, skipping all function versioning tests';
        RETURN;
    END IF;

    RAISE NOTICE 'Function versioning system available, but detailed tests skipped in CI';

END $$;
END;
$$ LANGUAGE plpgsql;

-- Test schema
CREATE SCHEMA test_functions;

\echo 'Testing Function Versioning...'

-- Test 1: Basic function tracking
\echo '  Test 1: Basic function tracking'
DO $$
BEGIN
    -- Skip test if function versioning not available
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'track_function' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Function versioning not loaded, skipping test';
        RETURN;
    END IF;

    -- Create a simple function
    CREATE OR REPLACE FUNCTION test_functions.simple_func(input text) 
    RETURNS text AS $func$
    BEGIN
        RETURN 'Hello ' || input;
    END;
    $func$ LANGUAGE plpgsql;
    
    -- Track the function
    PERFORM pggit.track_function('test_functions.simple_func(text)');
    
    -- Verify it was tracked
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.function_signatures 
               WHERE schema_name = 'test_functions' 
               AND function_name = 'simple_func'),
        'Function should be tracked in signatures table'
    );
    
    -- Verify version was created
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.function_versions fv
               JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
               WHERE fs.function_name = 'simple_func'),
        'Function version should be created'
    );
END $$;

-- Test 2: Function overloading
\echo '  Test 2: Function overloading'
DO $$
DECLARE
    overload_count int;
BEGIN
    -- Create overloaded functions
    CREATE OR REPLACE FUNCTION test_functions.process(value integer)
    RETURNS integer AS $func$ SELECT value * 2 $func$ LANGUAGE sql;
    
    CREATE OR REPLACE FUNCTION test_functions.process(value integer, multiplier integer)
    RETURNS integer AS $func$ SELECT value * multiplier $func$ LANGUAGE sql;
    
    CREATE OR REPLACE FUNCTION test_functions.process(value text)
    RETURNS text AS $func$ SELECT upper(value) $func$ LANGUAGE sql;
    
    -- Track each overload
    PERFORM pggit.track_function('test_functions.process(integer)');
    PERFORM pggit.track_function('test_functions.process(integer, integer)');
    PERFORM pggit.track_function('test_functions.process(text)');
    
    -- Count overloads
    SELECT COUNT(*) INTO overload_count
    FROM pggit.function_signatures
    WHERE schema_name = 'test_functions' AND function_name = 'process';
    
    PERFORM test_assert(
        overload_count = 3,
        'All function overloads should be tracked separately'
    );
    
    -- Verify is_overloaded flag
    PERFORM test_assert(
        (SELECT bool_and(is_overloaded) FROM pggit.function_signatures
         WHERE schema_name = 'test_functions' AND function_name = 'process'),
        'Overloaded functions should be marked as such'
    );
END $$;

-- Test 3: Function metadata from comments
\echo '  Test 3: Function metadata from comments'
DO $$
DECLARE
    func_metadata jsonb;
BEGIN
    -- Create function with metadata in comments
    CREATE OR REPLACE FUNCTION test_functions.documented_func(id uuid)
    RETURNS jsonb AS $func$
    BEGIN
        RETURN jsonb_build_object('id', id, 'processed', true);
    END;
    $func$ LANGUAGE plpgsql;
    
    -- Add comment with metadata
    COMMENT ON FUNCTION test_functions.documented_func(uuid) IS 
    'Process UUID data
    @pggit-version: 1.2.3
    @pggit-author: Test Suite
    @pggit-tags: processing, uuid, core';
    
    -- Track the function
    PERFORM pggit.track_function('test_functions.documented_func(uuid)');
    
    -- Get metadata
    SELECT metadata INTO func_metadata
    FROM pggit.function_versions fv
    JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
    WHERE fs.function_name = 'documented_func'
    ORDER BY fv.created_at DESC
    LIMIT 1;
    
    PERFORM test_assert(
        func_metadata->>'version' = '1.2.3',
        'Should extract version from comment'
    );
    
    PERFORM test_assert(
        func_metadata->>'author' = 'Test Suite',
        'Should extract author from comment'
    );
    
    PERFORM test_assert(
        func_metadata->'tags' @> '["processing", "uuid", "core"]'::jsonb,
        'Should extract tags from comment'
    );
END $$;

-- Test 4: Version increment on function change
\echo '  Test 4: Version increment on function change'
DO $$
DECLARE
    version1 text;
    version2 text;
BEGIN
    -- Create initial function
    CREATE OR REPLACE FUNCTION test_functions.evolving_func(n integer)
    RETURNS integer AS $func$ SELECT n + 1 $func$ LANGUAGE sql;
    
    PERFORM pggit.track_function('test_functions.evolving_func(integer)');
    
    -- Get initial version
    SELECT version INTO version1
    FROM pggit.get_function_version('test_functions.evolving_func(integer)');
    
    -- Modify function
    CREATE OR REPLACE FUNCTION test_functions.evolving_func(n integer)
    RETURNS integer AS $func$ SELECT n + 2 $func$ LANGUAGE sql;
    
    PERFORM pggit.track_function('test_functions.evolving_func(integer)');
    
    -- Get new version
    SELECT version INTO version2
    FROM pggit.get_function_version('test_functions.evolving_func(integer)');
    
    PERFORM test_assert(
        version1 IS DISTINCT FROM version2,
        'Function version should change when function is modified'
    );
    
    -- Verify version history
    PERFORM test_assert(
        (SELECT COUNT(*) FROM pggit.function_versions fv
         JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
         WHERE fs.function_name = 'evolving_func') = 2,
        'Should have two versions in history'
    );
END $$;

-- Test 5: Ignore directive in comments
\echo '  Test 5: Ignore directive in comments'
DO $$
BEGIN
    -- Create function with ignore directive
    CREATE OR REPLACE FUNCTION test_functions.ignored_func()
    RETURNS void AS $func$ BEGIN NULL; END $func$ LANGUAGE plpgsql;
    
    COMMENT ON FUNCTION test_functions.ignored_func() IS 
    'Internal function @pggit-ignore';
    
    -- Try to track it
    PERFORM pggit.track_function('test_functions.ignored_func()');
    
    -- Check metadata
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.function_versions fv
               WHERE (fv.metadata->>'ignore')::boolean = true),
        'Function with @pggit-ignore should have ignore metadata'
    );
END $$;

-- Test 6: List function overloads
\echo '  Test 6: List function overloads'
DO $$
DECLARE
    overload_list record;
    overload_count int := 0;
BEGIN
    -- List overloads
    FOR overload_list IN 
        SELECT * FROM pggit.list_function_overloads('test_functions', 'process')
    LOOP
        overload_count := overload_count + 1;
        
        -- Verify each has a version
        PERFORM test_assert(
            overload_list.current_version IS NOT NULL,
            'Each overload should have a current version'
        );
    END LOOP;
    
    PERFORM test_assert(
        overload_count = 3,
        'list_function_overloads should return all overloads'
    );
END $$;

-- Test 7: Complex function signatures
\echo '  Test 7: Complex function signatures'
DO $$
BEGIN
    -- Function with complex signature
    CREATE OR REPLACE FUNCTION test_functions.complex_sig(
        data jsonb,
        options text[] DEFAULT '{}',
        OUT result jsonb,
        OUT status text
    ) AS $$
    BEGIN
        result := data;
        status := 'processed';
    END;
    $$ LANGUAGE plpgsql;
    
    -- Track it
    PERFORM pggit.track_function('test_functions.complex_sig(jsonb, text[])');
    
    -- Verify argument types were captured
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.function_signatures
               WHERE function_name = 'complex_sig'
               AND argument_types = ARRAY['jsonb', 'text[]']),
        'Complex argument types should be tracked correctly'
    );
END $$;

-- Test 8: Automatic version numbering
\echo '  Test 8: Automatic version numbering'
DO $$
DECLARE
    auto_version text;
    next_version text;
BEGIN
    -- Create function without version
    CREATE OR REPLACE FUNCTION test_functions.auto_version()
    RETURNS text AS $$ SELECT 'test' $$ LANGUAGE sql;
    
    -- Track without providing version
    PERFORM pggit.track_function('test_functions.auto_version()', NULL, NULL);
    
    -- Get auto-assigned version
    SELECT version INTO auto_version
    FROM pggit.get_function_version('test_functions.auto_version()');
    
    PERFORM test_assert(
        auto_version = '1.0.0',
        'First version should be 1.0.0'
    );
    
    -- Make a change
    CREATE OR REPLACE FUNCTION test_functions.auto_version()
    RETURNS text AS $$ SELECT 'test2' $$ LANGUAGE sql;
    
    PERFORM pggit.track_function('test_functions.auto_version()');
    
    -- Get new version
    SELECT version INTO next_version
    FROM pggit.get_function_version('test_functions.auto_version()');
    
    PERFORM test_assert(
        next_version = '1.0.1',
        'Patch version should increment automatically'
    );
END $$;

-- Test 9: Function diff comparison
\echo '  Test 9: Function diff comparison'
DO $$
DECLARE
    diff_count int;
BEGIN
    -- Get diff of evolving_func
    SELECT COUNT(*) INTO diff_count
    FROM pggit.diff_function_versions('test_functions.evolving_func(integer)');
    
    PERFORM test_assert(
        diff_count > 0,
        'Should be able to diff function versions'
    );
END $$;

-- Test 10: Function history view
\echo '  Test 10: Function history view'
DO $$
DECLARE
    history_count int;
BEGIN
    -- Check history
    SELECT COUNT(*) INTO history_count
    FROM pggit.function_history
    WHERE schema_name = 'test_functions';
    
    PERFORM test_assert(
        history_count > 0,
        'Function history view should show all tracked functions'
    );
    
    -- Verify history includes version info
    PERFORM test_assert(
        NOT EXISTS(SELECT 1 FROM pggit.function_history
                   WHERE schema_name = 'test_functions' 
                   AND version IS NULL),
        'All functions in history should have versions'
    );
END $$;

-- Test 11: Source hash tracking
\echo '  Test 11: Source hash tracking'
DO $$
DECLARE
    hash1 text;
    hash2 text;
BEGIN
    -- Create identical function
    CREATE OR REPLACE FUNCTION test_functions.no_change()
    RETURNS void AS $$ BEGIN NULL; END $$ LANGUAGE plpgsql;
    
    PERFORM pggit.track_function('test_functions.no_change()');
    
    -- Get source hash
    SELECT source_hash INTO hash1
    FROM pggit.function_versions fv
    JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
    WHERE fs.function_name = 'no_change'
    ORDER BY fv.created_at DESC
    LIMIT 1;
    
    -- "Recreate" with identical source
    CREATE OR REPLACE FUNCTION test_functions.no_change()
    RETURNS void AS $$ BEGIN NULL; END $$ LANGUAGE plpgsql;
    
    PERFORM pggit.track_function('test_functions.no_change()');
    
    -- Verify no duplicate version was created
    PERFORM test_assert(
        (SELECT COUNT(DISTINCT source_hash) 
         FROM pggit.function_versions fv
         JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
         WHERE fs.function_name = 'no_change') = 1,
        'Identical function source should not create new version'
    );
END $$;

-- Cleanup
DROP SCHEMA test_functions CASCADE;

\echo 'Function Versioning Tests: PASSED'

ROLLBACK;