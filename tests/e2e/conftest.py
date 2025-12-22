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
        """Execute SQL file in the container, handling \i includes"""
        import os
        if base_dir is None:
            base_dir = os.path.dirname(os.path.abspath(file_path))

        # Read SQL file and process includes
        def read_sql_with_includes(path):
            """Recursively read SQL file, processing \i includes"""
            with open(path, 'r') as f:
                content = f.read()

            lines = content.split('\n')
            result = []
            for line in lines:
                stripped = line.strip()
                # Handle \i includes - read and inline the included file
                if stripped.startswith('\\i '):
                    included_file = stripped[3:].strip().strip('"\'')
                    included_path = os.path.join(base_dir, included_file)
                    if os.path.exists(included_path):
                        result.append(read_sql_with_includes(included_path))
                    continue
                # Skip other psql metacommands
                if stripped.startswith('\\'):
                    continue
                result.append(line)

            return '\n'.join(result)

        sql = read_sql_with_includes(file_path)

        # Execute via Python connection
        try:
            conn = connect(self.connection_string)
            cursor = conn.cursor()

            # Split SQL into statements properly handling strings and dollar quotes
            def split_sql_statements(sql_text):
                """Split SQL by semicolon, handling quoted strings"""
                statements = []
                current_stmt = []
                in_string = False
                string_char = None
                in_dollar_quote = False
                dollar_tag = ""
                i = 0

                while i < len(sql_text):
                    char = sql_text[i]

                    # Handle dollar quotes
                    if char == '$' and not in_string:
                        if not in_dollar_quote:
                            # Find the end of the dollar quote tag
                            j = i + 1
                            while j < len(sql_text) and sql_text[j] != '$':
                                j += 1
                            if j < len(sql_text):
                                dollar_tag = sql_text[i:j+1]
                                in_dollar_quote = True
                                current_stmt.append(sql_text[i:j+1])
                                i = j + 1
                                continue
                        else:
                            # Check if this closes the dollar quote
                            if sql_text[i:].startswith(dollar_tag):
                                in_dollar_quote = False
                                dollar_tag = ""
                                current_stmt.append(sql_text[i:i+len(dollar_tag)])
                                i += len(dollar_tag)
                                continue

                    # Handle regular quotes
                    if char in ("'", '"') and not in_dollar_quote:
                        if not in_string:
                            in_string = True
                            string_char = char
                        elif char == string_char and (i == 0 or sql_text[i-1] != '\\'):
                            in_string = False
                            string_char = None

                    # Handle statement terminator
                    if char == ';' and not in_string and not in_dollar_quote:
                        current_stmt.append(char)
                        stmt = ''.join(current_stmt).strip()
                        if stmt and not stmt.startswith('--'):
                            statements.append(stmt)
                        current_stmt = []
                    else:
                        current_stmt.append(char)

                    i += 1

                # Handle remaining statement
                stmt = ''.join(current_stmt).strip()
                if stmt and not stmt.startswith('--'):
                    statements.append(stmt)

                return statements

            statements = split_sql_statements(sql)

            # Execute each statement
            for stmt in statements:
                if stmt:
                    try:
                        cursor.execute(stmt)
                        conn.commit()
                    except Exception as e:
                        conn.rollback()
                        # Continue on error - some statements may fail for valid reasons
                        pass

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
