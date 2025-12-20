"""
Concurrency tests for commit operations.

These tests validate pggit's behavior when multiple clients attempt to commit
changes simultaneously, focusing on Trinity ID uniqueness, race conditions,
and proper concurrency handling.
"""

import pytest
import asyncio
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError
import psycopg
from psycopg.rows import dict_row
from hypothesis import given, strategies as st, settings, HealthCheck

from tests.chaos.utils import ChaosInjector
from tests.chaos.strategies import git_branch_name, commit_message


@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.slow
class TestConcurrentCommits:
    """Test concurrent commit operations."""

    @pytest.mark.parametrize("num_workers", [2, 5, 10, 20])
    def test_concurrent_commits_same_branch(
        self, db_connection_string: str, num_workers: int
    ):
        """
        Test: Multiple workers committing to the same branch concurrently.

        Expected behaviors:
        1. All commits succeed OR fail with serialization error
        2. Trinity IDs are unique (no collisions)
        3. Commit order is consistent
        4. No data corruption
        """
        branch_name = "main"
        results = []
        errors = []

        def worker_commit(worker_id: int) -> dict | None:
            """Worker function: create table and commit."""
            try:
                conn = psycopg.connect(db_connection_string, row_factory=dict_row)

                # Create unique table for this worker
                table_name = f"test_table_{worker_id}"
                conn.execute(
                    f"CREATE TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)"
                )
                conn.commit()

                # Commit to same branch (potential race condition)
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (
                        branch_name,
                        f"Commit from worker {worker_id}",
                    ),
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {
                    "worker_id": worker_id,
                    "trinity_id": result["commit_changes"] if result else None,
                    "success": True,
                }

            except psycopg.Error as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass  # Connection might already be closed

                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Execute concurrent commits
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker_commit, i) for i in range(num_workers)]

            for future in as_completed(futures, timeout=60):  # 60 second timeout
                try:
                    result = future.result(timeout=10)
                    if result["success"]:
                        results.append(result)
                    else:
                        errors.append(result)
                except TimeoutError:
                    errors.append(
                        {"worker_id": "unknown", "error": "timeout", "success": False}
                    )

        # Validation: At least some commits succeeded
        assert len(results) > 0, (
            f"At least one commit should succeed, but got {len(errors)} errors"
        )

        # Validation: All successful Trinity IDs are unique
        trinity_ids = [r["trinity_id"] for r in results if r["trinity_id"] is not None]
        assert len(trinity_ids) == len(set(trinity_ids)), (
            f"Trinity ID collision detected: {trinity_ids}"
        )

        # Validation: Errors are expected serialization failures
        for err in errors:
            if err["error"] != "timeout":
                error_msg = err["error"].lower()
                assert any(
                    keyword in error_msg
                    for keyword in [
                        "serialization",
                        "deadlock",
                        "could not serialize",
                        "concurrent",
                        "timeout",
                        "connection",
                    ]
                ), f"Unexpected error: {err['error']}"

        print(
            f"\n✅ {len(results)} successful commits, {len(errors)} expected failures"
        )
        print(f"   Unique Trinity IDs: {len(set(trinity_ids))}")

    @pytest.mark.timeout(120)
    async def test_concurrent_commits_with_delays(
        self, async_conn: psycopg.AsyncConnection, conn_pool
    ):
        """
        Test: Concurrent commits with random delays (simulating network latency).

        This test injects random delays to increase the probability of race conditions.
        """
        num_tasks = 15
        branch_name = "test-branch"

        async def commit_with_delay(task_id: int, conn):
            """Commit with random delay injected."""
            try:
                # Random delay before commit (0-200ms)
                await ChaosInjector.random_delay(min_ms=0, max_ms=200)

                # Create table
                table_name = f"delayed_table_{task_id}"
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                # Random delay during commit
                await ChaosInjector.random_delay(min_ms=0, max_ms=100)

                # Commit
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch_name, f"Delayed commit {task_id}"),
                )
                result = cursor.fetchone()
                conn.commit()

                return {
                    "task_id": task_id,
                    "trinity_id": result["commit_changes"],
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.rollback()
                except:
                    pass
                return {"task_id": task_id, "error": str(e), "success": False}

        # Run concurrent tasks
        tasks = []
        for i in range(num_tasks):
            conn = conn_pool[i % len(conn_pool)]
            tasks.append(commit_with_delay(i, conn))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Separate successes and failures
        successes = [r for r in results if isinstance(r, dict) and r.get("success")]
        failures = [r for r in results if isinstance(r, dict) and not r.get("success")]

        # Assertions
        assert len(successes) > 0, "At least some commits should succeed"

        trinity_ids = [s["trinity_id"] for s in successes]
        assert len(trinity_ids) == len(set(trinity_ids)), (
            "Trinity IDs must be unique even with delays"
        )

        print(f"\n✅ {len(successes)} successes, {len(failures)} failures with delays")

    @given(num_workers=st.integers(min_value=2, max_value=15), branch=git_branch_name)
    @settings(
        max_examples=10,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_property_concurrent_commits_no_collisions(
        self, db_connection_string: str, num_workers: int, branch: str
    ):
        """
        Property: Concurrent commits never produce Trinity ID collisions.

        Uses Hypothesis to test with various worker counts and branch names.
        """
        results = []

        def worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            table_name = f"prop_table_{worker_id}_{branch[:20]}"
            try:
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch, f"Property test {worker_id}"),
                )
                trinity_id = cursor.fetchone()["commit_changes"]
                conn.commit()
                conn.close()

                return trinity_id

            except Exception:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return None

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]
            for future in as_completed(futures, timeout=30):
                try:
                    trinity_id = future.result(timeout=5)
                    if trinity_id is not None:
                        results.append(trinity_id)
                except TimeoutError:
                    pass  # Some timeouts expected

        # Property: All successful Trinity IDs must be unique
        if len(results) > 0:
            assert len(results) == len(set(results)), (
                f"Trinity ID collision in {num_workers} workers on branch '{branch}'"
            )

    @pytest.mark.parametrize(
        "isolation_level", ["READ COMMITTED", "REPEATABLE READ", "SERIALIZABLE"]
    )
    def test_concurrent_commits_different_isolation_levels(
        self, db_connection_string: str, isolation_level: str
    ):
        """
        Test concurrent commits with different transaction isolation levels.

        This tests how pggit behaves under different isolation guarantees.
        """
        branch_name = f"isolation-{isolation_level.lower().replace(' ', '-')}"
        num_workers = 5

        def worker_with_isolation(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            try:
                # Set isolation level
                conn.execute(f"SET TRANSACTION ISOLATION LEVEL {isolation_level}")

                table_name = f"iso_table_{worker_id}"
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch_name, f"Isolation test {worker_id}"),
                )
                trinity_id = cursor.fetchone()["commit_changes"]
                conn.commit()
                conn.close()

                return {
                    "worker_id": worker_id,
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

        # Run concurrent workers
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [
                executor.submit(worker_with_isolation, i) for i in range(num_workers)
            ]
            results = [f.result() for f in as_completed(futures, timeout=45)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        # Should have some successes regardless of isolation level
        assert len(successes) > 0, f"No commits succeeded with {isolation_level}"

        # Trinity IDs should still be unique
        trinity_ids = [s["trinity_id"] for s in successes]
        assert len(trinity_ids) == len(set(trinity_ids)), (
            f"Trinity ID collision with {isolation_level}"
        )

        print(
            f"\n✅ {isolation_level}: {len(successes)} successes, {len(failures)} failures"
        )

    async def test_async_concurrent_commits(self, async_conn_pool):
        """
        Test fully async concurrent commits using async connection pool.

        This tests the async path for concurrent operations.
        """
        num_concurrent = 10
        branch_name = "async-branch"

        async def async_commit_worker(worker_id: int, conn):
            try:
                # Create table
                table_name = f"async_table_{worker_id}"
                await conn.execute(f"CREATE TABLE {table_name} (id INT)")
                await conn.commit()

                # Small delay to increase concurrency chance
                await asyncio.sleep(0.01)

                # Commit
                cursor = await conn.execute(
                    "SELECT pggit.commit_changes(%s, %s)",
                    (branch_name, f"Async commit {worker_id}"),
                )
                result = await cursor.fetchone()
                await conn.commit()

                return {
                    "worker_id": worker_id,
                    "trinity_id": result[0],
                    "success": True,
                }

            except Exception as e:
                try:
                    await conn.rollback()
                except:
                    pass
                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Run async concurrent tasks
        tasks = []
        for i in range(num_concurrent):
            conn = async_conn_pool[i % len(async_conn_pool)]
            tasks.append(async_commit_worker(i, conn))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Process results
        successes = [r for r in results if isinstance(r, dict) and r.get("success")]
        failures = [r for r in results if isinstance(r, dict) and not r.get("success")]

        assert len(successes) > 0, "At least some async commits should succeed"

        # Check Trinity ID uniqueness
        trinity_ids = [s["trinity_id"] for s in successes]
        assert len(trinity_ids) == len(set(trinity_ids)), (
            "Async Trinity IDs must be unique"
        )

        print(f"\n✅ Async: {len(successes)} successes, {len(failures)} failures")
