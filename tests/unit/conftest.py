"""
Unit test fixtures and configuration.

Unit tests focus on:
- Individual functions and classes
- No database access required
- Fast execution (< 1s per test)
- Mocked dependencies

Pytest markers:
- @pytest.mark.unit - Marks test as unit test
"""

import pytest


# Unit test marker
def pytest_configure(config):
    """Register custom pytest markers."""
    config.addinivalue_line(
        "markers", "unit: mark test as unit test (not requiring database)"
    )


@pytest.fixture(scope="session")
def unit_test_marker():
    """Session-scoped marker for all unit tests."""
    yield "unit"


@pytest.fixture
def mock_data():
    """Provide mock data for unit tests."""
    return {
        "branch": {
            "id": 1,
            "name": "main",
            "status": "ACTIVE",
        },
        "commit": {
            "id": 1,
            "hash": "abc123def456",
            "message": "Test commit",
            "author": "test-author",
        },
        "table": {
            "name": "test_table",
            "schema": "public",
            "columns": ["id", "name", "created_at"],
        },
    }


@pytest.fixture
def sample_strings():
    """Provide sample strings for unit tests."""
    return [
        "test-string-1",
        "test-string-2",
        "test-string-3",
        "branch-name-1",
        "branch-name-2",
    ]


@pytest.fixture
def sample_numbers():
    """Provide sample numbers for unit tests."""
    return list(range(1, 11))  # [1, 2, 3, ..., 10]


@pytest.fixture
def sample_dict():
    """Provide sample dictionary for unit tests."""
    return {
        "key1": "value1",
        "key2": "value2",
        "key3": {"nested": "value"},
        "key4": [1, 2, 3],
    }
