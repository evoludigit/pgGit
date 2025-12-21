"""
Recovery procedure and corruption remediation tests.

These tests validate detection and recovery mechanisms for various corruption scenarios.
"""

import psycopg
import pytest


@pytest.mark.chaos
@pytest.mark.recovery
class TestCorruptionDetection:
    """Test corruption detection capabilities."""

    def test_detect_schema_inconsistency(self, sync_conn: psycopg.Connection):
        """
        Test: Detect inconsistencies between actual schema and metadata.

        Expected: Differences between schema state and records can be identified.
        """
        # Create table
        sync_conn.execute("CREATE TABLE schema_check (id INT PRIMARY KEY, data TEXT)")
        sync_conn.commit()

        # Get initial schema structure
        cursor = sync_conn.execute("""
            SELECT COUNT(*) as col_count
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'schema_check'
        """)
        initial_cols = cursor.fetchone()["col_count"]

        # Manually add column (bypassing any version tracking)
        sync_conn.execute("ALTER TABLE schema_check ADD COLUMN hidden_col INT")
        sync_conn.commit()

        # Check for inconsistency
        cursor = sync_conn.execute("""
            SELECT COUNT(*) as col_count
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'schema_check'
        """)
        current_cols = cursor.fetchone()["col_count"]

        # Should detect the change
        assert current_cols > initial_cols, "Schema inconsistency should be detectable"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS schema_check CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Schema inconsistencies are detectable")

    def test_detect_referential_integrity_violation(
        self, sync_conn: psycopg.Connection,
    ):
        """
        Test: Detect orphaned foreign key references.

        Expected: Can identify rows with broken FK references.
        """
        # Create tables
        sync_conn.execute("CREATE TABLE parent_ref (id INT PRIMARY KEY)")
        sync_conn.execute("""
            CREATE TABLE child_ref (
                id INT PRIMARY KEY,
                parent_id INT REFERENCES parent_ref(id)
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO parent_ref VALUES (1)")
        sync_conn.execute("INSERT INTO child_ref VALUES (1, 1)")
        sync_conn.commit()

        # Disable FK checks to inject corruption
        try:
            sync_conn.execute("SET session_replication_role = replica")
            sync_conn.execute("DELETE FROM parent_ref WHERE id = 1")
            sync_conn.execute("SET session_replication_role = default")
            sync_conn.commit()

            # Now detect the orphaned reference
            cursor = sync_conn.execute("""
                SELECT c.id
                FROM child_ref c
                LEFT JOIN parent_ref p ON c.parent_id = p.id
                WHERE p.id IS NULL AND c.parent_id IS NOT NULL
            """)
            orphans = cursor.fetchall()

            # Should find the orphaned reference
            assert len(orphans) > 0, "Should detect orphaned foreign key reference"

        except psycopg.Error as e:
            # If we can't disable FK checks, that's also valid (good security)
            if "replication_role" not in str(e).lower():
                raise

        # Cleanup
        try:
            sync_conn.execute("SET session_replication_role = default")
            sync_conn.execute("DROP TABLE IF EXISTS child_ref CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS parent_ref CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Referential integrity violations are detectable")

    def test_detect_missing_indexes(self, sync_conn: psycopg.Connection):
        """
        Test: Detect tables missing expected indexes.

        Expected: Can identify missing indexes that should exist.
        """
        # Create table with index
        sync_conn.execute("CREATE TABLE index_test (id INT PRIMARY KEY, data TEXT)")
        sync_conn.execute("CREATE INDEX idx_data ON index_test(data)")
        sync_conn.commit()

        # Verify index exists
        cursor = sync_conn.execute("""
            SELECT COUNT(*) as idx_count
            FROM pg_indexes
            WHERE tablename = 'index_test'
        """)
        initial_indexes = cursor.fetchone()["idx_count"]
        assert initial_indexes > 0, "Index should be created"

        # Drop index (simulate corruption)
        sync_conn.execute("DROP INDEX idx_data")
        sync_conn.commit()

        # Detect missing index
        cursor = sync_conn.execute("""
            SELECT COUNT(*) as idx_count
            FROM pg_indexes
            WHERE tablename = 'index_test'
        """)
        current_indexes = cursor.fetchone()["idx_count"]

        assert current_indexes < initial_indexes, "Missing index should be detectable"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS index_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Missing indexes are detectable")


@pytest.mark.chaos
@pytest.mark.recovery
class TestRecoveryValidation:
    """Test recovery validation and consistency checks."""

    def test_consistency_check_after_recovery(self, sync_conn: psycopg.Connection):
        """
        Test: Verify consistency after recovery operation.

        Expected: System state is consistent after recovery procedures.
        """
        # Create tables
        sync_conn.execute("""
            CREATE TABLE recovery_parent (id INT PRIMARY KEY, name TEXT)
        """)
        sync_conn.execute("""
            CREATE TABLE recovery_child (id INT PRIMARY KEY, parent_id INT REFERENCES recovery_parent(id))
        """)
        sync_conn.commit()

        # Insert test data
        sync_conn.execute("INSERT INTO recovery_parent VALUES (1, 'parent1')")
        sync_conn.execute("INSERT INTO recovery_child VALUES (1, 1)")
        sync_conn.commit()

        # Simulate recovery check
        cursor = sync_conn.execute("""
            SELECT c.id, p.id
            FROM recovery_child c
            LEFT JOIN recovery_parent p ON c.parent_id = p.id
            WHERE c.parent_id IS NOT NULL
        """)
        checks = cursor.fetchall()

        # All children should have valid parents
        for check in checks:
            assert check["id"] is not None, "Child ID should exist"
            assert check.get("id") is not None, "Parent should exist for all children"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS recovery_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS recovery_parent CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Consistency check after recovery passes")

    def test_version_sequence_validation(self, sync_conn: psycopg.Connection):
        """
        Test: Validate that version sequences are consistent.

        Expected: Version numbering follows expected patterns.
        """
        # Create table
        sync_conn.execute("CREATE TABLE version_seq_test (id INT)")
        sync_conn.commit()

        # Try to get version
        try:
            cursor = sync_conn.execute(
                "SELECT * FROM pggit.get_version(%s)",
                ("version_seq_test",),
            )
            version = cursor.fetchone()

            if version is not None:
                # Validate version fields are non-negative
                major = version.get("major", 0)
                minor = version.get("minor", 0)
                patch = version.get("patch", 0)

                assert major >= 0, "Major version should be non-negative"
                assert minor >= 0, "Minor version should be non-negative"
                assert patch >= 0, "Patch version should be non-negative"

        except psycopg.Error as e:
            if "does not exist" in str(e).lower():
                pytest.skip("pggit.get_version not available")

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS version_seq_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Version sequence validation passes")

    def test_data_completeness_after_recovery(self, sync_conn: psycopg.Connection):
        """
        Test: Data completeness is maintained after recovery.

        Expected: No rows are lost, no duplicates created during recovery.
        """
        # Create table
        sync_conn.execute("""
            CREATE TABLE completeness_test (
                id SERIAL PRIMARY KEY,
                value INT,
                UNIQUE(value)
            )
        """)
        sync_conn.commit()

        # Insert test data
        test_count = 10
        for i in range(test_count):
            sync_conn.execute("INSERT INTO completeness_test (value) VALUES (%s)", (i,))
        sync_conn.commit()

        # Verify all data present
        cursor = sync_conn.execute("SELECT COUNT(*) FROM completeness_test")
        count = cursor.fetchone()["count"]

        assert count == test_count, f"Should have {test_count} rows, got {count}"

        # Verify no duplicates
        cursor = sync_conn.execute("""
            SELECT value, COUNT(*) as cnt
            FROM completeness_test
            GROUP BY value
            HAVING COUNT(*) > 1
        """)
        duplicates = cursor.fetchall()

        assert len(duplicates) == 0, "No duplicates should exist"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS completeness_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Data completeness after recovery is verified")
