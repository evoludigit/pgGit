-- File: templates/extension-template/tests/test-extension.sql
-- Example extension tests

BEGIN;

-- Test basic functionality
DO $$
DECLARE
    test_key TEXT := 'test_key';
    test_value JSONB := '{"message": "hello world"}';
    retrieved_value JSONB;
BEGIN
    -- Test set_metadata
    PERFORM pggit_example.set_metadata(test_key, test_value);
    RAISE NOTICE 'Set metadata: %', test_value;

    -- Test get_metadata
    SELECT pggit_example.get_metadata(test_key) INTO retrieved_value;
    RAISE NOTICE 'Retrieved metadata: %', retrieved_value;

    -- Verify
    IF retrieved_value = test_value THEN
        RAISE NOTICE '✅ PASS: Extension metadata functions work correctly';
    ELSE
        RAISE EXCEPTION '❌ FAIL: Retrieved value does not match set value';
    END IF;
END $$;

-- Test integration with pgGit
DO $$
DECLARE
    history_count_before INTEGER;
    history_count_after INTEGER;
BEGIN
    SELECT COUNT(*) INTO history_count_before FROM pggit.history;

    -- Trigger extension event
    PERFORM pggit_example.set_metadata('integration_test', '{"test": true}'::jsonb);

    SELECT COUNT(*) INTO history_count_after FROM pggit.history;

    IF history_count_after > history_count_before THEN
        RAISE NOTICE '✅ PASS: Extension integrates with pgGit history';
    ELSE
        RAISE NOTICE '⚠️  WARNING: No history entry created (may be expected)';
    END IF;
END $$;

-- Cleanup
DROP SCHEMA pggit_example CASCADE;

RAISE NOTICE 'Extension template tests complete';

ROLLBACK;