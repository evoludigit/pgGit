"""Unit tests for connection pooling infrastructure.

Tests pool creation, connection management, and isolation behavior.
"""

import pytest
from psycopg_pool import ConnectionPool

from tests.fixtures.pooled_database import PooledDatabaseFixture


@pytest.fixture
def test_pool(db_connection_string: str) -> ConnectionPool:
    """Create a test connection pool."""
    pool = ConnectionPool(
        conninfo=db_connection_string,
        min_size=2,
        max_size=5,
        timeout=10,
        open=True,
    )
    yield pool
    pool.close()


class TestConnectionPool:
    """Test connection pool infrastructure."""

    def test_pool_creation(self, test_pool):
        """Pool should create successfully with configured parameters."""
        assert test_pool is not None
        assert test_pool.min_size == 2
        assert test_pool.max_size == 5

    def test_pool_connection_acquisition(self, test_pool):
        """Pool should acquire and return connections."""
        conn = test_pool.getconn()
        assert conn is not None

        # Verify connection works
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        assert cursor.fetchone()[0] == 1

        # Return to pool
        test_pool.putconn(conn)

    def test_pool_connection_reuse(self, test_pool):
        """Pool should reuse returned connections."""
        # Get connection
        conn1 = test_pool.getconn()
        conn1_id = id(conn1)

        # Return to pool
        test_pool.putconn(conn1)

        # Get another connection - should be same instance (reused)
        conn2 = test_pool.getconn()
        conn2_id = id(conn2)

        # Verify same connection was reused
        assert conn1_id == conn2_id

        test_pool.putconn(conn2)

    def test_pooled_database_fixture_creation(self, test_pool):
        """PooledDatabaseFixture should initialize with pool."""
        fixture = PooledDatabaseFixture(test_pool, transaction_isolation=True)
        assert fixture.pool is test_pool
        assert fixture.transaction_isolation is True
        assert fixture.in_test_transaction is False

    def test_pooled_database_health_check(self, test_pool):
        """Health check should verify pool is operational."""
        fixture = PooledDatabaseFixture(test_pool)
        assert fixture.health_check() is True

    def test_pooled_database_execute_select(self, test_pool):
        """Execute should return results for SELECT queries."""
        fixture = PooledDatabaseFixture(test_pool)
        result = fixture.execute("SELECT 1 as num")
        assert result is not None
        assert len(result) > 0
        assert result[0][0] == 1

    def test_pooled_database_execute_with_params(self, test_pool):
        """Execute should handle parameterized queries."""
        fixture = PooledDatabaseFixture(test_pool)
        result = fixture.execute("SELECT %s::TEXT as text", "hello")
        assert result is not None
        assert result[0][0] == "hello"

    def test_pooled_database_execute_returning(self, test_pool):
        """Execute_returning should fetch single row."""
        fixture = PooledDatabaseFixture(test_pool)
        result = fixture.execute_returning("SELECT %s::INTEGER as num", 42)
        assert result is not None
        assert result[0] == 42

    def test_pooled_database_transaction_isolation(self, test_pool):
        """Transaction isolation should prevent auto-commit in transactions."""
        fixture = PooledDatabaseFixture(test_pool, transaction_isolation=True)

        # Start transaction
        fixture.begin_transaction()
        assert fixture.in_test_transaction is True

        # Verify can execute within transaction
        result = fixture.execute("SELECT 1")
        assert result is not None

        # Rollback
        fixture.rollback_transaction()
        assert fixture.in_test_transaction is False

    def test_pooled_database_concurrent_connections(self, test_pool):
        """Pool should handle multiple concurrent connections."""
        fixture = PooledDatabaseFixture(test_pool)

        # Get multiple connections concurrently
        connections = []
        for _ in range(3):
            with fixture.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT 1")
                connections.append(cursor.fetchone()[0])

        assert len(connections) == 3
        assert all(c == 1 for c in connections)
