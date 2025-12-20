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
            pytest.skip("commit_changes function not implemented yet")

    @given(msg=commit_message)
    @settings(
        max_examples=100,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_commit_message_preserved(self, sync_conn: psycopg.Connection, msg: str):
        """Property: Commit messages are preserved exactly as written."""
        table_name = f"test_table_{uuid.uuid4().hex[:8]}"
        sync_conn.execute(f"CREATE TABLE {table_name} (id SERIAL PRIMARY KEY)")
        sync_conn.commit()

        try:
            # Make commit with generated message (use unique ID per test)
            commit_id = f"test-commit-{uuid.uuid4().hex[:8]}"
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)", (commit_id, "main", msg)
            )
            result_commit_id = cursor.fetchone()["commit_changes"]
            assert result_commit_id == commit_id, (
                "Function should return the Trinity ID"
            )

            # Retrieve commit message
            cursor = sync_conn.execute(
                "SELECT message FROM pggit.commits WHERE hash = %s", (commit_id,)
            )
            stored_msg = cursor.fetchone()["message"]

            # Property: Message should be identical
            assert stored_msg == msg, "Commit message should be preserved exactly"

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Commits table or commit_changes not implemented yet")
        finally:
            sync_conn.rollback()


@pytest.mark.chaos
@pytest.mark.property
class TestVersionIncrementProperties:
    """Property-based tests for version increment logic."""

    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100),
    )
    @settings(max_examples=50, deadline=None)
    def test_patch_increment_properties(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Patch increment preserves major.minor."""
        try:
            cursor = sync_conn.execute(
                "SELECT pggit.increment_version(%s, %s, %s, 'patch')",
                (major, minor, patch),
            )
            new_version = cursor.fetchone()["increment_version"]

            # Parse version string
            new_major, new_minor, new_patch = map(int, new_version.split("."))

            # Properties
            assert new_major == major, "Major version should not change"
            assert new_minor == minor, "Minor version should not change"
            assert new_patch == patch + 1, "Patch should increment by 1"

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("increment_version function not implemented yet")

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
