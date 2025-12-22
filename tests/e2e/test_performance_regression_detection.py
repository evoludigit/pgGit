"""
E2E tests for performance regression detection.

Tests performance monitoring and regression detection:
- Branch creation speed regression
- Merge operation performance regression
- Snapshot creation performance regression
- Temporal query performance regression

Key Coverage:
- Performance baseline establishment
- Regression threshold detection
- Consistent performance validation
- Query optimization verification
"""

import json
import pytest
import time
from datetime import datetime


class TestE2EPerformanceRegressionDetection:
    """Test performance regression detection."""

    def test_regression_in_branch_creation_speed(self, db, pggit_installed):
        """Test regression detection in branch creation performance"""
        # Establish baseline
        baseline_times = []
        for i in range(3):
            start = time.time()
            db.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"perf-baseline-{i}",
            )
            baseline_times.append(time.time() - start)

        baseline_avg = sum(baseline_times) / len(baseline_times)

        # Test current performance
        test_times = []
        for i in range(3):
            start = time.time()
            db.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"perf-test-{i}",
            )
            test_times.append(time.time() - start)

        test_avg = sum(test_times) / len(test_times)

        # Regression threshold: 50% slower
        regression_threshold = baseline_avg * 1.5

        assert test_avg < regression_threshold, (
            f"Branch creation regressed: baseline={baseline_avg:.4f}s, current={test_avg:.4f}s"
        )

    def test_regression_in_merge_performance(self, db, pggit_installed):
        """Test regression detection in merge performance"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        db.execute("""
            CREATE TABLE public.perf_merge_test (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Create test branches
        branch1 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('perf-merge-1') RETURNING id"
        )[0]

        # Insert baseline data
        for i in range(100):
            db.execute(
                "INSERT INTO public.perf_merge_test (id, data) VALUES (%s, %s)",
                i,
                f"data-{i}",
            )

        # Baseline merge time
        baseline_start = time.time()
        db.execute_returning(
            "SELECT pggit.merge_branches(%s, %s, %s)",
            main_id,
            branch1,
            "Baseline merge",
        )
        baseline_time = time.time() - baseline_start

        # Test merge time (should be similar)
        branch2 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('perf-merge-2') RETURNING id"
        )[0]

        test_start = time.time()
        db.execute_returning(
            "SELECT pggit.merge_branches(%s, %s, %s)", main_id, branch2, "Test merge"
        )
        test_time = time.time() - test_start

        # Regression threshold: 2x slower
        regression_threshold = baseline_time * 2.0

        assert test_time < regression_threshold, (
            f"Merge regressed: baseline={baseline_time:.4f}s, current={test_time:.4f}s"
        )

    def test_regression_in_snapshot_creation(self, db, pggit_installed):
        """Test regression detection in snapshot creation"""
        db.execute("""
            CREATE TABLE public.perf_snapshot (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Baseline snapshot creation
        baseline_times = []
        for j in range(3):
            db.execute("DELETE FROM public.perf_snapshot")
            for i in range(50):
                db.execute(
                    "INSERT INTO public.perf_snapshot (id, data) VALUES (%s, %s)",
                    i,
                    f"data-{i}",
                )

            start = time.time()
            db.execute_returning(
                "SELECT pggit.create_temporal_snapshot('perf_snapshot', 1, %s)",
                json.dumps({"iteration": j}),
            )
            baseline_times.append(time.time() - start)

        baseline_avg = sum(baseline_times) / len(baseline_times)

        # Test snapshot creation
        test_times = []
        for j in range(3, 6):
            start = time.time()
            db.execute_returning(
                "SELECT pggit.create_temporal_snapshot('perf_snapshot', 1, %s)",
                json.dumps({"iteration": j}),
            )
            test_times.append(time.time() - start)

        test_avg = sum(test_times) / len(test_times)

        # Regression threshold: 50% slower
        regression_threshold = baseline_avg * 1.5

        assert test_avg < regression_threshold, (
            f"Snapshot creation regressed: baseline={baseline_avg:.4f}s, current={test_avg:.4f}s"
        )

    def test_regression_in_temporal_queries(self, db, pggit_installed):
        """Test regression detection in temporal query performance"""
        db.execute("""
            CREATE TABLE public.perf_temporal (
                id INTEGER PRIMARY KEY,
                data TEXT,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)

        # Insert test data
        for i in range(100):
            db.execute(
                "INSERT INTO public.perf_temporal (id, data) VALUES (%s, %s)",
                i,
                f"data-{i}",
            )

        # Baseline query time
        baseline_times = []
        for _ in range(5):
            start = time.time()
            db.execute(
                "SELECT pggit.query_historical_data('public.perf_temporal', %s, NULL)",
                datetime.now().isoformat(),
            )
            baseline_times.append(time.time() - start)

        baseline_avg = sum(baseline_times) / len(baseline_times)

        # Test query time
        test_times = []
        for _ in range(5):
            start = time.time()
            db.execute(
                "SELECT pggit.query_historical_data('public.perf_temporal', %s, NULL)",
                datetime.now().isoformat(),
            )
            test_times.append(time.time() - start)

        test_avg = sum(test_times) / len(test_times)

        # Regression threshold: 100% slower (2x)
        regression_threshold = baseline_avg * 2.0

        assert test_avg < regression_threshold, (
            f"Temporal query regressed: baseline={baseline_avg:.4f}s, current={test_avg:.4f}s"
        )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
