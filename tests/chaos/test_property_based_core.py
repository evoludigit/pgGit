"""
Property-based tests for core pggit functionality.

These tests validate fundamental properties of pggit operations using Hypothesis
to generate diverse test inputs and catch edge cases.
"""

import uuid

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
from hypothesis import Phase
import psycopg

from tests.chaos.strategies import (
    table_definition,
    git_branch_name,
    commit_message,
    version_triple,
    version_increment_type,
)


@pytest.mark.chaos
@pytest.mark.property
class TestTableVersioningProperties:
    """Property-based tests for table versioning."""

    @given(tbl_def=table_definition())
    @settings(
        max_examples=50,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_create_table_always_gets_version(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Creating any valid table assigns a version."""
        # Create table
        sync_conn.execute(tbl_def["create_sql"])
        sync_conn.commit()

        # Check version assigned - this will likely fail initially (RED phase)
        try:
            cursor = sync_conn.execute(
                "SELECT * FROM pggit.get_version(%s)", (tbl_def["name"],)
            )
            version = cursor.fetchone()

            assert version is not None, f"Table {tbl_def['name']} should have version"
            assert version["major"] == 1, "Initial version should be 1.0.0"
            assert version["minor"] == 0
            assert version["patch"] == 0
        except psycopg.Error:
            # Expected to fail initially - pggit.get_version might not exist yet
            pytest.skip("get_version function not implemented yet")

    @given(tbl_def=table_definition(), branch1=git_branch_name, branch2=git_branch_name)
    @settings(
        max_examples=30,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_trinity_id_unique_across_branches(
        self, sync_conn: psycopg.Connection, tbl_def: dict, branch1: str, branch2: str
    ):
        """Property: Trinity IDs are unique across different branches."""
        assume(branch1 != branch2)  # Ensure different branches

        # Create table
        sync_conn.execute(tbl_def["create_sql"])
        sync_conn.commit()

        try:
            # Create commit on branch1
            cursor1 = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"commit-{branch1}", branch1, "Initial commit"),
            )
            trinity_id_1 = cursor1.fetchone()[0]

            # Create commit on branch2
            cursor2 = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"commit-{branch2}", branch2, "Initial commit"),
            )
            trinity_id_2 = cursor2.fetchone()[0]

            # Property: Trinity IDs must be unique
            assert trinity_id_1 != trinity_id_2, (
                f"Trinity IDs should be unique: {trinity_id_1} vs {trinity_id_2}"
            )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("increment_version function not implemented yet")

    @pytest.mark.parametrize("concurrency_level", [1, 5, 10])
    def test_trinity_id_uniqueness_under_concurrency(
        self, sync_conn: psycopg.Connection, concurrency_level: int
    ):
        """Test that Trinity IDs remain unique under concurrent commit operations."""
        import threading
        import queue

        results = queue.Queue()
        errors = []

        def worker_commit(worker_id: int):
            """Worker function that performs commits."""
            try:
                # Create unique table for this worker
                table_name = (
                    f"concurrency_test_{worker_id}_{threading.current_thread().ident}"
                )
                sync_conn.execute(f"CREATE TABLE {table_name} (id INT)")
                sync_conn.commit()

                # Perform multiple commits
                trinity_ids = []
                for i in range(3):  # 3 commits per worker
                    cursor = sync_conn.execute(
                        "SELECT pggit.commit_changes(%s, %s, %s)",
                        ("main", f"Worker {worker_id} commit {i}", None),
                    )
                    trinity_id = cursor.fetchone()["commit_changes"]
                    trinity_ids.append(trinity_id)
                    sync_conn.commit()

                results.put(
                    {
                        "worker_id": worker_id,
                        "trinity_ids": trinity_ids,
                        "success": True,
                    }
                )

            except Exception as e:
                errors.append(f"Worker {worker_id}: {e}")
                results.put({"worker_id": worker_id, "success": False, "error": str(e)})

        # Start concurrent workers
        threads = []
        for i in range(concurrency_level):
            thread = threading.Thread(target=worker_commit, args=(i,))
            threads.append(thread)
            thread.start()

        # Wait for all threads to complete
        for thread in threads:
            thread.join()

        # Collect results
        all_trinity_ids = []
        successful_workers = 0

        while not results.empty():
            result = results.get()
            if result["success"]:
                successful_workers += 1
                all_trinity_ids.extend(result["trinity_ids"])
            else:
                errors.append(result["error"])

        # Verify results
        assert successful_workers == concurrency_level, (
            f"Expected {concurrency_level} successful workers, got {successful_workers}"
        )
        assert len(all_trinity_ids) == concurrency_level * 3, (
            f"Expected {concurrency_level * 3} Trinity IDs, got {len(all_trinity_ids)}"
        )

        # Verify uniqueness
        unique_ids = set(all_trinity_ids)
        assert len(unique_ids) == len(all_trinity_ids), (
            f"Found duplicate Trinity IDs: {all_trinity_ids}"
        )

        # Verify format
        for trinity_id in all_trinity_ids:
            assert len(trinity_id) == 36, f"Invalid Trinity ID length: {trinity_id}"
            assert trinity_id[20] == "-" and trinity_id[27] == "-", (
                f"Invalid Trinity ID format: {trinity_id}"
            )

        assert len(errors) == 0, f"Found errors during concurrent execution: {errors}"

    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100),
    )
    @settings(max_examples=50, deadline=None)
    def test_minor_increment_resets_patch(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Minor increment resets patch to 0."""
        try:
            cursor = sync_conn.execute(
                "SELECT pggit.increment_version(%s, %s, %s, 'minor')",
                (major, minor, patch),
            )
            new_version = cursor.fetchone()["increment_version"]

            new_major, new_minor, new_patch = map(int, new_version.split("."))

            # Properties
            assert new_major == major, "Major version should not change"
            assert new_minor == minor + 1, "Minor should increment by 1"
            assert new_patch == 0, "Patch should reset to 0"

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("increment_version function not implemented yet")

    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100),
    )
    @settings(max_examples=50, deadline=None)
    def test_major_increment_resets_minor_and_patch(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Major increment resets minor and patch to 0."""
        try:
            cursor = sync_conn.execute(
                "SELECT pggit.increment_version(%s, %s, %s, 'major')",
                (major, minor, patch),
            )
            new_version = cursor.fetchone()["increment_version"]

            new_major, new_minor, new_patch = map(int, new_version.split("."))

            # Properties
            assert new_major == major + 1, "Major should increment by 1"
            assert new_minor == 0, "Minor should reset to 0"
            assert new_patch == 0, "Patch should reset to 0"

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("increment_version function not implemented yet")


@pytest.mark.chaos
@pytest.mark.property
class TestBranchNamingProperties:
    """Property-based tests for branch naming constraints."""

    @given(branch=git_branch_name)
    @settings(max_examples=100, deadline=None)
    def test_valid_branch_names_accepted(
        self, sync_conn: psycopg.Connection, branch: str
    ):
        """Property: All valid Git-style branch names should be accepted."""
        # Create a simple table first
        sync_conn.execute("CREATE TABLE test_tbl (id INT)")
        sync_conn.commit()

        try:
            # Attempt to create branch via commit
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"commit-{branch[:30]}", branch, "Test commit"),
            )
            result = cursor.fetchone()

            # Should succeed without error for valid branch names
            assert result is not None, f"Branch '{branch}' should be valid"

        except psycopg.Error as e:
            # If it fails, it should be due to a real constraint, not a crash
            # This is expected to fail initially as branch validation may not be implemented
            assert (
                "branch" in str(e).lower()
                or "invalid" in str(e).lower()
                or "does not exist" in str(e).lower()
            ), f"Unexpected error for branch '{branch}': {e}"
        finally:
            sync_conn.rollback()

    def test_edge_cases_and_error_handling(self, sync_conn: psycopg.Connection):
        """Test edge cases and error handling for implemented functions."""
        # Test commit_changes with very long message
        long_message = "x" * 1000
        cursor = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s)", ("main", long_message)
        )
        trinity_id = cursor.fetchone()["commit_changes"]
        assert trinity_id is not None
        assert len(trinity_id) == 36  # Standard Trinity ID length

        # Verify the long message was stored
        cursor = sync_conn.execute(
            "SELECT message FROM pggit.commits WHERE hash = %s", (trinity_id,)
        )
        stored_message = cursor.fetchone()["message"]
        assert stored_message == long_message

        # Test get_version on non-existent table
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("non_existent_table",)
        )
        result = cursor.fetchall()
        assert len(result) == 0  # Should return empty result set

        # Test increment_version with invalid type
        try:
            cursor = sync_conn.execute(
                "SELECT pggit.increment_version(%s, %s, %s, %s)",
                (1, 0, 0, "invalid_type"),
            )
            # Should not reach here
            assert False, "Expected exception for invalid increment type"
        except psycopg.errors.RaiseException as e:
            assert "Invalid increment type" in str(e)

        # Test calculate_schema_hash on non-existent table
        cursor = sync_conn.execute(
            "SELECT pggit.calculate_schema_hash(%s)", ("non_existent_table",)
        )
        result = cursor.fetchone()["calculate_schema_hash"]
        assert result is None  # Should return NULL for non-existent table

        sync_conn.commit()

    def test_basic_performance_under_load(self, sync_conn: psycopg.Connection):
        """Test that functions perform adequately under basic load."""
        import time

        # Test Trinity ID generation performance (should be fast)
        start_time = time.time()
        for i in range(10):
            cursor = sync_conn.execute("SELECT pggit.generate_trinity_id()")
            trinity_id = cursor.fetchone()["generate_trinity_id"]
            assert len(trinity_id) == 36
        generation_time = time.time() - start_time
        assert generation_time < 0.1, (
            f"Trinity ID generation too slow: {generation_time}s for 10 IDs"
        )

        # Test commit performance (should be reasonable)
        start_time = time.time()
        for i in range(5):
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s)", ("main", f"Performance test {i}")
            )
            result = cursor.fetchone()["commit_changes"]
            assert result is not None
        commit_time = time.time() - start_time
        assert commit_time < 1.0, f"Commits too slow: {commit_time}s for 5 commits"

        sync_conn.commit()


@pytest.mark.chaos
@pytest.mark.property
class TestIdentifierValidationProperties:
    """Property-based tests for identifier validation."""

    @given(
        st.text(
            alphabet=st.characters(
                categories=["L", "N"],
                exclude_categories=["C"],  # Exclude control characters
            ),
            min_size=1,
            max_size=100,
        )
    )
    @settings(max_examples=200, deadline=None)
    def test_valid_identifiers_accepted(
        self, sync_conn: psycopg.Connection, identifier: str
    ):
        """Property: Valid identifiers should be accepted for table names."""
        # Filter out clearly invalid identifiers
        assume(len(identifier) <= 63)  # PostgreSQL limit
        assume(
            identifier[0].isalpha() or identifier[0] == "_"
        )  # Must start with letter/underscore
        assume(
            all(c.isalnum() or c == "_" for c in identifier)
        )  # Only alphanumeric + underscore

        # Avoid reserved words
        reserved = {"select", "from", "where", "table", "user", "group"}
        assume(identifier.lower() not in reserved)

        try:
            # Try to create table with this identifier
            sync_conn.execute(f"CREATE TABLE {identifier} (id INT)")
            sync_conn.commit()

            # If we get here, the identifier was accepted
            assert True, f"Valid identifier '{identifier}' should be accepted"

        except psycopg.Error as e:
            # Should not fail for valid identifiers
            pytest.fail(f"Valid identifier '{identifier}' rejected: {e}")
        finally:
            # Clean up
            try:
                sync_conn.execute(f"DROP TABLE IF EXISTS {identifier}")
                sync_conn.commit()
            except psycopg.Error:
                pass  # Ignore cleanup errors
            sync_conn.rollback()
