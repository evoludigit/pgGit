"""
Docker utilities for E2E testing.

Manages PostgreSQL Docker containers, lifecycle, and SQL file execution.

Features:
- Docker container lifecycle management
- PostgreSQL health checks and readiness verification
- SQL file execution via psql
- Connection string parsing and validation
"""

import os
import subprocess
import time
from urllib.parse import urlparse

import docker


class DockerPostgresSetup:
    """Manages PostgreSQL Docker container for E2E testing."""

    def __init__(self, image: str = "postgres:17-alpine", port: int = 5433):
        """
        Initialize Docker PostgreSQL container manager.

        Args:
            image: Docker image to use (default: postgres:17-alpine)
            port: Local port to bind to (default: 5433)
        """
        self.client = docker.from_env()
        self.container = None
        self.connection_string = None
        self.image = image
        self.port = port

    def start_container(self) -> str:
        """
        Start a fresh PostgreSQL container and return connection string.

        Removes existing test container if present, starts new one,
        and waits for PostgreSQL to be ready.

        Returns:
            PostgreSQL connection string (postgresql://user:password@host:port/db)

        Raises:
            Exception: If container fails to start or PostgreSQL doesn't become ready
        """
        # Remove existing test container if it exists
        try:
            existing = self.client.containers.get("pggit-e2e-test")
            existing.remove(force=True)
        except docker.errors.NotFound:
            pass

        # Start new container
        self.container = self.client.containers.run(
            self.image,
            name="pggit-e2e-test",
            environment={
                "POSTGRES_USER": "postgres",
                "POSTGRES_PASSWORD": "postgres",
                "POSTGRES_DB": "pggit_test",
            },
            ports={"5432/tcp": self.port},
            detach=True,
            remove=False,
        )

        # Wait for PostgreSQL to be ready
        max_retries = 30
        for attempt in range(max_retries):
            try:
                from psycopg import connect
                conn = connect(
                    f"postgresql://postgres:postgres@localhost:{self.port}/pggit_test"
                )
                conn.close()
                self.connection_string = (
                    f"postgresql://postgres:postgres@localhost:{self.port}/pggit_test"
                )
                return self.connection_string
            except Exception:
                if attempt < max_retries - 1:
                    time.sleep(1)
                else:
                    raise Exception("PostgreSQL container failed to start")

    def stop_container(self):
        """Stop and remove the test container."""
        if self.container:
            try:
                self.container.remove(force=True)
            except Exception:
                pass

    def is_ready(self) -> bool:
        """
        Check if PostgreSQL is ready for connections.

        Returns:
            True if connection successful, False otherwise
        """
        if not self.connection_string:
            return False

        try:
            from psycopg import connect
            conn = connect(self.connection_string)
            conn.close()
            return True
        except Exception:
            return False

    def exec_sql_file(self, file_path: str, base_dir: str = None) -> dict:
        """
        Execute SQL file via psql which properly handles all SQL syntax.

        Handles includes (\i) and all PostgreSQL-specific syntax.
        Returns execution results for verification.

        Args:
            file_path: Path to SQL file to execute
            base_dir: Base directory for relative path resolution

        Returns:
            Dict with keys: returncode, stdout, stderr

        Raises:
            Exception: If SQL file execution fails
        """
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
                    "-h", host,
                    "-p", port,
                    "-U", user,
                    "-d", dbname,
                    "-f", abs_file_path,
                ],
                env=env,
                cwd=sql_dir,
                capture_output=True,
                text=True,
                timeout=60,
            )

            return {
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }

        except Exception as e:
            raise Exception(f"SQL file execution failed: {str(e)}")

    def exec_sql_query(self, query: str) -> dict:
        """
        Execute a SQL query directly via psql.

        Args:
            query: SQL query string to execute

        Returns:
            Dict with keys: returncode, stdout, stderr

        Raises:
            Exception: If query execution fails
        """
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

            result = subprocess.run(
                [
                    "psql",
                    "-h", host,
                    "-p", port,
                    "-U", user,
                    "-d", dbname,
                    "-c", query,
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )

            return {
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }

        except Exception as e:
            raise Exception(f"SQL query execution failed: {str(e)}")
