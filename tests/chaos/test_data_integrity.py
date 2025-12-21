"""
Data integrity tests under adverse conditions.

These tests validate that data integrity guarantees are maintained,
including cascading deletes, type consistency, and constraint enforcement.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.integrity
class TestDataIntegrity:
    """Test data integrity guarantees."""

    def test_cascade_delete_integrity(self, sync_conn: psycopg.Connection):
        """
        Test: Cascading deletes maintain referential integrity.

        Expected: All dependent rows are deleted, no orphans remain.
        """
        # Create tables with cascade delete
        sync_conn.execute("CREATE TABLE cascade_parent (id INT PRIMARY KEY)")
        sync_conn.execute("""
            CREATE TABLE cascade_child (
                id INT PRIMARY KEY,
                parent_id INT REFERENCES cascade_parent(id) ON DELETE CASCADE
            )
        """)
        sync_conn.commit()

        # Insert test data
        sync_conn.execute("INSERT INTO cascade_parent VALUES (1)")
        sync_conn.execute("INSERT INTO cascade_parent VALUES (2)")
        sync_conn.execute("INSERT INTO cascade_child VALUES (1, 1)")
        sync_conn.execute("INSERT INTO cascade_child VALUES (2, 1)")
        sync_conn.execute("INSERT INTO cascade_child VALUES (3, 2)")
        sync_conn.commit()

        # Delete parent (should cascade)
        sync_conn.execute("DELETE FROM cascade_parent WHERE id = 1")
        sync_conn.commit()

        # Verify cascade occurred
        cursor = sync_conn.execute("SELECT COUNT(*) FROM cascade_child WHERE parent_id = 1")
        count = cursor.fetchone()["count"]

        assert count == 0, "Cascade should delete all child rows with parent_id=1"

        # Verify other rows unaffected
        cursor = sync_conn.execute("SELECT COUNT(*) FROM cascade_child WHERE parent_id = 2")
        count = cursor.fetchone()["count"]

        assert count == 1, "Other parent's children should be unaffected"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS cascade_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS cascade_parent CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Cascade delete maintains integrity correctly")

    def test_data_type_consistency_after_alteration(self, sync_conn: psycopg.Connection):
        """
        Test: Data remains consistent when column types are altered.

        Expected: Data survives compatible type changes without corruption.
        """
        # Create table
        sync_conn.execute("CREATE TABLE type_test (id INT PRIMARY KEY, value TEXT)")
        sync_conn.commit()

        # Insert test data
        sync_conn.execute("INSERT INTO type_test VALUES (1, 'test data')")
        sync_conn.commit()

        # Verify initial data
        cursor = sync_conn.execute("SELECT value FROM type_test WHERE id = 1")
        original_value = cursor.fetchone()["value"]

        # Alter column type (VARCHAR is compatible with TEXT)
        sync_conn.execute("ALTER TABLE type_test ALTER COLUMN value TYPE VARCHAR(255)")
        sync_conn.commit()

        # Verify data integrity after type change
        cursor = sync_conn.execute("SELECT value FROM type_test WHERE id = 1")
        modified_value = cursor.fetchone()["value"]

        assert original_value == modified_value, \
            f"Data should survive type change. Original: {original_value}, After: {modified_value}"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS type_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Data type consistency maintained after alteration")

    def test_unique_constraint_integrity(self, sync_conn: psycopg.Connection):
        """
        Test: Unique constraints prevent duplicate data even under concurrent pressure.

        Expected: No duplicates ever exist when unique constraint is enforced.
        """
        # Create table with unique constraint
        sync_conn.execute("""
            CREATE TABLE unique_test (
                id SERIAL PRIMARY KEY,
                unique_code TEXT UNIQUE NOT NULL
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO unique_test (unique_code) VALUES ('CODE-001')")
        sync_conn.execute("INSERT INTO unique_test (unique_code) VALUES ('CODE-002')")
        sync_conn.commit()

        # Try to insert duplicate
        try:
            sync_conn.execute("INSERT INTO unique_test (unique_code) VALUES ('CODE-001')")
            sync_conn.commit()

            pytest.fail("Should prevent duplicate unique values")

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify no duplicates exist
        cursor = sync_conn.execute("""
            SELECT unique_code, COUNT(*) as cnt
            FROM unique_test
            GROUP BY unique_code
            HAVING COUNT(*) > 1
        """)
        duplicates = cursor.fetchall()

        assert len(duplicates) == 0, "No duplicates should exist with unique constraint"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS unique_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Unique constraint integrity is maintained")

    def test_not_null_constraint_integrity(self, sync_conn: psycopg.Connection):
        """
        Test: NOT NULL constraints prevent incomplete data.

        Expected: No NULL values in columns with NOT NULL constraint.
        """
        # Create table with NOT NULL constraint
        sync_conn.execute("""
            CREATE TABLE not_null_test (
                id SERIAL PRIMARY KEY,
                required_field TEXT NOT NULL
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO not_null_test (required_field) VALUES ('value1')")
        sync_conn.commit()

        # Try to insert NULL
        try:
            sync_conn.execute("INSERT INTO not_null_test (required_field) VALUES (NULL)")
            sync_conn.commit()

            pytest.fail("Should prevent NULL in NOT NULL column")

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify no NULLs exist
        cursor = sync_conn.execute(
            "SELECT COUNT(*) FROM not_null_test WHERE required_field IS NULL"
        )
        null_count = cursor.fetchone()["count"]

        assert null_count == 0, "No NULLs should exist in NOT NULL column"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS not_null_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ NOT NULL constraint integrity is maintained")

    def test_check_constraint_integrity(self, sync_conn: psycopg.Connection):
        """
        Test: CHECK constraints maintain domain integrity.

        Expected: Only values within allowed range can be stored.
        """
        # Create table with CHECK constraint
        sync_conn.execute("""
            CREATE TABLE check_test (
                id SERIAL PRIMARY KEY,
                age INT CHECK (age >= 0 AND age <= 150)
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO check_test (age) VALUES (25)")
        sync_conn.execute("INSERT INTO check_test (age) VALUES (0)")
        sync_conn.execute("INSERT INTO check_test (age) VALUES (150)")
        sync_conn.commit()

        # Try to insert invalid data
        try:
            sync_conn.execute("INSERT INTO check_test (age) VALUES (-1)")
            sync_conn.commit()

            pytest.fail("Should prevent value below 0")

        except psycopg.IntegrityError:
            sync_conn.rollback()

        try:
            sync_conn.execute("INSERT INTO check_test (age) VALUES (151)")
            sync_conn.commit()

            pytest.fail("Should prevent value above 150")

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify only valid values exist
        cursor = sync_conn.execute(
            "SELECT COUNT(*) FROM check_test WHERE age < 0 OR age > 150"
        )
        invalid_count = cursor.fetchone()["count"]

        assert invalid_count == 0, "No invalid values should exist with CHECK constraint"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS check_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ CHECK constraint integrity is maintained")
