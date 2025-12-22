"""
Integration test fixtures and configuration.

Integration tests focus on:
- Multiple components working together
- Database access required
- Moderate execution speed (< 10s per test)
- Real database state validation

Pytest markers:
- @pytest.mark.integration - Marks test as integration test
"""

import pytest


# Integration test marker
def pytest_configure(config):
    """Register custom pytest markers."""
    config.addinivalue_line(
        "markers", "integration: mark test as integration test (requires database)"
    )


@pytest.fixture(scope="session")
def integration_test_marker():
    """Session-scoped marker for all integration tests."""
    yield "integration"


@pytest.fixture
def integration_db():
    """Provide database fixture for integration tests."""
    from tests.fixtures import DatabaseFixture

    # In actual use, this would be populated from a shared test database
    # For now, provide a placeholder that tests can use
    return {
        "connection_string": None,
        "fixture": None,
    }


@pytest.fixture
def schema_factory():
    """Provide schema creation utilities for integration tests."""
    def create_test_table(db_fixture, schema: str, table_name: str, columns: list):
        """Helper to create test tables with standard schema."""
        column_defs = ", ".join(
            [f"{name} {type_}" for name, type_ in columns]
        )
        query = f"CREATE TABLE {schema}.{table_name} ({column_defs})"
        db_fixture.execute(query)
        return f"{schema}.{table_name}"

    return {
        "create_test_table": create_test_table,
    }


@pytest.fixture
def cleanup_tables():
    """Fixture to track and cleanup tables created during tests."""
    tables = []

    def register_table(full_name: str):
        """Register a table for cleanup."""
        tables.append(full_name)

    def cleanup():
        """Clean up all registered tables."""
        # Will be called in teardown
        return tables

    cleanup.register_table = register_table
    return cleanup
