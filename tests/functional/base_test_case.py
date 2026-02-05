"""
pgGit Functional Tests - Base Test Case

Provides base class with common utilities for all functional tests:
- SQL execution helpers
- Custom assertions
- Database state verification
- Transaction management
"""

import pytest


class FunctionalTestCase:
    """
    Base class for all pgGit functional tests

    Provides:
    - execute_sql: Run SQL queries
    - assert_*: Custom assertions for database state
    - get_*: Retrieve values from database
    """

    def execute_sql(self, db_connection, sql: str, params=None):
        """Execute SQL and return all results (for SELECT) or None (for DML)"""
        try:
            if params:
                result = db_connection.execute(sql, params)
            else:
                result = db_connection.execute(sql)

            # Try to fetch results (works for SELECT)
            try:
                return result.fetchall()
            except Exception:
                # DML statements (INSERT/UPDATE/DELETE) don't have fetchable results
                # Return empty list to indicate successful execution
                return []
        except Exception as e:
            raise AssertionError(f"SQL execution failed: {e}\nSQL: {sql}")

    def execute_sql_one(self, db_connection, sql: str, params=None):
        """Execute SQL and return first result row"""
        try:
            if params:
                result = db_connection.execute(sql, params)
            else:
                result = db_connection.execute(sql)
            return result.fetchone()
        except Exception as e:
            raise AssertionError(f"SQL execution failed: {e}\nSQL: {sql}")

    def execute_sql_value(self, db_connection, sql: str, params=None):
        """Execute SQL and return first column of first row"""
        try:
            row = self.execute_sql_one(db_connection, sql, params)
            if row is None:
                return None
            return row[0]
        except Exception as e:
            raise AssertionError(f"SQL query failed: {e}\nSQL: {sql}")

    def assert_table_exists(self, db_connection, schema: str, table: str):
        """Assert that table exists in schema"""
        result = self.execute_sql(
            db_connection,
            """
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = %s AND table_name = %s
        """,
            (schema, table),
        )

        assert len(result) > 0, (
            f"Table {schema}.{table} not found in information_schema"
        )

    def assert_table_not_exists(self, db_connection, schema: str, table: str):
        """Assert that table does not exist"""
        result = self.execute_sql(
            db_connection,
            """
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = %s AND table_name = %s
        """,
            (schema, table),
        )

        assert len(result) == 0, (
            f"Table {schema}.{table} should not exist but was found"
        )

    def assert_function_exists(self, db_connection, schema: str, function: str):
        """Assert that function exists"""
        result = self.execute_sql(
            db_connection,
            """
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = %s AND p.proname = %s
        """,
            (schema, function),
        )

        assert len(result) > 0, f"Function {schema}.{function} not found"

    def assert_record_count(
        self, db_connection, table: str, expected: int, where_clause: str = None
    ):
        """Assert that table has expected number of records"""
        sql = f"SELECT COUNT(*) FROM {table}"
        if where_clause:
            sql += f" WHERE {where_clause}"

        count = self.execute_sql_value(db_connection, sql)

        assert count == expected, (
            f"Table {table}: expected {expected} records, got {count}"
        )

    def assert_record_count_gte(self, db_connection, table: str, min_count: int):
        """Assert that table has at least min_count records"""
        count = self.execute_sql_value(db_connection, f"SELECT COUNT(*) FROM {table}")

        assert count >= min_count, (
            f"Table {table}: expected >= {min_count} records, got {count}"
        )

    def assert_value_exists(self, db_connection, table: str, column: str, value):
        """Assert that value exists in table column"""
        result = self.execute_sql(
            db_connection,
            f"""
            SELECT 1 FROM {table} WHERE {column} = %s
        """,
            (value,),
        )

        assert len(result) > 0, f"Value '{value}' not found in {table}.{column}"

    def assert_value_not_exists(self, db_connection, table: str, column: str, value):
        """Assert that value does not exist in table column"""
        result = self.execute_sql(
            db_connection,
            f"""
            SELECT 1 FROM {table} WHERE {column} = %s
        """,
            (value,),
        )

        assert len(result) == 0, f"Value '{value}' should not exist in {table}.{column}"

    def assert_uuid_valid(self, value):
        """Assert that value is a valid UUID"""
        if value is None:
            pytest.fail("UUID is NULL")

        import uuid

        try:
            uuid.UUID(str(value))
        except ValueError:
            pytest.fail(f"Invalid UUID format: {value}")

    def assert_status_field(
        self,
        db_connection,
        table: str,
        key_column: str,
        key_value,
        status_column: str,
        expected_status: str,
    ):
        """Assert that record has expected status"""
        result = self.execute_sql(
            db_connection,
            f"""
            SELECT {status_column} FROM {table} WHERE {key_column} = %s
        """,
            (key_value,),
        )

        assert len(result) > 0, (
            f"Record with {key_column}={key_value} not found in {table}"
        )

        actual_status = result[0][0]
        assert actual_status == expected_status, (
            f"Expected {status_column}='{expected_status}', got '{actual_status}'"
        )

    def get_record(self, db_connection, table: str, key_column: str, key_value):
        """Get full record as dict"""
        result = self.execute_sql_one(
            db_connection,
            f"""
            SELECT * FROM {table} WHERE {key_column} = %s
        """,
            (key_value,),
        )

        assert result is not None, (
            f"Record with {key_column}={key_value} not found in {table}"
        )

        # Get column names
        cursor = db_connection.execute(f"SELECT 1 FROM {table} LIMIT 1")
        column_names = [desc[0] for desc in cursor.description]

        # Return as dict
        return dict(zip(column_names, result))

    def get_value(self, db_connection, sql: str, params=None):
        """Get first column value from SQL result"""
        return self.execute_sql_value(db_connection, sql, params)

    def get_count(self, db_connection, table: str, where_clause: str = None):
        """Get count of records in table"""
        sql = f"SELECT COUNT(*) FROM {table}"
        if where_clause:
            sql += f" WHERE {where_clause}"
        return self.get_value(db_connection, sql)

    def create_test_schema(self, db_connection, schema_name: str):
        """Create test schema"""
        self.execute_sql(db_connection, f"CREATE SCHEMA IF NOT EXISTS {schema_name}")

    def create_test_table(
        self,
        db_connection,
        table_name: str,
        schema_name: str = "public",
        with_rows: int = 0,
    ):
        """Create simple test table"""
        full_name = f"{schema_name}.{table_name}"
        self.execute_sql(
            db_connection,
            f"""
            CREATE TABLE IF NOT EXISTS {full_name} (
                id SERIAL PRIMARY KEY,
                data TEXT,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """,
        )

        if with_rows > 0:
            for i in range(with_rows):
                self.execute_sql(
                    db_connection,
                    f"""
                    INSERT INTO {full_name} (data) VALUES ('Row {i}')
                """,
                )

        return full_name

    def create_test_function(
        self,
        db_connection,
        function_name: str,
        schema_name: str = "public",
        params: str = "",
        returns: str = "text",
        body: str = "RETURN 'test'",
    ):
        """Create simple test function"""
        full_name = f"{schema_name}.{function_name}"
        self.execute_sql(
            db_connection,
            f"""
            CREATE OR REPLACE FUNCTION {full_name}({params})
            RETURNS {returns} AS $$
            BEGIN
                {body};
            END;
            $$ LANGUAGE plpgsql;
        """,
        )

        return full_name

    def drop_schema(self, db_connection, schema_name: str):
        """Drop test schema and all contents"""
        self.execute_sql(db_connection, f"DROP SCHEMA IF EXISTS {schema_name} CASCADE")

    def commit_transaction(self, db_connection):
        """Commit current transaction"""
        db_connection.execute("COMMIT;")

    def rollback_transaction(self, db_connection):
        """Rollback current transaction"""
        db_connection.execute("ROLLBACK;")

    def begin_transaction(self, db_connection):
        """Begin new transaction"""
        db_connection.execute("BEGIN;")
