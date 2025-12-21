"""
Example 3: Transaction Testing

This example demonstrates how to test transaction properties like atomicity,
isolation, and durability (ACID guarantees).

Concept:
  Transaction tests verify that database operations maintain consistency
  even when failures occur. Key properties include:
  - Atomicity: All or nothing
  - Isolation: Concurrent operations don't interfere
  - Consistency: Data remains valid
  - Durability: Changes persist

Key Insight:
  Transaction tests are critical because they verify that data integrity
  is maintained even when errors occur.
"""

import pytest


class TestTransactionAtomicity:
    """Examples of testing ACID properties in transactions."""

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_rollback_on_error(self, sync_conn, isolated_schema):
        """
        Test: Errors trigger rollback of all changes in transaction.

        Property: Either ALL changes commit, or NONE do.
        """
        # Setup
        sync_conn.execute("CREATE TABLE users (id SERIAL, email TEXT UNIQUE)")
        sync_conn.commit()

        count_before = sync_conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        assert count_before == 0

        # Try multi-step transaction with error
        try:
            sync_conn.execute("BEGIN")

            # First insert succeeds
            sync_conn.execute("INSERT INTO users (email) VALUES (%s)", ("user1@example.com",))

            # Second insert would violate constraint
            sync_conn.execute("INSERT INTO users (email) VALUES (%s)", ("user1@example.com",))

            # This would commit if we reached it
            sync_conn.commit()

        except Exception:
            # Error causes rollback
            sync_conn.rollback()

        # Verify complete rollback - no rows added
        count_after = sync_conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        assert count_after == 0, "Transaction should rollback completely on error"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_partial_completion_not_possible(self, sync_conn, isolated_schema):
        """
        Test: Cannot have partial completion - either all or nothing.

        This verifies the fundamental atomicity principle.
        """
        # Setup with 2 tables
        sync_conn.execute("CREATE TABLE accounts (id SERIAL, balance INT)")
        sync_conn.execute("CREATE TABLE transfers (id SERIAL, amount INT)")
        sync_conn.commit()

        # Add initial data
        sync_conn.execute("INSERT INTO accounts (balance) VALUES (%s)", (1000,))
        sync_conn.execute("INSERT INTO accounts (balance) VALUES (%s)", (500,))
        sync_conn.commit()

        try:
            sync_conn.execute("BEGIN")

            # First operation: debit from account 1
            sync_conn.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")

            # Second operation: credit to account 2
            sync_conn.execute("UPDATE accounts SET balance = balance + 100 WHERE id = 2")

            # Third operation: record transfer (intentional error)
            sync_conn.execute("INSERT INTO transfers (amount) VALUES (%s)", (100,))

            # Force an error
            sync_conn.execute("INVALID SQL")

            sync_conn.commit()

        except Exception:
            sync_conn.rollback()

        # Verify BOTH operations rolled back (not just one)
        account1 = sync_conn.execute("SELECT balance FROM accounts WHERE id = 1").fetchone()[0]
        account2 = sync_conn.execute("SELECT balance FROM accounts WHERE id = 2").fetchone()[0]
        transfers = sync_conn.execute("SELECT COUNT(*) FROM transfers").fetchone()[0]

        assert account1 == 1000, "Account 1 should be unchanged"
        assert account2 == 500, "Account 2 should be unchanged"
        assert transfers == 0, "Transfer should not be recorded"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_successful_commit_persists(self, sync_conn, isolated_schema):
        """
        Test: Successful commits persist after transaction ends.

        Property: Committed data survives and is visible to other connections.
        """
        sync_conn.execute("CREATE TABLE data (id SERIAL, value TEXT)")
        sync_conn.commit()

        # Insert and commit
        sync_conn.execute("BEGIN")
        sync_conn.execute("INSERT INTO data (value) VALUES (%s)", ("test_value",))
        sync_conn.commit()

        # In new transaction, data should be visible
        sync_conn.execute("BEGIN")
        rows = sync_conn.execute("SELECT COUNT(*) FROM data").fetchone()[0]
        sync_conn.commit()

        assert rows == 1, "Committed data should persist"


class TestTransactionIsolation:
    """Examples of testing transaction isolation levels."""

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_concurrent_transaction_isolation(self, sync_conn, isolated_schema):
        """
        Test: Concurrent transactions don't see uncommitted changes.

        Property: Isolation prevents "dirty reads" of uncommitted data.
        """
        sync_conn.execute("CREATE TABLE products (id SERIAL, price INT)")
        sync_conn.execute("INSERT INTO products (price) VALUES (%s)", (100,))
        sync_conn.commit()

        # Transaction 1: update but don't commit
        sync_conn.execute("BEGIN")
        sync_conn.execute("UPDATE products SET price = 200 WHERE id = 1")

        # In same transaction, we see the change
        new_price = sync_conn.execute("SELECT price FROM products WHERE id = 1").fetchone()[0]
        assert new_price == 200, "Uncommitted changes visible within transaction"

        # Rollback the change
        sync_conn.execute("ROLLBACK")

        # After rollback, original value restored
        restored_price = sync_conn.execute("SELECT price FROM products WHERE id = 1").fetchone()[0]
        assert restored_price == 100, "Rollback should restore original value"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_savepoint_usage(self, sync_conn, isolated_schema):
        """
        Test: Savepoints allow partial rollback within transaction.

        Property: Savepoints let you rollback part of a transaction
        while keeping other changes.
        """
        sync_conn.execute("CREATE TABLE items (id SERIAL, status TEXT)")
        sync_conn.commit()

        sync_conn.execute("BEGIN")

        # Insert first item
        sync_conn.execute("INSERT INTO items (status) VALUES (%s)", ("created",))

        # Create savepoint
        sync_conn.execute("SAVEPOINT sp1")

        # Insert second item
        sync_conn.execute("INSERT INTO items (status) VALUES (%s)", ("created",))

        # Rollback to savepoint (undo second insert)
        sync_conn.execute("ROLLBACK TO sp1")

        # Complete transaction
        sync_conn.execute("COMMIT")

        # Verify only first item exists
        count = sync_conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
        assert count == 1, "Only one item should remain after savepoint rollback"


class TestConstraintHandling:
    """Examples of testing constraint violations in transactions."""

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_unique_constraint_enforcement(self, sync_conn, isolated_schema):
        """
        Test: UNIQUE constraints prevent duplicate values.
        """
        sync_conn.execute(
            "CREATE TABLE users (id SERIAL PRIMARY KEY, username TEXT UNIQUE)"
        )
        sync_conn.commit()

        # Insert first user
        sync_conn.execute("INSERT INTO users (username) VALUES (%s)", ("alice",))
        sync_conn.commit()

        # Try to insert duplicate - should fail
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO users (username) VALUES (%s)", ("alice",))
            sync_conn.commit()
            assert False, "Should have raised error"
        except Exception:
            sync_conn.rollback()

        # Verify only one user
        count = sync_conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        assert count == 1, "Constraint should prevent duplicate"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_not_null_constraint_enforcement(self, sync_conn, isolated_schema):
        """
        Test: NOT NULL constraints require values.
        """
        sync_conn.execute(
            "CREATE TABLE products (id SERIAL, name TEXT NOT NULL)"
        )
        sync_conn.commit()

        # Try to insert null - should fail
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO products (name) VALUES (%s)", (None,))
            sync_conn.commit()
            assert False, "Should have raised error"
        except Exception:
            sync_conn.rollback()

        # Verify no row added
        count = sync_conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
        assert count == 0, "NOT NULL constraint should prevent null"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_foreign_key_constraint(self, sync_conn, isolated_schema):
        """
        Test: Foreign key constraints maintain referential integrity.
        """
        # Create parent table
        sync_conn.execute("CREATE TABLE categories (id SERIAL PRIMARY KEY, name TEXT)")

        # Create child table with FK
        sync_conn.execute(
            """CREATE TABLE products (
                id SERIAL,
                name TEXT,
                category_id INT REFERENCES categories(id)
            )"""
        )
        sync_conn.commit()

        # Insert category
        sync_conn.execute("INSERT INTO categories (name) VALUES (%s)", ("electronics",))
        sync_conn.commit()

        # Insert product with valid FK - succeeds
        sync_conn.execute("INSERT INTO products (name, category_id) VALUES (%s, %s)",
                         ("laptop", 1))
        sync_conn.commit()

        # Try to insert product with invalid FK - should fail
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO products (name, category_id) VALUES (%s, %s)",
                             ("phone", 999))  # Non-existent category
            sync_conn.commit()
            assert False, "Should have raised error"
        except Exception:
            sync_conn.rollback()

        # Verify only 1 product (the valid one)
        count = sync_conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
        assert count == 1, "FK constraint should prevent invalid references"

    @pytest.mark.chaos
    @pytest.mark.transaction
    def test_check_constraint_enforcement(self, sync_conn, isolated_schema):
        """
        Test: CHECK constraints enforce domain constraints.
        """
        sync_conn.execute(
            """CREATE TABLE accounts (
                id SERIAL,
                balance INT CHECK (balance >= 0)
            )"""
        )
        sync_conn.commit()

        # Insert valid balance
        sync_conn.execute("INSERT INTO accounts (balance) VALUES (%s)", (100,))
        sync_conn.commit()

        # Try to insert negative balance - should fail
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO accounts (balance) VALUES (%s)", (-50,))
            sync_conn.commit()
            assert False, "Should have raised error"
        except Exception:
            sync_conn.rollback()

        # Verify only valid account exists
        count = sync_conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        assert count == 1, "CHECK constraint should prevent invalid values"

        # Try to update to negative - should also fail
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("UPDATE accounts SET balance = -1 WHERE id = 1")
            sync_conn.commit()
            assert False, "Should have raised error"
        except Exception:
            sync_conn.rollback()

        # Verify value unchanged
        balance = sync_conn.execute("SELECT balance FROM accounts WHERE id = 1").fetchone()[0]
        assert balance == 100, "CHECK constraint should prevent negative balance"
