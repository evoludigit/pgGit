"""
Concurrency tests for branch operations.

These tests validate pggit's branch creation and manipulation behavior under
concurrent access, including race conditions during branch operations.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed

import psycopg
import pytest
from psycopg.rows import dict_row


@pytest.mark.chaos
@pytest.mark.concurrent
class TestConcurrentBranching:
    """Test concurrent branch creation and manipulation."""

    @pytest.mark.parametrize("num_branches", [5, 10, 20])
    def test_concurrent_branch_creation(
        self, db_connection_string: str, num_branches: int,
    ):
        """
        Test: Multiple workers creating different branches simultaneously.

        Expected: All branches created successfully, no conflicts.
        """

        def create_branch(branch_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            branch_name = f"concurrent-branch-{branch_id}"
            table_name = f"branch_table_{branch_id}"

            try:
                # Create table and commit on new branch
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch_name, f"Create branch {branch_id}"),
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {"branch_id": branch_id, "branch": branch_name, "success": True}

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"branch_id": branch_id, "error": str(e), "success": False}

        # Execute concurrent branch creation
        with ThreadPoolExecutor(max_workers=num_branches) as executor:
            futures = [executor.submit(create_branch, i) for i in range(num_branches)]
            results = [f.result() for f in as_completed(futures, timeout=60)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        # Validation: All should succeed (different branches)
        assert len(successes) == num_branches, (
            f"All {num_branches} branches should be created, but {len(failures)} failed"
        )

        print(f"\n✅ Successfully created {len(successes)} branches concurrently")

    def test_concurrent_branch_creation_same_name(self, db_connection_string: str):
        """
        Test: Multiple workers trying to create branches with the same name.

        Expected: At most one succeeds, others fail appropriately.
        """
        branch_name = "duplicate-branch-test"
        num_workers = 5

        def create_duplicate_branch(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            table_name = f"dup_table_{worker_id}"

            try:
                # Create table
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                # Try to commit to same branch name
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (
                        f"dup-{worker_id}",
                        branch_name,
                        f"Duplicate branch attempt {worker_id}",
                    ),
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {"worker_id": worker_id, "success": True}

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Run concurrent duplicate branch creation
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [
                executor.submit(create_duplicate_branch, i) for i in range(num_workers)
            ]
            results = [f.result() for f in as_completed(futures, timeout=45)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        # Validation: At most one success (first one to create branch)
        assert len(successes) <= 1, (
            f"At most one worker should succeed with duplicate branch name, got {len(successes)}"
        )

        # Failures should be due to branch conflicts, not system errors
        for failure in failures:
            error_msg = failure["error"].lower()
            assert any(
                keyword in error_msg
                for keyword in [
                    "branch",
                    "already exists",
                    "duplicate",
                    "conflict",
                    "concurrent",
                ]
            ), f"Unexpected failure reason: {failure['error']}"

        print(
            f"\n✅ Duplicate branch test: {len(successes)} successes, {len(failures)} expected failures",
        )

    def test_branch_deletion_during_active_commit(self, db_connection_string: str):
        """
        Test: Deleting a branch while another worker is committing to it.

        Expected: Either commit succeeds OR deletion succeeds (not both).
        """
        branch_name = "deletion-test-branch"

        def commit_worker():
            """Worker that commits to branch."""
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("CREATE TABLE deletion_test (id INT)")
                conn.commit()

                # Slow commit (simulate long transaction)
                conn.execute("SELECT pg_sleep(0.5)")
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    ("deletion-commit", branch_name, "Commit during deletion"),
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {"action": "commit", "success": True}

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"action": "commit", "error": str(e), "success": False}

        def delete_worker():
            """Worker that tries to delete branch."""
            import time

            time.sleep(0.2)  # Let commit start first

            conn = psycopg.connect(db_connection_string)

            try:
                # Try to delete branch (this may not be implemented yet)
                cursor = conn.execute(
                    "SELECT pggit.delete_branch_simple(%s)", (branch_name,),
                )
                conn.commit()
                conn.close()

                return {"action": "delete", "success": True}

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"action": "delete", "error": str(e), "success": False}

        # Run concurrent commit and delete
        with ThreadPoolExecutor(max_workers=2) as executor:
            commit_future = executor.submit(commit_worker)
            delete_future = executor.submit(delete_worker)

            commit_result = commit_future.result(timeout=30)
            delete_result = delete_future.result(timeout=30)

        # Validation: At most one succeeds (mutual exclusion)
        both_succeeded = commit_result.get("success", False) and delete_result.get(
            "success", False,
        )
        assert not both_succeeded, (
            "Commit and delete should not both succeed (race condition!)"
        )

        print(f"\n✅ Commit: {commit_result}, Delete: {delete_result}")

    @pytest.mark.parametrize("num_branches", [3, 6, 9])
    def test_concurrent_branch_operations_mixed(
        self, db_connection_string: str, num_branches: int,
    ):
        """
        Test: Mix of branch creation, commits, and potential conflicts.

        This tests a more realistic scenario with different branch operations.
        """
        results = []

        def mixed_branch_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            operations = []

            try:
                # Operation 1: Create branch
                branch_name = f"mixed-branch-{worker_id}"
                table_name = f"mixed_table_{worker_id}"

                conn.execute(f"CREATE TABLE {table_name} (id INT, data TEXT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (
                        branch_name,
                        f"Initialize branch {worker_id}",
                    ),
                )
                result = cursor.fetchone()
                operations.append(
                    {
                        "op": "create_branch",
                        "success": True,
                        "trinity_id": list(result.values())[0],
                    },
                )

                # Operation 2: Add more data and commit again
                conn.execute(
                    f"INSERT INTO {table_name} (id, data) VALUES (1, 'test data')",
                )
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch_name, f"Update branch {worker_id}"),
                )
                result = cursor.fetchone()
                operations.append(
                    {
                        "op": "update_commit",
                        "success": True,
                        "trinity_id": list(result.values())[0],
                    },
                )

                conn.close()
                return {
                    "worker_id": worker_id,
                    "operations": operations,
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {
                    "worker_id": worker_id,
                    "error": str(e),
                    "operations": operations,
                    "success": False,
                }

        # Run mixed operations concurrently
        with ThreadPoolExecutor(max_workers=num_branches) as executor:
            futures = [
                executor.submit(mixed_branch_worker, i) for i in range(num_branches)
            ]
            for future in as_completed(futures, timeout=90):
                try:
                    result = future.result(timeout=15)
                    results.append(result)
                except Exception as e:
                    results.append(
                        {"worker_id": "unknown", "error": str(e), "success": False},
                    )

        successes = [r for r in results if r.get("success")]
        failures = [r for r in results if not r.get("success")]

        # Should have reasonable success rate
        success_rate = len(successes) / num_branches
        assert success_rate > 0.5, f"Expected >50% success rate, got {success_rate:.2f}"

        # Collect all Trinity IDs from successful operations
        all_trinity_ids = []
        for success in successes:
            for op in success.get("operations", []):
                if "trinity_id" in op:
                    all_trinity_ids.append(op["trinity_id"])

        # All Trinity IDs should be unique
        assert len(all_trinity_ids) == len(set(all_trinity_ids)), (
            "Trinity ID collision in mixed branch operations"
        )

        print(
            f"\n✅ Mixed operations: {len(successes)}/{num_branches} workers succeeded",
        )
        print(
            f"   Total operations: {sum(len(s.get('operations', [])) for s in successes)}",
        )
        print(f"   Unique Trinity IDs: {len(set(all_trinity_ids))}")

    def test_branch_isolation_between_workers(self, db_connection_string: str) -> None:
        """
        Test: Branch operations from different workers should be isolated.

        Each worker gets their own branch and should not interfere with others.
        Ensures proper isolation between concurrent branch operations.
        """
        num_workers = 6

        def isolated_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            branch_name = f"isolation-branch-{worker_id}"
            table_name = f"isolation_table_{worker_id}"

            try:
                # Create worker's private table and branch
                conn.execute(f"CREATE TABLE {table_name} (id INT, worker_data TEXT)")
                conn.execute(
                    f"INSERT INTO {table_name} (id, worker_data) VALUES ({worker_id}, 'worker_{worker_id}_data')",
                )
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (
                        branch_name,
                        f"Isolated work by worker {worker_id}",
                    ),
                )
                trinity_id = cursor.fetchone()
                conn.commit()

                # Verify worker's data is visible
                cursor = conn.execute(f"SELECT worker_data FROM {table_name}")
                worker_data = cursor.fetchone()["worker_data"]
                assert worker_data == f"worker_{worker_id}_data", (
                    f"Worker {worker_id} data corrupted: {worker_data}"
                )

                conn.close()
                return {
                    "worker_id": worker_id,
                    "branch": branch_name,
                    "trinity_id": trinity_id,
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Run isolated workers
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(isolated_worker, i) for i in range(num_workers)]
            results = [f.result() for f in as_completed(futures, timeout=60)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        # All should succeed (no interference between branches)
        assert len(successes) == num_workers, (
            f"All {num_workers} isolated workers should succeed without interference. "
            f"Got {len(successes)} successes, {len(failures)} failures. "
            f"This indicates branch isolation is not working properly."
        )

        # All Trinity IDs should be unique
        trinity_ids = [list(s["trinity_id"].values())[0] for s in successes]
        assert len(trinity_ids) == len(set(trinity_ids)), (
            "Trinity IDs should be unique across isolated branches"
        )

        print(f"\n✅ Branch isolation: {len(successes)} workers completed successfully")
        print(f"   All Trinity IDs unique: {len(set(trinity_ids))} distinct IDs")

    @pytest.mark.slow
    def test_branch_contention_under_load(self, db_connection_string: str) -> None:
        """
        Test: High contention on branch operations with many workers.

        This stress tests branch creation and commit operations.
        """
        num_workers = 20
        base_branch = "load-test-branch"

        def load_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            # Each worker uses a slightly different branch name
            branch_name = f"{base_branch}-{worker_id % 3}"  # Only 3 different branches
            table_name = f"load_table_{worker_id}"

            operations_completed = 0

            try:
                # Perform multiple operations per worker
                for op in range(3):
                    try:
                        conn.execute(f"CREATE TABLE {table_name}_{op} (id INT)")
                        conn.commit()

                        cursor = conn.execute(
                            "SELECT pggit.commit_changes(%s, %s)",
                            (
                                branch_name,
                                f"Load operation {worker_id}-{op}",
                            ),
                        )
                        conn.commit()
                        operations_completed += 1

                    except Exception:
                        conn.rollback()

                conn.close()
                return {
                    "worker_id": worker_id,
                    "operations": operations_completed,
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.close()
                except:
                    pass
                return {
                    "worker_id": worker_id,
                    "error": str(e),
                    "operations": operations_completed,
                    "success": False,
                }

        # Run high-load test
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(load_worker, i) for i in range(num_workers)]
            results = []

            for future in as_completed(futures, timeout=180):  # 3 minute timeout
                try:
                    result = future.result(timeout=30)
                    results.append(result)
                except Exception as e:
                    results.append(
                        {"worker_id": "timeout", "error": str(e), "success": False},
                    )

        successes = [r for r in results if r.get("success")]
        total_operations = sum(r.get("operations", 0) for r in results)

        # Should have reasonable success rate under load
        assert len(successes) > num_workers * 0.3, (
            f"Expected >30% success rate under load, got {len(successes)}/{num_workers}"
        )

        assert total_operations > 0, "Some operations should complete under load"

        print(f"\n✅ Load test: {len(successes)}/{num_workers} workers succeeded")
        print(f"   Total operations completed: {total_operations}")
        print(f"   Average operations per worker: {total_operations / num_workers:.1f}")

    @pytest.mark.slow
    def test_extreme_branching_contention(self, db_connection_string: str) -> None:
        """
        Test: Extreme contention with many workers competing for the same branch.

        This pushes the limits of pggit's concurrency handling by having 10 workers
        perform multiple operations each on shared branches, testing conflict resolution
        and transaction isolation under maximum contention.
        """
        num_workers = 10
        branch_name = "extreme-contention-branch"

        def extreme_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            operations_completed = 0

            try:
                # All workers compete for the same branch
                for attempt in range(5):  # Multiple attempts per worker
                    try:
                        # Create table with unique name per worker-attempt
                        table_name = f"extreme_table_{worker_id}_{attempt}"
                        conn.execute(
                            f"CREATE TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)",
                        )
                        conn.execute(
                            f"INSERT INTO {table_name} (data) VALUES ('worker_{worker_id}_attempt_{attempt}')",
                        )
                        conn.commit()

                        # Commit to the shared branch
                        cursor = conn.execute(
                            "SELECT pggit.commit_changes(%s, %s)",
                            (
                                branch_name,
                                f"Extreme load operation {worker_id}-{attempt}",
                            ),
                        )
                        conn.commit()
                        operations_completed += 1

                        # Brief pause to create contention windows
                        import time

                        time.sleep(0.01)

                    except psycopg.Error as e:
                        # Expected under high contention - rollback and continue
                        conn.rollback()
                        continue

                conn.close()
                return {
                    "worker_id": worker_id,
                    "operations": operations_completed,
                    "success": operations_completed > 0,
                }

            except Exception as e:
                try:
                    conn.close()
                except:
                    pass
                return {
                    "worker_id": worker_id,
                    "error": str(e),
                    "operations": operations_completed,
                    "success": False,
                }

        # Run extreme contention test
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(extreme_worker, i) for i in range(num_workers)]
            results = []

            for future in as_completed(futures, timeout=120):  # 2 minute timeout
                try:
                    result = future.result(timeout=30)
                    results.append(result)
                except Exception as e:
                    results.append(
                        {"worker_id": "timeout", "error": str(e), "success": False},
                    )

        successes = [r for r in results if r.get("success")]
        total_operations = sum(r.get("operations", 0) for r in results)
        errors = [r for r in results if r.get("error") and not r.get("success")]

        # Under extreme contention, we expect some success but allow for conflicts
        assert len(successes) > 0, (
            "At least some operations should succeed under extreme contention"
        )

        # Should complete some operations despite conflicts
        assert total_operations > len(successes), (
            "Multiple operations per successful worker expected"
        )

        print(
            f"\n✅ Extreme contention test: {len(successes)}/{num_workers} workers had successes",
        )
        print(f"   Total operations across all workers: {total_operations}")
        print(f"   Errors/conflicts: {len(errors)}")
        print(f"   Average operations per worker: {total_operations / num_workers:.1f}")

    @pytest.mark.slow
    @pytest.mark.performance
    @pytest.mark.timeout(60)  # Allow 60 seconds for performance test
    def test_branching_performance_under_load(self, db_connection_string: str):
        """
        Test: Performance validation under sustained branching load.

        Measures throughput and validates performance remains acceptable.
        """
        import time

        num_workers = 8
        branch_name = "performance-test-branch"
        test_duration = 10  # 10 seconds

        def performance_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            operations = 0
            start_time = time.time()

            try:
                while time.time() - start_time < test_duration:
                    try:
                        # Create unique table for this operation
                        table_name = f"perf_table_{worker_id}_{operations}"
                        conn.execute(f"CREATE TABLE {table_name} (id INT, data TEXT)")
                        conn.execute(
                            f"INSERT INTO {table_name} (id, data) VALUES ({operations}, 'perf_data')",
                        )
                        conn.commit()

                        # Commit to shared branch
                        cursor = conn.execute(
                            "SELECT pggit.commit_changes(%s, %s)",
                            (branch_name, f"Performance op {worker_id}-{operations}"),
                        )
                        conn.commit()
                        operations += 1

                    except psycopg.Error:
                        # Conflict occurred, rollback and continue
                        conn.rollback()
                        continue

                conn.close()
                return {
                    "worker_id": worker_id,
                    "operations": operations,
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.close()
                except:
                    pass
                return {
                    "worker_id": worker_id,
                    "error": str(e),
                    "operations": operations,
                    "success": False,
                }

        # Run performance test
        start_time = time.time()
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [
                executor.submit(performance_worker, i) for i in range(num_workers)
            ]
            results = [
                f.result(timeout=60) for f in futures
            ]  # 1 minute timeout per worker

        end_time = time.time()
        total_time = end_time - start_time

        successes = [r for r in results if r.get("success")]
        total_operations = sum(r.get("operations", 0) for r in results)
        operations_per_second = total_operations / total_time

        # Performance expectations - should handle reasonable load
        # At least 50 operations in 10 seconds shows basic functionality
        assert total_operations > 50, (
            f"Expected >50 operations in {test_duration}s under normal load, got {total_operations}. "
            f"This may indicate performance issues."
        )
        # At least 2 operations per second is reasonable for database operations
        assert operations_per_second > 2.0, (
            f"Expected >2.0 operations/second, got {operations_per_second:.2f}. "
            f"Performance may be degraded under concurrent load."
        )

        print(f"\n✅ Performance test results:")
        print(f"   Duration: {total_time:.2f}s")
        print(f"   Total operations: {total_operations}")
        print(f"   Successful workers: {len(successes)}")
        print(f"   Operations per second: {operations_per_second:.2f}")

    @pytest.mark.slow
    def test_mixed_workload_chaos(self, db_connection_string: str):
        """
        Test: Mixed workload with different operation types under chaos.

        Simulates real-world usage with concurrent commits, branches, and queries.
        """
        import random

        num_workers = 12
        operations_per_worker = 8

        def chaos_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            operations_completed = 0
            errors_encountered = 0

            try:
                for op in range(operations_per_worker):
                    operation_type = random.choice(
                        [
                            "create_branch",
                            "commit_changes",
                            "create_table",
                            "query_data",
                        ],
                    )

                    try:
                        if operation_type == "create_branch":
                            branch_name = f"chaos-branch-{worker_id}-{op}"
                            table_name = f"chaos_table_{worker_id}_{op}"
                            conn.execute(
                                f"CREATE TABLE {table_name} (id INT, data TEXT)",
                            )
                            conn.execute(
                                f"INSERT INTO {table_name} (id, data) VALUES ({op}, 'chaos_data')",
                            )
                            conn.commit()

                            cursor = conn.execute(
                                "SELECT pggit.commit_changes(%s, %s)",
                                (branch_name, f"Chaos branch {worker_id}-{op}"),
                            )
                            conn.commit()

                        elif operation_type == "commit_changes":
                            # Use a shared branch for conflicts
                            branch_name = f"shared-chaos-branch-{worker_id % 3}"
                            table_name = f"shared_table_{worker_id}_{op}"
                            conn.execute(
                                f"CREATE TABLE {table_name} (id INT, data TEXT)",
                            )
                            conn.execute(
                                f"INSERT INTO {table_name} (id, data) VALUES ({op}, 'shared_data')",
                            )
                            conn.commit()

                            cursor = conn.execute(
                                "SELECT pggit.commit_changes(%s, %s)",
                                (branch_name, f"Shared chaos {worker_id}-{op}"),
                            )
                            conn.commit()

                        elif operation_type == "create_table":
                            # Just create a table without committing
                            table_name = f"simple_table_{worker_id}_{op}"
                            conn.execute(f"CREATE TABLE {table_name} (id INT)")
                            conn.commit()

                        elif operation_type == "query_data":
                            # Try to query existing tables
                            try:
                                cursor = conn.execute("""
                                    SELECT schemaname, tablename
                                    FROM pg_tables
                                    WHERE schemaname = 'public'
                                    AND tablename LIKE 'chaos_%'
                                    LIMIT 5
                                """)
                                tables = cursor.fetchall()
                                # Just accessing the data is enough for this test
                            except psycopg.Error:
                                # No tables to query, that's fine
                                pass

                        operations_completed += 1

                    except psycopg.Error as e:
                        # Expected under mixed workload chaos
                        conn.rollback()
                        errors_encountered += 1
                        continue

                conn.close()
                return {
                    "worker_id": worker_id,
                    "operations": operations_completed,
                    "errors": errors_encountered,
                    "success": operations_completed > 0,
                }

            except Exception as e:
                try:
                    conn.close()
                except:
                    pass
                return {
                    "worker_id": worker_id,
                    "error": str(e),
                    "operations": operations_completed,
                    "success": False,
                }

        # Run mixed workload chaos test
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(chaos_worker, i) for i in range(num_workers)]
            results = [f.result(timeout=60) for f in futures]  # 1 minute timeout

        successes = [r for r in results if r.get("success")]
        total_operations = sum(r.get("operations", 0) for r in results)
        total_errors = sum(r.get("errors", 0) for r in results)

        # Under mixed workload chaos, we expect some success despite conflicts
        assert len(successes) > num_workers * 0.5, (
            f"Expected >50% success under mixed workload, got {len(successes)}/{num_workers}"
        )

        # Should have completed many operations despite chaos
        assert total_operations > num_workers * 2, (
            f"Expected >{num_workers * 2} operations under chaos, got {total_operations}"
        )

        print(f"\n✅ Mixed workload chaos test completed:")
        print(
            f"   Workers: {len(successes)}/{num_workers} succeeded ({len(successes) / num_workers * 100:.1f}%)",
        )
        print(f"   Total operations: {total_operations}")
        failures = [r for r in results if not r.get("success", False)]
        print(f"   Errors/conflicts: {len(failures)}")
        print(f"   Average operations per worker: {total_operations / num_workers:.1f}")
        if len(failures) > 0:
            print(
                f"   Note: {len(failures)} conflicts occurred as expected under mixed workload",
            )
        print(f"   Average errors per worker: {total_errors / num_workers:.1f}")
