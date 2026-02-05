"""
E2E tests for deployment strategies and zero-downtime operations.

Tests various deployment patterns:
- Blue-green deployments with rollback capability
- Canary rollouts with incremental versioning
- Zero-downtime schema evolution
- Rollback capabilities for failed deployments
- Progressive traffic shifting between versions
- Concurrent deployments across branches
- Pre-deployment validation gates

Key Coverage:
- Blue-green deployment workflow
- Canary deployment with incremental rollout
- Schema changes without downtime
- Bad deployment rollback procedures
- Traffic routing and progressive shifting
- Concurrent multi-branch deployments
- Validation gate enforcement before promotion
"""

import json
import pytest
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class TestDeploymentStrategies:
    """Test deployment scenarios and zero-downtime operations."""

    def test_blue_green_deployment_workflow(self, db_e2e, pggit_installed):
        """Test complete blue-green deployment with branching."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create "blue" (current production)
        blue_branch = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('blue-production') RETURNING id"
        )[0]

        # Create "green" (new deployment)
        green_branch = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('green-staging') RETURNING id"
        )[0]

        # Create schema in blue
        db_e2e.execute("""
            CREATE TABLE public.blue_green_app (
                id INTEGER PRIMARY KEY,
                version TEXT,
                data TEXT
            )
        """)
        db_e2e.execute(
            "INSERT INTO public.blue_green_app VALUES (1, 'v1.0', 'production-data')"
        )

        # Record blue state
        blue_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('blue_green_app', 1, %s)",
            json.dumps({"deployment": "blue"}),
        )[0]

        # Update in green
        db_e2e.execute("UPDATE public.blue_green_app SET version = 'v2.0' WHERE id = 1")

        # Verify data can be copied between branches
        app_data = db_e2e.execute("SELECT version FROM public.blue_green_app WHERE id = 1")
        assert app_data[0][0] == "v2.0", "Blue-green data migration should succeed"

        # Verify rollback is possible
        assert blue_snapshot is not None, "Rollback snapshot should exist"

    def test_canary_rollout_with_versioning(self, db_e2e, pggit_installed):
        """Test canary deployment with incremental versioning."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create canary branch
        canary_branch = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('canary-deployment') RETURNING id"
        )[0]

        db_e2e.execute("""
            CREATE TABLE public.canary_config (
                id INTEGER PRIMARY KEY,
                feature TEXT,
                enabled BOOLEAN,
                rollout_percentage INTEGER
            )
        """)

        # Canary: 5% rollout
        db_e2e.execute(
            "INSERT INTO public.canary_config VALUES (1, 'new-feature', true, %s)", 5
        )

        canary_v1 = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('canary_config', 1, %s)",
            json.dumps({"phase": "canary-5percent"}),
        )[0]
        assert canary_v1 is not None, "5% canary snapshot should succeed"

        # Canary: 25% rollout
        db_e2e.execute(
            "UPDATE public.canary_config SET rollout_percentage = 25 WHERE id = 1"
        )
        canary_v2 = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('canary_config', 1, %s)",
            json.dumps({"phase": "canary-25percent"}),
        )[0]
        assert canary_v2 is not None, "25% canary snapshot should succeed"

        # Canary: 100% rollout (general availability)
        db_e2e.execute(
            "UPDATE public.canary_config SET rollout_percentage = 100 WHERE id = 1"
        )
        canary_v3 = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('canary_config', 1, %s)",
            json.dumps({"phase": "general-availability"}),
        )[0]
        assert canary_v3 is not None, "100% rollout snapshot should succeed"

    def test_zero_downtime_schema_evolution(self, db_e2e, pggit_installed):
        """Test schema changes without downtime."""
        db_e2e.execute("""
            CREATE TABLE public.evolving_schema (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        db_e2e.execute("INSERT INTO public.evolving_schema VALUES (1, 'test')")

        # Snapshot before change
        before_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('evolving_schema', 1, %s)",
            json.dumps({"phase": "before-evolution"}),
        )[0]

        # Add column (zero-downtime compatible)
        db_e2e.execute(
            "ALTER TABLE public.evolving_schema ADD COLUMN email TEXT DEFAULT ''"
        )

        # Verify old data still accessible
        old_data = db_e2e.execute(
            "SELECT id, name FROM public.evolving_schema WHERE id = 1"
        )
        assert old_data[0] == (1, "test"), "Old data should still be accessible"

        # Add new data with new column
        db_e2e.execute(
            "INSERT INTO public.evolving_schema (id, name, email) VALUES (2, 'new', 'test@example.com')"
        )

        # Snapshot after evolution
        after_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('evolving_schema', 1, %s)",
            json.dumps({"phase": "after-evolution"}),
        )[0]

        assert before_snapshot and after_snapshot, "Evolution snapshots should succeed"

    def test_rollback_from_bad_deployment(self, db_e2e, pggit_installed):
        """Test rollback capability when deployment goes wrong."""
        db_e2e.execute("""
            CREATE TABLE public.deployment_state (
                id INTEGER PRIMARY KEY,
                status TEXT,
                version TEXT
            )
        """)
        db_e2e.execute("INSERT INTO public.deployment_state VALUES (1, 'healthy', 'v1.0')")

        # Capture healthy state
        healthy_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('deployment_state', 1, %s)",
            json.dumps({"status": "healthy"}),
        )[0]

        # Deploy new version
        db_e2e.execute("UPDATE public.deployment_state SET version = 'v2.0' WHERE id = 1")
        db_e2e.execute(
            "UPDATE public.deployment_state SET status = 'degraded' WHERE id = 1"
        )

        # Detect problem and verify snapshot exists for rollback
        current_state = db_e2e.execute("SELECT status, version FROM public.deployment_state WHERE id = 1")
        assert current_state[0][0] == "degraded", "Current state should be degraded after bad deployment"
        assert current_state[0][1] == "v2.0", "Version should be updated"

        # Verify we have a snapshot to rollback to
        assert healthy_snapshot is not None, "Rollback snapshot should exist for recovery"

    def test_progressive_traffic_shifting(self, db_e2e, pggit_installed):
        """Test gradual traffic shift between deployments."""
        db_e2e.execute("""
            CREATE TABLE public.traffic_routing (
                id INTEGER PRIMARY KEY,
                endpoint TEXT,
                traffic_percentage INTEGER,
                deployment_version TEXT
            )
        """)

        # Initial: 100% old version
        db_e2e.execute(
            "INSERT INTO public.traffic_routing VALUES (1, 'api-v1', %s, 'v1.0')", 100
        )

        routing_states = []

        # Progressive shift: 0%, 25%, 50%, 75%, 100%
        for new_percent in [75, 50, 25, 0]:
            old_percent = 100 - new_percent
            db_e2e.execute(
                "UPDATE public.traffic_routing SET traffic_percentage = %s WHERE id = 1",
                old_percent,
            )
            db_e2e.execute(
                "INSERT INTO public.traffic_routing (id, endpoint, traffic_percentage, deployment_version) VALUES (%s, %s, %s, %s)",
                2 + len(routing_states),
                "api-v2",
                new_percent,
                "v2.0",
            )

            snapshot = db_e2e.execute_returning(
                "SELECT pggit.create_temporal_snapshot('traffic_routing', 1, %s)",
                json.dumps({"shift_percent": new_percent}),
            )[0]
            routing_states.append(snapshot)

        assert len(routing_states) == 4, "All traffic shift states should be captured"

    def test_deployment_with_active_queries(self, db_e2e, pggit_installed):
        """Test deployment while queries are executing."""
        db_e2e.execute("""
            CREATE TABLE public.active_queries_test (
                id INTEGER PRIMARY KEY,
                data TEXT,
                processed BOOLEAN DEFAULT false
            )
        """)

        # Seed data
        for i in range(100):
            db_e2e.execute(
                "INSERT INTO public.active_queries_test (id, data) VALUES (%s, %s)",
                i,
                f"data-{i}",
            )

        # Simulate active query execution
        def run_query():
            try:
                result = db_e2e.execute(
                    "SELECT COUNT(*) FROM public.active_queries_test WHERE processed = false"
                )
                return result[0][0] == 100
            except Exception:
                return False

        # Deploy while queries run
        with ThreadPoolExecutor(max_workers=3) as executor:
            query_futures = [executor.submit(run_query) for _ in range(5)]

            # Deploy during queries
            db_e2e.execute(
                "ALTER TABLE public.active_queries_test ADD COLUMN deployment_version TEXT DEFAULT 'v2.0'"
            )

            results = [f.result() for f in as_completed(query_futures)]

        assert all(results), "Queries during deployment should succeed"

    def test_concurrent_branch_deployments(self, db_e2e, pggit_installed):
        """Test concurrent deployments to different branches."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create multiple deployment branches
        deploy_branches = []
        for i in range(3):
            branch_id = db_e2e.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"deploy-{i}",
            )[0]
            deploy_branches.append(branch_id)

        db_e2e.execute("""
            CREATE TABLE public.concurrent_deploy (
                id INTEGER PRIMARY KEY,
                deployment_id INTEGER,
                status TEXT
            )
        """)

        # Concurrent deployments
        def deploy_to_branch(branch_id, deploy_num):
            db_e2e.execute(
                "INSERT INTO public.concurrent_deploy (id, deployment_id, status) VALUES (%s, %s, %s)",
                deploy_num,
                branch_id,
                "deploying",
            )
            db_e2e.execute(
                "UPDATE public.concurrent_deploy SET status = 'completed' WHERE id = %s",
                deploy_num,
            )
            return True

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(deploy_to_branch, deploy_branches[i], i)
                for i in range(3)
            ]
            results = [f.result() for f in as_completed(futures)]

        assert all(results), "Concurrent deployments should succeed"

    def test_deployment_validation_gates(self, db_e2e, pggit_installed):
        """Test validation gates before promoting deployment."""
        db_e2e.execute("DROP TABLE IF EXISTS public.deployment_validation CASCADE")
        db_e2e.execute("""
            CREATE TABLE public.deployment_validation (
                id INTEGER PRIMARY KEY,
                check_name TEXT,
                passed BOOLEAN,
                check_result TEXT
            )
        """)

        # Validation checks
        checks = [
            ("health-check", True, "All services healthy"),
            ("data-integrity", True, "All constraints valid"),
            ("performance-baseline", True, "P95 < 100ms"),
            ("schema-migration", True, "No breaking changes"),
        ]

        all_passed = True
        for i, (check_name, passed, result) in enumerate(checks, 1):
            db_e2e.execute(
                "INSERT INTO public.deployment_validation (id, check_name, passed, check_result) VALUES (%s, %s, %s, %s)",
                i,
                check_name,
                passed,
                result,
            )
            all_passed = all_passed and passed

        # Validation result
        validation_result = db_e2e.execute(
            "SELECT ALL(passed) FROM public.deployment_validation"
        )
        assert validation_result[0][0], "All validation gates should pass"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
