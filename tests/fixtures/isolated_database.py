"""Isolated database fixtures with proper transaction/savepoint support.

This module provides specialized fixture classes for different test isolation needs.
Each fixture maintains a persistent connection to ensure transaction/savepoint
boundaries are preserved across multiple operations.

Architecture:
- IsolatedDatabaseFixture: Base class with persistent connection management
- TransactionDatabaseFixture: Transaction-based isolation for unit tests (~1ms overhead)
- SavepointDatabaseFixture: Savepoint-based isolation for integration tests (~10ms overhead)
- LoadDatabaseFixture: No automatic cleanup for load/performance tests (~0ms overhead)

The key architectural fix vs the old PooledDatabaseFixture:
- Old pattern: get_connection() → execute BEGIN → putconn() → get_connection() → execute query
  PROBLEM: BEGIN was on connection A, query executed on connection B (from pool)
- New pattern: self._conn persistent → execute BEGIN → execute query (same connection)
  FIXED: All operations on same connection, transactions work correctly
"""

from contextlib import contextmanager
from typing import Generator
import time
import uuid

from psycopg import Connection
from psycopg.pq import TransactionStatus
from psycopg_pool import ConnectionPool


class IsolatedDatabaseFixture:
    """Base class for fixtures with persistent connection.

    Maintains a persistent connection from the pool for the lifetime of the test,
    ensuring that transaction and savepoint boundaries are preserved.
    """

    def __init__(self, pool: ConnectionPool):
        """Initialize with connection pool.

        Args:
            pool: psycopg ConnectionPool instance
        """
        self.pool = pool
        self._conn: Connection | None = None

    def _ensure_connection(self) -> Connection:
        """Get or create persistent connection.

        Returns:
            psycopg Connection from pool, reused for all operations
        """
        if self._conn is None:
            self._conn = self.pool.getconn()
        return self._conn

    def _release_connection(self):
        """Return connection to pool.

        Before returning, reset any error state so the next user gets a clean connection.
        """
        if self._conn is not None:
            # Reset error state before returning to pool
            try:
                if self._conn.info.transaction_status == TransactionStatus.INERROR:
                    self._conn.rollback()
            except Exception:
                pass  # Connection might be broken, pool will handle it

            self.pool.putconn(self._conn)
            self._conn = None

    def execute(self, query: str, *args):
        """Execute query on persistent connection.

        Automatically commits unless in a transaction/savepoint or executing
        transaction control statements.

        Args:
            query: SQL query string
            *args: Query parameters

        Returns:
            Query results for SELECT/SHOW/WITH/EXPLAIN, None otherwise
        """
        conn = self._ensure_connection()
        cursor = conn.cursor()
        cursor.execute(query, args)

        # Return results for SELECT, SHOW, WITH, EXPLAIN, and other result-producing queries
        query_upper = query.strip().upper()
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
        conn = self._ensure_connection()
        cursor = conn.cursor()
        cursor.execute(query, args)
        return cursor.fetchone()


class TransactionDatabaseFixture(IsolatedDatabaseFixture):
    """Fixture with transaction-based isolation for unit tests.

    Use for:
    - SQL function tests
    - Constraint validation
    - Schema validation
    - DDL tracking tests

    Guarantees:
    - Complete test isolation via transaction rollback
    - All changes automatically rolled back
    - ~1ms overhead per test

    Example:
        def test_unique_constraint(db_unit):
            db_unit.execute("CREATE TABLE test (id INT UNIQUE)")
            db_unit.execute("INSERT INTO test VALUES (1)")
            with pytest.raises(Exception):
                db_unit.execute("INSERT INTO test VALUES (1)")
            # No cleanup needed - automatic rollback
    """

    def begin_transaction(self):
        """Begin transaction for test isolation.

        All subsequent operations on this connection will be rolled back at test end.
        """
        conn = self._ensure_connection()
        # Reset connection state if it's in error state from previous transaction
        if conn.info.transaction_status == TransactionStatus.INERROR:
            try:
                conn.rollback()
            except Exception:
                pass
        conn.execute("BEGIN")

    def rollback_transaction(self):
        """Rollback transaction and release connection.

        Rolls back all changes made since begin_transaction() was called.
        """
        if self._conn is not None:
            try:
                self._conn.rollback()
            except Exception:
                pass  # Connection might be in failed state
            finally:
                self._release_connection()

    def rollback(self):
        """Alias for rollback_transaction for compatibility."""
        self.rollback_transaction()


class SavepointDatabaseFixture(IsolatedDatabaseFixture):
    """Fixture with savepoint-based isolation for integration tests.

    Use for:
    - Multi-operation workflows
    - Dependency tracking tests
    - Branch/merge operations
    - Tests with intermediate commits

    Guarantees:
    - Per-test isolation via savepoint
    - Can test transaction boundaries
    - Works with connection pooling
    - ~10ms overhead per test

    Example:
        def test_dependency_chain(db_integration):
            db_integration.execute("CREATE TABLE base (id INT)")
            db_integration.execute("CREATE VIEW v1 AS SELECT * FROM base")
            deps = db_integration.execute("SELECT * FROM pggit.dependencies ...")
            assert len(deps) >= 1
            # No cleanup needed - automatic savepoint rollback
    """

    def __init__(self, pool: ConnectionPool):
        """Initialize with connection pool.

        Args:
            pool: psycopg ConnectionPool instance
        """
        super().__init__(pool)
        self._savepoint_name: str | None = None
        self._in_savepoint = False

    def _execute_with_auto_commit(self, query: str, *args):
        """Execute query with auto-commit handling based on savepoint state.

        When inside a savepoint, we should not auto-commit. When outside,
        we auto-commit to maintain expected behavior.
        """
        conn = self._ensure_connection()
        cursor = conn.cursor()
        cursor.execute(query, args)

        # Return results for SELECT, SHOW, WITH, EXPLAIN, and other result-producing queries
        query_upper = query.strip().upper()

        # Don't auto-commit when inside a savepoint (let rollback handle it)
        # Don't auto-commit transaction control statements
        if (
            query_upper not in ("BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT")
            and not query_upper.startswith("ROLLBACK TO")
            and not self._in_savepoint
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

    def execute(self, query: str, *args):
        """Execute query on persistent connection, respecting savepoint context.

        Args:
            query: SQL query string
            *args: Query parameters

        Returns:
            Query results for SELECT/SHOW/WITH/EXPLAIN, None otherwise
        """
        return self._execute_with_auto_commit(query, *args)

    def begin_savepoint(self):
        """Begin savepoint for test isolation.

        Creates a named savepoint on the connection. All subsequent operations
        will be rolled back to this savepoint at test end.
        """
        conn = self._ensure_connection()

        # Reset connection state if it's in error state from previous transaction
        if conn.info.transaction_status == TransactionStatus.INERROR:
            try:
                conn.rollback()
            except Exception:
                pass

        # SAVEPOINT requires being in a transaction, so start one if needed
        try:
            # Check if we're in a transaction by trying a status check
            # If not in transaction, BEGIN will start one
            cursor = conn.cursor()
            cursor.execute("SELECT 1")  # Simple query to check state
            conn.commit()  # Commit any pending work
        except Exception:
            pass

        # Ensure we're in a transaction for the savepoint
        conn.execute("BEGIN")

        self._savepoint_name = f"test_sp_{uuid.uuid4().hex[:8]}"
        conn.execute(f"SAVEPOINT {self._savepoint_name}")
        self._in_savepoint = True

    def rollback_savepoint(self):
        """Rollback to savepoint and release connection.

        Rolls back all changes made since begin_savepoint() was called.
        """
        if self._conn is not None and self._savepoint_name is not None:
            try:
                self._conn.execute(f"ROLLBACK TO SAVEPOINT {self._savepoint_name}")
                # Complete the transaction that the savepoint was in
                self._conn.commit()
            except Exception:
                # If rollback fails, try to rollback the whole transaction
                try:
                    self._conn.rollback()
                except Exception:
                    pass
            finally:
                self._in_savepoint = False
                self._release_connection()

    def rollback(self):
        """Alias for rollback_savepoint for compatibility."""
        self.rollback_savepoint()


class LoadDatabaseFixture(IsolatedDatabaseFixture):
    """Minimal fixture for load testing with no automatic cleanup.

    Use for:
    - Performance benchmarks
    - Stress tests
    - Throughput measurements
    - Connection pool exhaustion tests

    Guarantees:
    - Minimal overhead (~0ms)
    - Manual cleanup responsibility
    - Timing metrics available

    Example:
        def test_commit_throughput(db_load):
            for i in range(10000):
                db_load.execute_timed("SELECT pggit.commit_changes(...)")

            print(f"Throughput: {10000 / db_load.metrics['time']:.0f} ops/sec")

            # Manual cleanup required
            db_load.cleanup()
    """

    def __init__(self, pool: ConnectionPool):
        """Initialize with connection pool and metrics.

        Args:
            pool: psycopg ConnectionPool instance
        """
        super().__init__(pool)
        self.metrics = {"queries": 0, "time": 0.0}

    def execute_timed(self, query: str, *args):
        """Execute query and track timing.

        Args:
            query: SQL query string
            *args: Query parameters

        Returns:
            Query results (same as execute())
        """
        start = time.perf_counter()
        result = self.execute(query, *args)
        elapsed = time.perf_counter() - start
        self.metrics["queries"] += 1
        self.metrics["time"] += elapsed
        return result

    def cleanup(self):
        """Manual cleanup - release connection to pool.

        Call this at the end of load tests to return the connection.
        """
        self._release_connection()
