"""Tests to validate fixture isolation guarantees.

These tests verify that each fixture provides proper test isolation as documented.
Run these tests first after adding new fixtures to ensure correct behavior.
"""

import pytest


@pytest.mark.db_unit
def test_db_unit_creates_table(db_unit):
    """Create table in first test with db_unit fixture."""
    db_unit.execute("CREATE TABLE isolation_test_unit (id INT)")
    result = db_unit.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'isolation_test_unit'"
    )
    assert result[0][0] == 1, "Table should have been created"


@pytest.mark.db_unit
def test_db_unit_table_rolled_back(db_unit):
    """Verify table from previous test was rolled back by transaction."""
    result = db_unit.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'isolation_test_unit'"
    )
    assert (
        result[0][0] == 0
    ), "Table should have been rolled back by transaction"


@pytest.mark.db_unit
def test_db_unit_data_isolated(db_unit):
    """Test data isolation in first test."""
    db_unit.execute("CREATE TABLE unit_data_test (id INT, value TEXT)")
    db_unit.execute("INSERT INTO unit_data_test VALUES (1, 'test')")
    result = db_unit.execute("SELECT COUNT(*) FROM unit_data_test")
    assert result[0][0] == 1, "One row should exist"


@pytest.mark.db_unit
def test_db_unit_data_isolated_clean(db_unit):
    """Verify data from previous test was rolled back."""
    # Table shouldn't exist (was created in previous test, rolled back)
    result = db_unit.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'unit_data_test'"
    )
    assert result[0][0] == 0, "Table should have been rolled back"


@pytest.mark.db_integration
def test_db_integration_creates_table(db_integration):
    """Create table in first test with db_integration fixture."""
    db_integration.execute("CREATE TABLE integration_test_table (id INT)")
    result = db_integration.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'integration_test_table'"
    )
    assert result[0][0] == 1, "Table should have been created"


@pytest.mark.db_integration
def test_db_integration_table_rolled_back(db_integration):
    """Verify table from previous test was rolled back by savepoint."""
    result = db_integration.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'integration_test_table'"
    )
    assert (
        result[0][0] == 0
    ), "Table should have been rolled back by savepoint"


@pytest.mark.db_integration
def test_db_integration_multi_table(db_integration):
    """Test multi-table operations with db_integration."""
    db_integration.execute("CREATE TABLE integration_users (id INT PRIMARY KEY, name TEXT)")
    db_integration.execute("CREATE TABLE integration_posts (id INT, user_id INT, title TEXT)")

    db_integration.execute("INSERT INTO integration_users VALUES (1, 'Alice')")
    db_integration.execute("INSERT INTO integration_posts VALUES (1, 1, 'First post')")

    result = db_integration.execute("SELECT COUNT(*) FROM integration_users")
    assert result[0][0] == 1, "Should have one user"

    result = db_integration.execute("SELECT COUNT(*) FROM integration_posts")
    assert result[0][0] == 1, "Should have one post"


@pytest.mark.db_integration
def test_db_integration_multi_table_rolled_back(db_integration):
    """Verify multi-table operations were rolled back."""
    result = db_integration.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name IN ('integration_users', 'integration_posts')"
    )
    assert result[0][0] == 0, "Tables should have been rolled back"


@pytest.mark.db_e2e
def test_db_e2e_creates_table(db_e2e):
    """Create table in first test with db_e2e fixture."""
    db_e2e.execute("CREATE TABLE e2e_test_table (id INT)")
    result = db_e2e.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'e2e_test_table'"
    )
    assert result[0][0] == 1, "Table should have been created"


@pytest.mark.db_e2e
def test_db_e2e_table_rolled_back(db_e2e):
    """Verify table from previous test was rolled back by savepoint."""
    result = db_e2e.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = 'e2e_test_table'"
    )
    assert result[0][0] == 0, "Table should have been rolled back"


@pytest.mark.db_e2e
def test_db_e2e_complex_workflow(db_e2e):
    """Test realistic workflow with db_e2e fixture."""
    # Setup
    db_e2e.execute("CREATE TABLE users (id INT PRIMARY KEY, name TEXT)")
    db_e2e.execute("CREATE TABLE posts (id INT PRIMARY KEY, user_id INT, title TEXT)")

    # Operations
    db_e2e.execute("INSERT INTO users VALUES (1, 'Alice')")
    db_e2e.execute("INSERT INTO posts VALUES (1, 1, 'First post')")

    # Verify
    result = db_e2e.execute("SELECT COUNT(*) FROM users")
    assert result[0][0] == 1

    result = db_e2e.execute("SELECT COUNT(*) FROM posts")
    assert result[0][0] == 1


@pytest.mark.db_e2e
def test_db_e2e_workflow_rolled_back(db_e2e):
    """Verify complex workflow was completely rolled back."""
    result = db_e2e.execute(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name IN ('users', 'posts')"
    )
    assert result[0][0] == 0, "Tables should have been rolled back"


@pytest.mark.db_load
def test_db_load_execute_timed(db_load):
    """Test db_load fixture timing capability."""
    # Execute some queries
    for _ in range(5):
        db_load.execute_timed("SELECT 1")

    # Verify metrics
    assert db_load.metrics["queries"] == 5, "Should have recorded 5 queries"
    assert db_load.metrics["time"] > 0, "Should have recorded positive time"

    # Cleanup
    db_load.cleanup()


@pytest.mark.db_load
def test_db_load_manual_cleanup(db_load):
    """Test that db_load allows manual cleanup."""
    db_load.execute("SELECT 1")
    assert db_load._conn is not None, "Connection should be active"

    # Manual cleanup
    db_load.cleanup()
    assert db_load._conn is None, "Connection should be released"


def test_isolation_tests_run_independently():
    """Meta test: these tests should all pass when run individually and together."""
    # This test just documents the expected behavior
    # pytest will verify all isolation tests pass
    assert True
