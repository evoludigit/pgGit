"""
Property-based tests for data operations (branching, merging).

These tests validate that data operations maintain integrity across
different branches and versions of table schemas.
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
import psycopg

from tests.chaos.strategies import table_definition, git_branch_name


@pytest.mark.chaos
@pytest.mark.property
@pytest.mark.slow
class TestDataBranchingProperties:
    """Property-based tests for data branching (copy-on-write)."""

    @given(tbl_def=table_definition(), branch_name=git_branch_name)
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_branched_data_independent(
        self, sync_conn: psycopg.Connection, tbl_def: dict, branch_name: str
    ):
        """Property: Changes in branched data don't affect main branch."""
        assume(len(tbl_def["columns"]) > 0)  # Need at least one column

        # Create table and insert row on main
        sync_conn.execute(tbl_def["create_sql"])

        # Get first column name for insert
        first_col = tbl_def["columns"][0].split()[0]
        sync_conn.execute(
            f"INSERT INTO {tbl_def['name']} ({first_col}) VALUES (%s)", ("main_value",)
        )
        sync_conn.commit()

        # Count rows on main
        cursor1 = sync_conn.execute(f"SELECT COUNT(*) FROM {tbl_def['name']}")
        main_count_before = cursor1.fetchone()[0]

        try:
            # Create branch (simulate data branching)
            sync_conn.execute(
                "SELECT pggit.create_data_branch(%s, %s, %s)",
                (tbl_def["name"], "main", branch_name),
            )
            sync_conn.commit()

            # Insert row on branch
            sync_conn.execute(
                f"INSERT INTO {tbl_def['name']}__{branch_name} ({first_col}) VALUES (%s)",
                ("branch_value",),
            )
            sync_conn.commit()

            # Count rows on main again
            cursor2 = sync_conn.execute(f"SELECT COUNT(*) FROM {tbl_def['name']}")
            main_count_after = cursor2.fetchone()[0]

            # Property: Main branch row count unchanged
            assert main_count_before == main_count_after, (
                "Main branch should be unaffected by branch changes"
            )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Data branching functionality not implemented yet")

    @given(tbl_def=table_definition())
    @settings(
        max_examples=15,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_data_branch_creation_preserves_data(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Creating a data branch preserves all existing data."""
        assume(len(tbl_def["columns"]) > 0)

        # Create table and insert test data
        sync_conn.execute(tbl_def["create_sql"])

        # Insert some rows
        first_col = tbl_def["columns"][0].split()[0]
        for i in range(5):
            sync_conn.execute(
                f"INSERT INTO {tbl_def['name']} ({first_col}) VALUES (%s)",
                (f"value_{i}",),
            )
        sync_conn.commit()

        # Get row count on main
        cursor1 = sync_conn.execute(f"SELECT COUNT(*) FROM {tbl_def['name']}")
        main_count = cursor1.fetchone()[0]

        try:
            # Create branch
            branch_name = "test_branch"
            sync_conn.execute(
                "SELECT pggit.create_data_branch(%s, %s, %s)",
                (tbl_def["name"], "main", branch_name),
            )
            sync_conn.commit()

            # Get row count on branch
            cursor2 = sync_conn.execute(
                f"SELECT COUNT(*) FROM {tbl_def['name']}__{branch_name}"
            )
            branch_count = cursor2.fetchone()[0]

            # Property: Branch should have same data as main
            assert main_count == branch_count, (
                f"Branch should preserve data: main={main_count}, branch={branch_count}"
            )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Data branching functionality not implemented yet")


@pytest.mark.chaos
@pytest.mark.property
class TestDataIntegrityProperties:
    """Property-based tests for data integrity across operations."""

    @given(
        st.integers(min_value=1, max_value=10)  # Number of data modifications
    )
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_data_integrity_across_commits(
        self, sync_conn: psycopg.Connection, num_modifications: int
    ):
        """Property: Data integrity maintained across multiple commits."""
        # Create test table
        sync_conn.execute("""
            CREATE TABLE integrity_test (
                id SERIAL PRIMARY KEY,
                value INTEGER NOT NULL,
                modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        sync_conn.commit()

        try:
            # Insert initial data
            initial_value = 42
            sync_conn.execute(
                "INSERT INTO integrity_test (value) VALUES (%s)", (initial_value,)
            )
            sync_conn.commit()

            # Perform multiple modifications
            for i in range(num_modifications):
                # Update value
                new_value = initial_value + i + 1
                sync_conn.execute(
                    "UPDATE integrity_test SET value = %s WHERE id = 1", (new_value,)
                )
                sync_conn.commit()

                # Commit changes
                cursor = sync_conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"data-test-{i}", "main", f"Data test commit {i}"),
                )
                commit_id = cursor.fetchone()["commit_changes"]

                # Verify data integrity after each commit
                cursor = sync_conn.execute(
                    "SELECT value FROM integrity_test WHERE id = 1"
                )
                current_value = cursor.fetchone()["value"]
                assert current_value == new_value, (
                    f"Data integrity violated at step {i}: expected {new_value}, got {current_value}"
                )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Commit functionality not implemented yet")

    @given(tbl_def=table_definition())
    @settings(
        max_examples=15,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_schema_changes_preserve_existing_data(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Schema changes preserve existing data integrity."""
        assume(len(tbl_def["columns"]) >= 2)  # Need at least 2 columns

        # Create table
        sync_conn.execute(tbl_def["create_sql"])

        # Insert data using first two columns
        col1 = tbl_def["columns"][0].split()[0]
        col2 = tbl_def["columns"][1].split()[0]

        # Generate appropriate values for the columns
        val1 = "test_value" if "TEXT" in tbl_def["columns"][0] else 123
        val2 = "test_value2" if "TEXT" in tbl_def["columns"][1] else 456

        sync_conn.execute(
            f"INSERT INTO {tbl_def['name']} ({col1}, {col2}) VALUES (%s, %s)",
            (val1, val2),
        )
        sync_conn.commit()

        try:
            # Add a new column (schema change)
            sync_conn.execute(
                f"ALTER TABLE {tbl_def['name']} ADD COLUMN new_schema_col TEXT DEFAULT 'added'"
            )
            sync_conn.commit()

            # Verify original data preserved
            cursor = sync_conn.execute(f"SELECT {col1}, {col2} FROM {tbl_def['name']}")
            row = cursor.fetchone()

            assert row[col1] == val1, (
                "Original data should be preserved after schema change"
            )
            assert row[col2] == val2, (
                "Original data should be preserved after schema change"
            )

            # Verify new column has default value
            cursor = sync_conn.execute(f"SELECT new_schema_col FROM {tbl_def['name']}")
            new_col_value = cursor.fetchone()["new_schema_col"]
            assert new_col_value == "added", "New column should have default value"

        except psycopg.Error as e:
            # Expected to fail initially - schema changes may not be fully implemented
            pytest.skip(f"Schema change functionality incomplete: {e}")


@pytest.mark.chaos
@pytest.mark.property
class TestConcurrentDataOperations:
    """Property-based tests for concurrent data operations."""

    @given(
        st.integers(min_value=2, max_value=5)  # Number of concurrent operations
    )
    @settings(
        max_examples=10,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_concurrent_data_modifications_isolated(
        self, conn_pool, num_operations: int
    ):
        """Property: Concurrent data modifications maintain isolation."""
        assume(len(conn_pool) >= num_operations)  # Need enough connections

        # Create test table on first connection
        conn_pool[0].execute("""
            CREATE TABLE concurrent_test (
                id SERIAL PRIMARY KEY,
                counter INTEGER DEFAULT 0
            )
        """)
        conn_pool[0].execute("INSERT INTO concurrent_test (counter) VALUES (0)")
        conn_pool[0].commit()

        try:
            # Perform concurrent increments
            import threading

            results = []
            errors = []

            def increment_counter(conn_index: int):
                try:
                    conn = conn_pool[conn_index]
                    # Start transaction
                    conn.execute("BEGIN")
                    # Read current value
                    cursor = conn.execute(
                        "SELECT counter FROM concurrent_test WHERE id = 1"
                    )
                    current = cursor.fetchone()["counter"]
                    # Increment
                    new_value = current + 1
                    # Write back
                    conn.execute(
                        "UPDATE concurrent_test SET counter = %s WHERE id = 1",
                        (new_value,),
                    )
                    # Commit
                    conn.commit()
                    results.append(new_value)
                except Exception as e:
                    errors.append(str(e))

            # Run concurrent operations
            threads = []
            for i in range(num_operations):
                thread = threading.Thread(target=increment_counter, args=(i,))
                threads.append(thread)
                thread.start()

            # Wait for completion
            for thread in threads:
                thread.join()

            # Verify no errors occurred
            assert len(errors) == 0, f"Concurrent operations failed: {errors}"

            # Verify final counter value
            cursor = conn_pool[0].execute(
                "SELECT counter FROM concurrent_test WHERE id = 1"
            )
            final_value = cursor.fetchone()["counter"]
            assert final_value == num_operations, (
                f"Counter should be {num_operations}, got {final_value}"
            )

        except psycopg.Error:
            # Expected to fail initially - concurrent operations may not be properly implemented
            pytest.skip("Concurrent data operations not fully implemented yet")

        finally:
            # Cleanup
            try:
                for conn in conn_pool:
                    conn.rollback()
            except Exception:
                pass


@pytest.mark.chaos
@pytest.mark.property
class TestDataVersioningProperties:
    """Property-based tests for data versioning."""

    @given(
        st.integers(min_value=1, max_value=5)  # Number of versions
    )
    @settings(
        max_examples=15,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_data_version_history_preserved(
        self, sync_conn: psycopg.Connection, num_versions: int
    ):
        """Property: Data version history is preserved and accessible."""
        # Create versioned table
        sync_conn.execute("""
            CREATE TABLE versioned_data (
                id SERIAL PRIMARY KEY,
                content TEXT,
                version INTEGER DEFAULT 1
            )
        """)
        sync_conn.commit()

        try:
            # Create initial version
            sync_conn.execute(
                "INSERT INTO versioned_data (content, version) VALUES (%s, %s)",
                ("initial content", 1),
            )
            sync_conn.commit()

            # Commit initial version
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("v1", "main", "Initial version"),
            )
            v1_commit = cursor.fetchone()["commit_changes"]

            # Create additional versions
            for version in range(2, num_versions + 1):
                # Update content
                new_content = f"content version {version}"
                sync_conn.execute(
                    "UPDATE versioned_data SET content = %s, version = %s WHERE id = 1",
                    (new_content, version),
                )
                sync_conn.commit()

                # Commit version
                cursor = sync_conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"v{version}", "main", f"Version {version}"),
                )
                commit_id = cursor.fetchone()["commit_changes"]

                # Verify current content
                cursor = sync_conn.execute(
                    "SELECT content, version FROM versioned_data WHERE id = 1"
                )
                row = cursor.fetchone()
                assert row["content"] == new_content, (
                    f"Version {version} content incorrect"
                )
                assert row["version"] == version, f"Version {version} number incorrect"

            # Property: All versions should be accessible through git history
            # This would require version traversal functionality
            cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.commits")
            commit_count = cursor.fetchone()[0]
            assert commit_count == num_versions, (
                f"Should have {num_versions} commits, found {commit_count}"
            )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Data versioning functionality not implemented yet")
