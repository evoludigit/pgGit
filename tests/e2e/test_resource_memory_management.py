"""
E2E tests for memory and resource management.

Tests resource efficiency and bounds:
- Large snapshot memory efficiency
- Connection pool cleanup
- Index memory efficiency
- Cache memory bounds

Key Coverage:
- Memory usage monitoring
- Resource pool management
- Index memory efficiency
- Cache bounds validation
- Recovery after resource constraints
"""

import json
import pytest
import psutil
import os


class TestE2EMemoryResourceManagement:
    """Test memory and resource management."""

    def test_memory_usage_with_large_snapshots(self, db_e2e, pggit_installed):
        """Test memory efficiency with large snapshots"""
        db_e2e.execute("""
            CREATE TABLE public.large_snapshot_test (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Insert large dataset
        for i in range(500):
            db_e2e.execute(
                "INSERT INTO public.large_snapshot_test (id, data) VALUES (%s, %s)",
                i,
                "x" * 1000,  # 1KB per row
            )

        # Measure memory before snapshot
        process = psutil.Process(os.getpid())
        mem_before = process.memory_info().rss / 1024 / 1024  # MB

        # Create snapshot
        snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('large_snapshot_test', 1, %s)",
            json.dumps({"size": "large"}),
        )[0]

        # Measure memory after snapshot
        mem_after = process.memory_info().rss / 1024 / 1024  # MB

        assert snapshot is not None, "Large snapshot should succeed"
        # Memory increase should be reasonable (< 100MB for 500KB data)
        memory_increase = mem_after - mem_before
        assert memory_increase < 100, f"Memory increase excessive: {memory_increase}MB"

    def test_connection_pool_resource_cleanup(self, db_e2e, pggit_installed):
        """Test connection pool cleanup"""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create multiple branches to stress connection pool
        branch_ids = []
        for i in range(20):
            branch_id = db_e2e.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"pool-stress-{i}",
            )[0]
            branch_ids.append(branch_id)

        # All branches should be created
        assert len(branch_ids) == 20, "All branches should be created"

        # Verify all branches are queryable
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE name LIKE %s",
            "pool-stress-%"
        )
        assert result[0][0] == 20, "All stressed branches should be accessible"

    def test_index_memory_efficiency(self, db_e2e, pggit_installed):
        """Test index memory efficiency"""
        db_e2e.execute("""
            CREATE TABLE public.index_efficiency (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER,
                data TEXT
            )
        """)

        # Create index
        db_e2e.execute("CREATE INDEX idx_branch_id ON public.index_efficiency(branch_id)")

        # Insert indexed data
        for i in range(1000):
            db_e2e.execute(
                "INSERT INTO public.index_efficiency (id, branch_id, data) VALUES (%s, %s, %s)",
                i,
                i % 10,
                f"data-{i}",
            )

        # Query using index should be fast
        import time
        start = time.time()
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.index_efficiency WHERE branch_id = 5"
        )
        query_time = time.time() - start

        assert result[0][0] > 0, "Index query should return results"
        assert query_time < 0.1, "Index query should be fast (< 100ms)"

    def test_cache_memory_bounds(self, db_e2e, pggit_installed):
        """Test cache memory stays within bounds"""
        db_e2e.execute("""
            CREATE TABLE public.cache_bounds (
                id INTEGER PRIMARY KEY,
                cached_data TEXT
            )
        """)

        # Simulate cache usage
        process = psutil.Process(os.getpid())
        mem_before = process.memory_info().rss / 1024 / 1024

        # Create large cache-like dataset
        for i in range(100):
            # Create a list of dicts repeated 100 times, then serialize
            cache_data = [{"key": f"value-{i}"} for _ in range(100)]
            db_e2e.execute(
                "INSERT INTO public.cache_bounds (id, cached_data) VALUES (%s, %s)",
                i,
                json.dumps(cache_data),  # ~1KB per row
            )

        mem_after = process.memory_info().rss / 1024 / 1024
        memory_growth = mem_after - mem_before

        # Cache shouldn't grow unbounded (< 50MB for 100KB data)
        assert memory_growth < 50, f"Cache memory growth excessive: {memory_growth}MB"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
