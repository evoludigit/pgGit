#!/usr/bin/env python3
"""
Diagnostic test to investigate why CREATE TABLE statements are not being
tracked in pggit.objects despite event triggers existing.

This script will:
1. Check if event trigger is actually firing
2. Verify pg_event_trigger_ddl_commands() returns data
3. Check if pggit.ensure_object() is being called
4. Look for any errors or exceptions
5. Test both with and without transaction isolation
"""

import subprocess
import sys
from urllib.parse import urlparse

def run_psql_script(connection_string: str, script: str) -> tuple[str, str, int]:
    """Run a psql script and return stdout, stderr, return code."""
    parsed = urlparse(connection_string)
    user = parsed.username or "postgres"
    password = parsed.password or "postgres"
    host = parsed.hostname or "localhost"
    port = str(parsed.port) if parsed.port else "5432"
    dbname = parsed.path.lstrip("/") or "pggit_test"

    import os
    env = os.environ.copy()
    env["PGPASSWORD"] = password

    result = subprocess.run(
        [
            "psql",
            "-h", host,
            "-p", port,
            "-U", user,
            "-d", dbname,
            "-v", "ON_ERROR_STOP=1",
        ],
        input=script,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )

    return result.stdout, result.stderr, result.returncode


def test_event_trigger_firing(connection_string: str):
    """Test 1: Check if event trigger is actually firing."""
    print("\n" + "="*80)
    print("TEST 1: IS THE EVENT TRIGGER FIRING?")
    print("="*80)

    script = """
-- Create a test table with RAISE NOTICE to debug
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command_debug() RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
BEGIN
    RAISE NOTICE 'DDL TRIGGER FIRED - Checking pg_event_trigger_ddl_commands()';

    -- Loop through all objects affected by the DDL command
    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        RAISE NOTICE 'Found DDL command: % on object: %', v_object.command_tag, v_object.object_identity;
    END LOOP;

    RAISE NOTICE 'DDL trigger function completed';
END;
$$ LANGUAGE plpgsql;

-- Replace the existing trigger with debug version
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_debug;
CREATE EVENT TRIGGER pggit_ddl_trigger_debug
    ON ddl_command_end
    EXECUTE FUNCTION pggit.handle_ddl_command_debug();

-- Now create a test table and watch for notices
CREATE TABLE diagnostic_test_1 (id INT, name TEXT);

-- Check if the table was created
SELECT tablename FROM pg_tables WHERE tablename = 'diagnostic_test_1';

-- Cleanup
DROP TABLE IF EXISTS diagnostic_test_1 CASCADE;
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_debug;
"""

    stdout, stderr, returncode = run_psql_script(connection_string, script)

    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nReturn code: {returncode}")

    if "DDL TRIGGER FIRED" in stdout or "DDL TRIGGER FIRED" in stderr:
        print("\n✅ EVENT TRIGGER IS FIRING!")
        return True
    else:
        print("\n❌ EVENT TRIGGER DID NOT FIRE - This is the problem!")
        return False


def test_event_trigger_data_availability(connection_string: str):
    """Test 2: Check if pg_event_trigger_ddl_commands() returns data."""
    print("\n" + "="*80)
    print("TEST 2: DOES pg_event_trigger_ddl_commands() RETURN DATA?")
    print("="*80)

    script = """
-- Create function that checks what data is available
CREATE OR REPLACE FUNCTION pggit.check_ddl_commands_data() RETURNS void AS $$
DECLARE
    v_object RECORD;
    v_count INT := 0;
BEGIN
    -- Count objects from pg_event_trigger_ddl_commands()
    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        v_count := v_count + 1;
        RAISE NOTICE 'Command: %, Type: %, Identity: %, Schema: %, OID: %',
            v_object.command_tag,
            v_object.object_type,
            v_object.object_identity,
            v_object.schema_name,
            v_object.objid;
    END LOOP;

    IF v_count = 0 THEN
        RAISE NOTICE 'WARNING: pg_event_trigger_ddl_commands() returned NO data!';
    ELSE
        RAISE NOTICE 'Found % DDL command(s)', v_count;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger that uses this function
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_test2;
CREATE EVENT TRIGGER pggit_ddl_trigger_test2
    ON ddl_command_end
    EXECUTE FUNCTION pggit.check_ddl_commands_data();

-- Create a test table
CREATE TABLE diagnostic_test_2 (id INT, data TEXT);

-- Verify table was created
SELECT count(*) as table_count FROM pg_tables WHERE tablename = 'diagnostic_test_2';

-- Cleanup
DROP TABLE IF EXISTS diagnostic_test_2 CASCADE;
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_test2;
DROP FUNCTION IF EXISTS pggit.check_ddl_commands_data();
"""

    stdout, stderr, returncode = run_psql_script(connection_string, script)

    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nReturn code: {returncode}")

    if "Found 1 DDL command" in stdout or "Found 1 DDL command" in stderr:
        print("\n✅ pg_event_trigger_ddl_commands() RETURNS DATA!")
        return True
    elif "WARNING: pg_event_trigger_ddl_commands() returned NO data" in stdout or \
         "WARNING: pg_event_trigger_ddl_commands() returned NO data" in stderr:
        print("\n❌ pg_event_trigger_ddl_commands() RETURNED NO DATA - This is a problem!")
        return False
    else:
        print("\n⚠️ UNCLEAR - Check output above")
        return None


def test_ensure_object_being_called(connection_string: str):
    """Test 3: Check if pggit.ensure_object() is being called."""
    print("\n" + "="*80)
    print("TEST 3: IS pggit.ensure_object() BEING CALLED?")
    print("="*80)

    script = """
-- Create wrapper to trace ensure_object calls
CREATE OR REPLACE FUNCTION pggit.ensure_object_traced(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
DECLARE
    v_result INTEGER;
BEGIN
    RAISE NOTICE 'ensure_object_traced CALLED: type=%, schema=%, name=%',
        p_object_type, p_schema_name, p_object_name;

    -- Call the original function
    v_result := pggit.ensure_object(p_object_type, p_schema_name, p_object_name, p_parent_name, p_metadata);

    RAISE NOTICE 'ensure_object_traced RETURNED id=%', v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Create DDL trigger that calls traced version
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command_traced() RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
BEGIN
    RAISE NOTICE 'DDL trigger fired - processing commands';

    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        RAISE NOTICE 'Processing: % %', v_object.command_tag, v_object.object_identity;

        IF v_object.object_type = 'table' AND v_object.command_tag = 'CREATE TABLE' THEN
            RAISE NOTICE 'About to call ensure_object for table: %', v_object.object_identity;
            PERFORM pggit.ensure_object_traced(
                'TABLE'::pggit.object_type,
                COALESCE(v_object.schema_name, 'public'),
                v_object.object_identity,
                NULL,
                '{}'::jsonb
            );
        END IF;
    END LOOP;

    RAISE NOTICE 'DDL trigger processing complete';
END;
$$ LANGUAGE plpgsql;

DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_test3;
CREATE EVENT TRIGGER pggit_ddl_trigger_test3
    ON ddl_command_end
    EXECUTE FUNCTION pggit.handle_ddl_command_traced();

-- Create test table
CREATE TABLE diagnostic_test_3 (id INT);

-- Check if it was tracked
SELECT count(*) as tracked_count FROM pggit.objects
WHERE object_name = 'diagnostic_test_3';

-- Cleanup
DROP TABLE IF EXISTS diagnostic_test_3 CASCADE;
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger_test3;
DROP FUNCTION IF EXISTS pggit.ensure_object_traced(pggit.object_type, TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION IF EXISTS pggit.handle_ddl_command_traced();
"""

    stdout, stderr, returncode = run_psql_script(connection_string, script)

    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nReturn code: {returncode}")

    if "ensure_object_traced CALLED" in stdout or "ensure_object_traced CALLED" in stderr:
        print("\n✅ ensure_object() IS BEING CALLED!")
        return True
    else:
        print("\n❌ ensure_object() WAS NOT CALLED - Trigger isn't reaching that code!")
        return False


def test_with_transaction_isolation(connection_string: str):
    """Test 4: Test with transaction isolation (simulating db_e2e fixture)."""
    print("\n" + "="*80)
    print("TEST 4: DOES TRANSACTION ISOLATION AFFECT EVENT TRIGGERS?")
    print("="*80)

    script = """
-- Test 1: Without transaction isolation
BEGIN;
RAISE NOTICE 'Test A: Creating table inside transaction';
CREATE TABLE diagnostic_test_4a (id INT);
RAISE NOTICE 'Test A: Checking if table was tracked';
SELECT count(*) as tracked_count FROM pggit.objects WHERE object_name = 'diagnostic_test_4a';
ROLLBACK;

-- Test 2: With auto-commit (no transaction)
RAISE NOTICE 'Test B: Creating table without transaction (auto-commit)';
CREATE TABLE diagnostic_test_4b (id INT);
RAISE NOTICE 'Test B: Checking if table was tracked';
SELECT count(*) as tracked_count FROM pggit.objects WHERE object_name = 'diagnostic_test_4b';
DROP TABLE IF EXISTS diagnostic_test_4b;
"""

    stdout, stderr, returncode = run_psql_script(connection_string, script)

    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nReturn code: {returncode}")

    # Count how many "tracked_count" results we got and their values
    import re
    counts = re.findall(r'tracked_count\s*\n\s*[-]*\n\s*(\d+)', stdout)

    if len(counts) >= 2:
        test_a_count = int(counts[0])
        test_b_count = int(counts[1]) if len(counts) > 1 else 0

        print(f"\n📊 Transaction Test Results:")
        print(f"  Test A (in transaction before rollback): {test_a_count} rows")
        print(f"  Test B (auto-commit): {test_b_count} rows")

        if test_a_count > 0 and test_b_count > 0:
            print("\n✅ EVENT TRIGGERS WORK BOTH WITH AND WITHOUT TRANSACTION ISOLATION")
            return True
        elif test_a_count == 0 and test_b_count > 0:
            print("\n⚠️ EVENT TRIGGERS ONLY WORK WITH AUTO-COMMIT, NOT IN TRANSACTIONS!")
            print("   This could explain test failures with db_e2e fixture (uses transaction isolation)")
            return False
        else:
            print("\n❌ EVENT TRIGGERS NOT WORKING IN EITHER CASE")
            return False
    else:
        print("\n⚠️ Could not parse results - check output above")
        return None


def test_check_event_trigger_status(connection_string: str):
    """Check the actual status of event triggers in the database."""
    print("\n" + "="*80)
    print("TEST 5: CHECKING EVENT TRIGGER STATUS IN DATABASE")
    print("="*80)

    script = """
-- Check what event triggers exist
SELECT
    pg_trigger.tgname as trigger_name,
    pg_proc.proname as function_name,
    pg_proc.pronamespace::regnamespace as function_schema
FROM pg_trigger
JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
WHERE pg_trigger.tgname LIKE 'pggit%'
ORDER BY pg_trigger.tgname;

-- Check if pggit_ddl_trigger exists
SELECT EXISTS (
    SELECT 1 FROM pg_event_trigger
    WHERE evtname = 'pggit_ddl_trigger'
) as pggit_ddl_trigger_exists;

-- Check if the trigger is enabled
SELECT
    evtname,
    evtenabled,
    evttags
FROM pg_event_trigger
WHERE evtname LIKE 'pggit%'
ORDER BY evtname;

-- Check the function definition
SELECT
    pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'handle_ddl_command'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit');
"""

    stdout, stderr, returncode = run_psql_script(connection_string, script)

    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nReturn code: {returncode}")

    if "pggit_ddl_trigger_exists" in stdout and "t" in stdout:
        print("\n✅ pggit_ddl_trigger EXISTS and is ENABLED")
        return True
    elif "pggit_ddl_trigger_exists" in stdout and "f" in stdout:
        print("\n❌ pggit_ddl_trigger DOES NOT EXIST or is DISABLED")
        return False
    else:
        print("\n⚠️ Could not determine trigger status")
        return None


def main():
    """Run all diagnostic tests."""
    # Get connection string from environment or use default
    import os
    connection_string = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5434/pggit_test")

    print("\n" + "="*80)
    print("EVENT TRIGGER DIAGNOSTIC TEST SUITE")
    print("="*80)
    print(f"Connection: {connection_string}")

    results = {}

    # Run all tests
    results["trigger_firing"] = test_event_trigger_firing(connection_string)
    results["data_available"] = test_event_trigger_data_availability(connection_string)
    results["ensure_object"] = test_ensure_object_being_called(connection_string)
    results["transaction_isolation"] = test_with_transaction_isolation(connection_string)
    results["trigger_status"] = test_check_event_trigger_status(connection_string)

    # Summary
    print("\n" + "="*80)
    print("DIAGNOSTIC SUMMARY")
    print("="*80)

    for test_name, result in results.items():
        status = "✅ PASS" if result is True else "❌ FAIL" if result is False else "⚠️ UNCLEAR"
        print(f"{status}: {test_name}")

    print("\n" + "="*80)
    print("RECOMMENDATIONS")
    print("="*80)

    if results.get("trigger_firing") is False:
        print("1. ❌ EVENT TRIGGER IS NOT FIRING")
        print("   - Check if event trigger is enabled in the database")
        print("   - Run: SELECT evtname, evtenabled FROM pg_event_trigger;")
        print("   - May need: ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;")

    if results.get("data_available") is False:
        print("2. ❌ pg_event_trigger_ddl_commands() returns no data")
        print("   - This is a PostgreSQL behavior issue")
        print("   - Event trigger function may not have proper context")

    if results.get("ensure_object") is False:
        print("3. ❌ pggit.ensure_object() is not being called")
        print("   - Event trigger function is not reaching the right code")
        print("   - Check if handle_ddl_command() has early returns or conditions")

    if results.get("transaction_isolation") is False:
        print("4. ⚠️ EVENT TRIGGERS NOT WORKING IN TRANSACTIONS")
        print("   - This explains test failures with db_e2e fixture")
        print("   - Event triggers fire AFTER transaction ends")
        print("   - Changes made in transaction are visible to trigger")
        print("   - But trigger changes might be rolled back if parent transaction rollsback")


if __name__ == "__main__":
    main()
