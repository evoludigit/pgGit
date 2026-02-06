"""
Diagnostic test to investigate event trigger issues in the actual test environment.

This test runs in the real E2E test environment with docker and pgGit installed,
so we can see exactly what's happening with event triggers.
"""

import pytest


class TestEventTriggerDiagnostic:
    """Diagnostic tests for event trigger functionality."""

    def test_01_check_event_trigger_exists(self, db_e2e, pggit_installed):
        """Test 1: Verify pggit_ddl_trigger exists and is enabled."""
        result = db_e2e.execute("""
            SELECT
                evtname,
                evtenabled,
                evttags
            FROM pg_event_trigger
            WHERE evtname = 'pggit_ddl_trigger'
        """)

        print("\n" + "="*80)
        print("TEST 1: EVENT TRIGGER EXISTS?")
        print("="*80)

        if result:
            print(f"✅ Event trigger exists: {result[0]}")
            assert result[0][1] is True or result[0][1] == 't', "Event trigger is disabled!"
        else:
            print("❌ pggit_ddl_trigger does not exist!")
            # List all event triggers
            all_triggers = db_e2e.execute("""
                SELECT evtname, evtenabled FROM pg_event_trigger ORDER BY evtname
            """)
            print(f"Available event triggers: {all_triggers}")

        assert result is not None and len(result) > 0, "pggit_ddl_trigger not found"

    def test_02_check_handle_ddl_function_exists(self, db_e2e, pggit_installed):
        """Test 2: Verify handle_ddl_command function exists."""
        result = db_e2e.execute("""
            SELECT
                proname,
                pg_get_functiondef(oid) as definition
            FROM pg_proc
            WHERE proname = 'handle_ddl_command'
            AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
        """)

        print("\n" + "="*80)
        print("TEST 2: handle_ddl_command FUNCTION EXISTS?")
        print("="*80)

        if result:
            print(f"✅ Function exists")
            print(f"Definition (first 500 chars):\n{result[0][1][:500]}")
        else:
            print("❌ handle_ddl_command function not found!")

        assert result is not None and len(result) > 0, "handle_ddl_command not found"

    def test_03_simple_table_creation_no_transaction(self, db_e2e, pggit_installed):
        """Test 3: Create table WITHOUT explicit transaction and check tracking."""
        print("\n" + "="*80)
        print("TEST 3: TABLE CREATION (NO EXPLICIT TRANSACTION)")
        print("="*80)

        # Create table (outside of any explicit transaction)
        db_e2e.execute("CREATE TABLE test_simple_table (id INT, name TEXT)")
        print("✅ Created test_simple_table")

        # Check if it's in pggit.objects
        result = db_e2e.execute("""
            SELECT id, object_type, schema_name, object_name, full_name
            FROM pggit.objects
            WHERE object_name = 'test_simple_table'
        """)

        print(f"Rows in pggit.objects: {len(result) if result else 0}")
        if result:
            print(f"✅ TABLE WAS TRACKED: {result}")
            for row in result:
                print(f"   ID: {row[0]}, Type: {row[1]}, Schema: {row[2]}, Name: {row[3]}")
        else:
            print("❌ TABLE WAS NOT TRACKED")
            # Let's check what's in pggit.objects at all
            all_objects = db_e2e.execute("""
                SELECT COUNT(*) as total, COUNT(DISTINCT object_name) as unique_names
                FROM pggit.objects
            """)
            print(f"Total objects in pggit.objects: {all_objects[0] if all_objects else 'error'}")

            # List all tables in database
            db_tables = db_e2e.execute("""
                SELECT tablename FROM pg_tables WHERE schemaname = 'public'
                ORDER BY tablename
            """)
            print(f"Tables in public schema: {[t[0] for t in db_tables] if db_tables else []}")

        assert result is not None and len(result) > 0, "Table not tracked in pggit.objects"

    def test_04_check_event_trigger_firing(self, db_e2e, pggit_installed):
        """Test 4: Check if event trigger is actually firing with RAISE NOTICE."""
        print("\n" + "="*80)
        print("TEST 4: EVENT TRIGGER FIRING (WITH NOTICES)?")
        print("="*80)

        # Create a version of handle_ddl_command that uses RAISE NOTICE
        db_e2e.execute("""
            CREATE OR REPLACE FUNCTION pggit.test_ddl_trigger() RETURNS event_trigger AS $$
            DECLARE
                v_object RECORD;
                v_count INT := 0;
            BEGIN
                RAISE NOTICE '🚀 TEST DDL TRIGGER FIRED!';

                FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
                    v_count := v_count + 1;
                    RAISE NOTICE 'Command %: % (type=%, schema=%)',
                        v_count,
                        v_object.command_tag,
                        v_object.object_type,
                        v_object.schema_name;
                END LOOP;

                IF v_count = 0 THEN
                    RAISE NOTICE '⚠️  pg_event_trigger_ddl_commands() returned 0 rows';
                ELSE
                    RAISE NOTICE '✅ Processed % DDL command(s)', v_count;
                END IF;
            END;
            $$ LANGUAGE plpgsql;
        """)

        # Create event trigger pointing to test function
        db_e2e.execute("""
            DROP EVENT TRIGGER IF EXISTS test_ddl_trigger;
            CREATE EVENT TRIGGER test_ddl_trigger
                ON ddl_command_end
                EXECUTE FUNCTION pggit.test_ddl_trigger();
        """)

        # Create a test table - this should fire our test trigger
        print("Creating test table... (watch for RAISE NOTICE output)")
        try:
            db_e2e.execute("CREATE TABLE test_trigger_fire (id INT)")
            print("✅ Table created")
        except Exception as e:
            print(f"⚠️  Exception during table creation: {e}")

        # Check if table exists
        table_exists = db_e2e.execute("""
            SELECT EXISTS(
                SELECT 1 FROM pg_tables
                WHERE tablename = 'test_trigger_fire' AND schemaname = 'public'
            )
        """)

        if table_exists and table_exists[0][0]:
            print("✅ Table does exist in pg_tables")
        else:
            print("❌ Table does NOT exist in pg_tables")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS test_trigger_fire CASCADE")
        db_e2e.execute("DROP EVENT TRIGGER IF EXISTS test_ddl_trigger")
        db_e2e.execute("DROP FUNCTION IF EXISTS pggit.test_ddl_trigger()")

    def test_05_check_pg_event_trigger_ddl_commands_in_trigger(self, db_e2e, pggit_installed):
        """Test 5: Verify pg_event_trigger_ddl_commands() returns data inside trigger."""
        print("\n" + "="*80)
        print("TEST 5: pg_event_trigger_ddl_commands() DATA AVAILABILITY")
        print("="*80)

        # Create a test table to store what the trigger sees
        db_e2e.execute("""
            CREATE TABLE IF NOT EXISTS pggit.trigger_debug_log (
                id SERIAL PRIMARY KEY,
                trigger_name TEXT,
                command_tag TEXT,
                object_type TEXT,
                object_identity TEXT,
                schema_name TEXT,
                recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create function that logs DDL commands
        db_e2e.execute("""
            CREATE OR REPLACE FUNCTION pggit.log_ddl_commands() RETURNS event_trigger AS $$
            DECLARE
                v_object RECORD;
            BEGIN
                FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
                    INSERT INTO pggit.trigger_debug_log (
                        trigger_name, command_tag, object_type, object_identity, schema_name
                    ) VALUES (
                        'test_trigger',
                        v_object.command_tag,
                        v_object.object_type,
                        v_object.object_identity,
                        v_object.schema_name
                    );
                END LOOP;
            END;
            $$ LANGUAGE plpgsql;
        """)

        # Clear log
        db_e2e.execute("TRUNCATE TABLE pggit.trigger_debug_log")

        # Create trigger
        db_e2e.execute("""
            DROP EVENT TRIGGER IF EXISTS test_log_trigger;
            CREATE EVENT TRIGGER test_log_trigger
                ON ddl_command_end
                EXECUTE FUNCTION pggit.log_ddl_commands();
        """)

        # Create a test table
        print("Creating test table...")
        db_e2e.execute("CREATE TABLE test_log_table (id INT, data TEXT)")

        # Check what was logged
        log_entries = db_e2e.execute("""
            SELECT command_tag, object_type, object_identity, schema_name
            FROM pggit.trigger_debug_log
            WHERE object_identity LIKE '%test_log_table%'
        """)

        print(f"Logged entries: {len(log_entries) if log_entries else 0}")
        if log_entries:
            print("✅ EVENT TRIGGER CAPTURED DATA FROM pg_event_trigger_ddl_commands():")
            for entry in log_entries:
                print(f"   Command: {entry[0]}, Type: {entry[1]}, Identity: {entry[2]}, Schema: {entry[3]}")
        else:
            print("❌ EVENT TRIGGER DID NOT LOG ANY ENTRIES")
            print("   This means pg_event_trigger_ddl_commands() returned no data")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS test_log_table CASCADE")
        db_e2e.execute("DROP EVENT TRIGGER IF EXISTS test_log_trigger")
        db_e2e.execute("DROP FUNCTION IF EXISTS pggit.log_ddl_commands()")

        assert log_entries is not None and len(log_entries) > 0, "Event trigger did not capture DDL commands"

    def test_06_compare_original_vs_debug_triggers(self, db_e2e, pggit_installed):
        """Test 6: Compare behavior of original pggit_ddl_trigger vs debug version."""
        print("\n" + "="*80)
        print("TEST 6: COMPARING ORIGINAL vs DEBUG TRIGGERS")
        print("="*80)

        # Check original trigger status
        original = db_e2e.execute("""
            SELECT evtname, evtenabled FROM pg_event_trigger WHERE evtname = 'pggit_ddl_trigger'
        """)

        if original:
            print(f"✅ Original pggit_ddl_trigger exists, enabled={original[0][1]}")
        else:
            print("❌ Original pggit_ddl_trigger does NOT exist")

        # Create tables with original trigger disabled
        print("\nTesting with ORIGINAL trigger...")
        db_e2e.execute("""
            CREATE TABLE test_with_original (id INT)
        """)

        original_tracked = db_e2e.execute("""
            SELECT COUNT(*) FROM pggit.objects WHERE object_name = 'test_with_original'
        """)

        print(f"Rows tracked by original trigger: {original_tracked[0][0] if original_tracked else 0}")

        # Now disable original and create our own
        print("\nTesting with CUSTOM debug trigger...")
        db_e2e.execute("""
            ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE
        """)

        db_e2e.execute("""
            CREATE OR REPLACE FUNCTION pggit.simple_debug_trigger() RETURNS event_trigger AS $$
            DECLARE
                v_object RECORD;
            BEGIN
                FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
                    IF v_object.object_type = 'table' THEN
                        INSERT INTO pggit.objects (
                            object_type, schema_name, object_name, is_active
                        ) VALUES (
                            'TABLE'::pggit.object_type,
                            COALESCE(v_object.schema_name, 'public'),
                            v_object.object_identity,
                            true
                        ) ON CONFLICT DO NOTHING;
                    END IF;
                END LOOP;
            END;
            $$ LANGUAGE plpgsql;
        """)

        db_e2e.execute("""
            DROP EVENT TRIGGER IF EXISTS debug_trigger;
            CREATE EVENT TRIGGER debug_trigger
                ON ddl_command_end
                EXECUTE FUNCTION pggit.simple_debug_trigger();
        """)

        # Create table with debug trigger
        db_e2e.execute("""
            CREATE TABLE test_with_debug (id INT)
        """)

        debug_tracked = db_e2e.execute("""
            SELECT COUNT(*) FROM pggit.objects WHERE object_name = 'test_with_debug'
        """)

        print(f"Rows tracked by debug trigger: {debug_tracked[0][0] if debug_tracked else 0}")

        # Re-enable original
        db_e2e.execute("""
            ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE
        """)

        print(f"\n📊 Summary:")
        print(f"  Original trigger: {original_tracked[0][0] if original_tracked else 0} objects")
        print(f"  Debug trigger: {debug_tracked[0][0] if debug_tracked else 0} objects")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS test_with_original CASCADE")
        db_e2e.execute("DROP TABLE IF EXISTS test_with_debug CASCADE")
        db_e2e.execute("DROP EVENT TRIGGER IF EXISTS debug_trigger")
        db_e2e.execute("DROP FUNCTION IF EXISTS pggit.simple_debug_trigger()")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
