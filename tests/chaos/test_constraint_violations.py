"""
Constraint violation and rollback tests.

These tests validate that constraint violations (UNIQUE, FK, CHECK, NOT NULL)
properly trigger transaction rollback and maintain database integrity.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.transaction
@pytest.mark.constraints
class TestConstraintViolations:
    """Test constraint enforcement and rollback behavior."""

    def test_unique_constraint_violation_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: UNIQUE constraint violation triggers complete transaction rollback.

        Expected: Duplicate insert fails, transaction is rolled back completely.
        """
        # Create test table with UNIQUE constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS unique_constraint_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE unique_constraint_test (
                    id SERIAL PRIMARY KEY,
                    unique_field TEXT UNIQUE NOT NULL
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert first row
        try:
            sync_conn.execute(
                "INSERT INTO unique_constraint_test (unique_field) VALUES (%s)",
                ("unique_value",)
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert initial row: {e}")

        # Get initial count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM unique_constraint_test")
        count_before = cursor.fetchone()["count"]

        # Try to insert duplicate - should fail and rollback
        try:
            sync_conn.execute("BEGIN")

            # Insert duplicate unique value
            sync_conn.execute(
                "INSERT INTO unique_constraint_test (unique_field) VALUES (%s)",
                ("unique_value",)  # Duplicate!
            )

            sync_conn.commit()
            # Should not reach here
            pytest.fail("Expected UNIQUE constraint violation")

        except psycopg.Error as e:
            # Expected: UNIQUE constraint violation
            sync_conn.rollback()
            assert "unique" in str(e).lower() or "duplicate" in str(e).lower(), (
                f"Expected UNIQUE constraint error, got: {e}"
            )

        # Verify count unchanged (rollback occurred)
        cursor = sync_conn.execute("SELECT COUNT(*) FROM unique_constraint_test")
        count_after = cursor.fetchone()["count"]

        assert count_before == count_after, (
            f"Constraint violation should rollback. Before: {count_before}, After: {count_after}"
        )

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS unique_constraint_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_foreign_key_violation_rollback(self, sync_conn: psycopg.Connection):
        """
        Test: Foreign key violation prevents insert and rolls back transaction.

        Expected: Child row insert fails due to FK constraint, no data persists.
        """
        # Create parent and child tables with FK constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS fk_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS fk_parent CASCADE")
            sync_conn.execute("""
                CREATE TABLE fk_parent (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL
                )
            """)
            sync_conn.execute("""
                CREATE TABLE fk_child (
                    id SERIAL PRIMARY KEY,
                    parent_id INT NOT NULL REFERENCES fk_parent(id),
                    data TEXT
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert parent row
        try:
            sync_conn.execute(
                "INSERT INTO fk_parent (name) VALUES (%s)",
                ("parent1",)
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert parent: {e}")

        # Try to insert child with non-existent parent
        try:
            sync_conn.execute("BEGIN")

            # Try to reference non-existent parent (ID = 999)
            sync_conn.execute(
                "INSERT INTO fk_child (parent_id, data) VALUES (%s, %s)",
                (999, "orphan_child")
            )

            sync_conn.commit()
            pytest.fail("Expected FK constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            # Expected FK constraint error
            assert "foreign" in str(e).lower() or "referenced" in str(e).lower(), (
                f"Expected FK constraint error, got: {e}"
            )

        # Verify no child row was inserted
        cursor = sync_conn.execute("SELECT COUNT(*) FROM fk_child")
        child_count = cursor.fetchone()["count"]

        assert child_count == 0, "FK constraint violation should prevent insert"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS fk_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS fk_parent CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_check_constraint_violation(self, sync_conn: psycopg.Connection):
        """
        Test: CHECK constraint prevents invalid data and rolls back transaction.

        Expected: Invalid data violates CHECK constraint, transaction fails.
        """
        # Create table with CHECK constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS check_constraint_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE check_constraint_test (
                    id SERIAL PRIMARY KEY,
                    age INT CHECK (age >= 0 AND age <= 150),
                    name TEXT NOT NULL
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert valid row first
        try:
            sync_conn.execute(
                "INSERT INTO check_constraint_test (age, name) VALUES (%s, %s)",
                (25, "John")
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert valid row: {e}")

        # Try to insert invalid row
        try:
            sync_conn.execute("BEGIN")

            # Try to insert age = 200 (violates CHECK constraint)
            sync_conn.execute(
                "INSERT INTO check_constraint_test (age, name) VALUES (%s, %s)",
                (200, "Invalid")
            )

            sync_conn.commit()
            pytest.fail("Expected CHECK constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            assert "check" in str(e).lower() or "constraint" in str(e).lower(), (
                f"Expected CHECK constraint error, got: {e}"
            )

        # Verify only valid row exists
        cursor = sync_conn.execute("SELECT COUNT(*) FROM check_constraint_test")
        count = cursor.fetchone()["count"]

        assert count == 1, "Only valid row should exist"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS check_constraint_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_not_null_constraint_violation(self, sync_conn: psycopg.Connection):
        """
        Test: NOT NULL constraint prevents NULL values and rolls back.

        Expected: NULL insert fails, transaction is rolled back.
        """
        # Create table with NOT NULL constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS not_null_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE not_null_test (
                    id SERIAL PRIMARY KEY,
                    required_field TEXT NOT NULL,
                    optional_field TEXT
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert valid row
        try:
            sync_conn.execute(
                "INSERT INTO not_null_test (required_field, optional_field) VALUES (%s, %s)",
                ("required_value", "optional_value")
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert valid row: {e}")

        # Try to insert NULL in NOT NULL field
        try:
            sync_conn.execute("BEGIN")

            # Try to insert NULL in required_field
            sync_conn.execute(
                "INSERT INTO not_null_test (required_field, optional_field) VALUES (%s, %s)",
                (None, "optional")
            )

            sync_conn.commit()
            pytest.fail("Expected NOT NULL constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            assert "not null" in str(e).lower() or "null" in str(e).lower(), (
                f"Expected NOT NULL constraint error, got: {e}"
            )

        # Verify only valid row exists
        cursor = sync_conn.execute("SELECT COUNT(*) FROM not_null_test")
        count = cursor.fetchone()["count"]

        assert count == 1, "Only valid row should exist"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS not_null_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_primary_key_duplicate_violation(self, sync_conn: psycopg.Connection):
        """
        Test: PRIMARY KEY constraint prevents duplicate keys and rolls back.

        Expected: Duplicate primary key insert fails, transaction is rolled back.
        """
        # Create table with PRIMARY KEY
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pk_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE pk_test (
                    id INT PRIMARY KEY,
                    data TEXT NOT NULL
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert first row
        try:
            sync_conn.execute(
                "INSERT INTO pk_test (id, data) VALUES (%s, %s)",
                (1, "first")
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert initial row: {e}")

        # Try to insert duplicate key
        try:
            sync_conn.execute("BEGIN")

            # Try to insert duplicate primary key
            sync_conn.execute(
                "INSERT INTO pk_test (id, data) VALUES (%s, %s)",
                (1, "duplicate")  # Duplicate key!
            )

            sync_conn.commit()
            pytest.fail("Expected PRIMARY KEY constraint violation")

        except psycopg.Error as e:
            sync_conn.rollback()
            assert "primary key" in str(e).lower() or "duplicate" in str(e).lower(), (
                f"Expected PK constraint error, got: {e}"
            )

        # Verify only first row exists
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pk_test")
        count = cursor.fetchone()["count"]

        assert count == 1, "Only first row should exist"

        # Verify first row is intact
        cursor = sync_conn.execute("SELECT data FROM pk_test WHERE id = 1")
        result = cursor.fetchone()
        assert result["data"] == "first", "First row should be unchanged"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS pk_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

    def test_constraint_violation_in_nested_transaction(self, sync_conn: psycopg.Connection):
        """
        Test: Constraint violation in nested transaction rolls back correctly.

        Expected: Savepoint rollback works when constraint violation occurs.
        """
        # Create test table with UNIQUE constraint
        try:
            sync_conn.execute("DROP TABLE IF EXISTS nested_constraint_test CASCADE")
            sync_conn.execute("""
                CREATE TABLE nested_constraint_test (
                    id SERIAL PRIMARY KEY,
                    unique_field TEXT UNIQUE NOT NULL
                )
            """)
            sync_conn.commit()
        except psycopg.Error:
            sync_conn.rollback()

        # Insert initial row
        try:
            sync_conn.execute(
                "INSERT INTO nested_constraint_test (unique_field) VALUES (%s)",
                ("value1",)
            )
            sync_conn.commit()
        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Failed to insert initial row: {e}")

        # Test nested transaction with constraint violation
        try:
            sync_conn.execute("BEGIN")

            # Insert valid row outside savepoint
            sync_conn.execute(
                "INSERT INTO nested_constraint_test (unique_field) VALUES (%s)",
                ("value2",)
            )

            # Create savepoint
            sync_conn.execute("SAVEPOINT sp1")

            # Try to insert duplicate (violates constraint)
            try:
                sync_conn.execute(
                    "INSERT INTO nested_constraint_test (unique_field) VALUES (%s)",
                    ("value1",)  # Duplicate
                )
                sync_conn.commit()
                pytest.fail("Expected constraint violation")

            except psycopg.Error:
                # Rollback to savepoint (not the whole transaction)
                sync_conn.execute("ROLLBACK TO SAVEPOINT sp1")

            # Commit outer transaction
            sync_conn.commit()

            # Verify: value1 and value2 exist, duplicate was rolled back
            cursor = sync_conn.execute("SELECT COUNT(*) FROM nested_constraint_test")
            count = cursor.fetchone()["count"]

            assert count == 2, "Savepoint rollback should keep outer transaction changes"

        except psycopg.Error as e:
            sync_conn.rollback()
            pytest.fail(f"Nested transaction with savepoint failed: {e}")

        finally:
            # Cleanup
            try:
                sync_conn.execute("DROP TABLE IF EXISTS nested_constraint_test CASCADE")
                sync_conn.commit()
            except psycopg.Error:
                pass
