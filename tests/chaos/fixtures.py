"""
Chaos Engineering Test Fixtures

This module provides additional reusable fixtures for chaos engineering tests,
including concurrent execution helpers, delay injection, and transaction monitoring.
"""

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable, Generator

import psycopg
import pytest

logger = logging.getLogger(__name__)

from tests.chaos.utils import AsyncTransactionMonitor, ChaosInjector, TransactionMonitor


@pytest.fixture
def concurrent_executor() -> Generator[ThreadPoolExecutor, None, None]:
    """Thread pool executor for running concurrent database operations."""
    with ThreadPoolExecutor(max_workers=20) as executor:
        yield executor


@pytest.fixture
async def async_concurrent_executor():
    """Async executor for running many async tasks concurrently."""

    async def run_concurrent_tasks(tasks: list[Callable], max_concurrent: int = 10):
        """Run tasks with limited concurrency."""
        semaphore = asyncio.Semaphore(max_concurrent)

        async def bounded_task(task):
            async with semaphore:
                return await task()

        return await asyncio.gather(*[bounded_task(t) for t in tasks])

    return run_concurrent_tasks


@pytest.fixture
def pg_sleep_injector(sync_conn: psycopg.Connection) -> Callable[[float, str], Any]:
    """Inject delays using PostgreSQL's pg_sleep for realistic testing."""

    def inject_delay(seconds: float, query: str) -> Any:
        """Execute query with delay injected via pg_sleep."""
        sync_conn.execute(f"SELECT pg_sleep({seconds})")
        return sync_conn.execute(query)

    return inject_delay


@pytest.fixture
async def async_pg_sleep_injector(async_conn: psycopg.AsyncConnection):
    """Async version of pg_sleep_injector."""

    async def inject_delay(seconds: float, query: str) -> Any:
        """Execute query with delay injected via pg_sleep."""
        await async_conn.execute(f"SELECT pg_sleep({seconds})")
        return await async_conn.execute(query)

    return inject_delay


@pytest.fixture
def transaction_monitor(sync_conn: psycopg.Connection) -> TransactionMonitor:
    """Monitor active transactions and locks."""
    return TransactionMonitor(sync_conn)


@pytest.fixture
async def async_transaction_monitor(
    async_conn: psycopg.AsyncConnection,
) -> AsyncTransactionMonitor:
    """Async version of transaction monitor."""
    return AsyncTransactionMonitor(async_conn)


@pytest.fixture
def chaos_injector() -> ChaosInjector:
    """Provide access to chaos injection utilities."""
    return ChaosInjector()


@pytest.fixture
def deadlock_setup() -> Callable:
    """Set up connections for deadlock testing."""

    def create_deadlock_pair(
        conn1: psycopg.Connection, conn2: psycopg.Connection
    ) -> tuple[psycopg.Connection, psycopg.Connection]:
        """Create a deadlock scenario between two connections."""
        # Start transaction on conn1 and lock resource A
        conn1.execute("BEGIN")
        conn1.execute("SELECT pg_advisory_lock(1)")
        conn1.commit()

        # Start transaction on conn2 and lock resource B
        conn2.execute("BEGIN")
        conn2.execute("SELECT pg_advisory_lock(2)")
        conn2.commit()

        return conn1, conn2

    def cleanup_deadlock(conn1: psycopg.Connection, conn2: psycopg.Connection) -> None:
        """Clean up deadlock test state."""
        try:
            conn1.execute("SELECT pg_advisory_unlock_all()")
            conn2.execute("SELECT pg_advisory_unlock_all()")
            conn1.rollback()
            conn2.rollback()
        except Exception as e:
            logger.debug(
                f"Cleanup rollback failed: {e}"
            )  # Ignore cleanup errors in tests

    return {
        "setup": create_deadlock_pair,
        "cleanup": cleanup_deadlock,
    }


@pytest.fixture
async def async_deadlock_setup():
    """Set up async connections for deadlock testing."""

    async def create_deadlock_pair(
        conn1: psycopg.AsyncConnection,
        conn2: psycopg.AsyncConnection,
    ):
        """Create a deadlock scenario between two async connections."""
        # Start transaction on conn1 and lock resource A
        await conn1.execute("BEGIN")
        await conn1.execute("SELECT pg_advisory_lock(1)")
        await conn1.commit()

        # Start transaction on conn2 and lock resource B
        await conn2.execute("BEGIN")
        await conn2.execute("SELECT pg_advisory_lock(2)")
        await conn2.commit()

        return conn1, conn2

    async def cleanup_deadlock(
        conn1: psycopg.AsyncConnection,
        conn2: psycopg.AsyncConnection,
    ):
        """Clean up async deadlock test state."""
        try:
            await conn1.execute("SELECT pg_advisory_unlock_all()")
            await conn2.execute("SELECT pg_advisory_unlock_all()")
            await conn1.rollback()
            await conn2.rollback()
        except Exception as e:
            logger.debug(
                f"Async cleanup rollback failed: {e}"
            )  # Ignore cleanup errors in tests

    return {
        "setup": create_deadlock_pair,
        "cleanup": cleanup_deadlock,
    }


@pytest.fixture
def load_generator(sync_conn: psycopg.Connection) -> dict:
    """Generate database load for stress testing."""

    def create_load_tables(
        num_tables: int = 5, rows_per_table: int = 1000
    ) -> list[str]:
        """Create tables with test data for load generation."""
        tables = []

        for i in range(num_tables):
            table_name = f"load_test_table_{i}"
            sync_conn.execute(f"""
                CREATE TABLE {table_name} (
                    id SERIAL PRIMARY KEY,
                    data TEXT,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)

            # Insert test data
            for j in range(rows_per_table):
                sync_conn.execute(f"""
                    INSERT INTO {table_name} (data)
                    VALUES ('test_data_{j}')
                """)

            tables.append(table_name)

        sync_conn.commit()
        return tables

    def cleanup_load_tables(tables: list[str]):
        """Clean up load test tables."""
        for table in tables:
            sync_conn.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
        sync_conn.commit()

    return {
        "create_tables": create_load_tables,
        "cleanup_tables": cleanup_load_tables,
    }


@pytest.fixture
async def async_load_generator(async_conn: psycopg.AsyncConnection):
    """Async version of load generator."""

    async def create_load_tables(num_tables: int = 5, rows_per_table: int = 1000):
        """Create tables with test data for load generation."""
        tables = []

        for i in range(num_tables):
            table_name = f"async_load_test_table_{i}"
            await async_conn.execute(f"""
                CREATE TABLE {table_name} (
                    id SERIAL PRIMARY KEY,
                    data TEXT,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)

            # Insert test data
            for j in range(rows_per_table):
                await async_conn.execute(f"""
                    INSERT INTO {table_name} (data)
                    VALUES ('test_data_{j}')
                """)

            tables.append(table_name)

        await async_conn.commit()
        return tables

    async def cleanup_load_tables(tables: list[str]):
        """Clean up load test tables."""
        for table in tables:
            await async_conn.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
        await async_conn.commit()

    return {
        "create_tables": create_load_tables,
        "cleanup_tables": cleanup_load_tables,
    }


@pytest.fixture
def connection_stressor() -> dict:
    """Utilities for stressing database connections."""

    def exhaust_connection_pool(max_connections: int = 50):
        """Attempt to exhaust the connection pool."""
        connections = []
        try:
            for i in range(max_connections):
                # This would normally fail when pool is exhausted
                # Implementation depends on actual connection pooling setup
                pass
        finally:
            for conn in connections:
                try:
                    conn.close()
                except Exception:
                    pass

        return len(connections)

    return {
        "exhaust_pool": exhaust_connection_pool,
    }


@pytest.fixture
def schema_isolator(sync_conn: psycopg.Connection) -> dict:
    """Create isolated schemas for testing schema-level operations."""
    schemas_created = []

    def create_isolated_schema(base_name: str = "test_schema") -> str:
        """Create an isolated schema for testing."""
        import uuid

        schema_name = f"{base_name}_{uuid.uuid4().hex[:8]}"

        sync_conn.execute(f"CREATE SCHEMA {schema_name}")
        sync_conn.execute(f"SET LOCAL search_path TO {schema_name}, public")
        schemas_created.append(schema_name)

        return schema_name

    def cleanup_schemas():
        """Clean up all created schemas."""
        for schema in schemas_created:
            try:
                sync_conn.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
            except Exception:
                pass  # Schema might already be dropped
        sync_conn.commit()
        schemas_created.clear()

    # Cleanup on teardown
    import atexit

    atexit.register(cleanup_schemas)

    yield create_isolated_schema

    # Final cleanup
    cleanup_schemas()
