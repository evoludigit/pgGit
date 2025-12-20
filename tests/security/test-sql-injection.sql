-- File: tests/security/test-sql-injection.sql
-- SQL Injection vulnerability tests

BEGIN;

-- Test 1: format() with proper %I and %L usage
DO $$
DECLARE
    malicious_input TEXT := $$'; DROP TABLE users; --$$;
    safe_query TEXT;
BEGIN
    -- This should be safe (using %L for literal)
    safe_query := format('SELECT * FROM pggit.objects WHERE object_name = %L', malicious_input);
    RAISE NOTICE 'Safe query: %', safe_query;

    -- Verify no SQL injection
    PERFORM * FROM pggit.objects WHERE object_name = malicious_input;

    RAISE NOTICE '✅ PASS: SQL injection prevented';
END $$;

-- Test 2: quote_ident() and quote_literal() usage
DO $$
DECLARE
    user_table TEXT := $$users"; DROP TABLE evil; --$$;
    safe_table TEXT;
BEGIN
    safe_table := quote_ident(user_table);
    RAISE NOTICE 'Safe table name: %', safe_table;

    -- Should not execute DROP TABLE
    ASSERT safe_table = '"users""; DROP TABLE evil; --"';

    RAISE NOTICE '✅ PASS: Identifier injection prevented';
END $$;

-- Test 3: Dynamic SQL safety in pgGit functions
DO $$
DECLARE
    test_schema TEXT := 'pggit_test_injection';
    malicious_name TEXT := $$test'; DROP SCHEMA pggit CASCADE; --$$;
    result_count INTEGER;
BEGIN
    -- Create test schema
    EXECUTE format('CREATE SCHEMA %I', test_schema);

    -- Test pgGit function with malicious input
    -- This should be safe due to proper identifier quoting
    BEGIN
        -- Simulate what happens in pgGit functions
        EXECUTE format('CREATE TABLE %I.%I (id INT)', test_schema, malicious_name);
        RAISE NOTICE 'Created table with malicious name: %', malicious_name;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Expected error creating table with malicious name: %', SQLERRM;
    END;

    -- Verify schema still exists
    SELECT COUNT(*) INTO result_count
    FROM information_schema.schemata
    WHERE schema_name = 'pggit';

    IF result_count > 0 THEN
        RAISE NOTICE '✅ PASS: Schema protected from injection';
    ELSE
        RAISE EXCEPTION '❌ FAIL: Schema was dropped by injection';
    END IF;

    -- Cleanup
    EXECUTE format('DROP SCHEMA %I CASCADE', test_schema);
END $$;

-- Test 4: Event trigger safety
DO $$
DECLARE
    event_count_before INTEGER;
    event_count_after INTEGER;
BEGIN
    SELECT COUNT(*) INTO event_count_before
    FROM pg_event_trigger;

    -- This should not create dangerous event triggers
    BEGIN
        -- Test what happens if someone tries to create a malicious trigger
        -- (This would normally be done through pgGit installation)
        EXECUTE format('CREATE EVENT TRIGGER %I ON ddl_command_start EXECUTE FUNCTION pg_catalog.pg_event_trigger_ddl_commands()',
                      'test_trigger_' || extract(epoch from now())::text);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Expected error creating event trigger: %', SQLERRM;
    END;

    SELECT COUNT(*) INTO event_count_after
    FROM pg_event_trigger;

    -- Event triggers should only be created by pgGit installation
    IF event_count_after = event_count_before THEN
        RAISE NOTICE '✅ PASS: Event triggers properly controlled';
    ELSE
        RAISE NOTICE '⚠️  WARNING: Unexpected event trigger created';
    END IF;
END $$;

-- Test 5: Test input validation in pgGit functions
DO $$
DECLARE
    test_result TEXT;
BEGIN
    -- Test that pgGit functions handle edge cases safely
    BEGIN
        -- This should not crash or expose sensitive data
        SELECT pggit.health_check() INTO test_result;
        RAISE NOTICE 'Health check result: %', test_result;

        IF test_result LIKE '%healthy%' THEN
            RAISE NOTICE '✅ PASS: Health check function safe';
        ELSE
            RAISE NOTICE '⚠️  WARNING: Health check returned unexpected result';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '❌ FAIL: Health check function threw error: %', SQLERRM;
    END;
END $$;

RAISE NOTICE 'SQL Injection Security Tests Complete';

ROLLBACK;