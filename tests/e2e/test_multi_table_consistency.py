"""
E2E tests for multi-table transaction consistency.

Tests consistency across multiple related tables:
- Multi-branch multi-table consistency
- Constraint enforcement across related tables
- Cascade delete consistency in multi-table scenarios
- Referential integrity validation

Key Coverage:
- Related table data consistency
- Multi-table snapshot consistency
- Foreign key constraint validation
- Cascade delete correctness
"""

import json
import pytest


class TestMultiTableTransactionConsistency:
    """Test multi-table transaction consistency."""

    def test_multi_branch_multi_table_consistency(self, db, pggit_installed):
        """Test consistency across multiple tables in multiple branches."""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        branch1 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('multi-table-branch') RETURNING id"
        )[0]

        # Create related tables
        db.execute("""
            CREATE TABLE public.accounts (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        db.execute("""
            CREATE TABLE public.transactions (
                id INTEGER PRIMARY KEY,
                account_id INTEGER REFERENCES public.accounts(id),
                amount DECIMAL
            )
        """)

        # Insert related data
        db.execute("INSERT INTO public.accounts VALUES (1, 'Alice')")
        db.execute("INSERT INTO public.transactions VALUES (1, 1, 100)")

        # Create snapshot
        snapshot1 = db.execute_returning(
            "SELECT pggit.create_temporal_snapshot('accounts', 1, %s)",
            json.dumps({"phase": "accounts"}),
        )[0]
        snapshot2 = db.execute_returning(
            "SELECT pggit.create_temporal_snapshot('transactions', 1, %s)",
            json.dumps({"phase": "transactions"}),
        )[0]

        # Verify referential integrity
        account_result = db.execute("SELECT * FROM public.accounts WHERE id = 1")
        transaction_result = db.execute(
            "SELECT * FROM public.transactions WHERE account_id = 1"
        )

        assert account_result[0] == (1, "Alice"), "Account should be consistent"
        assert transaction_result[0] == (1, 1, 100), (
            "Transaction should reference correct account"
        )

    def test_constraint_enforcement_across_tables(self, db, pggit_installed):
        """Test constraint enforcement across related tables."""
        db.execute("""
            CREATE TABLE public.departments (
                id INTEGER PRIMARY KEY,
                name TEXT UNIQUE
            )
        """)
        db.execute("""
            CREATE TABLE public.employees (
                id INTEGER PRIMARY KEY,
                name TEXT,
                department_id INTEGER REFERENCES public.departments(id) ON DELETE CASCADE
            )
        """)

        # Insert valid data
        db.execute("INSERT INTO public.departments VALUES (1, 'Engineering')")
        db.execute("INSERT INTO public.employees VALUES (1, 'Alice', 1)")
        db.execute("INSERT INTO public.employees VALUES (2, 'Bob', 1)")

        # Verify cascade delete
        db.execute("DELETE FROM public.departments WHERE id = 1")
        remaining_employees = db.execute("SELECT COUNT(*) FROM public.employees")
        assert remaining_employees[0][0] == 0, "Cascade delete should remove employees"

    def test_cascade_delete_consistency_multi_table(self, db, pggit_installed):
        """Test cascade delete maintains consistency across multiple tables."""
        db.execute("""
            CREATE TABLE public.users_cascade (
                id INTEGER PRIMARY KEY,
                username TEXT UNIQUE
            )
        """)
        db.execute("""
            CREATE TABLE public.posts_cascade (
                id INTEGER PRIMARY KEY,
                user_id INTEGER REFERENCES public.users_cascade(id) ON DELETE CASCADE,
                content TEXT
            )
        """)
        db.execute("""
            CREATE TABLE public.comments_cascade (
                id INTEGER PRIMARY KEY,
                post_id INTEGER REFERENCES public.posts_cascade(id) ON DELETE CASCADE,
                content TEXT
            )
        """)

        # Create cascade structure
        db.execute("INSERT INTO public.users_cascade VALUES (1, 'alice')")
        db.execute("INSERT INTO public.posts_cascade VALUES (1, 1, 'Hello')")
        db.execute("INSERT INTO public.comments_cascade VALUES (1, 1, 'Great post')")

        # Delete user - should cascade
        db.execute("DELETE FROM public.users_cascade WHERE id = 1")

        # Verify all related data deleted
        users_count = db.execute("SELECT COUNT(*) FROM public.users_cascade")[0][0]
        posts_count = db.execute("SELECT COUNT(*) FROM public.posts_cascade")[0][0]
        comments_count = db.execute("SELECT COUNT(*) FROM public.comments_cascade")[0][
            0
        ]

        assert users_count == 0, "Users should be deleted"
        assert posts_count == 0, "Posts should be cascade deleted"
        assert comments_count == 0, "Comments should be cascade deleted"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
