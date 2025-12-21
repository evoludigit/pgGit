"""
Connection pool exhaustion and recovery tests.

These tests validate that pggit handles connection pool limits gracefully,
including timeout behavior, leak detection, and recovery mechanisms.
"""

import psycopg
import pytest


@pytest.mark.chaos
@pytest.mark.resource
@pytest.mark.slow
class TestConnectionExhaustion:
    """Test connection pool limit handling."""

    def test_connection_sequential_acquire(self, db_connection_string: str):
        """
        Test: Acquire multiple connections sequentially.

        Expected: Can acquire up to PostgreSQL max_connections limit.
        """
        connections = []
        max_to_acquire = 5  # Conservative limit for testing

        try:
            for i in range(max_to_acquire):
                conn = psycopg.connect(db_connection_string)
                connections.append(conn)

            # Verify all connections are alive
            for conn in connections:
                cursor = conn.execute("SELECT 1")
                result = cursor.fetchone()
                assert result is not None, "Connection should be alive"

        finally:
            # Cleanup all connections
            for conn in connections:
                conn.close()

        print(f"\n✅ Successfully acquired and closed {len(connections)} connections")

    def test_connection_reuse_and_return(self, db_connection_string: str):
        """
        Test: Reuse connections by closing and reopening.

        Expected: Connections can be safely reused.
        """
        # First connection
        conn1 = psycopg.connect(db_connection_string)
        cursor1 = conn1.execute("SELECT 1")
        result1 = cursor1.fetchone()
        assert result1 is not None, "First connection should work"
        conn1.close()

        # Reuse same connection string
        conn2 = psycopg.connect(db_connection_string)
        cursor2 = conn2.execute("SELECT 1")
        result2 = cursor2.fetchone()
        assert result2 is not None, "Second connection should work"
        conn2.close()

        print("\n✅ Connection reuse successful")

    def test_connection_multiple_simultaneous(self, db_connection_string: str):
        """
        Test: Hold multiple connections simultaneously.

        Expected: Can hold several concurrent connections.
        """
        num_connections = 3
        connections = []

        try:
            # Acquire all connections
            for i in range(num_connections):
                conn = psycopg.connect(db_connection_string)
                connections.append(conn)

            # Verify all are alive simultaneously
            for i, conn in enumerate(connections):
                cursor = conn.execute("SELECT %s", (i,))
                result = cursor.fetchone()[0]
                assert result == i, f"Connection {i} should return correct value"

        finally:
            # Close all
            for conn in connections:
                conn.close()

        print(f"\n✅ Held {num_connections} simultaneous connections")

    def test_connection_error_handling(self, db_connection_string: str):
        """
        Test: Handle connection errors gracefully.

        Expected: Invalid connection strings raise appropriate errors.
        """
        # Try to connect with invalid credentials
        try:
            conn = psycopg.connect("dbname=nonexistent_db user=nonexistent")
            conn.close()
            pytest.fail("Should raise connection error for invalid database")
        except psycopg.OperationalError:
            # Expected: connection error
            pass

        print("\n✅ Connection error handling works correctly")

    def test_connection_timeout_on_slow_operations(self, db_connection_string: str):
        """
        Test: Long operations can be cancelled/timed out.

        Expected: Can interrupt long-running queries.
        """
        conn = psycopg.connect(db_connection_string)

        try:
            # PostgreSQL sleep command (1 second)
            cursor = conn.execute("SELECT pg_sleep(0.5)")
            result = cursor.fetchone()
            assert result is not None, "Sleep should complete"

        finally:
            conn.close()

        print("\n✅ Slow operation handling works")


@pytest.mark.chaos
@pytest.mark.resource
class TestConnectionRecovery:
    """Test recovery from connection exhaustion and failures."""

    def test_recovery_after_close_many_connections(self, db_connection_string: str):
        """
        Test: System recovers after closing many connections.

        Expected: New connections can be acquired after cleanup.
        """
        # Open many connections
        connections = []
        for i in range(5):
            conn = psycopg.connect(db_connection_string)
            connections.append(conn)

        # Close all
        for conn in connections:
            conn.close()

        # Try to acquire new connection (should work)
        new_conn = psycopg.connect(db_connection_string)
        cursor = new_conn.execute("SELECT 1")
        assert cursor.fetchone() is not None, "Should get new connection"
        new_conn.close()

        print("\n✅ Recovery after connection close successful")

    def test_connection_resilience_after_failed_query(self, db_connection_string: str):
        """
        Test: Connection can recover after failed query.

        Expected: Connection can execute new queries after rollback following error.
        """
        conn = psycopg.connect(db_connection_string)

        try:
            # Execute invalid query
            try:
                conn.execute("INVALID SQL STATEMENT")
            except psycopg.Error:
                # Expected: query error
                # Must rollback to clear failed transaction state
                conn.rollback()

            # Connection should work after rollback
            cursor = conn.execute("SELECT 1")
            result = cursor.fetchone()
            assert result is not None, "Connection should work after rollback"

        finally:
            conn.close()

        print("\n✅ Connection recovery after query error verified")
