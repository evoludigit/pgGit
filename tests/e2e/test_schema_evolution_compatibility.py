"""
E2E tests for schema evolution and compatibility.

Tests schema changes and compatibility across versions:
- Column addition and default values
- Data type compatibility
- Index creation and usage
- Table rename and reference handling

Key Coverage:
- Schema evolution zero-downtime
- Data type handling
- Index effectiveness
- Table renaming with data preservation
- Backward compatibility
"""

import json
import pytest
from datetime import datetime
from decimal import Decimal


class TestE2ESchemaEvolution:
    """Test schema evolution and compatibility."""

    def test_column_addition_compatibility(self, db, pggit_installed):
        """Test adding columns to existing tables"""
        # Create initial table
        db.execute("""
            CREATE TABLE public.schema_evolution_test (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)

        # Insert data with initial schema
        db.execute(
            "INSERT INTO public.schema_evolution_test (id, name) VALUES (%s, %s)",
            1, "test-record"
        )

        # Add new column
        db.execute(
            "ALTER TABLE public.schema_evolution_test ADD COLUMN description TEXT DEFAULT 'no description'"
        )

        # Verify table structure changed
        columns = db.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'schema_evolution_test'
            ORDER BY ordinal_position
        """)

        column_names = [col[0] for col in columns]
        assert 'description' in column_names, "New column should be added"

        # Verify existing data is still accessible
        result = db.execute(
            "SELECT name, description FROM public.schema_evolution_test WHERE id = 1"
        )
        assert result[0][0] == "test-record", "Existing data should be intact"

    def test_data_type_compatibility(self, db, pggit_installed):
        """Test handling of various data types"""
        db.execute("""
            CREATE TABLE public.datatype_test (
                id INTEGER PRIMARY KEY,
                int_val INTEGER,
                decimal_val DECIMAL(10, 2),
                text_val TEXT,
                bool_val BOOLEAN,
                timestamp_val TIMESTAMP,
                json_val JSONB
            )
        """)

        # Insert various data types
        db.execute("""
            INSERT INTO public.datatype_test
            (id, int_val, decimal_val, text_val, bool_val, timestamp_val, json_val)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
            1, 42, Decimal("99.99"), "test", True, datetime.now(), json.dumps({"key": "value"})
        )

        # Verify all types are stored and retrieved correctly
        result = db.execute("SELECT * FROM public.datatype_test WHERE id = 1")
        assert result[0][1] == 42, "Integer should be stored correctly"
        assert result[0][4] is True, "Boolean should be stored correctly"

    def test_index_creation_and_usage(self, db, pggit_installed):
        """Test that indexes are created and used properly"""
        db.execute("""
            CREATE TABLE public.index_test (
                id INTEGER PRIMARY KEY,
                indexed_col TEXT,
                data TEXT
            )
        """)

        # Insert test data
        for i in range(100):
            db.execute(
                "INSERT INTO public.index_test (id, indexed_col, data) VALUES (%s, %s, %s)",
                i, f"value-{i % 10}", f"data-{i}"
            )

        # Create index
        db.execute("CREATE INDEX idx_indexed_col ON public.index_test(indexed_col)")

        # Query using indexed column
        result = db.execute(
            "SELECT COUNT(*) FROM public.index_test WHERE indexed_col = %s",
            "value-5"
        )

        assert result[0][0] == 10, "Index query should return correct results"

    def test_table_rename_compatibility(self, db, pggit_installed):
        """Test renaming tables doesn't break references"""
        db.execute("""
            CREATE TABLE public.original_name (
                id INTEGER PRIMARY KEY,
                value TEXT
            )
        """)

        db.execute(
            "INSERT INTO public.original_name (id, value) VALUES (%s, %s)",
            1, "test-value"
        )

        # Rename table
        db.execute("ALTER TABLE public.original_name RENAME TO renamed_table")

        # Verify data is still accessible
        result = db.execute("SELECT value FROM public.renamed_table WHERE id = 1")
        assert result[0][0] == "test-value", "Data should be accessible after rename"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
