"""
Partial failure and multi-table atomicity tests.

These tests validate that failures in complex multi-table operations result in
complete rollback, ensuring ACID properties across multiple tables and operations.
"""

import psycopg
import pytest


@pytest.mark.chaos
@pytest.mark.transaction
@pytest.mark.partial_failure
class TestPartialFailures:
    """Test atomicity of multi-table transactions and partial failure scenarios."""

    def test_multi_table_transaction_failure(self, sync_conn: psycopg.Connection):
        """
        Test: Failure in one table causes rollback of ALL tables.

        Expected: Complete atomic rollback across all tables when error occurs.
        """
        # Create multiple test tables
        try:
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_a CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_b CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_c CASCADE")

            sync_conn.execute(
                "CREATE TABLE multi_table_a (id SERIAL PRIMARY KEY, data TEXT)",
            )
            sync_conn.execute(
                "CREATE TABLE multi_table_b (id SERIAL PRIMARY KEY, value INT)",
            )
            sync_conn.execute(
                "CREATE TABLE multi_table_c (id SERIAL PRIMARY KEY, amount DECIMAL)",
            )
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Get initial counts
        cursor_a = sync_conn.execute("SELECT COUNT(*) FROM multi_table_a")
        count_a_before = cursor_a.fetchone()["count"]

        cursor_b = sync_conn.execute("SELECT COUNT(*) FROM multi_table_b")
        count_b_before = cursor_b.fetchone()["count"]

        cursor_c = sync_conn.execute("SELECT COUNT(*) FROM multi_table_c")
        count_c_before = cursor_c.fetchone()["count"]

        # Multi-table transaction with failure
        try:
            sync_conn.execute("BEGIN")

            # Insert into table A (succeeds)
            sync_conn.execute(
                "INSERT INTO multi_table_a (data) VALUES (%s)", ("data1",),
            )

            # Insert into table B (succeeds)
            sync_conn.execute(
                "INSERT INTO multi_table_b (value) VALUES (%s)", (42,),
            )

            # Insert into table C (succeeds)
            sync_conn.execute(
                "INSERT INTO multi_table_c (amount) VALUES (%s)", (100.50,),
            )

            # Cause error - all inserts should be rolled back
            sync_conn.execute("SELECT 1/0")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify ALL tables remained unchanged
        cursor_a = sync_conn.execute("SELECT COUNT(*) FROM multi_table_a")
        count_a_after = cursor_a.fetchone()["count"]

        cursor_b = sync_conn.execute("SELECT COUNT(*) FROM multi_table_b")
        count_b_after = cursor_b.fetchone()["count"]

        cursor_c = sync_conn.execute("SELECT COUNT(*) FROM multi_table_c")
        count_c_after = cursor_c.fetchone()["count"]

        assert count_a_before == count_a_after, (
            f"Table A should be unchanged. Before: {count_a_before}, After: {count_a_after}"
        )
        assert count_b_before == count_b_after, (
            f"Table B should be unchanged. Before: {count_b_before}, After: {count_b_after}"
        )
        assert count_c_before == count_c_after, (
            f"Table C should be unchanged. Before: {count_c_before}, After: {count_c_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_a CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_b CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_table_c CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_trigger_failure_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: Trigger that fails causes transaction rollback.

        Expected: Trigger exception prevents insert and rolls back entire transaction.
        """
        # Create test table and trigger
        try:
            sync_conn.execute("DROP TABLE IF EXISTS trigger_test CASCADE")
            sync_conn.execute(
                "CREATE TABLE trigger_test (id SERIAL PRIMARY KEY, value INT)",
            )

            # Create trigger that raises exception for values > 100
            sync_conn.execute("""
                CREATE OR REPLACE FUNCTION trigger_test_check()
                RETURNS TRIGGER AS $$
                BEGIN
                    IF NEW.value > 100 THEN
                        RAISE EXCEPTION 'Value too large: %', NEW.value;
                    END IF;
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql;

                CREATE TRIGGER trigger_test_insert
                BEFORE INSERT ON trigger_test
                FOR EACH ROW EXECUTE FUNCTION trigger_test_check();
            """)
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.skip(f"Failed to create trigger: {e}")

        # Get initial count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM trigger_test")
        count_before = cursor.fetchone()["count"]

        # Try to insert value that fails trigger
        try:
            sync_conn.execute("BEGIN")

            # Insert valid value (succeeds)
            sync_conn.execute(
                "INSERT INTO trigger_test (value) VALUES (%s)", (50,),
            )

            # Insert invalid value (fails trigger)
            sync_conn.execute(
                "INSERT INTO trigger_test (value) VALUES (%s)", (150,),
            )

            sync_conn.commit()
            pytest.fail("Expected trigger to raise exception")

        except psycopg.Error as e:
            sync_conn.rollback()
            # Should have trigger exception
            assert "too large" in str(e).lower() or "trigger" in str(e).lower(), (
                f"Expected trigger exception, got: {e}"
            )

        # Verify no rows were inserted (complete rollback)
        cursor = sync_conn.execute("SELECT COUNT(*) FROM trigger_test")
        count_after = cursor.fetchone()["count"]

        assert count_before == count_after, (
            f"Trigger failure should rollback all inserts. Before: {count_before}, After: {count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TRIGGER IF EXISTS trigger_test_insert ON trigger_test")
            sync_conn.execute("DROP FUNCTION IF EXISTS trigger_test_check()")
            sync_conn.execute("DROP TABLE IF EXISTS trigger_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_multi_row_insert_partial_failure(self, sync_conn: psycopg.Connection):
        """
        Test: Failure in batch insert rolls back entire batch.

        Expected: When one row fails in a batch insert, all rows are rolled back.
        """
        # Create test table with UNIQUE constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS batch_insert_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE batch_insert_test (
                    id SERIAL PRIMARY KEY,
                    unique_field TEXT UNIQUE NOT NULL,
                    data TEXT
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert initial data
        try:
            sync_conn.execute(
                "INSERT INTO batch_insert_test (unique_field, data) VALUES (%s, %s)",
                ("existing", "initial"),
            )
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Get initial count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM batch_insert_test")
        count_before = cursor.fetchone()["count"]

        # Try batch insert where one row fails
        try:
            sync_conn.execute("BEGIN")

            # Insert rows in a batch
            for i in range(1, 11):
                if i == 5:
                    # 5th row uses duplicate unique_field
                    sync_conn.execute(
                        "INSERT INTO batch_insert_test (unique_field, data) VALUES (%s, %s)",
                        ("existing", f"row_{i}"),  # Duplicate!
                    )
                else:
                    sync_conn.execute(
                        "INSERT INTO batch_insert_test (unique_field, data) VALUES (%s, %s)",
                        (f"row_{i}", f"data_{i}"),
                    )

            sync_conn.commit()
            pytest.fail("Expected UNIQUE constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            # Should be UNIQUE constraint error
            assert "unique" in str(e).lower() or "duplicate" in str(e).lower(), (
                f"Expected UNIQUE constraint error, got: {e}"
            )

        # Verify count is unchanged (all rows rolled back)
        cursor = sync_conn.execute("SELECT COUNT(*) FROM batch_insert_test")
        count_after = cursor.fetchone()["count"]

        assert count_before == count_after, (
            f"Batch insert failure should rollback all rows. "
            f"Before: {count_before}, After: {count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS batch_insert_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_constraint_violation_in_multi_table_transaction(
        self, sync_conn: psycopg.Connection,
    ):
        """
        Test: Constraint violation in multi-table transaction rolls back all tables.

        Expected: FK constraint violation in one table causes rollback across all.
        """
        # Create parent and child tables with FK
        try:
            sync_conn.execute("DROP TABLE IF EXISTS multi_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_parent CASCADE")
            sync_conn.execute("""
                CREATE TABLE multi_parent (
                    id INT PRIMARY KEY,
                    name TEXT NOT NULL
                )
            """)
            sync_conn.execute("""
                CREATE TABLE multi_child (
                    id SERIAL PRIMARY KEY,
                    parent_id INT NOT NULL REFERENCES multi_parent(id),
                    data TEXT
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Get initial counts
        cursor = sync_conn.execute("SELECT COUNT(*) FROM multi_parent")
        parent_count_before = cursor.fetchone()["count"]

        cursor = sync_conn.execute("SELECT COUNT(*) FROM multi_child")
        child_count_before = cursor.fetchone()["count"]

        # Multi-table transaction with FK violation
        try:
            sync_conn.execute("BEGIN")

            # Insert into parent table
            sync_conn.execute(
                "INSERT INTO multi_parent (id, name) VALUES (%s, %s)",
                (1, "parent1"),
            )

            # Try to insert into child with non-existent parent
            sync_conn.execute(
                "INSERT INTO multi_child (parent_id, data) VALUES (%s, %s)",
                (999, "child_orphan"),  # FK violation!
            )

            sync_conn.commit()
            pytest.fail("Expected FK constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            # Should be FK error
            assert "foreign" in str(e).lower() or "referenced" in str(e).lower(), (
                f"Expected FK constraint error, got: {e}"
            )

        # Verify both tables are unchanged
        cursor = sync_conn.execute("SELECT COUNT(*) FROM multi_parent")
        parent_count_after = cursor.fetchone()["count"]

        cursor = sync_conn.execute("SELECT COUNT(*) FROM multi_child")
        child_count_after = cursor.fetchone()["count"]

        assert parent_count_before == parent_count_after, (
            f"Parent table should be unchanged. Before: {parent_count_before}, After: {parent_count_after}"
        )
        assert child_count_before == child_count_after, (
            f"Child table should be unchanged. Before: {child_count_before}, After: {child_count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS multi_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS multi_parent CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_transaction_with_pggit_partial_failure(self, sync_conn: psycopg.Connection):
        """
        Test: Failure during pggit operation causes complete rollback.

        Expected: If pggit function fails, data changes are rolled back.
        """
        # Create test table
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pggit_partial_test CASCADE")
            sync_conn.execute(
                "CREATE TABLE pggit_partial_test (id SERIAL PRIMARY KEY, value INT)",
            )
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Get initial count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit_partial_test")
        count_before = cursor.fetchone()["count"]

        # Transaction with pggit operation and failure
        try:
            sync_conn.execute("BEGIN")

            # Insert data
            sync_conn.execute(
                "INSERT INTO pggit_partial_test (value) VALUES (%s)", (42,),
            )

            # Try pggit operation (might fail)
            try:
                sync_conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    ("main", "Test", "pggit-partial-test"),
                )
            except psycopg.Error:
                # If pggit operation fails, this is expected
                pass

            # Intentionally cause error to force rollback
            sync_conn.execute("SELECT 1/0")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify data was rolled back
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit_partial_test")
        count_after = cursor.fetchone()["count"]

        assert count_before == count_after, (
            f"Data should be rolled back. Before: {count_before}, After: {count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pggit_partial_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass
