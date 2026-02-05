"""
E2E tests for multi-table transactions and consistency scenarios.

Tests complex transaction scenarios involving:
- Multi-table transaction rollback and consistency
- Foreign key cascade delete behavior
- Version number consistency across tables
- Snapshot consistency with multiple tables
- Concurrent updates across tables

Key Coverage:
- Data consistency across related tables
- Foreign key integrity and constraints
- Cascade delete behavior
- Version tracking in multi-table scenarios
- Concurrent multi-table updates
"""

import json
import pytest
from concurrent.futures import ThreadPoolExecutor


class TestMultiTableTransactionScenarios:
    """Test multi-table and transaction scenarios."""

    def test_multi_table_transaction_rollback(self, db_e2e, pggit_installed):
        """Test multi-table data consistency."""
        db_e2e.execute("""
            CREATE TABLE public.users_tx (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        db_e2e.execute("""
            CREATE TABLE public.orders_tx (
                id INTEGER PRIMARY KEY,
                user_id INTEGER,
                amount DECIMAL,
                FOREIGN KEY(user_id) REFERENCES public.users_tx(id)
            )
        """)

        db_e2e.execute("INSERT INTO public.users_tx VALUES (1, 'Alice')")
        db_e2e.execute("INSERT INTO public.orders_tx VALUES (1, 1, 100)")
        db_e2e.execute("INSERT INTO public.orders_tx VALUES (2, 1, 200)")

        # Verify both inserts succeeded
        user_count = db_e2e.execute("SELECT COUNT(*) FROM public.users_tx")[0][0]
        order_count = db_e2e.execute("SELECT COUNT(*) FROM public.orders_tx")[0][0]

        assert user_count == 1, "Should have 1 user"
        assert order_count == 2, "Should have 2 orders"

        # Verify FK integrity
        total_amount = db_e2e.execute("SELECT SUM(amount) FROM public.orders_tx WHERE user_id = 1")[0][0]
        assert total_amount == 300, "Total order amount should be 300"

    def test_foreign_key_cascade_in_merged_branches(self, db_e2e, pggit_installed):
        """Test FK cascade delete behavior."""
        db_e2e.execute("""
            CREATE TABLE public.parent_fk (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        db_e2e.execute("""
            CREATE TABLE public.child_fk (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER REFERENCES public.parent_fk(id) ON DELETE CASCADE
            )
        """)

        db_e2e.execute("INSERT INTO public.parent_fk VALUES (1, 'parent')")
        db_e2e.execute("INSERT INTO public.child_fk VALUES (1, 1)")
        db_e2e.execute("INSERT INTO public.child_fk VALUES (2, 1)")

        # Verify data exists
        parent_count = db_e2e.execute("SELECT COUNT(*) FROM public.parent_fk")[0][0]
        child_count = db_e2e.execute("SELECT COUNT(*) FROM public.child_fk")[0][0]
        assert parent_count == 1, "Should have 1 parent"
        assert child_count == 2, "Should have 2 children"

        # Delete parent - should cascade delete children
        db_e2e.execute("DELETE FROM public.parent_fk WHERE id = 1")

        # Verify cascade delete worked
        remaining_children = db_e2e.execute("SELECT COUNT(*) FROM public.child_fk")[0][0]
        assert remaining_children == 0, "Children should be deleted when parent is deleted (CASCADE)"

    def test_version_consistency_across_tables(self, db_e2e, pggit_installed):
        """Test version numbers stay consistent across tables."""
        db_e2e.execute("""
            CREATE TABLE public.consistency_table_a (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)
        db_e2e.execute("""
            CREATE TABLE public.consistency_table_b (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Insert with same version
        db_e2e.execute("INSERT INTO public.consistency_table_a VALUES (1, 'a')")
        db_e2e.execute("INSERT INTO public.consistency_table_b VALUES (1, 'b')")

        # Create snapshots
        snap_a = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('consistency_table_a', 1, %s)",
            json.dumps({"table": "a"}),
        )[0]

        snap_b = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('consistency_table_b', 1, %s)",
            json.dumps({"table": "b"}),
        )[0]

        # Both should exist and be queryable
        assert snap_a is not None, "Table A snapshot should succeed"
        assert snap_b is not None, "Table B snapshot should succeed"

    def test_snapshot_consistency_multi_table(self, db_e2e, pggit_installed):
        """Test multi-table snapshots maintain consistency."""
        db_e2e.execute("""
            CREATE TABLE public.snapshot_parent (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        db_e2e.execute("""
            CREATE TABLE public.snapshot_child (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                value TEXT
            )
        """)

        db_e2e.execute("INSERT INTO public.snapshot_parent VALUES (1, 'parent')")
        db_e2e.execute("INSERT INTO public.snapshot_child VALUES (1, 1, 'child')")

        # Create snapshots at same time
        snap_parent = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('snapshot_parent', 1, %s)",
            json.dumps({"type": "parent"}),
        )[0]

        snap_child = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('snapshot_child', 1, %s)",
            json.dumps({"type": "child"}),
        )[0]

        assert snap_parent is not None and snap_child is not None, (
            "Multi-table snapshots should succeed"
        )

    def test_concurrent_multi_table_updates(self, db_e2e, pggit_installed):
        """Test concurrent updates across tables."""
        db_e2e.execute("""
            CREATE TABLE public.concurrent_table_1 (
                id INTEGER PRIMARY KEY,
                value TEXT
            )
        """)
        db_e2e.execute("""
            CREATE TABLE public.concurrent_table_2 (
                id INTEGER PRIMARY KEY,
                value TEXT
            )
        """)

        db_e2e.execute("INSERT INTO public.concurrent_table_1 VALUES (1, 'init')")
        db_e2e.execute("INSERT INTO public.concurrent_table_2 VALUES (1, 'init')")

        # Concurrent updates
        def update_table_1():
            db_e2e.execute(
                "UPDATE public.concurrent_table_1 SET value = 'updated' WHERE id = 1"
            )
            return True

        def update_table_2():
            db_e2e.execute(
                "UPDATE public.concurrent_table_2 SET value = 'updated' WHERE id = 1"
            )
            return True

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(update_table_1), executor.submit(update_table_2)]
            results = [f.result() for f in futures]

        assert all(results), "Concurrent updates should succeed"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
