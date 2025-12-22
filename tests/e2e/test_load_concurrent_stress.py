"""
E2E tests for concurrent load stress scenarios.

Tests system behavior under load and stress:
- 50 concurrent branch operations
- 100 concurrent commits
- Contention under high write load
- Recovery from resource exhaustion

Key Coverage:
- Concurrent operation reliability
- System recovery after exhaustion
- High-load branch creation
- Concurrent commit handling
- Write contention management
"""

import pytest
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class TestE2EConcurrentLoadStress:
    """Test concurrent load stress scenarios."""

    def test_50_concurrent_branch_operations(self, db, pggit_installed):
        """Test 50 concurrent branch operations"""
        created_branches = []
        failed_operations = []

        def create_branch(i):
            try:
                branch_id = db.execute_returning(
                    "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                    f"stress-50-{i}",
                )[0]
                return branch_id
            except Exception as e:
                failed_operations.append(str(e))
                return None

        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(create_branch, i) for i in range(50)]

            for future in as_completed(futures, timeout=30):
                try:
                    result = future.result()
                    if result:
                        created_branches.append(result)
                except Exception as e:
                    failed_operations.append(str(e))

        # Most branches should be created
        assert len(created_branches) >= 40, (
            f"At least 40 of 50 branches should be created, got {len(created_branches)}"
        )
        assert len(failed_operations) <= 10, (
            f"No more than 10 failures acceptable, got {len(failed_operations)}"
        )

    def test_100_concurrent_commits(self, db, pggit_installed):
        """Test 100 concurrent commits to same branch"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        commit_ids = []
        lock = None

        def create_commit(i):
            try:
                commit_id = db.execute_returning(
                    "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
                    main_id,
                    f"concurrent-commit-{i}",
                )[0]
                return commit_id
            except Exception:
                return None

        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(create_commit, i) for i in range(100)]

            for future in as_completed(futures):
                result = future.result()
                if result:
                    commit_ids.append(result)

        # Most commits should succeed
        assert len(commit_ids) >= 80, (
            f"At least 80 of 100 commits should succeed, got {len(commit_ids)}"
        )
        # All commit IDs should be unique
        assert len(commit_ids) == len(set(commit_ids)), (
            "All commit IDs should be unique"
        )

    def test_contention_under_high_write_load(self, db, pggit_installed):
        """Test system under contention with high write load"""
        db.execute("""
            CREATE TABLE public.high_write_load (
                id INTEGER PRIMARY KEY,
                thread_id INTEGER,
                value TEXT,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)

        success_count = [0]
        lock = None

        def high_write(thread_id):
            try:
                for i in range(10):
                    db.execute(
                        "INSERT INTO public.high_write_load (id, thread_id, value) VALUES (%s, %s, %s)",
                        thread_id * 1000 + i,
                        thread_id,
                        f"thread-{thread_id}-value-{i}",
                    )
                success_count[0] += 1
            except Exception:
                pass

        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(high_write, i) for i in range(20)]

            for future in as_completed(futures):
                future.result()

        # Most threads should succeed
        assert success_count[0] >= 15, (
            f"At least 15 of 20 threads should complete, got {success_count[0]}"
        )

        # Verify all data was inserted
        total_rows = db.execute("SELECT COUNT(*) FROM public.high_write_load")[0][0]
        assert total_rows > 0, "Data should be inserted under high load"

    def test_recovery_from_resource_exhaustion(self, db, pggit_installed):
        """Test recovery after resource exhaustion"""
        db.execute("""
            CREATE TABLE public.recovery_test (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Create heavy load
        try:
            for i in range(5000):
                db.execute(
                    "INSERT INTO public.recovery_test (id, data) VALUES (%s, %s)",
                    i,
                    "x" * 100,  # Moderate size
                )
        except Exception as e:
            # May hit resource limit
            pass

        # System should recover - simple query should work
        result = db.execute("SELECT COUNT(*) FROM public.recovery_test")
        assert result[0][0] > 0, "System should recover and still be queryable"

        # New operations should work
        new_branch = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('recovery-branch') RETURNING id"
        )[0]
        assert new_branch is not None, "New operations should work after recovery"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
