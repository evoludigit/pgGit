"""
Shared fixtures for E2E tests
Provides Docker setup, database connection, and pgGit installation
"""

import subprocess
import time

import docker
import pytest
from psycopg import connect


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
            "postgres:16-alpine",
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
            if result.returncode != 0 and result.stderr:
                print(f"STDERR: {result.stderr[:300]}")

        except Exception as e:
            raise Exception(f"SQL file execution failed: {str(e)}")


class E2ETestFixture:
    """Fixture managing test database connection"""

    def __init__(self, connection_string: str):
        self.connection_string = connection_string
        self.conn = None

    def connect(self):
        """Establish database connection"""
        self.conn = connect(self.connection_string)
        return self.conn

    def execute(self, query: str, *args):
        """Execute a query and return results"""
        if not self.conn:
            self.connect()

        cursor = self.conn.cursor()
        cursor.execute(query, args)
        self.conn.commit()

        # Return results if it's a SELECT query
        if query.strip().upper().startswith("SELECT"):
            return cursor.fetchall()
        return None

    def execute_returning(self, query: str, *args):
        """Execute query that returns a single row as tuple"""
        if not self.conn:
            self.connect()

        try:
            cursor = self.conn.cursor()
            cursor.execute(query, args)
            result = cursor.fetchone()
            self.conn.commit()
            return result
        except Exception as e:
            self.conn.rollback()
            raise Exception(f"Query failed: {query} with args {args}") from e

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()


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
    yield
    # Cleanup is handled by container removal


@pytest.fixture
def db(docker_setup, pggit_installed):
    """Fixture providing test database connection"""
    fixture = E2ETestFixture(docker_setup.connection_string)
    fixture.connect()

    # Create main branch if it doesn't exist (required for tests)
    try:
        fixture.execute(
            "INSERT INTO pggit.branches (name, status) VALUES ('main', 'ACTIVE')"
        )
    except Exception as e:
        # Branch might already exist, rollback and continue
        fixture.conn.rollback()

    yield fixture
    fixture.close()
