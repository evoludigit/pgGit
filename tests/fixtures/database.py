"""
Database fixture module for test suite.

Provides database connection management, setup/teardown, and cleanup utilities
for E2E, integration, and other database-dependent tests.

Features:
- Thread-safe connection pooling with threading.local()
- Auto-commit behavior for test consistency
- SELECT query result fetching
- Transaction control (BEGIN/COMMIT/ROLLBACK)
"""

import threading
from psycopg import connect


class DatabaseFixture:
    """Manages database connections with thread-safety."""

    _local = threading.local()

    def __init__(self, connection_string: str):
        """Initialize with PostgreSQL connection string."""
        self.connection_string = connection_string

    def connect(self):
        """Establish thread-local database connection."""
        if not hasattr(self._local, "conn") or self._local.conn is None:
            self._local.conn = connect(self.connection_string)
        return self._local.conn

    @property
    def conn(self):
        """Get thread-local connection without establishing new one."""
        return getattr(self._local, "conn", None)

    def execute(self, query: str, *args):
        """
        Execute a query and return results for SELECT queries.

        Args:
            query: SQL query string with %s placeholders for params
            *args: Query parameters

        Returns:
            List of tuples for SELECT queries, None otherwise
            Automatically commits after execution
        """
        if not self.conn:
            self.connect()

        cursor = self.conn.cursor()
        cursor.execute(query, args)

        # Don't auto-commit transaction control statements
        query_upper = query.strip().upper()
        if query_upper not in ("BEGIN", "COMMIT", "ROLLBACK"):
            self.conn.commit()

        # Return results if it's a SELECT query
        if query_upper.startswith("SELECT"):
            return cursor.fetchall()
        return None

    def execute_returning(self, query: str, *args):
        """
        Execute query that returns a single row as tuple.

        Useful for INSERT/UPDATE/DELETE ... RETURNING queries.

        Args:
            query: SQL query string with %s placeholders
            *args: Query parameters

        Returns:
            Single tuple result from fetchone()

        Raises:
            Exception: If query fails, includes original query and args in message
        """
        if not self.conn:
            self.connect()

        try:
            cursor = self.conn.cursor()
            cursor.execute(query, args)
            result = cursor.fetchone()
            self.conn.commit()
            return result
        except Exception as e:
            self.conn.rollback()
            raise Exception(f"Query failed: {query} with args {args}") from e

    def close(self):
        """Close thread-local database connection."""
        if hasattr(self._local, "conn") and self._local.conn:
            self._local.conn.close()
            self._local.conn = None
