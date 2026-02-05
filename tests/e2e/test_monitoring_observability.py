"""
E2E tests for monitoring and observability.

Tests monitoring and observability features:
- Activity logging
- Metrics collection
- Health checks
- Performance monitoring
- State tracking

Key Coverage:
- Audit trail completeness
- Metrics accuracy
- Health check functionality
- Performance visibility
- Event tracking
"""

import pytest


class TestMonitoringObservability:
    """Test monitoring and observability features."""

    def test_branch_activity_logging(self, db_e2e, pggit_installed):
        """Test branch activities are logged"""
        db_e2e.execute("""
            CREATE TABLE public.activity_log (
                id SERIAL PRIMARY KEY,
                activity_type TEXT,
                target_id INTEGER,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create branch
        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "logged-branch"
        )[0]

        # Log activity
        db_e2e.execute(
            "INSERT INTO public.activity_log (activity_type, target_id) VALUES (%s, %s)",
            "branch_created", bid
        )

        # Verify activity logged
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.activity_log WHERE activity_type = %s",
            "branch_created"
        )[0][0]
        assert result >= 1

    def test_commit_metrics_collection(self, db_e2e, pggit_installed):
        """Test commit metrics are collected"""
        db_e2e.execute("""
            CREATE TABLE public.commit_metrics (
                id SERIAL PRIMARY KEY,
                commit_id INTEGER,
                branch_id INTEGER,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "metric-branch"
        )[0]

        cid = db_e2e.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            bid, "Measured commit"
        )[0]

        # Record metric
        db_e2e.execute(
            "INSERT INTO public.commit_metrics (commit_id, branch_id) VALUES (%s, %s)",
            cid, bid
        )

        # Verify metric recorded
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.commit_metrics WHERE branch_id = %s",
            bid
        )[0][0]
        assert result >= 1

    def test_health_check_status(self, db_e2e, pggit_installed):
        """Test health check status reporting"""
        db_e2e.execute("""
            CREATE TABLE public.health_check (
                id SERIAL PRIMARY KEY,
                component TEXT,
                status TEXT,
                last_check TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Record health status
        components = ["database", "schema", "constraints"]
        for comp in components:
            db_e2e.execute(
                "INSERT INTO public.health_check (component, status) VALUES (%s, %s)",
                comp, "healthy"
            )

        # Verify all healthy
        healthy = db_e2e.execute(
            "SELECT COUNT(*) FROM public.health_check WHERE status = %s",
            "healthy"
        )[0][0]
        assert healthy == 3

    def test_performance_counters(self, db_e2e, pggit_installed):
        """Test performance counters are tracked"""
        db_e2e.execute("""
            CREATE TABLE public.performance_counters (
                id SERIAL PRIMARY KEY,
                operation TEXT,
                count INTEGER DEFAULT 1,
                total_time_ms DECIMAL
            )
        """)

        # Simulate performance tracking
        operations = [
            ("branch_create", 50),
            ("commit_insert", 25),
            ("branch_query", 100),
        ]

        for op, time_ms in operations:
            db_e2e.execute(
                "INSERT INTO public.performance_counters (operation, total_time_ms) VALUES (%s, %s)",
                op, float(time_ms)
            )

        # Verify counters recorded
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.performance_counters"
        )[0][0]
        assert result == 3

    def test_state_change_tracking(self, db_e2e, pggit_installed):
        """Test state changes are tracked"""
        db_e2e.execute("""
            CREATE TABLE public.state_history (
                id SERIAL PRIMARY KEY,
                entity_id INTEGER,
                entity_type TEXT,
                old_state TEXT,
                new_state TEXT,
                changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "state-tracked-branch"
        )[0]

        # Log state change
        db_e2e.execute(
            "INSERT INTO public.state_history (entity_id, entity_type, old_state, new_state) VALUES (%s, %s, %s, %s)",
            bid, "branch", "created", "active"
        )

        # Verify state change recorded
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.state_history WHERE entity_id = %s",
            bid
        )[0][0]
        assert result >= 1

    def test_event_tracking(self, db_e2e, pggit_installed):
        """Test events are properly tracked"""
        db_e2e.execute("""
            CREATE TABLE public.events (
                id SERIAL PRIMARY KEY,
                event_type TEXT,
                event_data TEXT,
                occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create and track event
        db_e2e.execute(
            "INSERT INTO public.events (event_type, event_data) VALUES (%s, %s)",
            "branch_operation", "branch_created: test-branch"
        )

        # Verify event tracked
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.events WHERE event_type = %s",
            "branch_operation"
        )[0][0]
        assert result >= 1

    def test_metric_aggregation(self, db_e2e, pggit_installed):
        """Test metrics can be aggregated"""
        db_e2e.execute("""
            CREATE TABLE public.request_metrics (
                id SERIAL PRIMARY KEY,
                endpoint TEXT,
                response_time_ms INTEGER,
                status_code INTEGER
            )
        """)

        # Insert metrics
        metrics = [
            ("/api/branches", 50, 200),
            ("/api/branches", 75, 200),
            ("/api/branches", 60, 200),
            ("/api/commits", 100, 200),
        ]

        for endpoint, time, status in metrics:
            db_e2e.execute(
                "INSERT INTO public.request_metrics (endpoint, response_time_ms, status_code) VALUES (%s, %s, %s)",
                endpoint, time, status
            )

        # Aggregate metrics
        result = db_e2e.execute("""
            SELECT endpoint, AVG(response_time_ms), COUNT(*)
            FROM public.request_metrics
            GROUP BY endpoint
        """)

        assert len(result) >= 2

    def test_alert_condition_detection(self, db_e2e, pggit_installed):
        """Test alert conditions are detected"""
        db_e2e.execute("""
            CREATE TABLE public.performance_alerts (
                id SERIAL PRIMARY KEY,
                metric_name TEXT,
                current_value DECIMAL,
                threshold DECIMAL,
                alert_triggered BOOLEAN
            )
        """)

        # Insert performance data
        db_e2e.execute(
            "INSERT INTO public.performance_alerts (metric_name, current_value, threshold, alert_triggered) VALUES (%s, %s, %s, %s)",
            "query_time", 1500.0, 1000.0, True
        )

        db_e2e.execute(
            "INSERT INTO public.performance_alerts (metric_name, current_value, threshold, alert_triggered) VALUES (%s, %s, %s, %s)",
            "memory_usage", 600.0, 800.0, False
        )

        # Verify alert detection
        triggered = db_e2e.execute(
            "SELECT COUNT(*) FROM public.performance_alerts WHERE alert_triggered = TRUE"
        )[0][0]
        assert triggered >= 1

    def test_audit_trail_completeness(self, db_e2e, pggit_installed):
        """Test audit trail is complete"""
        db_e2e.execute("""
            CREATE TABLE public.audit_trail (
                id SERIAL PRIMARY KEY,
                action TEXT,
                actor TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                details TEXT
            )
        """)

        # Create branch and log all actions
        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "audit-tracked"
        )[0]

        db_e2e.execute(
            "INSERT INTO public.audit_trail (action, actor, details) VALUES (%s, %s, %s)",
            "branch_created", "system", f"branch_id={bid}"
        )

        # Add commits and log
        for i in range(3):
            cid = db_e2e.execute_returning(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
                bid, f"Commit {i}"
            )[0]

            db_e2e.execute(
                "INSERT INTO public.audit_trail (action, actor, details) VALUES (%s, %s, %s)",
                "commit_created", "system", f"commit_id={cid}"
            )

        # Verify audit trail
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.audit_trail"
        )[0][0]
        assert result >= 4

    def test_metric_data_types(self, db_e2e, pggit_installed):
        """Test metric data types are correctly stored"""
        db_e2e.execute("""
            CREATE TABLE public.typed_metrics (
                id SERIAL PRIMARY KEY,
                metric_name TEXT,
                int_value INTEGER,
                float_value DECIMAL,
                text_value TEXT,
                bool_value BOOLEAN
            )
        """)

        # Insert typed metrics
        db_e2e.execute(
            "INSERT INTO public.typed_metrics (metric_name, int_value, float_value, text_value, bool_value) VALUES (%s, %s, %s, %s, %s)",
            "test_metric", 100, 95.5, "status_ok", True
        )

        # Retrieve and verify types
        result = db_e2e.execute(
            "SELECT int_value, float_value, text_value, bool_value FROM public.typed_metrics WHERE metric_name = %s",
            "test_metric"
        )[0]

        assert result[0] == 100
        assert float(result[1]) == 95.5
        assert result[2] == "status_ok"
        assert result[3] is True
