"""
Shared fixtures for E2E tests
Provides Docker setup, database connection, and pgGit installation
"""

import subprocess
import threading
import time

import docker
import pytest
from psycopg import connect
from psycopg_pool import ConnectionPool

from tests.fixtures.pooled_database import PooledDatabaseFixture


class DockerPostgresSetup:
    """Manages PostgreSQL Docker container for testing"""

    def __init__(self):
        self.client = docker.from_env()
        self.container = None
        self.connection_string = None

    def start_container(self) -> str:
        """Start a fresh PostgreSQL container and return connection string"""
        # Remove existing test container if it exists
        try:
            existing = self.client.containers.get("pggit-e2e-test")
            existing.remove(force=True)
        except docker.errors.NotFound:
            pass

        # Start new container
        self.container = self.client.containers.run(
            "postgres:17-alpine",
            name="pggit-e2e-test",
            environment={
                "POSTGRES_USER": "postgres",
                "POSTGRES_PASSWORD": "postgres",
                "POSTGRES_DB": "pggit_test",
            },
            ports={"5432/tcp": 5433},
            detach=True,
            remove=False,
        )

        # Wait for PostgreSQL to be ready
        max_retries = 30
        for attempt in range(max_retries):
            try:
                conn = connect(
                    "postgresql://postgres:postgres@localhost:5433/pggit_test"
                )
                conn.close()
                self.connection_string = (
                    "postgresql://postgres:postgres@localhost:5433/pggit_test"
                )
                return self.connection_string
            except Exception:
                if attempt < max_retries - 1:
                    time.sleep(1)
                else:
                    raise Exception("PostgreSQL container failed to start")

    def stop_container(self):
        """Stop and remove the test container"""
        if self.container:
            try:
                self.container.remove(force=True)
            except Exception:
                pass

    def exec_sql_file(self, file_path: str, base_dir: str = None) -> None:
        """Execute SQL file via psql which properly handles all SQL syntax"""
        import os
        from urllib.parse import urlparse

        try:
            # Parse connection string
            parsed = urlparse(self.connection_string)
            user = parsed.username or "postgres"
            password = parsed.password or "postgres"
            host = parsed.hostname or "localhost"
            port = str(parsed.port) if parsed.port else "5432"
            dbname = parsed.path.lstrip("/") or "pggit_test"

            env = os.environ.copy()
            env["PGPASSWORD"] = password

            # Get the directory containing the SQL file for psql includes to work
            sql_dir = os.path.dirname(os.path.abspath(file_path))
            abs_file_path = os.path.abspath(file_path)

            # Run psql from the sql directory so \i includes work with relative paths
            result = subprocess.run(
                [
                    "psql",
                    "-h",
                    host,
                    "-p",
                    port,
                    "-U",
                    user,
                    "-d",
                    dbname,
                    "-f",
                    abs_file_path,
                ],
                env=env,
                cwd=sql_dir,  # Change to sql directory for includes
                capture_output=True,
                text=True,
                timeout=60,
            )

            print(f"DEBUG: PSQL executed from {sql_dir}")
            print(f"Return code: {result.returncode}")
            if result.returncode != 0:
                print(f"STDERR: {result.stderr[:2000]}")
                print(f"STDOUT: {result.stdout[:1000]}")
            elif result.stderr:
                # Check for critical errors in stderr
                stderr_lines = result.stderr.split("\n")
                critical_errors = [
                    line
                    for line in stderr_lines
                    if "ERROR" in line
                    and (
                        "060_time_travel" in line or "create_temporal_snapshot" in line
                    )
                ]
                if critical_errors:
                    print(f"⚠️ Critical errors found in schema installation:")
                    for error in critical_errors[:5]:
                        print(f"  {error}")
                else:
                    print(f"STDERR (non-fatal): {result.stderr[:500]}")

        except Exception as e:
            raise Exception(f"SQL file execution failed: {str(e)}")


class E2ETestFixture:
    """Fixture managing test database connection"""

    _local = threading.local()

    def __init__(self, connection_string: str):
        self.connection_string = connection_string
        self.in_test_transaction = False

    def connect(self):
        """Establish database connection"""
        import threading

        thread_id = threading.current_thread().ident

        # Use thread ID as key for thread-safe connections
        conn_key = f"conn_{thread_id}"
        if not hasattr(self._local, conn_key) or getattr(self._local, conn_key) is None:
            setattr(self._local, conn_key, connect(self.connection_string))
        return getattr(self._local, conn_key)

    @property
    def conn(self):
        """Get thread-local connection"""
        import threading

        thread_id = threading.current_thread().ident
        conn_key = f"conn_{thread_id}"
        return getattr(self._local, conn_key, None)

    def execute(self, query: str, *args):
        """Execute a query and return results

        Returns results for SELECT, SHOW, and other queries that produce results.
        Automatically commits unless it's a transaction control statement or in test transaction.
        """
        # Get or create thread-local connection
        conn = self.connect()

        cursor = conn.cursor()
        cursor.execute(query, args)

        # Don't auto-commit transaction control statements or when in test transaction
        query_upper = query.strip().upper()
        if (
            query_upper not in ("BEGIN", "COMMIT", "ROLLBACK")
            and not self.in_test_transaction
        ):
            conn.commit()

        # Return results for queries that produce output
        # This includes SELECT, SHOW, EXPLAIN, WITH ... SELECT, etc.
        if (
            query_upper.startswith("SELECT")
            or query_upper.startswith("SHOW")
            or query_upper.startswith("WITH")
            or query_upper.startswith("EXPLAIN")
            or cursor.description is not None
        ):  # Has result columns
            try:
                return cursor.fetchall()
            except Exception:
                # Query didn't produce results (e.g., DDL)
                return None
        return None

    def execute_returning(self, query: str, *args):
        """Execute query that returns a single row as tuple"""
        # Get or create thread-local connection
        conn = self.connect()

        try:
            cursor = conn.cursor()
            cursor.execute(query, args)
            result = cursor.fetchone()
            # Only commit if not in a test transaction
            if not self.in_test_transaction:
                conn.commit()
            return result
        except Exception as e:
            # Only rollback if not in a test transaction (let fixture handle it)
            if not self.in_test_transaction:
                conn.rollback()
            raise Exception(f"Query failed: {query} with args {args}") from e

    def close(self):
        """Close all thread-local database connections"""
        import threading

        # Close all connections for all threads
        for attr_name in dir(self._local):
            if attr_name.startswith("conn_"):
                try:
                    conn = getattr(self._local, attr_name)
                    if conn:
                        conn.close()
                except Exception:
                    pass
                setattr(self._local, attr_name, None)


@pytest.fixture(scope="session")
def docker_setup():
    """Session-scoped fixture for Docker container"""
    setup = DockerPostgresSetup()
    conn_str = setup.start_container()
    print(f"\n✅ PostgreSQL container started: {conn_str}")
    yield setup
    setup.stop_container()
    print("\n✅ PostgreSQL container cleaned up")


@pytest.fixture(scope="session")
def pggit_installed(docker_setup):
    """Install pggit extension in the test database"""
    # Execute install script
    docker_setup.exec_sql_file("sql/install.sql")
    print("\n✅ pgGit extension installed")

    # Verify critical functions exist
    try:
        from psycopg import connect

        conn = connect(docker_setup.connection_string)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT proname FROM pg_proc
            WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit')
            AND proname = 'create_temporal_snapshot'
        """)
        result = cursor.fetchone()
        if result:
            print(f"✅ Verified: create_temporal_snapshot function exists")
        else:
            print("⚠️ WARNING: create_temporal_snapshot function NOT found!")
        conn.close()
    except Exception as e:
        print(f"⚠️ Could not verify functions: {e}")

    yield
    # Cleanup is handled by container removal


@pytest.fixture(scope="session")
def e2e_pool(docker_setup, pggit_installed) -> ConnectionPool:
    """Session-scoped connection pool for E2E tests."""
    pool = ConnectionPool(
        conninfo=docker_setup.connection_string,
        min_size=2,
        max_size=10,
        timeout=30,
        open=True,
    )
    print(f"\n✅ Connection pool initialized: min_size=2, max_size=10")
    yield pool
    pool.close()
    print("\n✅ Connection pool closed")


@pytest.fixture
def db(e2e_pool) -> PooledDatabaseFixture:
    """Fixture providing test database connection with transaction isolation"""
    fixture = PooledDatabaseFixture(e2e_pool, transaction_isolation=True)

    # Ensure commits table exists (required for tests)
    try:
        fixture.execute("""
            CREATE TABLE IF NOT EXISTS pggit.commits (
                id SERIAL PRIMARY KEY,
                hash TEXT NOT NULL UNIQUE DEFAULT (md5(random()::text)),
                branch_id INTEGER NOT NULL REFERENCES pggit.branches(id),
                parent_commit_hash TEXT,
                message TEXT,
                author TEXT DEFAULT CURRENT_USER,
                authored_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                committer TEXT DEFAULT CURRENT_USER,
                committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                tree_hash TEXT,
                metadata JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
    except Exception:
        pass  # Table might already exist

    # Create main branch if it doesn't exist (required for tests)
    try:
        fixture.execute(
            "INSERT INTO pggit.branches (name, status) VALUES ('main', 'ACTIVE')"
        )
    except Exception:
        pass  # Branch might already exist

    # Start a transaction for test isolation
    try:
        fixture.begin_transaction()
    except Exception:
        fixture.in_test_transaction = False

    yield fixture

    # Rollback the transaction to undo all test changes
    fixture.rollback_transaction()
