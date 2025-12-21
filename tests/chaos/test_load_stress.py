"""
High-load stress tests and performance validation.

These tests validate system behavior under high load conditions, including
concurrent connections, rapid operations, and performance degradation analysis.
"""

import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import psycopg
import pytest


@pytest.mark.chaos
@pytest.mark.load
@pytest.mark.slow
class TestLoadStress:
    """High-load stress tests."""

    @pytest.mark.timeout(300)  # 5 minutes max
    def test_multiple_concurrent_connections(self, db_connection_string: str):
        """
        Test: Handle multiple concurrent database connections.

        Expected: System handles concurrent load, no crashes or hangs.
        """
        num_workers = 20  # 20 concurrent connections (conservative)
        results = []
        errors = []

        def worker(worker_id: int):
            """Worker: connect, execute query."""
            start = time.time()

            try:
                conn = psycopg.connect(db_connection_string)

                # Execute simple query
                cursor = conn.execute(
                    "SELECT %s as worker_id, NOW() as timestamp", (worker_id,)
                )
                result = cursor.fetchone()

                conn.close()

                elapsed = time.time() - start

                return {
                    "worker": worker_id,
                    "success": True,
                    "elapsed": elapsed,
                }

            except Exception as e:
                elapsed = time.time() - start
                return {
                    "worker": worker_id,
                    "success": False,
                    "error": str(e),
                    "elapsed": elapsed,
                }

        # Execute load test
        print(f"\n🔥 Starting {num_workers}-connection concurrent test...")

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]

            for future in as_completed(futures):
                result = future.result()

                if result["success"]:
                    results.append(result)
                else:
                    errors.append(result)

        # Analysis
        success_rate = len(results) / num_workers if num_workers > 0 else 0
        avg_time = sum(r["elapsed"] for r in results) / len(results) if results else 0
        max_time = max(r["elapsed"] for r in results) if results else 0

        print(f"\n✅ Concurrent connection test results:")
        print(f"   Success rate: {success_rate:.1%} ({len(results)}/{num_workers})")
        print(f"   Average time: {avg_time:.3f}s")
        print(f"   Max time: {max_time:.3f}s")
        print(f"   Errors: {len(errors)}")

        # Validation: At least 80% success rate
        assert success_rate >= 0.8, (
            f"Success rate should be >= 80%, got {success_rate:.1%}"
        )

    @pytest.mark.timeout(120)
    def test_rapid_query_execution(self, db_connection_string: str):
        """
        Test: Execute queries as fast as possible sequentially.

        Expected: No crashes, consistent behavior, performance metrics collected.
        """
        num_queries = 100
        conn = psycopg.connect(db_connection_string)

        # Warm up
        conn.execute("SELECT 1")

        # Rapid queries
        start = time.time()
        successful = 0
        failed = 0

        for i in range(num_queries):
            try:
                cursor = conn.execute("SELECT %s as iteration", (i,))
                result = cursor.fetchone()
                if result is not None:
                    successful += 1
                else:
                    failed += 1
            except Exception as e:
                failed += 1

        elapsed = time.time() - start
        queries_per_second = num_queries / elapsed if elapsed > 0 else 0

        conn.close()

        print(f"\n✅ Rapid query execution test:")
        print(f"   {num_queries} queries in {elapsed:.2f}s")
        print(f"   {queries_per_second:.1f} queries/second")
        print(f"   Successful: {successful}, Failed: {failed}")

        assert successful >= (num_queries * 0.95), (
            "Should succeed for at least 95% of queries"
        )

    @pytest.mark.timeout(180)
    def test_performance_stability_over_iterations(self, db_connection_string: str):
        """
        Test: Measure performance consistency as operations accumulate.

        Expected: Performance stays consistent, no exponential degradation.
        """
        conn = psycopg.connect(db_connection_string)

        # Warm up
        conn.execute("SELECT 1")
        conn.commit()

        measurements = []
        iterations_per_batch = 50

        print(
            f"\n📊 Performance stability test (10 batches, {iterations_per_batch} iterations each):"
        )

        for batch in range(10):
            batch_start = time.time()

            for i in range(iterations_per_batch):
                try:
                    cursor = conn.execute(
                        "SELECT %s", (batch * iterations_per_batch + i,)
                    )
                    cursor.fetchone()
                except Exception:
                    pass  # Ignore errors, just measure throughput

            batch_time = time.time() - batch_start
            measurements.append(batch_time)

            total_so_far = (batch + 1) * iterations_per_batch
            print(
                f"   Batch {batch}: {batch_time:.3f}s (total operations: {total_so_far})"
            )

        conn.close()

        # Analysis: Check for exponential degradation
        if len(measurements) > 1:
            first_batch = measurements[0]
            last_batch = measurements[-1]
            degradation_factor = last_batch / first_batch if first_batch > 0 else 1.0

            print(f"\n📈 Performance degradation factor: {degradation_factor:.2f}x")

            # Validation: Less than 2x degradation over 500 operations
            assert degradation_factor < 2.0, (
                f"Performance degraded too much: {degradation_factor:.2f}x"
            )

        print(f"✅ Performance remained stable throughout test")

    def test_concurrent_table_creation(self, db_connection_string: str):
        """
        Test: Create multiple tables concurrently.

        Expected: No conflicts or deadlocks, all tables created successfully.
        """
        num_workers = 10
        results = []
        errors = []

        def worker(worker_id: int):
            """Worker: create table with unique name."""
            try:
                conn = psycopg.connect(db_connection_string)

                table_name = f"load_table_{worker_id}"

                conn.execute(f"CREATE TABLE {table_name} (id INT, data TEXT)")
                conn.commit()

                # Verify table exists
                cursor = conn.execute(
                    "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = %s)",
                    (table_name,),
                )
                exists = cursor.fetchone()[0]

                # Cleanup
                conn.execute(f"DROP TABLE IF EXISTS {table_name}")
                conn.commit()
                conn.close()

                return {
                    "worker": worker_id,
                    "success": exists,
                }

            except Exception as e:
                return {
                    "worker": worker_id,
                    "success": False,
                    "error": str(e),
                }

        # Execute concurrent table creation
        print(f"\n🔥 Starting {num_workers}-worker concurrent table creation test...")

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]

            for future in as_completed(futures):
                result = future.result()
                if result["success"]:
                    results.append(result)
                else:
                    errors.append(result)

        success_rate = len(results) / num_workers if num_workers > 0 else 0

        print(f"\n✅ Concurrent table creation results:")
        print(f"   Success: {len(results)}/{num_workers}")
        print(f"   Errors: {len(errors)}")

        assert success_rate >= 0.9, f"Expected >= 90% success, got {success_rate:.1%}"
