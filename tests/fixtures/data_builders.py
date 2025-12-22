"""
Test data builders and factories for E2E and integration testing.

Provides factory patterns for creating test data consistently
across different test scenarios. Reduces duplication of test setup code.

Features:
- Branch creation factories
- Commit data builders
- Table creation helpers
- Test data generation utilities
"""

import json
from datetime import datetime, timedelta
from decimal import Decimal


class BranchBuilder:
    """Factory for creating test branches with consistent data."""

    def __init__(self, db_fixture, base_name: str = "test-branch"):
        """
        Initialize branch builder.

        Args:
            db_fixture: DatabaseFixture instance
            base_name: Base name for generated branches
        """
        self.db = db_fixture
        self.base_name = base_name
        self.counter = 0

    def create(self, name: str = None, status: str = "ACTIVE") -> dict:
        """
        Create a test branch.

        Args:
            name: Branch name (auto-generated if not provided)
            status: Branch status (default: ACTIVE)

        Returns:
            Dict with keys: id, name, status
        """
        if not name:
            self.counter += 1
            name = f"{self.base_name}-{self.counter}"

        try:
            result = self.db.execute_returning(
                "INSERT INTO pggit.branches (name, status) VALUES (%s, %s) RETURNING id",
                name, status
            )
            return {
                "id": result[0] if result else None,
                "name": name,
                "status": status,
            }
        except Exception:
            # Branch might already exist
            result = self.db.execute_returning(
                "SELECT id FROM pggit.branches WHERE name = %s",
                name
            )
            return {
                "id": result[0] if result else None,
                "name": name,
                "status": status,
            }

    def create_multiple(self, count: int = 5, prefix: str = None) -> list:
        """
        Create multiple branches.

        Args:
            count: Number of branches to create
            prefix: Name prefix for generated branches

        Returns:
            List of branch dicts
        """
        branches = []
        for i in range(count):
            name = f"{prefix or self.base_name}-{i}" if prefix else None
            branches.append(self.create(name=name))
        return branches


class CommitBuilder:
    """Factory for creating test commits with consistent data."""

    def __init__(self, db_fixture):
        """
        Initialize commit builder.

        Args:
            db_fixture: DatabaseFixture instance
        """
        self.db = db_fixture
        self.counter = 0

    def create(
        self,
        branch_id: int,
        message: str = None,
        author: str = "test-author",
        metadata: dict = None,
    ) -> dict:
        """
        Create a test commit.

        Args:
            branch_id: ID of branch to create commit on
            message: Commit message (auto-generated if not provided)
            author: Author name (default: test-author)
            metadata: Optional metadata dict (default: empty)

        Returns:
            Dict with keys: id, hash, branch_id, message, author, metadata
        """
        if not message:
            self.counter += 1
            message = f"Test commit {self.counter}"

        if metadata is None:
            metadata = {}

        result = self.db.execute_returning(
            """
            INSERT INTO pggit.commits (branch_id, message, author, metadata)
            VALUES (%s, %s, %s, %s)
            RETURNING id, hash
            """,
            branch_id,
            message,
            author,
            json.dumps(metadata),
        )

        if result:
            return {
                "id": result[0],
                "hash": result[1],
                "branch_id": branch_id,
                "message": message,
                "author": author,
                "metadata": metadata,
            }
        return None

    def create_multiple(
        self, branch_id: int, count: int = 5, author: str = "test-author"
    ) -> list:
        """
        Create multiple commits on same branch.

        Args:
            branch_id: ID of branch to create commits on
            count: Number of commits to create
            author: Author name for all commits

        Returns:
            List of commit dicts
        """
        commits = []
        for i in range(count):
            commits.append(
                self.create(
                    branch_id=branch_id,
                    message=f"Commit {i + 1}",
                    author=author,
                    metadata={"sequence": i + 1},
                )
            )
        return commits


class TableBuilder:
    """Factory for creating test tables with consistent schema."""

    def __init__(self, db_fixture):
        """
        Initialize table builder.

        Args:
            db_fixture: DatabaseFixture instance
        """
        self.db = db_fixture

    def create_simple(self, table_name: str, schema: str = "public") -> str:
        """
        Create a simple test table.

        Args:
            table_name: Name of table to create
            schema: Schema name (default: public)

        Returns:
            Full table name (schema.table)
        """
        full_name = f"{schema}.{table_name}"
        try:
            self.db.execute(
                f"""
                CREATE TABLE {full_name} (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """
            )
        except Exception:
            # Table might already exist
            self.db.conn.rollback()

        return full_name

    def create_with_schema(
        self, table_name: str, schema: str = "public", columns: list = None
    ) -> str:
        """
        Create a test table with custom schema.

        Column format: (name, type, constraints)
        Example: [("id", "SERIAL", "PRIMARY KEY"), ("data", "TEXT", "NOT NULL")]

        Args:
            table_name: Name of table to create
            schema: Schema name (default: public)
            columns: List of column definitions

        Returns:
            Full table name (schema.table)
        """
        if columns is None:
            columns = [
                ("id", "SERIAL", "PRIMARY KEY"),
                ("data", "TEXT", "NOT NULL"),
            ]

        full_name = f"{schema}.{table_name}"
        column_defs = ", ".join([f"{name} {type_} {constraints}".strip()
                                  for name, type_, constraints in columns])

        try:
            self.db.execute(f"CREATE TABLE {full_name} ({column_defs})")
        except Exception:
            # Table might already exist
            self.db.conn.rollback()

        return full_name

    def insert_rows(
        self,
        table_name: str,
        rows: list,
        schema: str = "public",
    ) -> int:
        """
        Insert multiple rows into a table.

        Args:
            table_name: Name of table
            rows: List of dicts with column values
            schema: Schema name (default: public)

        Returns:
            Number of rows inserted
        """
        full_name = f"{schema}.{table_name}"
        count = 0

        for row in rows:
            columns = ", ".join(row.keys())
            placeholders = ", ".join(["%s"] * len(row))
            values = tuple(row.values())

            try:
                self.db.execute(
                    f"INSERT INTO {full_name} ({columns}) VALUES ({placeholders})",
                    *values
                )
                count += 1
            except Exception:
                # Continue on error
                self.db.conn.rollback()

        return count


class DataGenerator:
    """Utilities for generating test data."""

    @staticmethod
    def generate_strings(count: int = 5, prefix: str = "str") -> list:
        """Generate list of test strings."""
        return [f"{prefix}-{i}" for i in range(count)]

    @staticmethod
    def generate_numbers(count: int = 5, start: int = 1) -> list:
        """Generate list of sequential numbers."""
        return list(range(start, start + count))

    @staticmethod
    def generate_timestamps(count: int = 5, interval_seconds: int = 60) -> list:
        """Generate list of timestamps with regular intervals."""
        now = datetime.now()
        return [
            (now - timedelta(seconds=i * interval_seconds)).isoformat()
            for i in range(count)
        ]

    @staticmethod
    def generate_decimals(count: int = 5, base: float = 10.50) -> list:
        """Generate list of decimal numbers."""
        return [Decimal(str(base + i)) for i in range(count)]

    @staticmethod
    def generate_json_objects(count: int = 5) -> list:
        """Generate list of JSON objects."""
        return [
            json.dumps({
                "id": i,
                "name": f"item-{i}",
                "value": 10.0 + i,
                "timestamp": datetime.now().isoformat(),
            })
            for i in range(count)
        ]

    @staticmethod
    def generate_test_rows(count: int = 5, include_types: list = None) -> list:
        """
        Generate test rows with mixed data types.

        Args:
            count: Number of rows to generate
            include_types: List of type names to include

        Returns:
            List of dicts with mixed test data
        """
        rows = []
        for i in range(count):
            row = {
                "id": i,
                "name": f"test-{i}",
                "value": float(10 + i),
                "created_at": datetime.now().isoformat(),
            }
            rows.append(row)
        return rows
