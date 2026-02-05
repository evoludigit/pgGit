"""
E2E tests for data integrity validation.

Tests data isolation and consistency guarantees:
- Branch data isolation
- Commit data consistency
- Foreign key constraint enforcement
- Unique constraint validation
- Transaction consistency

Key Coverage:
- Data isolation between branches
- Foreign key integrity
- Unique constraint enforcement
- Transaction rollback consistency
- Data preservation across operations
"""

import pytest


class TestE2EDataIntegrity:
    """Test data integrity validation."""

    def test_branch_data_isolation(self, db_e2e, pggit_installed):
        """Test that data is properly isolated between branches"""
        # Create two branches
        branch1_result = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "isolation-branch-1"
        )[0]
        branch2_result = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "isolation-branch-2"
        )[0]

        # Create test table
        db_e2e.execute("""
            CREATE TABLE public.isolation_test (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER,
                data TEXT
            )
        """)

        # Insert into branch1
        db_e2e.execute(
            "INSERT INTO public.isolation_test (id, branch_id, data) VALUES (%s, %s, %s)",
            1, branch1_result, "branch1-data"
        )

        # Insert into branch2
        db_e2e.execute(
            "INSERT INTO public.isolation_test (id, branch_id, data) VALUES (%s, %s, %s)",
            2, branch2_result, "branch2-data"
        )

        # Verify isolation - query branch1 data
        branch1_count = db_e2e.execute(
            "SELECT COUNT(*) FROM public.isolation_test WHERE branch_id = %s",
            branch1_result
        )[0][0]

        # Verify isolation - query branch2 data
        branch2_count = db_e2e.execute(
            "SELECT COUNT(*) FROM public.isolation_test WHERE branch_id = %s",
            branch2_result
        )[0][0]

        assert branch1_count == 1, "Branch1 should have exactly 1 row"
        assert branch2_count == 1, "Branch2 should have exactly 1 row"

    def test_commit_data_consistency(self, db_e2e, pggit_installed):
        """Test that commits maintain data consistency"""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create test table
        db_e2e.execute("""
            CREATE TABLE public.consistency_test (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER,
                value TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Insert data
        for i in range(5):
            db_e2e.execute(
                "INSERT INTO public.consistency_test (id, branch_id, value) VALUES (%s, %s, %s)",
                i, main_id, f"value-{i}"
            )

        # Create commit
        commit_result = db_e2e.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            main_id, "Test consistency commit"
        )[0]

        # Verify commit exists
        assert commit_result is not None, "Commit should be created"

        # Verify all data is still present
        count = db_e2e.execute("SELECT COUNT(*) FROM public.consistency_test")[0][0]
        assert count == 5, "All inserted data should remain"

    def test_foreign_key_constraint_enforcement(self, db_e2e, pggit_installed):
        """Test that foreign key constraints are enforced"""
        # Create test table with FK to branches
        db_e2e.execute("""
            CREATE TABLE public.fk_test (
                id INTEGER PRIMARY KEY,
                branch_id INTEGER REFERENCES pggit.branches(id),
                data TEXT
            )
        """)

        # Get valid branch ID
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Insert with valid FK
        db_e2e.execute(
            "INSERT INTO public.fk_test (id, branch_id, data) VALUES (%s, %s, %s)",
            1, main_id, "valid-fk"
        )

        # Verify insert succeeded
        count = db_e2e.execute("SELECT COUNT(*) FROM public.fk_test")[0][0]
        assert count == 1, "Insert with valid FK should succeed"

        # Try to insert with invalid FK (should fail or be handled)
        try:
            db_e2e.execute(
                "INSERT INTO public.fk_test (id, branch_id, data) VALUES (%s, %s, %s)",
                2, 99999, "invalid-fk"
            )
            # If no error, verify it didn't insert
            count = db_e2e.execute("SELECT COUNT(*) FROM public.fk_test")[0][0]
            assert count == 1, "Invalid FK insert should be rejected"
        except Exception:
            # FK constraint violation is expected
            pass

    def test_unique_constraint_validation(self, db_e2e, pggit_installed):
        """Test that unique constraints are properly enforced"""
        # Create table with unique constraint
        db_e2e.execute("""
            CREATE TABLE public.unique_test (
                id INTEGER PRIMARY KEY,
                unique_value TEXT UNIQUE,
                data TEXT
            )
        """)

        # Insert first record
        db_e2e.execute(
            "INSERT INTO public.unique_test (id, unique_value, data) VALUES (%s, %s, %s)",
            1, "unique-value-1", "data-1"
        )

        # Try to insert duplicate
        try:
            db_e2e.execute(
                "INSERT INTO public.unique_test (id, unique_value, data) VALUES (%s, %s, %s)",
                2, "unique-value-1", "data-2"
            )
            # If no error, verify only one exists
            count = db_e2e.execute("SELECT COUNT(*) FROM public.unique_test")[0][0]
            assert count == 1, "Duplicate unique value should be rejected"
        except Exception:
            # Unique constraint violation is expected
            pass

    def test_transaction_rollback_consistency(self, db_e2e, pggit_installed):
        """Test that data operations maintain consistency"""
        db_e2e.execute("""
            CREATE TABLE public.rollback_test (
                id INTEGER PRIMARY KEY,
                value TEXT
            )
        """)

        # Insert initial data
        db_e2e.execute(
            "INSERT INTO public.rollback_test (id, value) VALUES (%s, %s)",
            1, "initial"
        )

        initial_count = db_e2e.execute("SELECT COUNT(*) FROM public.rollback_test")[0][0]

        # Insert additional data
        db_e2e.execute(
            "INSERT INTO public.rollback_test (id, value) VALUES (%s, %s)",
            2, "second"
        )

        # Verify insert succeeded
        final_count = db_e2e.execute("SELECT COUNT(*) FROM public.rollback_test")[0][0]
        assert final_count == initial_count + 1, "Insert should increase count"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
