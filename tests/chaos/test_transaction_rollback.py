"""
Transaction rollback correctness tests.

These tests validate that pggit and PostgreSQL properly handle transaction
rollbacks, ensuring no partial commits or orphaned data occur when errors
happen during complex operations.
"""

import psycopg
import pytest


@pytest.mark.chaos
@pytest.mark.transaction
class TestTransactionRollback:
    """Test transaction rollback behavior under various conditions."""

    def test_complete_rollback_on_error(self, sync_conn: psycopg.Connection):
        """
        Test: Transaction with error rolls back ALL changes.

        Expected: No partial commits, database returns to pre-transaction state.
        All DDL operations are reversed.
        """
        # Create table first to have clean state
        try:
            sync_conn.execute("DROP TABLE IF EXISTS rollback_test_1 CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS rollback_test_2 CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Verify tables don't exist before test
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name IN ('rollback_test_1', 'rollback_test_2')
        """)
        count_before = cursor.fetchone()["count"]
        assert count_before == 0, "Tables should not exist before test"

        # Start transaction and create tables
        try:
            sync_conn.execute("BEGIN")

            # Create first table (should be rolled back)
            sync_conn.execute("CREATE TABLE rollback_test_1 (id INT)")

            # Create second table (should be rolled back)
            sync_conn.execute("CREATE TABLE rollback_test_2 (id INT)")

            # Cause error - invalid SQL
            sync_conn.execute("THIS IS INVALID SQL")

            sync_conn.commit()

        except psycopg.Error:
            # Error expected, rollback
            sync_conn.rollback()

        # Verify complete rollback - tables should not exist
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name IN ('rollback_test_1', 'rollback_test_2')
        """)
        count_after = cursor.fetchone()["count"]

        assert count_after == 0, "Both tables should be rolled back (deleted)"

    def test_pggit_commit_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: Failed pggit.commit_changes() doesn't create orphaned Trinity IDs.

        This is critical: if commit_changes() fails, Trinity ID should not be
        assigned and the transaction should completely rollback.
        """
        # Create test table
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pggit_rollback_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE pggit_rollback_test (
                    id SERIAL PRIMARY KEY,
                    value INT NOT NULL
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Capture Trinity ID count before
        try:
            cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.commits")
            commit_count_before = cursor.fetchone()["count"]
        except psycopg.Error:
            # If table doesn't exist, skip this test
            pytest.skip("pggit.commits table not available")
            return

        # Insert initial data
        try:
            sync_conn.execute(
                "INSERT INTO pggit_rollback_test (value) VALUES (%s)",
                (42,),
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert initial data: {e}")

        # Attempt commit that will fail
        try:
            sync_conn.execute("BEGIN")

            # Modify data
            sync_conn.execute(
                "UPDATE pggit_rollback_test SET value = %s WHERE id = 1",
                (100,),
            )

            # Try to commit (using unique Trinity ID)
            sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("main", "Rollback test commit", "rollback-test-trinity-id"),
            )

            # Intentionally cause error AFTER commit attempt to force rollback
            sync_conn.execute("SELECT 1/0")  # Division by zero

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify NO new commit was created
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.commits")
        commit_count_after = cursor.fetchone()["count"]

        assert commit_count_before == commit_count_after, (
            f"Failed commit should not create new Trinity ID. "
            f"Before: {commit_count_before}, After: {commit_count_after}"
        )

        # Verify data was rolled back to original value
        cursor = sync_conn.execute("SELECT value FROM pggit_rollback_test WHERE id = 1")
        result = cursor.fetchone()
        if result:
            current_value = result["value"]
            assert current_value == 42, (
                f"Data should be rolled back to original value (42), got {current_value}"
            )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pggit_rollback_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_savepoint_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: Savepoint allows partial rollback within transaction.

        Expected: Changes after savepoint are rolled back, changes before persist.
        """
        # Clean up first
        try:
            sync_conn.execute("DROP TABLE IF EXISTS savepoint_test_1 CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS savepoint_test_2 CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        try:
            # Start transaction
            sync_conn.execute("BEGIN")

            # Create first table (before savepoint)
            sync_conn.execute("CREATE TABLE savepoint_test_1 (id INT)")

            # Create savepoint
            sync_conn.execute("SAVEPOINT sp1")

            # Create second table (after savepoint)
            sync_conn.execute("CREATE TABLE savepoint_test_2 (id INT)")

            # Rollback to savepoint (should remove table 2)
            sync_conn.execute("ROLLBACK TO SAVEPOINT sp1")

            # Commit transaction
            sync_conn.commit()

            # Verify: table 1 exists, table 2 doesn't
            cursor = sync_conn.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name IN ('savepoint_test_1', 'savepoint_test_2')
            """)
            tables = [row["table_name"] for row in cursor.fetchall()]

            assert "savepoint_test_1" in tables, "Table before savepoint should exist"
            assert "savepoint_test_2" not in tables, (
                "Table after savepoint should not exist"
            )

        finally:
            # Cleanup
            try:
                sync_conn.execute("DROP TABLE IF EXISTS savepoint_test_1 CASCADE")
                sync_conn.execute("DROP TABLE IF EXISTS savepoint_test_2 CASCADE")
                sync_conn.commit()
            except psycopg.Error:
                sync_conn.rollback()

    def test_nested_transaction_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: Nested transaction (via savepoints) rollback isolation.

        Expected: Outer transaction persists, inner transaction rolls back.
        """
        # Clean up first
        try:
            sync_conn.execute("DROP TABLE IF EXISTS nested_outer CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS nested_inner CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        try:
            # Outer transaction
            sync_conn.execute("BEGIN")

            # Create table in outer transaction
            sync_conn.execute("CREATE TABLE nested_outer (id INT)")

            # Create savepoint for nested transaction
            sync_conn.execute("SAVEPOINT nested_sp")

            # Create table in nested transaction
            sync_conn.execute("CREATE TABLE nested_inner (id INT)")

            # Rollback nested transaction
            sync_conn.execute("ROLLBACK TO SAVEPOINT nested_sp")

            # Commit outer transaction
            sync_conn.commit()

            # Verify: outer table exists, inner table doesn't
            cursor = sync_conn.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name IN ('nested_outer', 'nested_inner')
            """)
            tables = [row["table_name"] for row in cursor.fetchall()]

            assert "nested_outer" in tables, "Outer transaction table should exist"
            assert "nested_inner" not in tables, (
                "Inner transaction table should not exist"
            )

        finally:
            # Cleanup
            try:
                sync_conn.execute("DROP TABLE IF EXISTS nested_outer CASCADE")
                sync_conn.execute("DROP TABLE IF EXISTS nested_inner CASCADE")
                sync_conn.commit()
            except psycopg.Error:
                sync_conn.rollback()

    def test_insert_rollback_data_integrity(self, sync_conn: psycopg.Connection):
        """
        Test: Data modifications are completely rolled back on error.

        Expected: Inserted rows don't persist, counts return to original.
        """
        # Create test table
        try:
            sync_conn.execute("DROP TABLE IF EXISTS insert_rollback_test CASCADE")
            sync_conn.execute(
                "CREATE TABLE insert_rollback_test (id SERIAL PRIMARY KEY, data TEXT)"
            )
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert initial data
        try:
            sync_conn.execute(
                "INSERT INTO insert_rollback_test (data) VALUES (%s)",
                ("initial_data",),
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert initial data: {e}")

        # Get initial count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM insert_rollback_test")
        count_before = cursor.fetchone()["count"]

        # Try to insert multiple rows but fail
        try:
            sync_conn.execute("BEGIN")

            # Insert first row (will commit)
            sync_conn.execute(
                "INSERT INTO insert_rollback_test (data) VALUES (%s)",
                ("row_1",),
            )

            # Insert second row (will commit)
            sync_conn.execute(
                "INSERT INTO insert_rollback_test (data) VALUES (%s)",
                ("row_2",),
            )

            # Cause error
            sync_conn.execute("SELECT 1/0")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify count is unchanged
        cursor = sync_conn.execute("SELECT COUNT(*) FROM insert_rollback_test")
        count_after = cursor.fetchone()["count"]

        assert count_before == count_after, (
            f"Data should be rolled back. Before: {count_before}, After: {count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS insert_rollback_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass
