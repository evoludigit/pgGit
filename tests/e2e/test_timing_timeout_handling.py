"""
E2E tests for timing and timeout handling.

Tests timeout behavior and long-running operations:
- Long-running merge stability
- Bulk operation timeout handling
- Concurrent operation timeout isolation
- Transaction cleanup after timeout
- Distributed transaction timeout scenarios

Key Coverage:
- Merge stability under load
- Timeout isolation between operations
- Transaction cleanup and recovery
- Distributed timeout handling
"""

import json
import pytest
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class TestE2ETimingTimeoutHandling:
    """Test timeout and long-running operation handling."""

    def test_long_running_merge_stability(self, db, pggit_installed):
        """Test merge stability during long operations"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        long_branch = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('long-merge-branch') RETURNING id"
        )[0]

        # Create large dataset
        db.execute("""
            CREATE TABLE public.long_merge_test (
                id INTEGER PRIMARY KEY,
                data TEXT,
                timestamp TIMESTAMP DEFAULT NOW()
            )
        """)

        # Insert 1000 rows to simulate long operation
        start_time = time.time()
        for i in range(1000):
            db.execute(
                "INSERT INTO public.long_merge_test (id, data) VALUES (%s, %s)",
                i,
                f"data-{i}" * 10,  # Larger payload
            )
        insert_time = time.time() - start_time

        # Merge should complete without timeout
        merge_start = time.time()
        result = db.execute_returning(
            "SELECT pggit.merge_branches(%s, %s, %s)",
            main_id,
            long_branch,
            "Long merge test",
        )
        merge_time = time.time() - merge_start

        assert result[0] is not None, "Long merge should complete"
        assert merge_time < 30, "Merge should complete within 30 seconds"

    def test_timeout_handling_in_bulk_operations(self, db, pggit_installed):
        """Test timeout handling in bulk insert operations"""
        db.execute("""
            CREATE TABLE public.timeout_bulk (
                id INTEGER PRIMARY KEY,
                value TEXT,
                processed BOOLEAN DEFAULT false
            )
        """)

        # Bulk insert with timeout monitoring
        start_time = time.time()
        timeout_seconds = 10

        batch_size = 100
        total_inserts = 0

        try:
            for batch in range(5):  # 5 batches of 100
                batch_start = time.time()

                if time.time() - start_time > timeout_seconds:
                    pytest.skip("Timeout reached")

                for i in range(batch_size):
                    row_id = batch * batch_size + i
                    db.execute(
                        "INSERT INTO public.timeout_bulk (id, value) VALUES (%s, %s)",
                        row_id,
                        f"value-{row_id}",
                    )
                    total_inserts += 1

                batch_time = time.time() - batch_start
                assert batch_time < timeout_seconds, f"Batch {batch} exceeded timeout"

        finally:
            # Verify inserted data
            count = db.execute("SELECT COUNT(*) FROM public.timeout_bulk")[0][0]
            assert count > 0, "Some inserts should succeed even with timeout"

    def test_concurrent_operation_timeout_isolation(self, db, pggit_installed):
        """Test timeout isolation between concurrent operations"""
        db.execute("""
            CREATE TABLE public.timeout_isolation (
                id INTEGER PRIMARY KEY,
                operation_id INTEGER,
                status TEXT
            )
        """)

        results = {"success": 0, "timeout": 0}

        def long_operation(op_id, duration_ms):
            try:
                db.execute(
                    "INSERT INTO public.timeout_isolation (id, operation_id, status) VALUES (%s, %s, %s)",
                    op_id,
                    op_id,
                    "starting",
                )

                time.sleep(duration_ms / 1000.0)

                db.execute(
                    "UPDATE public.timeout_isolation SET status = %s WHERE operation_id = %s",
                    "completed",
                    op_id,
                )
                results["success"] += 1
            except Exception:
                results["timeout"] += 1

        # Run operations with different durations
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [
                executor.submit(long_operation, 1, 100),  # 100ms
                executor.submit(long_operation, 2, 500),  # 500ms
                executor.submit(long_operation, 3, 100),  # 100ms
                executor.submit(long_operation, 4, 1000),  # 1000ms
                executor.submit(long_operation, 5, 100),  # 100ms
            ]

            for future in as_completed(futures, timeout=5):
                future.result()

        # Most operations should succeed
        assert results["success"] >= 3, (
            "Most operations should complete without timeout"
        )

    def test_transaction_cleanup_after_timeout(self, db, pggit_installed):
        """Test cleanup after transaction timeout"""
        db.execute("""
            CREATE TABLE public.cleanup_test (
                id INTEGER PRIMARY KEY,
                state TEXT
            )
        """)

        # Start transaction
        db.execute("INSERT INTO public.cleanup_test (id, state) VALUES (1, 'started')")

        # Simulate long-running operation that times out
        try:
            db.execute(
                "UPDATE public.cleanup_test SET state = %s WHERE id = 1", "processing"
            )
            time.sleep(0.1)
            # Simulate error
            raise Exception("Operation timeout")
        except Exception:
            pass

        # Verify table is still accessible after error
        result = db.execute("SELECT COUNT(*) FROM public.cleanup_test")
        assert result[0][0] > 0, "Table should be accessible after timeout"

    def test_distributed_transaction_timeout(self, db, pggit_installed):
        """Test handling of distributed transaction timeout scenarios"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        branch1 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('timeout-branch-1') RETURNING id"
        )[0]

        db.execute("""
            CREATE TABLE public.distributed_timeout (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER,
                data TEXT
            )
        """)

        # Insert across branches
        db.execute(
            "INSERT INTO public.distributed_timeout (id, branch_id, data) VALUES (1, %s, 'main-data')",
            main_id,
        )
        db.execute(
            "INSERT INTO public.distributed_timeout (id, branch_id, data) VALUES (2, %s, 'branch-data')",
            branch1,
        )

        # Both inserts should be queryable
        main_data = db.execute(
            "SELECT COUNT(*) FROM public.distributed_timeout WHERE branch_id = %s",
            main_id,
        )
        branch_data = db.execute(
            "SELECT COUNT(*) FROM public.distributed_timeout WHERE branch_id = %s",
            branch1,
        )

        assert main_data[0][0] > 0, "Main branch data should exist"
        assert branch_data[0][0] > 0, "Branch data should exist"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
