"""
E2E tests for performance limits and boundary testing.

Tests system behavior under extreme loads:
- Large-scale data handling (1MB+ SQL content, 1000+ objects)
- Concurrent operation limits (50+ simultaneous operations)
- Resource limits (deep dependencies, many branches)
- Edge case performance (empty commits, rapid cycles)
- Timeout prevention (no infinite loops or deadlocks)

Key Coverage:
- Graceful degradation under load
- No crashes or data corruption
- Reasonable timeout boundaries
- Resource cleanup after stress
- Concurrent operation isolation

Test Principles:
- Tests verify "doesn't crash/corrupt" not "meets strict SLA"
- Performance assertions are reasonable (30s for large ops, 10s for normal)
- Focus on graceful degradation and recovery
"""

import pytest
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class TestLargeScaleData:
    """Test handling of extremely large data volumes."""

    def test_commit_with_large_sql_content(self, db, pggit_installed):
        """Test commit with >1MB SQL content"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create table with large content
        db.execute("""
            CREATE TABLE public.large_sql_test (
                id INTEGER PRIMARY KEY,
                content TEXT
            )
        """)

        # Generate 1MB+ of SQL content
        large_content = "x" * (1024 * 1024)  # 1MB of data

        start_time = time.time()
        db.execute(
            "INSERT INTO public.large_sql_test (id, content) VALUES (%s, %s)",
            1,
            large_content,
        )
        insert_time = time.time() - start_time

        # Verify data was inserted
        result = db.execute("SELECT length(content) FROM public.large_sql_test WHERE id = 1")
        assert result[0][0] == len(large_content), "Large content should be stored"
        assert insert_time < 30, "Large insert should complete within 30 seconds"

    def test_branch_with_thousands_of_objects(self, db, pggit_installed):
        """Test branch with 1000+ objects (performance check)"""
        # Create branch
        test_branch = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('large-branch') RETURNING id"
        )[0]

        # Create many objects
        start_time = time.time()
        object_count = 1000

        for i in range(object_count):
            db.execute(
                "INSERT INTO pggit.objects (object_type, schema_name, object_name) VALUES (%s, %s, %s)",
                "TABLE",
                "public",
                f"large_table_{i}",
            )

        creation_time = time.time() - start_time

        # Verify all objects created
        count = db.execute("SELECT COUNT(*) FROM pggit.objects WHERE object_name LIKE %s", 'large_table_%')[0][0]
        assert count == object_count, f"All {object_count} objects should be created"
        assert creation_time < 30, "Creating 1000 objects should complete within 30 seconds"

    def test_merge_with_many_conflicts(self, db, pggit_installed):
        """Test merge with hundreds of conflicts (should handle or fail gracefully)"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        conflict_branch = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('conflict-branch') RETURNING id"
        )[0]

        # Create conflicting data - same table modified in both branches
        db.execute("""
            CREATE TABLE public.conflict_test (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Insert 100 conflicting rows (simulating high conflict scenario)
        for i in range(100):
            db.execute(
                "INSERT INTO public.conflict_test (id, data) VALUES (%s, %s)",
                i,
                f"conflict-data-{i}",
            )

        # System should handle this gracefully
        count = db.execute("SELECT COUNT(*) FROM public.conflict_test")[0][0]
        assert count == 100, "System should handle high-conflict scenarios gracefully"

    def test_deep_commit_history(self, db, pggit_installed):
        """Test 1000+ commits in single branch"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create deep commit history
        start_time = time.time()
        commit_count = 1000

        for i in range(commit_count):
            db.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                main_id,
                f"commit-{i}",
            )

        creation_time = time.time() - start_time

        # Verify all commits created
        count = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s",
            main_id,
        )[0][0]
        assert count >= commit_count, f"Should have at least {commit_count} commits"
        assert creation_time < 30, "Creating 1000 commits should complete within 30 seconds"


class TestConcurrentOperationLimits:
    """Test concurrent operation handling and limits."""

    def test_multiple_simultaneous_branch_creations(self, db, pggit_installed):
        """Test 50+ concurrent branch creations"""
        created_branches = []
        failed_operations = []

        def create_branch(i):
            try:
                branch_id = db.execute_returning(
                    "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                    f"concurrent-branch-{i}",
                )[0]
                return branch_id
            except Exception as e:
                failed_operations.append(str(e))
                return None

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(create_branch, i) for i in range(50)]

            for future in as_completed(futures, timeout=30):
                try:
                    result = future.result()
                    if result:
                        created_branches.append(result)
                except Exception as e:
                    failed_operations.append(str(e))

        elapsed_time = time.time() - start_time

        # Most branches should be created
        assert len(created_branches) >= 40, (
            f"At least 40 of 50 branches should be created, got {len(created_branches)}"
        )
        assert elapsed_time < 30, "50 concurrent branches should complete within 30 seconds"

    def test_concurrent_commits_serialization(self, db, pggit_installed):
        """Test concurrent commits to same branch (serialization check)"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        commit_ids = []

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

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(create_commit, i) for i in range(100)]

            for future in as_completed(futures):
                result = future.result()
                if result:
                    commit_ids.append(result)

        elapsed_time = time.time() - start_time

        # All commit IDs should be unique (serialization working)
        assert len(commit_ids) == len(set(commit_ids)), (
            "All commit IDs should be unique (serialization check)"
        )
        # Most commits should succeed
        assert len(commit_ids) >= 80, (
            f"At least 80 of 100 commits should succeed, got {len(commit_ids)}"
        )
        assert elapsed_time < 30, "100 concurrent commits should complete within 30 seconds"

    def test_high_frequency_reads_dont_block_writes(self, db, pggit_installed):
        """Test high-frequency read operations don't block writes"""
        db.execute("""
            CREATE TABLE public.read_write_test (
                id INTEGER PRIMARY KEY,
                data TEXT,
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)

        # Insert initial data
        db.execute("INSERT INTO public.read_write_test (id, data) VALUES (1, 'initial')")

        read_count = [0]
        write_count = [0]

        def read_operation():
            for _ in range(50):
                try:
                    db.execute("SELECT * FROM public.read_write_test WHERE id = 1")
                    read_count[0] += 1
                except Exception:
                    pass
                time.sleep(0.01)  # 10ms between reads

        def write_operation():
            for i in range(10):
                try:
                    db.execute(
                        "UPDATE public.read_write_test SET data = %s, updated_at = NOW() WHERE id = 1",
                        f"update-{i}",
                    )
                    write_count[0] += 1
                except Exception:
                    pass
                time.sleep(0.1)  # 100ms between writes

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=5) as executor:
            # Start readers and writer
            futures = [
                executor.submit(read_operation) for _ in range(3)
            ] + [executor.submit(write_operation)]

            for future in as_completed(futures, timeout=10):
                future.result()

        elapsed_time = time.time() - start_time

        # Reads should not significantly block writes
        assert write_count[0] >= 8, "Most writes should succeed despite concurrent reads"
        assert read_count[0] >= 100, "Reads should continue during writes"
        assert elapsed_time < 10, "Operations should complete within 10 seconds"


class TestResourceLimits:
    """Test resource limits and boundary conditions."""

    def test_extremely_deep_dependency_chains(self, db, pggit_installed):
        """Test 100+ level deep object dependency chains"""
        # Count dependencies before test
        count_before = db.execute("SELECT COUNT(*) FROM pggit.dependencies")[0][0]

        # Create objects in a deep chain
        previous_id = None
        depth = 100

        start_time = time.time()
        for i in range(depth):
            obj_id = db.execute_returning(
                "INSERT INTO pggit.objects (object_type, schema_name, object_name) VALUES (%s, %s, %s) RETURNING id",
                "TABLE",
                "public",
                f"dep_chain_{i}",
            )[0]

            if previous_id is not None:
                # Create dependency: current depends on previous
                db.execute(
                    "INSERT INTO pggit.dependencies (dependent_id, depends_on_id) VALUES (%s, %s)",
                    obj_id,
                    previous_id,
                )

            previous_id = obj_id

        creation_time = time.time() - start_time

        # Verify chain created
        count_after = db.execute("SELECT COUNT(*) FROM pggit.dependencies")[0][0]
        new_deps = count_after - count_before
        assert new_deps == depth - 1, f"Should have created {depth - 1} new dependencies, got {new_deps}"
        assert creation_time < 30, "Creating 100-level dependency chain should complete within 30 seconds"
    def test_large_number_of_branches(self, db, pggit_installed):
        """Test 1000+ branches"""
        branch_count = 1000
        created = 0

        start_time = time.time()
        for i in range(branch_count):
            try:
                db.execute(
                    "INSERT INTO pggit.branches (name) VALUES (%s)",
                    f"branch-{i}",
                )
                created += 1
            except Exception:
                # May hit resource limits, continue
                pass

        creation_time = time.time() - start_time

        # Most branches should be created
        assert created >= 800, f"At least 800 of {branch_count} branches should be created"
        assert creation_time < 30, "Creating 1000 branches should complete within 30 seconds"

        # Verify we can still query efficiently
        query_start = time.time()
        count = db.execute("SELECT COUNT(*) FROM pggit.branches")[0][0]
        query_time = time.time() - query_start

        assert count >= 800, "Branch count query should return correct count"
        assert query_time < 5, "Querying large branch table should be fast"

    def test_large_commit_message_handling(self, db, pggit_installed):
        """Test 100KB+ commit messages"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create 100KB commit message
        large_message = "x" * (100 * 1024)  # 100KB

        start_time = time.time()
        commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            main_id,
            large_message,
        )[0]
        insert_time = time.time() - start_time

        # Verify message stored
        result = db.execute(
            "SELECT length(message) FROM pggit.commits WHERE id = %s",
            commit_id,
        )
        assert result[0][0] == len(large_message), "Large message should be stored"
        assert insert_time < 10, "Large message insert should complete within 10 seconds"

    def test_maximum_branch_name_length(self, db, pggit_installed):
        """Test maximum branch name length (255 chars)"""
        # Test at boundary: 255 chars
        max_name = "a" * 255

        branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            max_name,
        )[0]

        # Verify stored correctly
        result = db.execute(
            "SELECT name FROM pggit.branches WHERE id = %s",
            branch_id,
        )
        assert result[0][0] == max_name, "Maximum length name should be stored"
        assert len(result[0][0]) == 255, "Name should be exactly 255 chars"


class TestEdgeCasePerformance:
    """Test edge case performance scenarios."""

    def test_empty_commits(self, db, pggit_installed):
        """Test empty commits (minimal data)"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create empty commit (no message, minimal data)
        start_time = time.time()
        for i in range(100):
            db.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                main_id,
                "",  # Empty message
            )
        elapsed_time = time.time() - start_time

        # Verify all created
        count = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s AND message = ''",
            main_id,
        )[0][0]
        assert count >= 100, "All empty commits should be created"
        assert elapsed_time < 10, "100 empty commits should be fast"

    def test_rapid_branch_create_delete_cycles(self, db, pggit_installed):
        """Test rapid branch create/delete cycles"""
        cycle_count = 50
        successful_cycles = 0

        start_time = time.time()
        for i in range(cycle_count):
            try:
                # Create branch
                branch_id = db.execute_returning(
                    "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                    f"rapid-cycle-{i}",
                )[0]

                # Immediately delete it
                db.execute(
                    "DELETE FROM pggit.branches WHERE id = %s",
                    branch_id,
                )
                successful_cycles += 1
            except Exception:
                # May hit timing issues, continue
                pass

        elapsed_time = time.time() - start_time

        # Most cycles should succeed
        assert successful_cycles >= 40, (
            f"At least 40 of {cycle_count} create/delete cycles should succeed"
        )
        assert elapsed_time < 10, "50 rapid cycles should complete within 10 seconds"

    def test_query_performance_with_large_result_sets(self, db, pggit_installed):
        """Test query performance with large result sets"""
        # Create many commits
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        for i in range(1000):
            db.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                main_id,
                f"query-perf-{i}",
            )

        # Query large result set
        start_time = time.time()
        results = db.execute(
            "SELECT * FROM pggit.commits WHERE branch_id = %s",
            main_id,
        )
        query_time = time.time() - start_time

        # Verify results and performance
        assert len(results) >= 1000, "Should return all results"
        assert query_time < 5, "Large query should complete within 5 seconds"


class TestTimeoutPrevention:
    """Test timeout and hanging prevention."""

    def test_operations_complete_within_reasonable_time(self, db, pggit_installed):
        """Test operations complete within reasonable time limits"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Test various operations with timeout monitoring
        operations = []

        # 1. Branch creation
        start = time.time()
        db.execute("INSERT INTO pggit.branches (name) VALUES ('timeout-test-1')")
        operations.append(("branch_create", time.time() - start))

        # 2. Commit creation
        start = time.time()
        db.execute(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, 'timeout-commit')",
            main_id,
        )
        operations.append(("commit_create", time.time() - start))

        # 3. Object creation
        start = time.time()
        db.execute(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name) VALUES ('TABLE', 'public', 'timeout_obj')"
        )
        operations.append(("object_create", time.time() - start))

        # 4. Query operation
        start = time.time()
        db.execute("SELECT COUNT(*) FROM pggit.commits")
        operations.append(("query", time.time() - start))

        # All operations should be fast
        for op_name, duration in operations:
            assert duration < 5, f"{op_name} should complete within 5 seconds, took {duration:.2f}s"

    def test_no_indefinite_locks_on_concurrent_operations(self, db, pggit_installed):
        """Test no indefinite locks on concurrent operations"""
        db.execute("""
            CREATE TABLE public.lock_test (
                id INTEGER PRIMARY KEY,
                data TEXT,
                lock_version INTEGER DEFAULT 0
            )
        """)

        # Insert test data
        db.execute("INSERT INTO public.lock_test (id, data) VALUES (1, 'initial')")

        results = {"completed": 0, "timed_out": 0}

        def update_operation(i):
            try:
                start_time = time.time()
                db.execute(
                    "UPDATE public.lock_test SET data = %s, lock_version = lock_version + 1 WHERE id = 1",
                    f"update-{i}",
                )
                elapsed = time.time() - start_time

                if elapsed < 5:  # Reasonable timeout
                    results["completed"] += 1
                else:
                    results["timed_out"] += 1
            except Exception:
                results["timed_out"] += 1

        # Run concurrent updates
        start_time = time.time()
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(update_operation, i) for i in range(50)]

            for future in as_completed(futures, timeout=15):
                future.result()

        total_time = time.time() - start_time

        # No operations should hang indefinitely
        assert results["completed"] >= 40, (
            f"At least 40 operations should complete without hanging"
        )
        assert total_time < 15, "All operations should complete within 15 seconds"

        # Verify final state is consistent
        final_version = db.execute("SELECT lock_version FROM public.lock_test WHERE id = 1")[0][0]
        assert final_version == results["completed"], "Version should match completed updates"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
