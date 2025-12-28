"""
Integration test fixtures for Phase 8 Week 2 API testing
"""

import os
import pytest
import asyncpg
from pathlib import Path
from datetime import datetime, timedelta
from httpx import AsyncClient, ASGITransport
from jose import jwt


def pytest_collection_modifyitems(items):
    """
    Modify test collection order to ensure Phase 8/merge tests run before Phase 6.

    This ensures the database schema with webhooks/alerts tables is set up first,
    preventing Phase 6 tests (which use a different conftest) from interfering.
    """
    def sort_key(item):
        # Run Phase 8 and merge tests first, then Phase 6
        if 'phase8' in item.nodeid or 'merge_api' in item.nodeid:
            return (0, item.nodeid)
        elif 'phase6' in item.nodeid:
            return (1, item.nodeid)
        else:
            return (2, item.nodeid)

    items.sort(key=sort_key)


@pytest.fixture(scope="session", autouse=True)
def setup_test_env():
    """
    Set up test environment variables required by the API.

    This runs once per test session before any tests run.
    """
    # Get database password from environment or use empty string for local trust auth
    db_password = os.getenv("PGPASSWORD") or os.getenv("DATABASE_PASSWORD") or ""

    test_env = {
        "DATABASE_HOST": os.getenv("PGHOST", "localhost"),
        "DATABASE_PORT": os.getenv("PGPORT", "5432"),
        "DATABASE_NAME": os.getenv("PGDATABASE", "pggit_test"),
        "DATABASE_USER": os.getenv("PGUSER", "postgres"),
        "DATABASE_PASSWORD": db_password,
        "JWT_SECRET_KEY": "test_jwt_secret_key_for_integration_tests_only_minimum_32_characters_required_for_security",
        "WEBHOOK_ENCRYPTION_KEY": "0123456789abcdef0123456789abcdef",  # 32 chars
        "WEBHOOK_SIGNING_SECRET": "test_webhook_signing_secret",
        "REDIS_HOST": "localhost",
        "REDIS_PORT": "6379",
        "CACHE_TYPE": "in-memory",  # Use in-memory cache for tests
        "API_HOST": "0.0.0.0",
        "API_PORT": "8080",
        "ENVIRONMENT": "test",
    }

    # Set environment variables for tests
    for key, value in test_env.items():
        os.environ.setdefault(key, value)

    yield

    # Cleanup is optional since these are test-specific values


@pytest.fixture(scope="session")
def db_schema_setup(setup_test_env):
    """
    Create and initialize test database with all Phase 1-8 schemas.

    This is a synchronous session-scoped fixture that runs once.
    """
    import psycopg
    from services.config import get_settings

    settings = get_settings()

    # Step 1: Create test database using psycopg (sync)
    try:
        with psycopg.connect(
            host=settings.database.host,
            port=settings.database.port,
            user=settings.database.user,
            password=settings.database.password,
            dbname="postgres",
            autocommit=True,
        ) as conn:
            with conn.cursor() as cur:
                # Drop and recreate test database
                cur.execute(f"DROP DATABASE IF EXISTS {settings.database.database}")
                cur.execute(f"CREATE DATABASE {settings.database.database}")
    except Exception as e:
        print(f"Error creating test database: {e}")
        raise

    # Step 2: Initialize schema
    try:
        with psycopg.connect(
            host=settings.database.host,
            port=settings.database.port,
            user=settings.database.user,
            password=settings.database.password,
            dbname=settings.database.database,
            autocommit=True,
        ) as conn:
            with conn.cursor() as cur:
                # Load all schema files in order
                schema_files = [
                    # Phase 1: Core schema
                    "sql/v1.0.0/phase_1_schema.sql",
                    "sql/v1.0.0/phase_1_utilities.sql",
                    "sql/v1.0.0/phase_1_triggers.sql",
                    "sql/v1.0.0/phase_1_bootstrap.sql",
                    # Phase 2-6: Additional schemas
                    "sql/030_pggit_branch_management.sql",
                    "sql/031_pggit_object_tracking.sql",
                    "sql/032_pggit_merge_operations.sql",
                    "sql/033_pggit_history_audit.sql",
                    "sql/034_pggit_rollback_operations.sql",
                    # Minimal API tables for testing (webhooks, alerts)
                    "sql/v1.0.0/test_api_tables.sql",
                    # NOTE: Phase 7+ schemas skipped for now due to FK/data issues
                    # Will be fixed in separate commit
                    # TODO: Fix branch_id references and bootstrap data constraints
                ]

                for schema_file in schema_files:
                    file_path = Path(schema_file)
                    if file_path.exists():
                        print(f"Loading schema: {schema_file}")
                        try:
                            with open(file_path, "r") as f:
                                cur.execute(f.read())
                        except Exception as e:
                            print(f"ERROR loading {schema_file}: {e}")
                            raise
                    else:
                        print(f"Warning: Schema file not found: {schema_file}")
    except Exception as e:
        print(f"Error initializing schema: {e}")
        raise

    yield settings.database.url

    # Cleanup: Drop test database after all tests
    try:
        with psycopg.connect(
            host=settings.database.host,
            port=settings.database.port,
            user=settings.database.user,
            password=settings.database.password,
            dbname="postgres",
            autocommit=True,
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(f"DROP DATABASE IF EXISTS {settings.database.database}")
    except Exception as e:
        print(f"Error dropping test database: {e}")


@pytest.fixture(scope="function")
async def db_pool(db_schema_setup):
    """
    Create asyncpg connection pool for each test.

    This uses the database initialized by db_schema_setup.
    """
    # Create asyncpg pool
    pool = await asyncpg.create_pool(
        dsn=db_schema_setup,
        min_size=2,
        max_size=10,
        command_timeout=10,
    )

    yield pool

    # Cleanup: Close pool
    await pool.close()


def create_test_token(user_id: str = "test_user", expires_minutes: int = 30) -> str:
    """
    Create a test JWT token for authentication.

    Args:
        user_id: User identifier
        expires_minutes: Token expiration time in minutes

    Returns:
        JWT token string
    """
    from services.config import get_settings

    settings = get_settings()
    expire = datetime.utcnow() + timedelta(minutes=expires_minutes)

    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": datetime.utcnow(),
    }

    token = jwt.encode(
        payload,
        settings.jwt.secret_key,
        algorithm=settings.jwt.algorithm,
    )

    return token


@pytest.fixture(scope="function")
async def client(db_pool):
    """
    Create an async HTTP client for testing the FastAPI application.

    This fixture:
    1. Overrides the database dependency with the test pool
    2. Initializes cache for testing
    3. Provides a properly configured AsyncClient with authentication
    4. Cleans up after each test

    Scope: function - Each test gets a fresh client instance
    """
    from api.main import app
    import services.dependencies as deps
    from services.cache import init_cache, shutdown_cache
    from services.config import get_settings

    # Override the global pool with test pool
    original_pool = deps._pool
    deps._pool = db_pool

    # Initialize cache for tests (in-memory only)
    settings = get_settings()
    await init_cache(settings.cache)

    # Create test JWT token
    test_token = create_test_token()

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {test_token}"},
        ) as client:
            yield client
    finally:
        # Cleanup
        await shutdown_cache()
        deps._pool = original_pool
