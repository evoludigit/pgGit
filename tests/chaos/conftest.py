"""
Chaos Engineering Test Configuration and Fixtures

This module provides pytest configuration and shared fixtures for chaos engineering
tests of the pgGit PostgreSQL extension. It includes database connection management,
chaos injection utilities, and test isolation mechanisms.

Test Categories:
- @pytest.mark.chaos: All chaos engineering tests
- @pytest.mark.slow: Tests taking >30 seconds
- @pytest.mark.concurrent: Concurrency/race condition tests
- @pytest.mark.destructive: Tests that may leave artifacts
"""

import pytest
import psycopg
from psycopg.rows import dict_row
from typing import Generator, AsyncGenerator
import asyncio
from contextlib import asynccontextmanager
import uuid


# Pytest configuration
def pytest_configure(config):
    """Register custom markers for chaos tests."""
    config.addinivalue_line("markers", "chaos: mark test as chaos engineering test")
    config.addinivalue_line("markers", "slow: mark test as slow (may take >30s)")
    config.addinivalue_line("markers", "concurrent: mark test as testing concurrency")
    config.addinivalue_line(
        "markers", "destructive: mark test as potentially destructive"
    )
    config.addinivalue_line("markers", "property: mark test as property-based test")


@pytest.fixture(scope="session")
def db_config() -> dict[str, str | int | None]:
    """Database configuration for chaos tests."""
    return {
        "host": "localhost",
        "port": 5432,
        "dbname": "pggit_chaos_test",
        "user": "postgres",
        "password": None,
    }


@pytest.fixture(scope="session")
def db_connection_string(db_config: dict[str, str | None]) -> str:
    """PostgreSQL connection string."""
    parts = [f"{k}={v}" for k, v in db_config.items() if v is not None]
    return " ".join(parts)


@pytest.fixture(scope="function")
def sync_conn(db_connection_string: str) -> Generator[psycopg.Connection, None, None]:
    """Synchronous database connection for a single test."""
    with psycopg.connect(db_connection_string, row_factory=dict_row) as conn:
        # Set up pggit extension
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        conn.commit()

        yield conn

        # Cleanup: rollback any uncommitted changes
        conn.rollback()


@pytest.fixture(scope="function")
async def async_conn(
    db_connection_string: str,
) -> AsyncGenerator[psycopg.AsyncConnection, None]:
    """Asynchronous database connection for a single test."""
    async with await psycopg.AsyncConnection.connect(
        db_connection_string, row_factory=dict_row
    ) as conn:
        # Set up pggit extension
        await conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        await conn.commit()

        yield conn

        # Cleanup
        await conn.rollback()


@pytest.fixture(scope="function")
def conn_pool(
    db_connection_string: str, request
) -> Generator[list[psycopg.Connection], None, None]:
    """Pool of synchronous database connections for concurrent testing."""
    pool_size = getattr(request, "param", 10)  # Default 10 connections

    connections = []
    for _ in range(pool_size):
        conn = psycopg.connect(db_connection_string, row_factory=dict_row)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        conn.commit()
        connections.append(conn)

    yield connections

    # Cleanup
    for conn in connections:
        conn.rollback()
        conn.close()


@pytest.fixture(scope="function")
async def async_conn_pool(
    db_connection_string: str, request
) -> AsyncGenerator[list[psycopg.AsyncConnection], None]:
    """Pool of asynchronous database connections for concurrent testing."""
    pool_size = getattr(request, "param", 10)  # Default 10 connections

    connections = []
    for _ in range(pool_size):
        conn = await psycopg.AsyncConnection.connect(
            db_connection_string, row_factory=dict_row
        )
        await conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        await conn.commit()
        connections.append(conn)

    yield connections

    # Cleanup
    for conn in connections:
        await conn.rollback()
        await conn.close()


@pytest.fixture(scope="function")
def isolated_schema(sync_conn: psycopg.Connection) -> Generator[str, None, None]:
    """Create an isolated schema for a test, clean up afterward."""
    import uuid

    schema_name = f"chaos_test_{uuid.uuid4().hex[:8]}"

    sync_conn.execute(f"CREATE SCHEMA {schema_name}")
    sync_conn.execute(f"SET search_path TO {schema_name}, public")
    sync_conn.commit()

    try:
        yield schema_name
    finally:
        # Always cleanup, even if test fails
        try:
            sync_conn.execute("SET search_path TO public")
            sync_conn.execute(f"DROP SCHEMA IF EXISTS {schema_name} CASCADE")
            sync_conn.commit()
        except Exception as e:
            # Log cleanup failure but don't raise (cleanup is best-effort)
            print(f"Warning: Failed to cleanup schema {schema_name}: {e}")


@pytest.fixture(scope="function")
async def async_isolated_schema(
    async_conn: psycopg.AsyncConnection,
) -> AsyncGenerator[str, None]:
    """Create an isolated schema for an async test, clean up afterward."""
    schema_name = f"chaos_test_{uuid.uuid4().hex[:8]}"

    await async_conn.execute(f"CREATE SCHEMA {schema_name}")
    await async_conn.execute(f"SET search_path TO {schema_name}, public")
    await async_conn.commit()

    yield schema_name

    # Cleanup
    await async_conn.execute("SET search_path TO public")
    await async_conn.execute(f"DROP SCHEMA IF EXISTS {schema_name} CASCADE")
    await async_conn.commit()


@pytest.fixture(scope="function")
def temp_table(sync_conn: psycopg.Connection) -> Generator[str, None, None]:
    """Create a temporary table for testing, clean up afterward."""
    table_name = f"temp_chaos_{uuid.uuid4().hex[:8]}"

    sync_conn.execute(
        f"CREATE TEMP TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)"
    )
    sync_conn.commit()

    yield table_name

    # Cleanup handled automatically by PostgreSQL for temp tables
    sync_conn.rollback()


@pytest.fixture(scope="function")
async def async_temp_table(
    async_conn: psycopg.AsyncConnection,
) -> AsyncGenerator[str, None]:
    """Create a temporary table for async testing, clean up afterward."""
    table_name = f"temp_chaos_{uuid.uuid4().hex[:8]}"

    await async_conn.execute(
        f"CREATE TEMP TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)"
    )
    await async_conn.commit()

    yield table_name

    # Cleanup handled automatically by PostgreSQL for temp tables
    await async_conn.rollback()


@pytest.fixture(scope="session")
def chaos_test_db_setup(db_connection_string: str):
    """Set up the chaos test database once per session."""
    # Create database if it doesn't exist
    admin_conn_string = db_connection_string.replace("pggit_chaos_test", "postgres")

    try:
        with psycopg.connect(admin_conn_string) as conn:
            conn.execute("CREATE DATABASE pggit_chaos_test")
            conn.commit()
    except psycopg.errors.DuplicateDatabase:
        # Database already exists
        pass

    # Verify the test database exists and is accessible
    with psycopg.connect(db_connection_string) as conn:
        conn.execute("SELECT 1")
        conn.commit()


@pytest.fixture(scope="function")
def chaos_cleanup(sync_conn: psycopg.Connection):
    """Ensure clean state for each chaos test."""
    # Reset any session-level state
    sync_conn.execute("RESET ALL")
    sync_conn.execute(
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED"
    )
    sync_conn.commit()

    yield

    # Final cleanup
    sync_conn.execute("RESET ALL")
    sync_conn.rollback()
