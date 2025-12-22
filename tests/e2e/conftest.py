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

    def exec_sql_file(self, file_path: str) -> None:
        """Execute SQL file in the container"""
        # Read SQL file
        with open(file_path, 'r') as f:
            lines = f.readlines()

        # Filter out psql-specific commands
        sql_lines = []
        for line in lines:
            # Skip psql metacommands (lines starting with \)
            if not line.strip().startswith('\\'):
                sql_lines.append(line)

        sql = ''.join(sql_lines)

        # Execute via Python connection
        try:
            conn = connect(self.connection_string)
            cursor = conn.cursor()
            # Split by semicolon and execute each statement
            for statement in sql.split(';'):
                statement = statement.strip()
                # Skip empty statements
                if statement:
                    cursor.execute(statement)
            conn.commit()
            conn.close()
        except Exception as e:
            raise Exception(f"SQL execution failed: {str(e)}")


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
        """Execute query that returns values"""
        if not self.conn:
            self.connect()

        cursor = self.conn.cursor()
        cursor.execute(query, args)
        result = cursor.fetchone()
        self.conn.commit()
        return result

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
def db(docker_setup):
    """Fixture providing test database connection"""
    fixture = E2ETestFixture(docker_setup.connection_string)
    fixture.connect()
    yield fixture
    fixture.close()
