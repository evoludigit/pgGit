import pytest
from contextlib import contextmanager


class FeatureRequirement:
    """Manages feature availability checks"""

    @staticmethod
    def require_function(conn, function_name, schema="pggit"):
        """Require that a function exists"""
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM pg_proc
                WHERE proname = %s
                AND pronamespace = %s::regnamespace
            """,
                (function_name, schema),
            )
            if not cur.fetchone():
                pytest.skip(
                    f"Required function {schema}.{function_name}() not installed. "
                    "This feature module must be installed to run this test."
                )

    @staticmethod
    def require_table(conn, table_name, schema="pggit"):
        """Require that a table exists"""
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = %s AND table_name = %s
            """,
                (schema, table_name),
            )
            if not cur.fetchone():
                pytest.skip(
                    f"Required table {schema}.{table_name} not installed. "
                    "This feature module must be installed to run this test."
                )

    @staticmethod
    def require_type(conn, type_name, schema="pggit"):
        """Require that a custom type exists"""
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM information_schema.schemata s
                JOIN pg_type t ON t.typnamespace = (s.schema_name::regnamespace)::oid
                WHERE s.schema_name = %s AND t.typname = %s
            """,
                (schema, type_name),
            )
            if not cur.fetchone():
                pytest.skip(
                    f"Required type {schema}.{type_name} not installed. "
                    "This feature module must be installed to run this test."
                )


@contextmanager
def assert_no_exception(context="operation"):
    """Context manager that fails if ANY exception occurs"""
    try:
        yield
    except Exception as e:
        pytest.fail(f"Unexpected exception in {context}: {e}")
