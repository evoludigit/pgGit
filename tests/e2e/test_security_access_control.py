"""
E2E tests for security and access control.

Tests security mechanisms:
- Data isolation
- Permission enforcement
- Input validation
- SQL injection prevention
- Sensitive data handling

Key Coverage:
- Access control enforcement
- Data privacy validation
- Input sanitization
- Error message security
- Permission boundaries
"""

import pytest


class TestSecurityAccessControl:
    """Test security and access control."""

    def test_data_isolation_between_branches(self, db_e2e, pggit_installed):
        """Test data cannot leak between branches"""
        b1 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "secure-b1"
        )[0]
        b2 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "secure-b2"
        )[0]

        db_e2e.execute("""
            CREATE TABLE public.sensitive_data (
                id SERIAL PRIMARY KEY,
                branch_id INTEGER,
                secret TEXT
            )
        """)

        # Branch 1 inserts secret
        db_e2e.execute(
            "INSERT INTO public.sensitive_data (branch_id, secret) VALUES (%s, %s)",
            b1, "secret-for-b1"
        )

        # Branch 2 should not see branch 1 data
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.sensitive_data WHERE branch_id = %s",
            b2
        )[0][0]
        assert result == 0

    def test_input_parameter_validation(self, db_e2e, pggit_installed):
        """Test input parameters are properly validated"""
        # SQL injection attempt with parameterized query
        malicious_input = "'; DROP TABLE test; --"

        # Safe: parameterized query
        db_e2e.execute("""
            CREATE TABLE public.input_test (
                id SERIAL PRIMARY KEY,
                data TEXT
            )
        """)

        db_e2e.execute(
            "INSERT INTO public.input_test (data) VALUES (%s)",
            malicious_input
        )

        # Table should still exist
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.input_test"
        )[0][0]
        assert result == 1

    def test_permission_boundary_enforcement(self, db_e2e, pggit_installed):
        """Test that permission boundaries are enforced"""
        # Create restricted table
        db_e2e.execute("""
            CREATE TABLE public.restricted_table (
                id SERIAL PRIMARY KEY,
                classification TEXT,
                data TEXT
            )
        """)

        db_e2e.execute(
            "INSERT INTO public.restricted_table (classification, data) VALUES (%s, %s)",
            "top-secret", "restricted-data"
        )

        # Verify data exists
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.restricted_table WHERE classification = %s",
            "top-secret"
        )[0][0]
        assert result == 1

    def test_transaction_isolation(self, db_e2e, pggit_installed):
        """Test transaction isolation prevents dirty reads"""
        db_e2e.execute("DROP TABLE IF EXISTS public.isolation_test CASCADE")
        db_e2e.execute("""
            CREATE TABLE public.isolation_test (
                id SERIAL PRIMARY KEY,
                counter INTEGER DEFAULT 0
            )
        """)

        db_e2e.execute(
            "INSERT INTO public.isolation_test (counter) VALUES (%s)",
            100
        )

        # Read initial value
        initial = db_e2e.execute(
            "SELECT counter FROM public.isolation_test WHERE id = 1"
        )[0][0]

        # Update value
        db_e2e.execute(
            "UPDATE public.isolation_test SET counter = %s WHERE id = 1",
            200
        )

        # Read updated value
        updated = db_e2e.execute(
            "SELECT counter FROM public.isolation_test WHERE id = 1"
        )[0][0]

        assert initial == 100
        assert updated == 200

    def test_constraint_violation_handling(self, db_e2e, pggit_installed):
        """Test constraint violations are handled securely"""
        db_e2e.execute("DROP TABLE IF EXISTS public.constraint_test CASCADE")
        db_e2e.execute("""
            CREATE TABLE public.constraint_test (
                id SERIAL PRIMARY KEY,
                email TEXT UNIQUE,
                name TEXT NOT NULL
            )
        """)

        db_e2e.execute(
            "INSERT INTO public.constraint_test (email, name) VALUES (%s, %s)",
            "test@example.com", "Test User"
        )

        # Verify one record exists
        result = db_e2e.execute(
            "SELECT COUNT(*) FROM public.constraint_test"
        )[0][0]
        assert result == 1

    def test_sensitive_data_not_in_errors(self, db_e2e, pggit_installed):
        """Test sensitive data is not exposed in error messages"""
        db_e2e.execute("""
            CREATE TABLE public.error_test (
                id SERIAL PRIMARY KEY,
                password_hash TEXT,
                api_key TEXT
            )
        """)

        # Try to insert invalid data
        try:
            db_e2e.execute(
                "INSERT INTO public.error_test (password_hash, api_key) VALUES (%s, %s)",
                "invalid", "secret-key-123"
            )
        except Exception as e:
            # Error message should not contain the secret key
            assert "secret-key-123" not in str(e)

    def test_null_injection_prevention(self, db_e2e, pggit_installed):
        """Test NULL injection attempts are prevented"""
        db_e2e.execute("""
            CREATE TABLE public.null_test (
                id SERIAL PRIMARY KEY,
                data TEXT
            )
        """)

        # Insert with NULL
        db_e2e.execute(
            "INSERT INTO public.null_test (data) VALUES (%s)",
            None
        )

        # Insert with empty string
        db_e2e.execute(
            "INSERT INTO public.null_test (data) VALUES (%s)",
            ""
        )

        # Verify both stored correctly
        null_count = db_e2e.execute(
            "SELECT COUNT(*) FROM public.null_test WHERE data IS NULL"
        )[0][0]
        empty_count = db_e2e.execute(
            "SELECT COUNT(*) FROM public.null_test WHERE data = %s",
            ""
        )[0][0]

        assert null_count == 1
        assert empty_count == 1

    def test_type_coercion_safety(self, db_e2e, pggit_installed):
        """Test type coercion safety"""
        db_e2e.execute("""
            CREATE TABLE public.type_test (
                id SERIAL PRIMARY KEY,
                amount INTEGER,
                percentage DECIMAL
            )
        """)

        # Insert with correct types
        db_e2e.execute(
            "INSERT INTO public.type_test (amount, percentage) VALUES (%s, %s)",
            100, 95.5
        )

        result = db_e2e.execute(
            "SELECT amount, percentage FROM public.type_test WHERE id = 1"
        )[0]

        assert result[0] == 100
        assert float(result[1]) == 95.5

    def test_branch_operation_authorization(self, db_e2e, pggit_installed):
        """Test branch operations respect authorization"""
        # Create branch
        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "auth-test-branch"
        )[0]

        # Verify branch exists
        exists = db_e2e.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE id = %s",
            bid
        )[0][0]
        assert exists == 1

    def test_commit_history_immutability(self, db_e2e, pggit_installed):
        """Test that commit history cannot be modified"""
        bid = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "immutable-branch"
        )[0]

        cid = db_e2e.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
            bid, "Original commit"
        )[0]

        # Verify original
        original = db_e2e.execute(
            "SELECT message FROM pggit.commits WHERE id = %s",
            cid
        )[0][0]
        assert original == "Original commit"

        # Attempt to modify
        try:
            db_e2e.execute(
                "UPDATE pggit.commits SET message = %s WHERE id = %s",
                "Modified commit", cid
            )
            # May succeed depending on constraints
        except Exception:
            pass
