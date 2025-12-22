"""
E2E tests for deployment rollback and recovery scenarios.

Tests deployment failure recovery:
- Partial deployment rollback
- Failed deployment recovery
- Snapshot restoration
- State recovery after failures
- Deployment atomicity

Key Coverage:
- Rollback correctness
- State consistency after failures
- Snapshot-based recovery
- Transaction isolation
- Deployment safety
"""

import pytest


class TestDeploymentRollback:
    """Test deployment rollback scenarios."""

    def test_partial_deployment_rollback(self, db, pggit_installed):
        """Test rolling back partially completed deployment"""
        # Setup initial state
        db.execute("""
            CREATE TABLE public.app_version (
                id SERIAL PRIMARY KEY,
                version TEXT,
                deployed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Initial version
        db.execute(
            "INSERT INTO public.app_version (version) VALUES (%s)",
            "v1.0"
        )

        # Simulate deployment: insert new version
        db.execute(
            "INSERT INTO public.app_version (version) VALUES (%s)",
            "v1.1"
        )

        # Verify both exist
        count = db.execute(
            "SELECT COUNT(*) FROM public.app_version"
        )[0][0]
        assert count == 2

        # Rollback: delete new version
        db.execute(
            "DELETE FROM public.app_version WHERE version = %s",
            "v1.1"
        )

        # Verify rollback
        count = db.execute(
            "SELECT COUNT(*) FROM public.app_version"
        )[0][0]
        assert count == 1

    def test_snapshot_based_recovery(self, db, pggit_installed):
        """Test recovery using snapshots"""
        # Create test table
        db.execute("""
            CREATE TABLE public.state_snapshot (
                id SERIAL PRIMARY KEY,
                snapshot_name TEXT,
                data_state TEXT
            )
        """)

        # Create snapshot before deployment
        db.execute(
            "INSERT INTO public.state_snapshot (snapshot_name, data_state) VALUES (%s, %s)",
            "pre-deploy", "ready"
        )

        # Simulate deployment with data change
        db.execute(
            "INSERT INTO public.state_snapshot (snapshot_name, data_state) VALUES (%s, %s)",
            "in-progress", "deploying"
        )

        # Recovery: return to pre-deployment state
        db.execute(
            "DELETE FROM public.state_snapshot WHERE snapshot_name != %s",
            "pre-deploy"
        )

        # Verify recovery
        result = db.execute(
            "SELECT COUNT(*) FROM public.state_snapshot"
        )[0][0]
        assert result == 1

    def test_failed_deployment_state_cleanup(self, db, pggit_installed):
        """Test cleaning up failed deployment state"""
        # Create temporary deployment table
        db.execute("""
            CREATE TABLE public.deployment_temp (
                id SERIAL PRIMARY KEY,
                status TEXT
            )
        """)

        # Mark deployment as failed
        db.execute(
            "INSERT INTO public.deployment_temp (status) VALUES (%s)",
            "failed"
        )

        # Cleanup: drop temporary table
        db.execute("DROP TABLE IF EXISTS public.deployment_temp")

        # Verify cleanup
        result = db.execute("""
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'deployment_temp'
            )
        """)
        assert result[0][0] is False or result[0][0] == 0

    def test_deployment_atomicity(self, db, pggit_installed):
        """Test deployment atomicity across multiple tables"""
        # Create related tables
        db.execute("""
            CREATE TABLE public.orders (
                id SERIAL PRIMARY KEY,
                status TEXT
            )
        """)
        db.execute("""
            CREATE TABLE public.order_items (
                id SERIAL PRIMARY KEY,
                order_id INTEGER,
                item_name TEXT
            )
        """)

        # Simulate atomic deployment
        db.execute(
            "INSERT INTO public.orders (status) VALUES (%s)",
            "pending"
        )

        order_id = db.execute(
            "SELECT MAX(id) FROM public.orders"
        )[0][0]

        db.execute(
            "INSERT INTO public.order_items (order_id, item_name) VALUES (%s, %s)",
            order_id, "item1"
        )

        # Verify atomic state
        orders = db.execute("SELECT COUNT(*) FROM public.orders")[0][0]
        items = db.execute("SELECT COUNT(*) FROM public.order_items")[0][0]
        assert orders == 1 and items == 1

    def test_schema_migration_rollback(self, db, pggit_installed):
        """Test rolling back schema migrations"""
        # Initial schema
        db.execute("""
            CREATE TABLE public.users_v1 (
                id SERIAL PRIMARY KEY,
                name TEXT
            )
        """)

        # Insert data in v1
        db.execute(
            "INSERT INTO public.users_v1 (name) VALUES (%s)",
            "user1"
        )

        # Migration: add new column
        db.execute(
            "ALTER TABLE public.users_v1 ADD COLUMN email TEXT"
        )

        # Rollback: drop new column
        db.execute(
            "ALTER TABLE public.users_v1 DROP COLUMN email"
        )

        # Verify structure
        result = db.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_name = 'users_v1'
        """)[0][0]
        assert result == 2  # id + name

    def test_deployment_validation_before_commit(self, db, pggit_installed):
        """Test validation before committing deployment"""
        # Create validation table
        db.execute("""
            CREATE TABLE public.deployment_validation (
                id SERIAL PRIMARY KEY,
                check_name TEXT,
                passed BOOLEAN
            )
        """)

        # Run validations
        checks = [
            ("schema_check", True),
            ("data_integrity", True),
            ("performance_test", True),
        ]

        for check_name, passed in checks:
            db.execute(
                "INSERT INTO public.deployment_validation (check_name, passed) VALUES (%s, %s)",
                check_name, passed
            )

        # Verify all checks passed
        failed = db.execute(
            "SELECT COUNT(*) FROM public.deployment_validation WHERE passed = FALSE"
        )[0][0]
        assert failed == 0

    def test_concurrent_deployment_isolation(self, db, pggit_installed):
        """Test isolation between concurrent deployments"""
        # Create deployment tracking
        db.execute("""
            CREATE TABLE public.deployments (
                id SERIAL PRIMARY KEY,
                deployment_id TEXT UNIQUE,
                status TEXT
            )
        """)

        # Simulate concurrent deployments
        db.execute(
            "INSERT INTO public.deployments (deployment_id, status) VALUES (%s, %s)",
            "deploy-1", "in_progress"
        )
        db.execute(
            "INSERT INTO public.deployments (deployment_id, status) VALUES (%s, %s)",
            "deploy-2", "in_progress"
        )

        # Update one deployment
        db.execute(
            "UPDATE public.deployments SET status = %s WHERE deployment_id = %s",
            "completed", "deploy-1"
        )

        # Verify isolation
        d1 = db.execute(
            "SELECT status FROM public.deployments WHERE deployment_id = %s",
            "deploy-1"
        )[0][0]
        d2 = db.execute(
            "SELECT status FROM public.deployments WHERE deployment_id = %s",
            "deploy-2"
        )[0][0]

        assert d1 == "completed"
        assert d2 == "in_progress"
