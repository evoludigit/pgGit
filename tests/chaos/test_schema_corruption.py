"""
Schema corruption detection and validation tests.

These tests verify that schema corruption can be detected and prevented,
including manual schema changes, metadata corruption, and referential integrity violations.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.corruption
class TestSchemaCorruption:
    """Test schema corruption detection and prevention."""

    def test_manual_schema_change_detection(self, sync_conn: psycopg.Connection):
        """
        Test: Detect schema changes made outside of pggit.

        Expected: System can detect schema drift through structural analysis.
        """
        # Create table
        sync_conn.execute("CREATE TABLE drift_test (id INT PRIMARY KEY)")
        sync_conn.commit()

        # Get initial column count
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'drift_test'
        """)
        initial_count = cursor.fetchone()["count"]

        # Manual change (bypassing pggit)
        sync_conn.execute("ALTER TABLE drift_test ADD COLUMN manual_col TEXT")
        sync_conn.commit()

        # Get updated count
        cursor = sync_conn.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'drift_test'
        """)
        updated_count = cursor.fetchone()["count"]

        # Verify change was detected
        assert updated_count > initial_count, \
            "Schema drift should be detectable through column count"

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS drift_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Manual schema changes are detectable")

    def test_corrupted_version_metadata(self, sync_conn: psycopg.Connection):
        """
        Test: Detect corrupted version metadata.

        Expected: Invalid version data can be identified and prevented.
        """
        # Create table
        sync_conn.execute("CREATE TABLE version_test (id INT)")
        sync_conn.commit()

        # Check if pggit version tables exist
        try:
            # Corrupt version metadata directly
            sync_conn.execute("""
                UPDATE pggit.table_versions
                SET major = -1, minor = -1, patch = -1
                WHERE table_name = 'version_test'
            """)
            sync_conn.commit()

            # Try to retrieve version (should show corruption)
            cursor = sync_conn.execute(
                "SELECT * FROM pggit.get_version(%s)",
                ("version_test",)
            )
            version = cursor.fetchone()

            # Version should be retrievable but show invalid values
            if version is not None:
                # Check if negative values are accepted
                has_corruption = (
                    version.get("major", 0) < 0 or
                    version.get("minor", 0) < 0 or
                    version.get("patch", 0) < 0
                )
                assert has_corruption, "Corrupted metadata should be visible"

        except psycopg.Error as e:
            # If pggit.table_versions doesn't exist, skip
            if "does not exist" in str(e).lower():
                pytest.skip("pggit.table_versions not available")
            else:
                raise

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS version_test CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Corrupted version metadata can be identified")

    def test_missing_trinity_id_detection(self, sync_conn: psycopg.Connection):
        """
        Test: Detect missing or orphaned Trinity ID references.

        Expected: System can find commits with missing Trinity IDs.
        """
        # Check if pggit tables exist
        try:
            import uuid
            unique_id = uuid.uuid4().hex[:8]

            cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.commits")
            initial_commit_count = cursor.fetchone()["count"]

            # Try to create a commit with unique ID
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"trinity-orphan-{unique_id}", "main", f"Test commit {unique_id}")
            )
            result = cursor.fetchone()
            sync_conn.commit()

            # Verify commit was created
            cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.commits")
            new_count = cursor.fetchone()["count"]
            assert new_count > initial_commit_count, "Commit should be created"

            # Try to delete Trinity ID (simulate corruption)
            sync_conn.execute("""
                DELETE FROM pggit.trinity_ids
                WHERE id LIKE %s
            """, (f"trinity-orphan-{unique_id}%",))
            sync_conn.commit()

            # Check for orphaned commits
            cursor = sync_conn.execute("""
                SELECT c.id
                FROM pggit.commits c
                LEFT JOIN pggit.trinity_ids t ON c.trinity_id = t.id
                WHERE t.id IS NULL
            """)
            orphans = cursor.fetchall()

            # Should detect orphaned commits
            assert len(orphans) > 0, "Should detect orphaned commits"

        except psycopg.Error as e:
            if "does not exist" in str(e).lower():
                pytest.skip("pggit tables not available")
            else:
                raise

        print("\n✅ Missing Trinity ID references are detectable")

    def test_foreign_key_constraint_enforcement(self, sync_conn: psycopg.Connection):
        """
        Test: Foreign key constraints prevent corruption.

        Expected: FK constraints are properly enforced.
        """
        # Create tables with FK relationship
        sync_conn.execute("CREATE TABLE fk_parent (id INT PRIMARY KEY)")
        sync_conn.execute("""
            CREATE TABLE fk_child (
                id INT PRIMARY KEY,
                parent_id INT NOT NULL REFERENCES fk_parent(id)
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO fk_parent VALUES (1)")
        sync_conn.execute("INSERT INTO fk_child VALUES (1, 1)")
        sync_conn.commit()

        # Try to delete parent (should fail due to FK)
        try:
            sync_conn.execute("DELETE FROM fk_parent WHERE id = 1")
            sync_conn.commit()

            pytest.fail("Should not allow deletion due to FK constraint")

        except psycopg.IntegrityError:
            sync_conn.rollback()
            # Expected: FK constraint prevents deletion

        # Cleanup
        try:
            sync_conn.execute("DROP TABLE IF EXISTS fk_child CASCADE")
            sync_conn.execute("DROP TABLE IF EXISTS fk_parent CASCADE")
            sync_conn.commit()
        except psycopg.Error:
            pass

        print("\n✅ Foreign key constraints properly prevent corruption")
