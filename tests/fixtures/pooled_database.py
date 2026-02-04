"""Connection pooling fixture for database tests.

Provides PooledDatabaseFixture class for managing psycopg connection pools
with support for transaction isolation and autocommit modes.
"""

from contextlib import contextmanager
from typing import Any

from psycopg import Connection
from psycopg_pool import ConnectionPool


class PooledDatabaseFixture:
    """Fixture managing pooled database connections with transaction isolation."""

    def __init__(
        self,
        pool: ConnectionPool,
        transaction_isolation: bool = False,
    ):
        """Initialize pooled database fixture.

        Args:
            pool: psycopg ConnectionPool instance
            transaction_isolation: If True, uses transactions for test isolation
        """
        self.pool = pool
        self.transaction_isolation = transaction_isolation
        self.in_test_transaction = False

    @contextmanager
    def get_connection(self):
        """Context manager for acquiring and returning connections from pool.

        Yields:
            psycopg Connection from the pool

        Example:
            with fixture.get_connection() as conn:
                conn.execute("SELECT 1")
        """
        conn = self.pool.getconn()
        try:
            yield conn
        finally:
            self.pool.putconn(conn)

    def execute(self, query: str, *args):
        """Execute a query and return results.

        Automatically commits unless in test transaction or executing transaction
        control statements.

        Args:
            query: SQL query string
            *args: Query parameters

        Returns:
            Query results for SELECT/SHOW/WITH/EXPLAIN, None otherwise
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, args)

            query_upper = query.strip().upper()
            if (
                query_upper not in ("BEGIN", "COMMIT", "ROLLBACK")
                and not self.in_test_transaction
            ):
                conn.commit()

            if (
                query_upper.startswith("SELECT")
                or query_upper.startswith("SHOW")
                or query_upper.startswith("WITH")
                or query_upper.startswith("EXPLAIN")
                or cursor.description is not None
            ):
                try:
                    return cursor.fetchall()
                except Exception:
                    return None
            return None

    def execute_returning(self, query: str, *args):
        """Execute query that returns a single row.

        Args:
            query: SQL query string
            *args: Query parameters

        Returns:
            Single row as tuple, or None if no results
        """
        with self.get_connection() as conn:
            try:
                cursor = conn.cursor()
                cursor.execute(query, args)
                result = cursor.fetchone()
                if not self.in_test_transaction:
                    conn.commit()
                return result
            except Exception as e:
                if not self.in_test_transaction:
                    conn.rollback()
                raise Exception(f"Query failed: {query} with args {args}\nOriginal error: {str(e)}") from e

    def begin_transaction(self):
        """Start a test transaction for isolation.

        Call this to begin a transaction that will be rolled back after test.
        """
        with self.get_connection() as conn:
            try:
                conn.execute("BEGIN")
                self.in_test_transaction = True
            except Exception:
                self.in_test_transaction = False

    def rollback_transaction(self):
        """Rollback the test transaction.

        Call this to rollback all changes made during test.
        """
        self.in_test_transaction = False
        with self.get_connection() as conn:
            try:
                conn.rollback()
            except Exception:
                pass  # Connection might already be closed

    def health_check(self) -> bool:
        """Verify pool is working and can execute queries.

        Returns:
            True if pool is healthy, False otherwise
        """
        try:
            with self.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT 1")
                return cursor.fetchone()[0] == 1
        except Exception:
            return False
