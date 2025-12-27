"""
Integration tests for Phase 7: Performance Monitoring Functions
Tests function behavior, workflows, and data integrity
"""

import pytest
import time
from datetime import datetime, timedelta
from tests.fixtures.scenario_builder import ScenarioBuilder


class TestPerformanceTraceFunctions:
    """Test distributed trace functions"""

    def test_start_performance_trace_creates_span(self, db_connection):
        """Verify start_performance_trace creates a trace span"""
        with db_connection.cursor() as cur:
            span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'merge',
                    p_span_name := 'merge_feature_main',
                    p_user_name := 'test_user'
                )
            """).fetchall()[0][0]

            # Verify trace was recorded
            cur.execute("""
                SELECT span_id, operation_type, span_name, span_status
                FROM pggit.operation_traces
                WHERE span_id = %s
            """, (span_id,))
            row = cur.fetchone()

        assert row is not None
        assert row[0] == span_id
        assert row[1] == 'merge'
        assert row[2] == 'merge_feature_main'
        assert row[3] == 'RUNNING'

    def test_start_performance_trace_generates_ids(self, db_connection):
        """Verify trace IDs are auto-generated when not provided"""
        with db_connection.cursor() as cur:
            span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'commit'
                )
            """).fetchall()[0][0]

            # IDs should be UUIDs
            assert len(span_id) > 20

    def test_parent_child_span_relationship(self, db_connection):
        """Verify parent-child span relationships work correctly"""
        with db_connection.cursor() as cur:
            # Create parent span
            parent_span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'merge_workflow',
                    p_span_name := 'merge_main_to_feature'
                )
            """).fetchall()[0][0]

            # Create child span
            child_span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'merge_workflow',
                    p_span_name := 'conflict_detection',
                    p_parent_span_id := %s
                )
            """, (parent_span_id,)).fetchall()[0][0]

            # Verify relationship
            cur.execute("""
                SELECT parent_span_id FROM pggit.operation_traces
                WHERE span_id = %s
            """, (child_span_id,))
            result = cur.fetchone()

        assert result[0] == parent_span_id

    def test_end_performance_trace_calculates_duration(self, db_connection):
        """Verify trace duration is calculated correctly"""
        with db_connection.cursor() as cur:
            span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'commit'
                )
            """).fetchall()[0][0]

            # Wait briefly to accumulate time
            time.sleep(0.01)

            # End trace
            cur.execute("""
                SELECT pggit.end_performance_trace(
                    p_span_id := %s,
                    p_span_status := 'SUCCESS'
                )
            """, (span_id,))

            # Verify duration was recorded (should be ~10ms)
            cur.execute("""
                SELECT duration_microseconds, span_status
                FROM pggit.operation_traces
                WHERE span_id = %s
            """, (span_id,))
            row = cur.fetchone()

        assert row is not None
        assert row[0] > 1000  # At least 1ms
        assert row[1] == 'SUCCESS'

    def test_end_performance_trace_with_error(self, db_connection):
        """Verify trace can record error details"""
        with db_connection.cursor() as cur:
            span_id = cur.execute("""
                SELECT pggit.start_performance_trace(
                    p_operation_type := 'merge'
                )
            """).fetchall()[0][0]

            # End with error
            cur.execute("""
                SELECT pggit.end_performance_trace(
                    p_span_id := %s,
                    p_span_status := 'FAILED',
                    p_error_message := 'Merge conflict unresolvable',
                    p_error_code := 'CONFLICT_UNRESOLVABLE'
                )
            """, (span_id,))

            # Verify error was recorded
            cur.execute("""
                SELECT span_status, error_message, error_code
                FROM pggit.operation_traces
                WHERE span_id = %s
            """, (span_id,))
            row = cur.fetchone()

        assert row[0] == 'FAILED'
        assert 'Merge conflict' in row[1]
        assert row[2] == 'CONFLICT_UNRESOLVABLE'


class TestPerformanceMetricFunctions:
    """Test metric recording functions"""

    def test_record_performance_metric_stores_timing(self, db_connection):
        """Verify metric recording stores microsecond precision"""
        with db_connection.cursor() as cur:
            metric_id = cur.execute("""
                SELECT pggit.record_performance_metric(
                    p_operation_type := 'commit',
                    p_duration_microseconds := 5000,
                    p_user_name := 'test_user'
                )
            """).fetchall()[0][0]

            # Verify metric was recorded
            cur.execute("""
                SELECT duration_microseconds, duration_ms, operation_type
                FROM pggit.performance_metrics
                WHERE metric_id = %s
            """, (metric_id,))
            row = cur.fetchone()

        assert row is not None
        assert row[0] == 5000  # Microseconds
        assert row[1] == 5.0  # Milliseconds (computed)
        assert row[2] == 'commit'

    def test_record_performance_metric_validates_duration(self, db_connection):
        """Verify negative durations are rejected"""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):  # Should raise EXCEPTION
                cur.execute("""
                    SELECT pggit.record_performance_metric(
                        p_operation_type := 'commit',
                        p_duration_microseconds := -1000,
                        p_user_name := 'test_user'
                    )
                """)

    def test_record_performance_metric_calculates_period(self, db_connection):
        """Verify period_start is calculated correctly (midnight)"""
        with db_connection.cursor() as cur:
            midnight = cur.execute("""
                SELECT DATE_TRUNC('day', CURRENT_TIMESTAMP)
            """).fetchall()[0][0]

            metric_id = cur.execute("""
                SELECT pggit.record_performance_metric(
                    p_operation_type := 'commit',
                    p_duration_microseconds := 1000
                )
            """).fetchall()[0][0]

            cur.execute("""
                SELECT period_start FROM pggit.performance_metrics
                WHERE metric_id = %s
            """, (metric_id,))
            result = cur.fetchone()

        assert result[0] == midnight

    def test_record_performance_metric_with_metadata(self, db_connection):
        """Verify flexible metadata storage"""
        import json

        with db_connection.cursor() as cur:
            metadata = {'source': 'feature', 'target': 'main', 'conflict_count': 3}

            metric_id = cur.execute("""
                SELECT pggit.record_performance_metric(
                    p_operation_type := 'merge',
                    p_duration_microseconds := 50000,
                    p_operation_metadata := %s::jsonb
                )
            """, (json.dumps(metadata),)).fetchall()[0][0]

            cur.execute("""
                SELECT operation_metadata FROM pggit.performance_metrics
                WHERE metric_id = %s
            """, (metric_id,))
            result = cur.fetchone()

        assert result[0]['source'] == 'feature'
        assert result[0]['conflict_count'] == 3


class TestBaselineCalculationFunctions:
    """Test baseline calculation and management"""

    def test_calculate_performance_baseline_with_sufficient_data(self, db_connection):
        """Verify baseline calculation with adequate sample size"""
        with db_connection.cursor() as cur:
            # Insert sample metrics (at least 10 needed)
            for i in range(15):
                duration = 1000 + (i * 100)  # Range from 1000 to 2400 us
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('test_op', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test_user', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """, (duration, duration / 1000))

            # Calculate baseline
            baseline_id = cur.execute("""
                SELECT pggit.calculate_performance_baseline(
                    p_operation_type := 'test_op',
                    p_lookback_days := 7
                )
            """).fetchall()[0][0]

            # Verify baseline was created
            cur.execute("""
                SELECT baseline_id, p50_microseconds, p99_microseconds, sample_count
                FROM pggit.performance_baselines
                WHERE baseline_id = %s
            """, (baseline_id,))
            row = cur.fetchone()

        assert row is not None
        assert row[2] > row[1]  # p99 > p50
        assert row[3] == 15  # All 15 samples counted

    def test_baseline_deactivates_old_baseline(self, db_connection):
        """Verify new baseline deactivates previous one"""
        with db_connection.cursor() as cur:
            # Create first baseline
            for i in range(15):
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('baseline_test', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """, (1000 + i * 100, (1000 + i * 100) / 1000))

            baseline_id_1 = cur.execute("""
                SELECT pggit.calculate_performance_baseline(
                    p_operation_type := 'baseline_test'
                )
            """).fetchall()[0][0]

            # Create second baseline
            for i in range(15):
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('baseline_test', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """, (2000 + i * 200, (2000 + i * 200) / 1000))

            baseline_id_2 = cur.execute("""
                SELECT pggit.calculate_performance_baseline(
                    p_operation_type := 'baseline_test'
                )
            """).fetchall()[0][0]

            # Verify first is inactive
            cur.execute("""
                SELECT is_active FROM pggit.performance_baselines
                WHERE baseline_id = %s
            """, (baseline_id_1,))
            is_active = cur.fetchone()[0]

        assert is_active is False

    def test_check_performance_baseline_creates_alert(self, db_connection):
        """Verify alert is created when metric exceeds baseline"""
        with db_connection.cursor() as cur:
            # Create baseline
            for i in range(15):
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('alert_test', 1000, 1.0, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """)

            cur.execute("""
                SELECT pggit.calculate_performance_baseline(
                    p_operation_type := 'alert_test'
                )
            """)

            # Record metric that exceeds baseline
            metric_id = cur.execute("""
                SELECT pggit.record_performance_metric(
                    p_operation_type := 'alert_test',
                    p_duration_microseconds := 10000
                )
            """).fetchall()[0][0]

            # Verify alert was created
            cur.execute("""
                SELECT COUNT(*) FROM pggit.performance_alerts
                WHERE metric_id = %s
            """, (metric_id,))
            alert_count = cur.fetchone()[0]

        assert alert_count > 0


class TestAnalysisFunctions:
    """Test analysis and reporting functions"""

    def test_get_performance_trend(self, db_connection):
        """Verify performance trend aggregation"""
        with db_connection.cursor() as cur:
            # Insert metrics for multiple days
            for day in range(3):
                for i in range(5):
                    ts = CURRENT_TIMESTAMP - timedelta(days=day)
                    duration = 1000 + (i * 200)
                    cur.execute("""
                        INSERT INTO pggit.performance_metrics
                        (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start, recorded_at)
                        VALUES ('trend_test', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', %s, %s)
                    """, (duration, duration / 1000, ts.date(), ts))

            # Get trend
            cur.execute("""
                SELECT * FROM pggit.get_performance_trend(
                    p_operation_type := 'trend_test',
                    p_days := 7
                )
            """)
            rows = cur.fetchall()

        assert len(rows) >= 1
        assert rows[0][1] >= 5  # At least 5 samples per day

    def test_get_slowest_operations(self, db_connection):
        """Verify slowest operations are returned in order"""
        with db_connection.cursor() as cur:
            # Insert operations with varying durations
            durations = [1000, 5000, 10000, 2000, 8000]
            for duration in durations:
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('slowest_test', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """, (duration, duration / 1000))

            # Get slowest
            cur.execute("""
                SELECT duration_ms FROM pggit.get_slowest_operations(
                    p_operation_type := 'slowest_test',
                    p_limit := 3
                )
            """)
            results = cur.fetchall()

        # Should return top 3 in descending order
        assert len(results) == 3
        assert results[0][0] == 10.0
        assert results[1][0] == 8.0
        assert results[2][0] == 5.0

    def test_get_operation_statistics(self, db_connection):
        """Verify aggregate statistics"""
        with db_connection.cursor() as cur:
            # Insert multiple metrics
            for i in range(20):
                duration = 1000 + (i * 50)
                cur.execute("""
                    INSERT INTO pggit.performance_metrics
                    (operation_type, duration_microseconds, duration_ms, start_time, end_time, user_name, period_start)
                    VALUES ('stats_test', %s, %s, CURRENT_TIMESTAMP - INTERVAL '1 minute', CURRENT_TIMESTAMP, 'test', DATE_TRUNC('day', CURRENT_TIMESTAMP))
                """, (duration, duration / 1000))

            # Get statistics
            cur.execute("""
                SELECT total_executions, avg_duration_ms, p99_ms
                FROM pggit.get_operation_statistics(
                    p_operation_type := 'stats_test'
                )
            """)
            row = cur.fetchone()

        assert row is not None
        assert row[0] == 20  # Total executions
        assert row[1] > 0  # Average calculated
        assert row[2] > row[1]  # p99 > average


class TestMergePerformanceFunctions:
    """Test merge-specific performance tracking"""

    def test_record_merge_performance_detailed_metrics(self, db_connection, db_conn):
        """Verify detailed merge metrics are recorded"""
        with db_connection.cursor() as cur:
            # Create branches
            builder = ScenarioBuilder(db_conn)
            builder.add_branches(['feature'])

            # Get branch IDs
            cur.execute("""
                SELECT id FROM pggit.branches WHERE name = 'main'
            """)
            main_id = cur.fetchone()[0]

            cur.execute("""
                SELECT id FROM pggit.branches WHERE name = 'feature'
            """)
            feature_id = cur.fetchone()[0]

            # Record merge
            merge_id = cur.execute("""
                SELECT pggit.record_merge_performance(
                    p_source_branch_id := %s,
                    p_target_branch_id := %s,
                    p_total_merge_us := 50000,
                    p_merge_base_calc_us := 5000,
                    p_conflict_detection_us := 20000,
                    p_conflict_count := 3,
                    p_auto_resolution_us := 25000,
                    p_auto_success_count := 2,
                    p_auto_failure_count := 1,
                    p_merge_status := 'SUCCESS'
                )
            """, (feature_id, main_id)).fetchall()[0][0]

            # Verify merge metrics
            cur.execute("""
                SELECT total_merge_us, conflict_count, merge_status
                FROM pggit.merge_performance_metrics
                WHERE merge_metric_id = %s
            """, (merge_id,))
            row = cur.fetchone()

        assert row is not None
        assert row[0] == 50000
        assert row[1] == 3
        assert row[2] == 'SUCCESS'

    def test_merge_performance_creates_overall_metric(self, db_connection, db_conn):
        """Verify merge also records in performance_metrics"""
        with db_connection.cursor() as cur:
            builder = ScenarioBuilder(db_conn)
            builder.add_branches(['test_branch'])

            cur.execute("SELECT id FROM pggit.branches WHERE name = 'main'")
            main_id = cur.fetchone()[0]

            cur.execute("SELECT id FROM pggit.branches WHERE name = 'test_branch'")
            branch_id = cur.fetchone()[0]

            # Record merge
            merge_id = cur.execute("""
                SELECT pggit.record_merge_performance(
                    p_source_branch_id := %s,
                    p_target_branch_id := %s,
                    p_total_merge_us := 100000
                )
            """, (branch_id, main_id)).fetchall()[0][0]

            # Verify metric in performance_metrics table
            cur.execute("""
                SELECT COUNT(*) FROM pggit.performance_metrics
                WHERE operation_type = 'merge'
                AND operation_metadata ->> 'merge_metric_id' = %s::text
            """, (str(merge_id),))
            count = cur.fetchone()[0]

        assert count > 0


class TestAlertManagement:
    """Test alert acknowledgment and management"""

    def test_acknowledge_performance_alert(self, db_connection):
        """Verify alert acknowledgment workflow"""
        with db_connection.cursor() as cur:
            # Create an alert
            cur.execute("""
                INSERT INTO pggit.performance_alerts
                (metric_id, operation_type, alert_type, severity, baseline_p99_microseconds, actual_duration_microseconds, user_name)
                VALUES (1, 'test', 'THRESHOLD_EXCEEDED', 'WARNING', 10000, 25000, 'test_user')
                RETURNING alert_id
            """)
            alert_id = cur.fetchone()[0]

            # Acknowledge it
            cur.execute("""
                SELECT pggit.acknowledge_performance_alert(
                    p_alert_id := %s,
                    p_acknowledged_by := 'admin',
                    p_resolution_notes := 'Tuned query'
                )
            """, (alert_id,))

            # Verify acknowledgment
            cur.execute("""
                SELECT is_acknowledged, acknowledged_by, resolution_notes
                FROM pggit.performance_alerts
                WHERE alert_id = %s
            """, (alert_id,))
            row = cur.fetchone()

        assert row[0] is True
        assert row[1] == 'admin'
        assert 'Tuned' in row[2]

    def test_get_unacknowledged_alerts(self, db_connection):
        """Verify unacknowledged alerts are returned"""
        with db_connection.cursor() as cur:
            # Insert multiple alerts
            for i in range(3):
                cur.execute("""
                    INSERT INTO pggit.performance_alerts
                    (metric_id, operation_type, alert_type, severity, baseline_p99_microseconds, actual_duration_microseconds, user_name)
                    VALUES (%s, 'test', 'THRESHOLD_EXCEEDED', 'WARNING', 10000, 25000 + (i*5000), 'test_user')
                """, (i+1,))

            # Get unacknowledged
            cur.execute("""
                SELECT * FROM pggit.get_unacknowledged_alerts()
            """)
            rows = cur.fetchall()

        assert len(rows) >= 3
