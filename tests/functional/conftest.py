"""
pgGit Functional Tests - Shared Fixtures and Configuration

Provides:
- Database connection management
- Transaction fixtures for test isolation
- Test markers and configuration
- Database cleanup and setup helpers
"""

import os
import pytest
import psycopg
from contextlib import contextmanager


# Database Configuration
DB_HOST = os.getenv("PGHOST", "localhost")
DB_PORT = os.getenv("PGPORT", "5432")
DB_USER = os.getenv("PGUSER", "postgres")
DB_PASSWORD = os.getenv("PGPASSWORD", "")
DB_NAME = os.getenv("PGDATABASE", "postgres")

# Build connection string
CONN_STRING = f"postgresql://{DB_USER}"
if DB_PASSWORD:
    CONN_STRING += f":{DB_PASSWORD}"
CONN_STRING += f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"


def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests that test multiple modules together"
    )
    config.addinivalue_line(
        "markers", "requires_real_time: marks tests that can't use mocked time"
    )


@pytest.fixture(scope="session")
def db_session_connection():
    """Session-scoped database connection for setup/teardown"""
    try:
        conn = psycopg.connect(CONN_STRING)
        conn.autocommit = True
        yield conn
    finally:
        conn.close()


@pytest.fixture(scope="session", autouse=True)
def setup_test_database(db_session_connection):
    """Setup pgGit extension and test infrastructure once per session"""
    conn = db_session_connection

    try:
        # Check if pggit extension exists
        result = conn.execute(
            "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit'"
        ).fetchone()

        if not result:
            # Load pggit from source
            import subprocess
            result = subprocess.run(
                ["psql", "-f", "sql/install.sql"],
                cwd="/home/lionel/code/pggit",
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                print(f"Warning: pggit installation may have issues: {result.stderr}")
    except Exception as e:
        print(f"Warning: Could not verify pggit extension: {e}")

    yield

    # Cleanup (optional - comment out if you want to keep test data)
    # try:
    #     conn.execute("DROP SCHEMA IF EXISTS pggit CASCADE")
    # except Exception as e:
    #     print(f"Cleanup warning: {e}")


@pytest.fixture
def db_connection():
    """Per-test database connection"""
    conn = psycopg.connect(CONN_STRING)
    conn.autocommit = False  # For transaction control

    yield conn

    try:
        conn.close()
    except:
        pass


@pytest.fixture
def db_transaction(db_connection):
    """
    Per-test transaction fixture with automatic rollback

    Usage:
        def test_something(db_transaction):
            result = db_transaction.execute("SELECT 1")
            # Automatically rolled back after test
    """
    db_connection.execute("BEGIN;")

    yield db_connection

    # Always rollback - provides automatic cleanup
    try:
        db_connection.execute("ROLLBACK;")
    except:
        pass


@pytest.fixture
def clean_db(db_connection):
    """
    Clean database state fixture

    Clears test schemas and tables before and after test
    """
    # Setup: clear any previous test data
    try:
        db_connection.execute("""
            DROP SCHEMA IF EXISTS test_command CASCADE;
            DROP SCHEMA IF EXISTS test_query CASCADE;
            DROP SCHEMA IF EXISTS test_reference CASCADE;
            DROP SCHEMA IF EXISTS test_functions CASCADE;
            DROP SCHEMA IF EXISTS test_migrations CASCADE;
            DROP SCHEMA IF EXISTS test_conflicts CASCADE;
        """)
        db_connection.commit()
    except Exception as e:
        print(f"Setup cleanup warning: {e}")
        db_connection.rollback()

    # Begin test transaction
    db_connection.execute("BEGIN;")

    yield db_connection

    # Teardown: rollback transaction
    try:
        db_connection.execute("ROLLBACK;")
    except:
        pass


@contextmanager
def temporary_schema(db_connection, schema_name: str):
    """
    Context manager for creating and cleaning up temporary test schemas

    Usage:
        with temporary_schema(db, "my_schema") as schema:
            db.execute(f"CREATE TABLE {schema}.test_table (...)")
    """
    try:
        db_connection.execute(f"CREATE SCHEMA IF NOT EXISTS {schema_name}")
        yield schema_name
    finally:
        try:
            db_connection.execute(f"DROP SCHEMA IF EXISTS {schema_name} CASCADE")
        except:
            pass


@pytest.fixture
def execute_sql(db_connection):
    """
    Helper fixture for executing SQL queries

    Usage:
        def test_something(execute_sql):
            result = execute_sql("SELECT * FROM table")
            result_with_params = execute_sql("SELECT * FROM table WHERE id = %s", (123,))
    """
    def _execute(sql: str, params=None):
        try:
            if params:
                return db_connection.execute(sql, params)
            else:
                return db_connection.execute(sql)
        except Exception as e:
            raise AssertionError(f"SQL execution failed: {e}\nSQL: {sql}")

    return _execute


@pytest.fixture
def assert_table_exists(db_connection):
    """
    Helper fixture for asserting table existence

    Usage:
        def test_something(assert_table_exists):
            assert_table_exists("public", "my_table")
    """
    def _assert(schema: str, table: str):
        result = db_connection.execute("""
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = %s AND table_name = %s
        """, (schema, table)).fetchone()

        assert result is not None, \
            f"Table {schema}.{table} not found in information_schema"

    return _assert


@pytest.fixture
def assert_function_exists(db_connection):
    """
    Helper fixture for asserting function existence

    Usage:
        def test_something(assert_function_exists):
            assert_function_exists("pggit", "begin_deployment")
    """
    def _assert(schema: str, function: str):
        result = db_connection.execute("""
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = %s AND p.proname = %s
        """, (schema, function)).fetchone()

        assert result is not None, \
            f"Function {schema}.{function} not found in pg_proc"

    return _assert


@pytest.fixture
def assert_record_count(db_connection):
    """
    Helper fixture for asserting record counts

    Usage:
        def test_something(assert_record_count):
            assert_record_count("public.my_table", 10)
            assert_record_count("public.my_table", 5, "status = 'active'")
    """
    def _assert(table: str, expected: int, where_clause: str = None):
        sql = f"SELECT COUNT(*) as cnt FROM {table}"
        if where_clause:
            sql += f" WHERE {where_clause}"

        result = db_connection.execute(sql).fetchone()
        actual = result[0]

        assert actual == expected, \
            f"Table {table}: expected {expected} records, got {actual}"

    return _assert


@pytest.fixture
def get_record_value(db_connection):
    """
    Helper fixture for retrieving single values

    Usage:
        def test_something(get_record_value):
            value = get_record_value("SELECT COUNT(*) FROM table")
            status = get_record_value("SELECT status FROM users WHERE id = %s", (123,))
    """
    def _get(sql: str, params=None):
        try:
            if params:
                result = db_connection.execute(sql, params).fetchone()
            else:
                result = db_connection.execute(sql).fetchone()

            if result is None:
                return None
            return result[0]
        except Exception as e:
            raise AssertionError(f"SQL query failed: {e}\nSQL: {sql}")

    return _get
