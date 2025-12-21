"""
Migration failure and rollback scenario tests.

These tests validate that migration failures are handled gracefully,
including syntax errors, partial application, and rollback correctness.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.migration
class TestMigrationFailures:
    """Test migration failure scenarios."""

    def test_migration_syntax_error(self, sync_conn: psycopg.Connection):
        """
        Test: Migration with syntax error fails gracefully.

        Expected: Error raised, no partial application, transaction rolled back.
        """
        # Create table
        sync_conn.execute("CREATE TABLE migration_test (id INT)")
        sync_conn.commit()

        # Attempt migration with syntax error
        try:
            sync_conn.execute("BEGIN")

            # Valid change
            sync_conn.execute("ALTER TABLE migration_test ADD COLUMN valid_col TEXT")

            # Syntax error - missing column name
            sync_conn.execute("ALTER TABLE migration_test ADD COLUMN INVALID SYNTAX")

            sync_conn.commit()
            pytest.fail("Expected syntax error")

        except psycopg.Error:
            sync_conn.rollback()

        # Verify complete rollback - valid_col should not exist
        cursor = sync_conn.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = 'migration_test'
            AND column_name = 'valid_col'
        """)

        assert cursor.fetchone() is None, \
            "Migration with error should rollback all changes, not just failed part"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS migration_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Syntax error in migration properly rolled back")

    def test_partial_migration_detection(self, sync_conn: psycopg.Connection):
        """
        Test: Detect when table state suggests partial migration.

        Expected: System can identify incomplete migrations through schema analysis.
        """
        # Create table
        sync_conn.execute("CREATE TABLE partial_migration_test (id INT)")
        sync_conn.commit()

        # Apply first part of migration
        sync_conn.execute("BEGIN")
        sync_conn.execute("ALTER TABLE partial_migration_test ADD COLUMN col1 TEXT")
        sync_conn.commit()

        # Simulate scenario: process terminates before second part
        # (In real scenario, we would have more schema analysis here)

        # Detect the state
        cursor = sync_conn.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = 'partial_migration_test'
            ORDER BY ordinal_position
        """)
        columns = [row["column_name"] for row in cursor.fetchall()]

        # We have id and col1 - partial migration visible
        assert "id" in columns, "Should have id column"
        assert "col1" in columns, "Should have col1 from partial migration"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS partial_migration_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Partial migration state is detectable")

    def test_conflicting_migrations(self, sync_conn: psycopg.Connection):
        """
        Test: Two migrations conflict (e.g., both add same column).

        Expected: Second migration fails cleanly without partial application.
        """
        # Create table
        sync_conn.execute("CREATE TABLE conflict_test (id INT)")
        sync_conn.commit()

        # First migration: add column
        sync_conn.execute("ALTER TABLE conflict_test ADD COLUMN conflict_col TEXT")
        sync_conn.commit()

        # Second migration: try to add same column
        try:
            sync_conn.execute("ALTER TABLE conflict_test ADD COLUMN conflict_col TEXT")
            sync_conn.commit()

            pytest.fail("Should raise error for duplicate column")

        except psycopg.Error as e:
            sync_conn.rollback()

            # Expected error
            error_msg = str(e).lower()
            assert "already exists" in error_msg or "duplicate" in error_msg, \
                f"Expected duplicate column error, got: {e}"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS conflict_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Conflicting migrations detected and prevented")

    def test_migration_rollback_completeness(self, sync_conn: psycopg.Connection):
        """
        Test: Migration rollback completely reverses all changes.

        Expected: No residual changes after rollback, clean state restored.
        """
        # Create table
        sync_conn.execute("CREATE TABLE rollback_test (id INT)")
        sync_conn.commit()

        # Get initial column count
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'rollback_test'
        """)
        initial_cols = cursor.fetchone()["count"]

        # Attempt migration that will fail
        try:
            sync_conn.execute("BEGIN")

            # Add multiple columns
            sync_conn.execute("ALTER TABLE rollback_test ADD COLUMN col1 TEXT")
            sync_conn.execute("ALTER TABLE rollback_test ADD COLUMN col2 TEXT")
            sync_conn.execute("ALTER TABLE rollback_test ADD COLUMN col3 TEXT")

            # Force error
            sync_conn.execute("SELECT 1/0")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify complete rollback
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'rollback_test'
        """)
        final_cols = cursor.fetchone()["count"]

        assert initial_cols == final_cols, \
            f"Rollback should restore original state. Before: {initial_cols}, After: {final_cols}"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS rollback_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Migration rollback is complete and thorough")

    def test_migration_with_data_changes(self, sync_conn: psycopg.Connection):
        """
        Test: Migration involving both schema and data changes rolls back completely.

        Expected: Both schema and data changes are rolled back on error.
        """
        # Create table with data
        sync_conn.execute("CREATE TABLE data_migration_test (id INT PRIMARY KEY, value TEXT)")
        sync_conn.commit()

        # Insert initial data
        sync_conn.execute("INSERT INTO data_migration_test VALUES (1, 'initial')")
        sync_conn.commit()

        # Get initial state
        cursor = sync_conn.execute("SELECT COUNT(*) FROM data_migration_test")
        initial_count = cursor.fetchone()["count"]

        # Attempt migration with data changes
        try:
            sync_conn.execute("BEGIN")

            # Schema change
            sync_conn.execute("ALTER TABLE data_migration_test ADD COLUMN new_col INT")

            # Data change
            sync_conn.execute("INSERT INTO data_migration_test VALUES (2, 'new', NULL)")

            # Force error
            sync_conn.execute("SELECT 1/0")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify both schema and data rolled back
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'data_migration_test'
        """)
        final_cols = cursor.fetchone()["count"]

        cursor = sync_conn.execute("SELECT COUNT(*) FROM data_migration_test")
        final_count = cursor.fetchone()["count"]

        # Should be back to 2 columns (id, value) and 1 row
        assert final_cols == 2, f"Schema should rollback, expected 2 cols, got {final_cols}"
        assert final_count == initial_count, \
            f"Data should rollback, expected {initial_count} rows, got {final_count}"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS data_migration_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Schema and data migrations roll back completely together")
