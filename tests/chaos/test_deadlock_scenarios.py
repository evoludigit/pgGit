"""
Tests that deliberately create deadlock scenarios.

These tests validate that pggit properly handles deadlock situations and that
PostgreSQL's deadlock detection works correctly with pggit operations.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor
import psycopg
import time


@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.destructive
class TestDeadlockScenarios:
    """Test deadlock detection and recovery."""

    @pytest.mark.timeout(30)
    def test_circular_lock_deadlock(self, db_connection_string: str):
        """
        Test: Create circular lock dependency (classic deadlock).

        Worker 1: Lock A → Lock B
        Worker 2: Lock B → Lock A

        Expected: PostgreSQL detects deadlock and kills one transaction.
        """
        table_a = "deadlock_table_a"
        table_b = "deadlock_table_b"

        # Setup tables
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_a} (id INT)")
        setup_conn.execute(f"CREATE TABLE {table_b} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def worker1():
            """Lock A, then B."""
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Lock table A
                conn.execute(f"LOCK TABLE {table_a} IN EXCLUSIVE MODE")
                time.sleep(0.5)  # Give worker2 time to lock B

                # Try to lock table B (will cause deadlock)
                conn.execute(f"LOCK TABLE {table_b} IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {"worker": 1, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                # Deadlock is expected
                if "deadlock" in str(e).lower():
                    return {"worker": 1, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 1, "error": str(e), "success": False}

        def worker2():
            """Lock B, then A."""
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Lock table B
                conn.execute(f"LOCK TABLE {table_b} IN EXCLUSIVE MODE")
                time.sleep(0.5)  # Give worker1 time to lock A

                # Try to lock table A (will cause deadlock)
                conn.execute(f"LOCK TABLE {table_a} IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {"worker": 2, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {"worker": 2, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 2, "error": str(e), "success": False}

        # Run workers concurrently
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(worker1)
            future2 = executor.submit(worker2)

            result1 = future1.result(timeout=20)
            result2 = future2.result(timeout=20)

        # Validation: At least one deadlock detected
        deadlocks = [r for r in [result1, result2] if r.get("deadlock_detected")]
        assert len(deadlocks) > 0, (
            "PostgreSQL should detect deadlock and abort one transaction"
        )

        print(f"\n✅ Deadlock correctly detected and handled: {result1}, {result2}")

    def test_deadlock_with_pggit_operations(self, db_connection_string: str):
        """
        Test: Deadlock involving pggit operations (commits, version changes).

        This tests if pggit operations can participate in deadlocks.
        """
        table_name = "pggit_deadlock_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def pggit_worker1():
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Lock the table
                conn.execute(f"LOCK TABLE {table_name} IN EXCLUSIVE MODE")
                time.sleep(0.3)

                # Try pggit operation (may cause deadlock)
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    ("deadlock-test-1", "deadlock-branch", "Deadlock test 1"),
                )
                conn.commit()
                conn.close()

                return {"worker": 1, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {"worker": 1, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 1, "error": str(e), "success": False}

        def pggit_worker2():
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Add data first (to trigger pggit versioning)
                conn.execute(f"ALTER TABLE {table_name} ADD COLUMN test_col INT")
                time.sleep(0.3)

                # Lock - may conflict with worker1
                conn.execute(f"LOCK TABLE {table_name} IN EXCLUSIVE MODE")

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    ("deadlock-test-2", "deadlock-branch", "Deadlock test 2"),
                )
                conn.commit()
                conn.close()

                return {"worker": 2, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {"worker": 2, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 2, "error": str(e), "success": False}

        # Run concurrent pggit operations
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(pggit_worker1)
            future2 = executor.submit(pggit_worker2)

            result1 = future1.result(timeout=25)
            result2 = future2.result(timeout=25)

        # At least one should succeed (no deadlock) or deadlock properly detected
        successes = [result1.get("success"), result2.get("success")]
        deadlocks = [r for r in [result1, result2] if r.get("deadlock_detected")]

        # Either both succeed (no deadlock) or deadlock detected
        if sum(successes) == 2:
            print("✅ No deadlock occurred - both operations succeeded")
        elif len(deadlocks) > 0:
            print(f"✅ Deadlock properly detected: {len(deadlocks)} deadlocks")
        else:
            pytest.fail(
                "Unexpected deadlock scenario - neither success nor proper deadlock detection"
            )

    @pytest.mark.timeout(45)
    def test_multiple_table_deadlock(self, db_connection_string: str):
        """
        Test: Deadlock involving multiple tables and pggit operations.

        More complex deadlock scenario with 3 workers and multiple tables.
        """
        tables = ["multi_table_a", "multi_table_b", "multi_table_c"]

        # Setup tables
        setup_conn = psycopg.connect(db_connection_string)
        for table in tables:
            setup_conn.execute(f"CREATE TABLE {table} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def multi_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Each worker locks tables in different order to create deadlock potential
                table_order = tables[worker_id:] + tables[:worker_id]  # Rotate order

                for table in table_order:
                    conn.execute(f"LOCK TABLE {table} IN EXCLUSIVE MODE")
                    time.sleep(0.2)  # Increase deadlock chance

                # Perform pggit operation
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (
                        f"multi-{worker_id}",
                        "multi-branch",
                        f"Multi-table worker {worker_id}",
                    ),
                )

                conn.commit()
                conn.close()
                return {"worker": worker_id, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {
                        "worker": worker_id,
                        "deadlock_detected": True,
                        "success": False,
                    }
                else:
                    return {"worker": worker_id, "error": str(e), "success": False}

        # Run 3 concurrent workers
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(multi_worker, i) for i in range(3)]
            results = [f.result(timeout=30) for f in futures]

        successes = [r for r in results if r.get("success")]
        deadlocks = [r for r in results if r.get("deadlock_detected")]

        # Should either have successes or deadlock detection, but not corruption
        total_resolved = len(successes) + len(deadlocks)
        assert total_resolved == 3, (
            f"All operations should either succeed or detect deadlock: {len(successes)} success, {len(deadlocks)} deadlocks"
        )

        if len(deadlocks) > 0:
            print(
                f"✅ Complex deadlock detected: {len(deadlocks)} deadlocks, {len(successes)} successes"
            )
        else:
            print(f"✅ No deadlock in complex scenario: {len(successes)} successes")

    def test_deadlock_timeout_behavior(self, db_connection_string: str):
        """
        Test: Deadlock detection with different timeout settings.

        Verifies that deadlocks are detected within reasonable time.
        """
        table_x = "timeout_table_x"
        table_y = "timeout_table_y"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_x} (id INT)")
        setup_conn.execute(f"CREATE TABLE {table_y} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def timeout_worker1():
            start_time = time.time()
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")
                conn.execute(f"LOCK TABLE {table_x} IN EXCLUSIVE MODE")
                time.sleep(0.3)

                conn.execute(f"LOCK TABLE {table_y} IN EXCLUSIVE MODE")
                conn.commit()
                conn.close()

                elapsed = time.time() - start_time
                return {"worker": 1, "success": True, "time": elapsed}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()
                elapsed = time.time() - start_time

                if "deadlock" in str(e).lower():
                    return {
                        "worker": 1,
                        "deadlock_detected": True,
                        "time": elapsed,
                        "success": False,
                    }
                else:
                    return {
                        "worker": 1,
                        "error": str(e),
                        "time": elapsed,
                        "success": False,
                    }

        def timeout_worker2():
            start_time = time.time()
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")
                conn.execute(f"LOCK TABLE {table_y} IN EXCLUSIVE MODE")
                time.sleep(0.3)

                conn.execute(f"LOCK TABLE {table_x} IN EXCLUSIVE MODE")
                conn.commit()
                conn.close()

                elapsed = time.time() - start_time
                return {"worker": 2, "success": True, "time": elapsed}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()
                elapsed = time.time() - start_time

                if "deadlock" in str(e).lower():
                    return {
                        "worker": 2,
                        "deadlock_detected": True,
                        "time": elapsed,
                        "success": False,
                    }
                else:
                    return {
                        "worker": 2,
                        "error": str(e),
                        "time": elapsed,
                        "success": False,
                    }

        # Run with timeout
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(timeout_worker1)
            future2 = executor.submit(timeout_worker2)

            result1 = future1.result(timeout=15)  # Should complete within 15 seconds
            result2 = future2.result(timeout=15)

        # Verify reasonable timing
        for result in [result1, result2]:
            assert result["time"] < 10, (
                f"Deadlock resolution took too long: {result['time']:.2f}s"
            )

        # Verify deadlock behavior
        deadlocks = [r for r in [result1, result2] if r.get("deadlock_detected")]
        assert len(deadlocks) > 0, "Deadlock should be detected and resolved quickly"

        print(
            f"✅ Deadlock resolved in {result1['time']:.2f}s and {result2['time']:.2f}s"
        )

    def test_deadlock_recovery_data_integrity(self, db_connection_string: str):
        """
        Test: Data integrity is maintained after deadlock recovery.

        Ensures that failed deadlock transactions don't leave partial state.
        """
        test_table = "integrity_table"

        # Setup with initial data
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {test_table} (id INT PRIMARY KEY, data TEXT)")
        setup_conn.execute(f"INSERT INTO {test_table} VALUES (1, 'initial')")
        setup_conn.commit()

        # Record initial state
        cursor = setup_conn.execute(f"SELECT data FROM {test_table} WHERE id = 1")
        initial_data = cursor.fetchone()[0]
        setup_conn.close()

        def integrity_worker1():
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")
                conn.execute(f"LOCK TABLE {test_table} IN EXCLUSIVE MODE")
                time.sleep(0.2)

                # Modify data (will be rolled back on deadlock)
                conn.execute(
                    f"UPDATE {test_table} SET data = 'modified_by_1' WHERE id = 1"
                )

                # This lock will cause deadlock
                conn.execute("LOCK TABLE pg_class IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {"worker": 1, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {"worker": 1, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 1, "error": str(e), "success": False}

        def integrity_worker2():
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")
                conn.execute(
                    "LOCK TABLE pg_class IN EXCLUSIVE MODE"
                )  # Opposite lock order
                time.sleep(0.2)

                conn.execute(f"LOCK TABLE {test_table} IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {"worker": 2, "success": True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {"worker": 2, "deadlock_detected": True, "success": False}
                else:
                    return {"worker": 2, "error": str(e), "success": False}

        # Run deadlock scenario
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(integrity_worker1)
            future2 = executor.submit(integrity_worker2)

            result1 = future1.result(timeout=20)
            result2 = future2.result(timeout=20)

        # Verify deadlock occurred
        deadlocks = [r for r in [result1, result2] if r.get("deadlock_detected")]
        assert len(deadlocks) > 0, "Deadlock should occur in this scenario"

        # Verify data integrity maintained
        final_conn = psycopg.connect(db_connection_string)
        cursor = final_conn.execute(f"SELECT data FROM {test_table} WHERE id = 1")
        final_data = cursor.fetchone()[0]
        final_conn.close()

        assert final_data == initial_data, (
            f"Data integrity violated by deadlock: expected '{initial_data}', got '{final_data}'"
        )

        print(
            f"✅ Data integrity maintained through deadlock: '{final_data}' preserved"
        )

    @pytest.mark.slow
    def test_deadlock_under_load(self, db_connection_string: str):
        """
        Test: Deadlock detection under high concurrent load.

        Stress test with many workers competing for locks.
        """
        num_tables = 5
        tables = [f"load_deadlock_table_{i}" for i in range(num_tables)]

        # Setup multiple tables
        setup_conn = psycopg.connect(db_connection_string)
        for table in tables:
            setup_conn.execute(f"CREATE TABLE {table} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def load_deadlock_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Each worker locks tables in a different pattern to create deadlock potential
                # Worker 0: 0,1,2,3,4
                # Worker 1: 1,2,3,4,0
                # Worker 2: 2,3,4,0,1
                # etc.
                start_idx = worker_id % num_tables
                lock_order = tables[start_idx:] + tables[:start_idx]

                for table in lock_order:
                    conn.execute(f"LOCK TABLE {table} IN EXCLUSIVE MODE")
                    time.sleep(0.1)  # Small delay to increase deadlock chance

                conn.commit()
                conn.close()
                return {"worker": worker_id, "success": True, "deadlocks": 0}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if "deadlock" in str(e).lower():
                    return {
                        "worker": worker_id,
                        "deadlock_detected": True,
                        "success": False,
                        "deadlocks": 1,
                    }
                else:
                    return {
                        "worker": worker_id,
                        "error": str(e),
                        "success": False,
                        "deadlocks": 0,
                    }

        # Run many concurrent workers
        num_workers = 15
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [
                executor.submit(load_deadlock_worker, i) for i in range(num_workers)
            ]
            results = [f.result(timeout=60) for f in futures]

        successes = [r for r in results if r.get("success")]
        deadlocks = [r for r in results if r.get("deadlock_detected")]

        # Should have some successes and some deadlocks under load
        total_resolved = len(successes) + len(deadlocks)
        assert total_resolved == num_workers, (
            f"All operations should complete: {total_resolved}/{num_workers}"
        )

        assert len(deadlocks) > 0, "Some deadlocks should occur under high contention"

        total_deadlock_count = 0
        for r in results:
            deadlock_count = r.get("deadlocks")
            if deadlock_count is not None:
                total_deadlock_count += deadlock_count
        print(
            f"✅ Load deadlock test: {len(successes)} successes, {len(deadlocks)} deadlocks"
        )
        print(f"   Total deadlock detections: {total_deadlock_count}")
