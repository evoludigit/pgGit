"""
Shared pytest configuration for pgGit tests
"""
import os
import subprocess
import psycopg
from psycopg import sql
import pytest


@pytest.fixture(scope="session")
def db_connection_params():
    """Get database connection parameters from environment or defaults"""
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "port": int(os.getenv("PGPORT", "5432")),
        "user": os.getenv("PGUSER", "postgres"),
        "password": os.getenv("PGPASSWORD", ""),
        "dbname": os.getenv("PGDATABASE", "pggit_test"),
    }


@pytest.fixture(scope="session")
def test_db_setup(db_connection_params):
    """Create test database and initialize schema"""
    # Create database
    conn_params = db_connection_params.copy()
    dbname = conn_params.pop("dbname")

    try:
        # Connect to postgres to create test database
        with psycopg.connect(
            **conn_params,
            dbname="postgres",
            autocommit=True,
        ) as conn:
            with conn.cursor() as cur:
                # Drop existing test database if it exists
                cur.execute("DROP DATABASE IF EXISTS %s" % dbname)
                # Create fresh test database
                cur.execute("CREATE DATABASE %s" % dbname)
    except Exception as e:
        print(f"Error creating test database: {e}")
        raise

    # Initialize schema in test database
    conn_params["dbname"] = dbname

    try:
        with psycopg.connect(**conn_params, autocommit=True) as conn:
            with conn.cursor() as cur:
                # Read and execute schema files in order
                schema_files = [
                    "sql/v1.0.0/phase_1_schema.sql",
                    "sql/v1.0.0/phase_1_utilities.sql",
                    "sql/v1.0.0/phase_1_triggers.sql",
                    "sql/v1.0.0/phase_1_bootstrap.sql",
                    "sql/030_pggit_branch_management.sql",
                    "sql/031_pggit_object_tracking.sql",
                    "sql/032_pggit_merge_operations.sql",
                    "sql/033_pggit_history_audit.sql",
                    "sql/034_pggit_rollback_operations.sql",
                ]

                for schema_file in schema_files:
                    if os.path.exists(schema_file):
                        with open(schema_file, "r") as f:
                            cur.execute(f.read())
                    else:
                        print(f"Warning: Schema file not found: {schema_file}")
    except Exception as e:
        print(f"Error initializing schema: {e}")
        raise

    yield conn_params

    # Cleanup after all tests
    try:
        with psycopg.connect(
            **conn_params,
            autocommit=True,
        ) as conn:
            pass  # Connection established, database exists
        with psycopg.connect(
            **{**conn_params, "dbname": "postgres"},
            autocommit=True,
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(f"DROP DATABASE IF EXISTS {dbname}")
    except Exception as e:
        print(f"Error cleaning up test database: {e}")


@pytest.fixture
def db_conn(test_db_setup):
    """Get database connection for each test"""
    conn_params = test_db_setup
    conn = psycopg.connect(**conn_params)
    yield conn
    conn.close()


@pytest.fixture
def db_connection(test_db_setup):
    """Alias for db_conn to support different test styles"""
    conn_params = test_db_setup
    conn = psycopg.connect(**conn_params)
    yield conn
    conn.close()


@pytest.fixture
def test_db(test_db_setup):
    """Alias for db_conn to support different test styles"""
    conn_params = test_db_setup
    conn = psycopg.connect(**conn_params)
    yield conn
    conn.close()


@pytest.fixture
def db_cursor(db_conn):
    """Get database cursor for each test"""
    with db_conn.cursor() as cur:
        yield cur
    db_conn.rollback()  # Rollback changes after each test


@pytest.fixture
def execute_sql(db_conn):
    """Helper to execute SQL and fetch results"""
    def _execute(query, params=None):
        with db_conn.cursor() as cur:
            if params:
                cur.execute(query, params)
            else:
                cur.execute(query)
            try:
                return cur.fetchall()
            except:
                return None
    return _execute


@pytest.fixture
def clear_tables(db_conn):
    """Helper to clear test tables between tests"""
    def _clear():
        # Clear test-created data while preserving system bootstrap state
        tables = [
            "pggit.rollback_validations",
            "pggit.rollback_operations",
            "pggit.object_history",
            "pggit.merge_operations",
            "pggit.object_dependencies",
            "pggit.data_tables",
            "pggit.commits",
            # Note: Preserve branches and configuration tables for system state
            # "pggit.branches",
            # "pggit.schema_objects",
            # "pggit.configuration",
        ]
        with db_conn.cursor() as cur:
            for table in tables:
                try:
                    cur.execute(f"TRUNCATE TABLE {table} CASCADE")
                except:
                    pass

            # Explicitly clear test-created data (preserve bootstrap state)
            try:
                cur.execute("DELETE FROM pggit.object_dependencies")
                # Only delete schema_objects for non-pggit schemas
                cur.execute("DELETE FROM pggit.schema_objects WHERE schema_name != 'pggit'")
                # Keep initial system commit, delete test commits
                cur.execute("DELETE FROM pggit.commits WHERE commit_message NOT LIKE 'Initial commit%'")
                # Keep main branch, delete feature branches
                cur.execute("DELETE FROM pggit.branches WHERE branch_name != 'main'")
            except:
                pass
        db_conn.commit()
    return _clear
