"""
Integration test fixtures for Phase 8 Week 2 API testing
"""

import os
import pytest
from httpx import AsyncClient, ASGITransport
from unittest.mock import patch


@pytest.fixture(scope="session", autouse=True)
def setup_test_env():
    """
    Set up test environment variables required by the API.

    This runs once per test session before any tests run.
    """
    test_env = {
        "DATABASE_HOST": "localhost",
        "DATABASE_PORT": "5432",
        "DATABASE_NAME": "pggit_test",
        "DATABASE_USER": "postgres",
        "DATABASE_PASSWORD": "test_password",
        "JWT_SECRET_KEY": "test_jwt_secret_key_for_integration_tests_only",
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


@pytest.fixture(scope="function")
async def client():
    """
    Create an async HTTP client for testing the FastAPI application.

    This fixture provides a properly configured AsyncClient that uses
    ASGI transport to test the FastAPI app without requiring a running server.

    Scope: function - Each test gets a fresh client instance
    """
    from api.main import app

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield client
