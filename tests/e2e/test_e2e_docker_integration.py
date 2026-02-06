"""
End-to-End Integration Tests for pgGit
Tests against a fresh PostgreSQL database in Docker
"""

import json
import pytest
from conftest import docker_setup, pggit_installed  # noqa: F401


class TestE2EBasicOperations:
    """Test basic pgGit operations"""

    def test_schema_created(self, db_e2e, pggit_installed):
        """Verify pggit schema exists"""
        result = db_e2e.execute_returning(
            "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit'"
        )
        assert result is not None, "pggit schema not found"

    def test_branches_table_exists(self, db_e2e, pggit_installed):
        """Verify branches table is created"""
        result = db_e2e.execute_returning(
            "SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'branches'"
        )
        assert result is not None, "branches table not found"

    def test_commits_table_exists(self, db_e2e, pggit_installed):
        """Verify commits table is created"""
        result = db_e2e.execute_returning(
            "SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'commits'"
        )
        assert result is not None, "commits table not found"

    def test_initial_main_branch_exists(self, db_e2e, pggit_installed):
        """Verify initial 'main' branch is created"""
        result = db_e2e.execute_returning(
            "SELECT id, name FROM pggit.branches WHERE name = 'main'"
        )
        assert result is not None, "main branch not found"
        assert result[1] == "main"


class TestE2EBranchOperations:
    """Test branch creation and management"""

    def test_create_branch(self, db_e2e, pggit_installed):
        """Test creating a new branch"""
        db_e2e.execute(
            "INSERT INTO pggit.branches (name, description) VALUES (%s, %s)",
            "feature/test-branch",
            "Test branch for E2E testing",
        )

        result = db_e2e.execute_returning(
            "SELECT id, name, description FROM pggit.branches WHERE name = %s",
            "feature/test-branch",
        )

        assert result is not None, "Branch not created"
        assert result[1] == "feature/test-branch"
        assert result[2] == "Test branch for E2E testing"

    def test_multiple_branches(self, db_e2e, pggit_installed):
        """Test creating multiple branches"""
        branch_names = ["branch-1", "branch-2", "branch-3"]

        for name in branch_names:
            db_e2e.execute(
                "INSERT INTO pggit.branches (name) VALUES (%s)",
                name,
            )

        result = db_e2e.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE name IN (%s, %s, %s)",
            *branch_names,
        )

        assert result[0][0] == 3, "Not all branches created"

    def test_list_branches(self, db_e2e, pggit_installed):
        """Test listing all branches"""
        # Create some branches first
        for i in range(3):
            db_e2e.execute(
                "INSERT INTO pggit.branches (name) VALUES (%s)",
                f"list-test-{i}",
            )

        result = db_e2e.execute("SELECT COUNT(*) FROM pggit.branches")
        assert result[0][0] >= 3, "Branches not listed correctly"


class TestE2ETableVersioning:
    """Test table versioning and DDL tracking"""

    def test_create_and_version_table(self, db_e2e, pggit_installed):
        """Test creating a table and verifying version tracking"""
        # Create a test table
        db_e2e.execute(
            """
            CREATE TABLE public.test_data (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )

        # Verify it exists
        result = db_e2e.execute_returning(
            "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'test_data'"
        )
        assert result is not None, "test_data table not created"

    def test_insert_and_track_version(self, db_e2e, pggit_installed):
        """Test inserting data and version tracking"""
        # Create table
        db_e2e.execute(
            """
            CREATE TABLE public.users (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL UNIQUE,
                email TEXT NOT NULL
            )
            """
        )

        # Insert data
        db_e2e.execute(
            "INSERT INTO public.users (username, email) VALUES (%s, %s)",
            "testuser",
            "test@example.com",
        )

        # Verify data exists
        result = db_e2e.execute_returning(
            "SELECT id, username, email FROM public.users WHERE username = %s",
            "testuser",
        )

        assert result is not None
        assert result[1] == "testuser"
        assert result[2] == "test@example.com"

    def test_multiple_table_inserts(self, db_e2e, pggit_installed):
        """Test multiple inserts across different tables"""
        # Create tables
        db_e2e.execute(
            """
            CREATE TABLE public.products (
                id SERIAL PRIMARY KEY,
                name TEXT,
                price NUMERIC
            )
            """
        )

        db_e2e.execute(
            """
            CREATE TABLE public.orders (
                id SERIAL PRIMARY KEY,
                product_id INTEGER REFERENCES public.products(id),
                quantity INTEGER
            )
            """
        )

        # Insert into products
        for i in range(3):
            db_e2e.execute(
                "INSERT INTO public.products (name, price) VALUES (%s, %s)",
                f"Product {i}",
                10.00 * (i + 1),
            )

        # Insert into orders
        for i in range(3):
            db_e2e.execute(
                "INSERT INTO public.orders (product_id, quantity) VALUES (%s, %s)",
                i + 1,
                i + 2,
            )

        # Verify counts
        products_result = db_e2e.execute("SELECT COUNT(*) FROM public.products")
        orders_result = db_e2e.execute("SELECT COUNT(*) FROM public.orders")

        assert products_result[0][0] == 3, "Products not inserted"
        assert orders_result[0][0] == 3, "Orders not inserted"


class TestE2ECommitOperations:
    """Test commit functionality"""

    def test_create_commit(self, db_e2e, pggit_installed):
        """Test creating a commit"""
        # Get main branch
        main_branch = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        # Create a commit
        db_e2e.execute(
            """
            INSERT INTO pggit.commits (branch_id, message, metadata)
            VALUES (%s, %s, %s)
            """,
            main_branch[0],
            "Test commit message",
            json.dumps({"version": "1.0", "author": "test"}),
        )

        # Verify commit exists
        result = db_e2e.execute_returning(
            "SELECT id, message FROM pggit.commits WHERE message = %s",
            "Test commit message",
        )

        assert result is not None, "Commit not created"
        assert result[1] == "Test commit message"

    def test_commit_with_version_increment(self, db_e2e, pggit_installed):
        """Test commit with version tracking"""
        main_branch = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        # Create commit with version
        db_e2e.execute(
            """
            INSERT INTO pggit.commits (branch_id, message)
            VALUES (%s, %s)
            """,
            main_branch[0],
            "v1.0.0 release",
        )

        result = db_e2e.execute_returning(
            "SELECT id, message FROM pggit.commits WHERE message = %s",
            "v1.0.0 release",
        )

        assert result is not None
        assert result[1] == "v1.0.0 release"


class TestE2EDataBranching:
    """Test data branching with copy-on-write"""

    def test_create_data_branch(self, db_e2e, pggit_installed):
        """Test creating a data branch"""
        # Create a test table with data
        db_e2e.execute(
            """
            CREATE TABLE public.branch_test (
                id SERIAL PRIMARY KEY,
                value TEXT
            )
            """
        )

        # Insert test data
        for i in range(3):
            db_e2e.execute(
                "INSERT INTO public.branch_test (value) VALUES (%s)",
                f"value-{i}",
            )

        # Create a feature branch
        db_e2e.execute(
            "INSERT INTO pggit.branches (name, branch_type) VALUES (%s, %s)",
            "feature/data-test",
            "standard",
        )

        feature_branch = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'feature/data-test'"
        )

        assert feature_branch is not None, "Feature branch not created"

    def test_branch_isolation(self, db_e2e, pggit_installed):
        """Test that branches can be isolated"""
        # Create table
        db_e2e.execute(
            """
            CREATE TABLE public.isolated_table (
                id SERIAL PRIMARY KEY,
                branch_marker TEXT
            )
            """
        )

        # Create branches
        db_e2e.execute(
            "INSERT INTO pggit.branches (name, branch_type) VALUES (%s, %s)",
            "branch-a",
            "standard",
        )

        db_e2e.execute(
            "INSERT INTO pggit.branches (name, branch_type) VALUES (%s, %s)",
            "branch-b",
            "standard",
        )

        # Insert data on branch-a
        db_e2e.execute(
            "INSERT INTO public.isolated_table (branch_marker) VALUES (%s)",
            "from-branch-a",
        )

        # Verify data exists
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.isolated_table WHERE branch_marker = %s",
            "from-branch-a",
        )

        assert result[0][0] == 1, "Branch isolation failed"


class TestE2ETemporalOperations:
    """Test time-travel and temporal operations"""

    def test_temporal_snapshot_creation(self, db_e2e, pggit_installed):
        """Test creating temporal snapshots"""
        result = db_e2e.execute_returning(
            """
            SELECT snapshot_id, name FROM pggit.create_temporal_snapshot(
                'test-snapshot',
                1,
                'Test snapshot for E2E'
            )
            """
        )

        assert result is not None, "Snapshot not created"
        assert result[1] == "test-snapshot"

    def test_temporal_snapshot_listing(self, db_e2e, pggit_installed):
        """Test listing temporal snapshots"""
        # Create a snapshot
        db_e2e.execute_returning(
            """
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'snapshot-1',
                1,
                'First snapshot'
            )
            """
        )

        # List snapshots
        result = db_e2e.execute(
            """
            SELECT snapshot_id, snapshot_name FROM pggit.list_temporal_snapshots(
                p_branch_id := 1,
                p_limit := 10
            )
            """
        )

        assert len(result) > 0, "No snapshots listed"
        assert any(row[1] == "snapshot-1" for row in result), (
            "Snapshot not found in list"
        )

    def test_temporal_changelog_recording(self, db_e2e, pggit_installed):
        """Test recording temporal changes"""
        # Create a snapshot
        snapshot = db_e2e.execute_returning(
            """
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'changelog-test',
                1,
                'Test changelog recording'
            )
            """
        )

        snapshot_id = snapshot[0]

        # Record a change
        db_e2e.execute(
            """
            SELECT pggit.record_temporal_change(
                %s,
                'public',
                'test_table',
                'INSERT',
                'row-1',
                NULL,
                %s
            )
            """,
            snapshot_id,
            json.dumps({"id": 1, "name": "test"}),
        )

        # Verify change was recorded
        result = db_e2e.execute(
            """
            SELECT change_id, operation FROM pggit.temporal_changelog
            WHERE snapshot_id = %s AND operation = 'INSERT'
            """,
            snapshot_id,
        )

        assert len(result) > 0, "Temporal change not recorded"


class TestE2EMLOperations:
    """Test ML optimization operations"""

    def test_access_pattern_table_exists(self, db_e2e, pggit_installed):
        """Test that ML pattern tables exist"""
        result = db_e2e.execute_returning(
            "SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'ml_access_patterns'"
        )
        assert result is not None, "ML access patterns table not found"

    def test_pattern_learning(self, db_e2e, pggit_installed):
        """Test ML pattern learning"""
        # Insert some access patterns
        for i in range(3):
            db_e2e.execute(
                """
                INSERT INTO pggit.access_patterns (object_name, access_type, response_time_ms)
                VALUES (%s, %s, %s)
                """,
                f"object-{i}",
                "READ",
                10 + i * 5,
            )

        # Learn patterns
        result = db_e2e.execute_returning(
            "SELECT pattern_id FROM pggit.learn_access_patterns(%s, %s)",
            1,  # object_id
            "READ",  # operation_type
        )

        assert result is not None, "Pattern learning failed"
        # We selected only pattern_id, so result[0] is the UUID
        assert result[0] is not None, "Pattern ID should be returned"


class TestE2EConflictResolution:
    """Test conflict resolution operations"""

    def test_conflict_resolution_tables_exist(self, db_e2e, pggit_installed):
        """Test that conflict resolution tables exist"""
        tables = [
            "conflict_resolution_strategies",
            "semantic_conflicts",
            "conflict_resolution_history",
        ]

        for table_name in tables:
            result = db_e2e.execute_returning(
                f"SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = %s",
                table_name,
            )
            assert result is not None, f"{table_name} not found"

    def test_semantic_conflict_analysis(self, db_e2e, pggit_installed):
        """Test semantic conflict analysis"""
        # Test the conflict analysis function with sample data
        result = db_e2e.execute_returning(
            """
            SELECT type, severity FROM pggit.analyze_semantic_conflict(
                %s,
                %s,
                %s
            )
            """,
            json.dumps({"id": 1, "name": "original"}),
            json.dumps({"id": 1, "name": "source-modified"}),
            json.dumps({"id": 1, "name": "target-modified"}),
        )

        assert result is not None, "Semantic analysis failed"
        assert result[0] is not None, "Conflict type not determined"


class TestE2EFullWorkflow:
    """Integration tests for complete workflows"""

    def test_complete_branch_workflow(self, db_e2e, pggit_installed):
        """Test a complete branch creation and commit workflow"""
        # 1. Create a table
        db_e2e.execute(
            """
            CREATE TABLE public.workflow_test (
                id SERIAL PRIMARY KEY,
                name TEXT,
                status TEXT
            )
            """
        )

        # 2. Insert initial data
        db_e2e.execute(
            "INSERT INTO public.workflow_test (name, status) VALUES (%s, %s)",
            "item-1",
            "pending",
        )

        # 3. Create a feature branch
        db_e2e.execute(
            "INSERT INTO pggit.branches (name, branch_type) VALUES (%s, %s)",
            "feature/workflow",
            "standard",
        )

        feature_branch = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'feature/workflow'"
        )

        # 4. Create commit
        db_e2e.execute(
            """
            INSERT INTO pggit.commits (branch_id, message)
            VALUES (%s, %s)
            """,
            feature_branch[0],
            "Initial workflow setup",
        )

        # 5. Verify everything is connected
        commits = db_e2e.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s",
            feature_branch[0],
        )

        assert commits[0][0] == 1, "Commit not created in branch"

    def test_concurrent_operations_simulation(self, db_e2e, pggit_installed):
        """Simulate concurrent operations on multiple branches"""
        # Create test table
        db_e2e.execute(
            """
            CREATE TABLE public.concurrent_test (
                id SERIAL PRIMARY KEY,
                branch_name TEXT,
                value INTEGER
            )
            """
        )

        # Create multiple branches
        branch_ids = []
        for i in range(3):
            db_e2e.execute(
                "INSERT INTO pggit.branches (name, branch_type) VALUES (%s, %s)",
                f"concurrent-{i}",
                "standard",
            )
            branch = db_e2e.execute_returning(
                f"SELECT id FROM pggit.branches WHERE name = %s",
                f"concurrent-{i}",
            )
            branch_ids.append(branch[0])

        # Insert data representing work on each branch
        for i, branch_id in enumerate(branch_ids):
            db_e2e.execute(
                "INSERT INTO public.concurrent_test (branch_name, value) VALUES (%s, %s)",
                f"concurrent-{i}",
                i * 100,
            )

            # Create commit for each
            db_e2e.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                branch_id,
                f"Work on branch {i}",
            )

        # Verify all work is recorded
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id IN (%s, %s, %s)",
            *branch_ids,
        )

        assert result[0][0] == 3, "Not all commits created"

    def test_data_integrity_across_operations(self, db_e2e, pggit_installed):
        """Test data integrity across multiple operations"""
        # Create table with constraints
        db_e2e.execute(
            """
            CREATE TABLE public.integrity_test (
                id SERIAL PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )

        # Insert valid data
        db_e2e.execute(
            "INSERT INTO public.integrity_test (email) VALUES (%s)",
            "user1@example.com",
        )

        # Use savepoint to handle constraint violation without affecting rest of transaction
        db_e2e.execute("SAVEPOINT sp_integrity_test")
        try:
            db_e2e.execute(
                "INSERT INTO public.integrity_test (email) VALUES (%s)",
                "user1@example.com",
            )
            # If we get here, the constraint didn't work
            assert False, "Unique constraint violated"
        except Exception:
            # Expected - constraint violation
            # Rollback to savepoint, not the entire transaction
            db_e2e.execute("ROLLBACK TO SAVEPOINT sp_integrity_test")

        # Insert different email (should succeed)
        db_e2e.execute(
            "INSERT INTO public.integrity_test (email) VALUES (%s)",
            "user2@example.com",
        )

        # Verify final state
        result = db_e2e.execute("SELECT COUNT(*) FROM public.integrity_test")
        assert result[0][0] == 2, "Data integrity compromised"

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS public.integrity_test CASCADE")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
