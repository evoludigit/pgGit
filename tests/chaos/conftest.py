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

import uuid
from collections.abc import AsyncGenerator, Generator

import psycopg
import pytest
from psycopg.rows import dict_row


# Pytest configuration
def pytest_configure(config):
    """Register custom markers for chaos tests."""
    config.addinivalue_line("markers", "chaos: mark test as chaos engineering test")
    config.addinivalue_line("markers", "slow: mark test as slow (may take >30s)")
    config.addinivalue_line("markers", "concurrent: mark test as testing concurrency")
    config.addinivalue_line(
        "markers",
        "destructive: mark test as potentially destructive",
    )
    config.addinivalue_line("markers", "property: mark test as property-based test")
    config.addinivalue_line("markers", "performance: mark test as performance test")
    config.addinivalue_line("markers", "transaction: mark test as transaction test")
    config.addinivalue_line("markers", "constraints: mark test as constraint test")
    config.addinivalue_line("markers", "crash: mark test as crash recovery test")
    config.addinivalue_line("markers", "partial_failure: mark test as partial failure test")
    config.addinivalue_line("markers", "resource: mark test as resource exhaustion test")
    config.addinivalue_line("markers", "load: mark test as load stress test")
    config.addinivalue_line("markers", "migration: mark test as migration failure test")
    config.addinivalue_line("markers", "corruption: mark test as schema corruption test")
    config.addinivalue_line("markers", "integrity: mark test as data integrity test")
    config.addinivalue_line("markers", "recovery: mark test as recovery procedure test")


def function_exists(db_connection_string: str, function_name: str) -> bool:
    """Check if a pggit function exists in the database."""
    try:
        with psycopg.connect(db_connection_string) as conn:
            cursor = conn.execute(
                "SELECT EXISTS (SELECT 1 FROM information_schema.routines "
                "WHERE routine_schema = 'pggit' AND routine_name = %s)",
                (function_name,),
            )
            return cursor.fetchone()[0]
    except psycopg.Error:
        return False


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


@pytest.fixture(scope="function", autouse=True)
def cleanup_test_tables(db_connection_string: str):
    """Clean up test tables before each test function runs."""
    with psycopg.connect(db_connection_string, autocommit=True) as conn:
        try:
            # Drop tables that might be created by chaos tests
            # Be very aggressive about cleaning up test tables
            cursor = conn.execute("""
                SELECT tablename FROM pg_tables
                WHERE schemaname = 'public'
                AND (
                    tablename LIKE 'test_table_%' OR
                    tablename LIKE '%_%' OR  -- Tables with underscores (generated names)
                    tablename ~ '^[a-z_]+_[0-9]+$' OR  -- name_number pattern
                    length(tablename) <= 15  -- Short table names
                )
                AND tablename NOT LIKE 'pg_%'  -- Don't drop system tables
                AND tablename NOT LIKE 'pggit%'  -- Don't drop pggit tables
                AND tablename NOT IN ('spatial_ref_sys')  -- Don't drop PostGIS tables
            """)
            test_tables = cursor.fetchall()

            for row in test_tables:
                table_name = row[0]  # tablename is first column
                try:
                    conn.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE")
                except psycopg.Error:
                    pass  # Ignore errors during cleanup
        except psycopg.Error:
            pass  # Ignore errors if cleanup query fails


@pytest.fixture
def sync_conn(db_connection_string: str) -> Generator[psycopg.Connection, None, None]:
    """Synchronous database connection for a single test."""
    # First check schema without dict_row to avoid KeyError
    with psycopg.connect(db_connection_string) as check_conn:
        cursor = check_conn.execute(
            "SELECT EXISTS (SELECT 1 FROM information_schema.schemata "
            "WHERE schema_name = 'pggit')"
        )
        if not cursor.fetchone()[0]:
            raise RuntimeError(
                "pggit schema not found. Please install: cd sql && "
                "psql -d pggit_chaos_test -f install.sql"
            )

    # Now create the actual connection with dict_row
    # Note: autocommit=True is set to prevent transaction state issues between hypothesis examples,
    # but tests can override this with explicit BEGIN/COMMIT if needed
    with psycopg.connect(
        db_connection_string,
        row_factory=dict_row,
    ) as conn:
        # Set autocommit to avoid issues with hypothesis examples
        conn.autocommit = True

        # Aggressive cleanup before yielding connection to prevent table collisions
        # This runs before each test, including between hypothesis examples
        try:
            # Clean up test tables that might be left over from previous runs
            cursor = conn.execute("""
                SELECT tablename FROM pg_tables
                WHERE schemaname = 'public'
                AND (tablename LIKE 'test_%' OR tablename LIKE '%_test%' OR
                     tablename LIKE 'a_%' OR tablename LIKE 'x%' OR
                     tablename ~ '^[a-z_]+_[0-9]+$' OR
                     length(tablename) <= 20)
                AND tablename NOT LIKE 'pg_%'
                AND tablename NOT LIKE 'pggit%'
                AND tablename NOT IN ('spatial_ref_sys')
            """)
            test_tables = cursor.fetchall()

            for row in test_tables:
                table_name = row["tablename"]
                try:
                    conn.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE")
                except psycopg.Error:
                    pass  # Ignore errors during cleanup
        except psycopg.Error:
            pass  # Ignore errors if cleanup query fails

        yield conn


@pytest.fixture
def sync_conn_with_transactions(
    db_connection_string: str,
) -> Generator[psycopg.Connection, None, None]:
    """Synchronous database connection that allows explicit transaction control."""
    # First check schema without dict_row to avoid KeyError
    with psycopg.connect(db_connection_string) as check_conn:
        cursor = check_conn.execute(
            "SELECT EXISTS (SELECT 1 FROM information_schema.schemata "
            "WHERE schema_name = 'pggit')"
        )
        if not cursor.fetchone()[0]:
            raise RuntimeError(
                "pggit schema not found. Please install: cd sql && "
                "psql -d pggit_chaos_test -f install.sql"
            )

    # Create connection without autocommit for explicit transaction control
    with psycopg.connect(
        db_connection_string,
        row_factory=dict_row,
    ) as conn:
        # Explicitly disable autocommit for transaction control
        conn.autocommit = False
        yield conn


@pytest.fixture
async def async_conn(
    db_connection_string: str,
) -> AsyncGenerator[psycopg.AsyncConnection, None]:
    """Asynchronous database connection for a single test."""
    async with await psycopg.AsyncConnection.connect(
        db_connection_string,
        row_factory=dict_row,
    ) as conn:
        # Verify pggit schema exists (should be pre-installed)
        cursor = await conn.execute(
            "SELECT EXISTS (SELECT 1 FROM information_schema.schemata "
            "WHERE schema_name = 'pggit')",
        )
        result = await cursor.fetchone()
        if not list(result.values())[0]:
            msg = (
                "pggit schema not found. Please install: cd sql && "
                "psql -d pggit_chaos_test -f install.sql"
            )
            raise RuntimeError(msg)

        yield conn

        # Cleanup
        await conn.rollback()


@pytest.fixture
def conn_pool(
    db_connection_string: str,
    request,
) -> Generator[list[psycopg.Connection], None, None]:
    """Pool of synchronous database connections for concurrent testing."""
    pool_size = getattr(request, "param", 10)  # Default 10 connections

    connections = []
    for _ in range(pool_size):
        conn = psycopg.connect(db_connection_string, row_factory=dict_row)
        # No need to create extension, just verify schema exists
        connections.append(conn)

    yield connections

    # Cleanup
    for conn in connections:
        conn.rollback()
        conn.close()


@pytest.fixture
async def async_conn_pool(
    db_connection_string: str,
    request,
) -> AsyncGenerator[list[psycopg.AsyncConnection], None]:
    """Pool of asynchronous database connections for concurrent testing."""
    pool_size = getattr(request, "param", 10)  # Default 10 connections

    connections = []
    for _ in range(pool_size):
        conn = await psycopg.AsyncConnection.connect(
            db_connection_string,
            row_factory=dict_row,
        )
        await conn.commit()
        connections.append(conn)

    yield connections

    # Cleanup
    for conn in connections:
        await conn.rollback()
        await conn.close()


@pytest.fixture
def isolated_schema(sync_conn: psycopg.Connection) -> Generator[str, None, None]:
    """Create an isolated schema for a test, clean up afterward."""

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
        except psycopg.Error:
            # Cleanup is best-effort, don't raise on failure
            pass


@pytest.fixture
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


@pytest.fixture
def temp_table(sync_conn: psycopg.Connection) -> Generator[str, None, None]:
    """Create a temporary table for testing, clean up afterward."""
    table_name = f"temp_chaos_{uuid.uuid4().hex[:8]}"

    sync_conn.execute(
        f"CREATE TEMP TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)",
    )
    sync_conn.commit()

    yield table_name

    # Cleanup handled automatically by PostgreSQL for temp tables
    sync_conn.rollback()


@pytest.fixture
async def async_temp_table(
    async_conn: psycopg.AsyncConnection,
) -> AsyncGenerator[str, None]:
    """Create a temporary table for async testing, clean up afterward."""
    table_name = f"temp_chaos_{uuid.uuid4().hex[:8]}"

    await async_conn.execute(
        f"CREATE TEMP TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)",
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


@pytest.fixture
def chaos_cleanup(sync_conn: psycopg.Connection):
    """Ensure clean state for each chaos test."""
    # Reset any session-level state
    sync_conn.execute("RESET ALL")
    sync_conn.execute(
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED",
    )
    sync_conn.commit()

    yield

    # Final cleanup
    sync_conn.execute("RESET ALL")
    sync_conn.rollback()
