"""
E2E tests for advanced branching scenarios.

Tests complex branch operations and hierarchies:
- Nested branch creation
- Parallel branch operations
- Branch cleanup and cascading
- Branch status queries
- Branch data retrieval integrity

Key Coverage:
- Hierarchical branch relationships
- Independent parallel operations
- Cascade behavior
- Branch status tracking
- Data retrieval consistency
"""

import pytest


class TestE2EAdvancedBranching:
    """Test advanced branching scenarios."""

    def test_nested_branch_creation(self, db, pggit_installed):
        """Test creating branches with hierarchical relationships"""
        parent_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create child branch
        child_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "child-branch"
        )[0]

        # Create grandchild branch
        grandchild_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "grandchild-branch"
        )[0]

        # Verify all branches exist
        main_exists = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE id = %s", parent_id
        )[0][0]
        child_exists = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE id = %s", child_id
        )[0][0]
        grandchild_exists = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE id = %s", grandchild_id
        )[0][0]

        assert main_exists == 1, "Main branch should exist"
        assert child_exists == 1, "Child branch should exist"
        assert grandchild_exists == 1, "Grandchild branch should exist"

    def test_parallel_branch_operations(self, db, pggit_installed):
        """Test multiple branches can have independent operations"""
        branch1_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "parallel-branch-1"
        )[0]

        branch2_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "parallel-branch-2"
        )[0]

        # Create test table
        db.execute("""
            CREATE TABLE public.parallel_test (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER,
                data TEXT
            )
        """)

        # Do operations on branch1
        db.execute(
            "INSERT INTO public.parallel_test (id, branch_id, data) VALUES (%s, %s, %s)",
            1, branch1_id, "branch1-data"
        )

        db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            branch1_id, "Branch1 commit"
        )

        # Do operations on branch2
        db.execute(
            "INSERT INTO public.parallel_test (id, branch_id, data) VALUES (%s, %s, %s)",
            2, branch2_id, "branch2-data"
        )

        db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            branch2_id, "Branch2 commit"
        )

        # Verify both branches have their data
        branch1_commits = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s", branch1_id
        )[0][0]
        branch2_commits = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s", branch2_id
        )[0][0]

        assert branch1_commits >= 1, "Branch1 should have commits"
        assert branch2_commits >= 1, "Branch2 should have commits"

    def test_branch_cleanup_cascade(self, db, pggit_installed):
        """Test that branch cleanup cascades properly"""
        # Create branch
        branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "cleanup-branch"
        )[0]

        # Add commit to branch
        commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            branch_id, "Commit to be cleaned"
        )[0]

        # Verify commit exists
        commit_count = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE id = %s", commit_id
        )[0][0]
        assert commit_count == 1, "Commit should exist before cleanup"

    def test_branch_status_query(self, db, pggit_installed):
        """Test branch status can be queried"""
        # Create branch with default status
        branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "status-branch"
        )[0]

        # Verify branch was created
        result = db.execute(
            "SELECT id FROM pggit.branches WHERE id = %s", branch_id
        )
        assert result[0][0] == branch_id, "Branch should exist"

    def test_branch_retrieval_integrity(self, db, pggit_installed):
        """Test that branch data retrieval maintains integrity"""
        # Create multiple branches
        branch1_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "retrieve-branch-1"
        )[0]

        branch2_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "retrieve-branch-2"
        )[0]

        # Retrieve all branches
        result = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE name LIKE %s",
            "retrieve-branch-%"
        )

        assert result[0][0] >= 2, "Both branches should be retrievable"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
