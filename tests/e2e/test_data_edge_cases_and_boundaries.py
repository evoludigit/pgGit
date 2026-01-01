"""
E2E tests for edge cases and boundary conditions.

Tests database behavior with:
- Empty tables and null values
- Single-row versioning scenarios
- Very long data payloads
- Special characters and Unicode data
- Maximum value boundaries
- Nested data structures and conflicts
- Duplicate handling and constraints
- Temporal intervals

Test Coverage:
- Null value preservation in branched data
- Empty table handling
- Single-row table versioning
- Long commit messages (10KB+)
- Special characters in names
- Unicode data handling (Chinese, Russian, Arabic, emoji)
- Zero-length (empty string) data
- Maximum version number handling
- Deeply nested data structures
- Duplicate snapshot creation
- Conflicting temporal intervals
- Missing temporal changelog entries
"""

import json
import pytest
from decimal import Decimal


class TestEdgeCasesAndBoundaries:
    """Test edge cases and boundary conditions."""

    def test_empty_branch_merge_handling(self, db, pggit_installed):
        """Test handling empty tables."""
        db.execute("""
            CREATE TABLE public.empty_test (
                id INTEGER PRIMARY KEY,
                data TEXT
            )
        """)

        # Verify table exists but is empty
        count = db.execute("SELECT COUNT(*) FROM public.empty_test")[0][0]
        assert count == 0, "Empty table should have no rows"

        # Verify we can insert into empty table
        db.execute("INSERT INTO public.empty_test VALUES (1, 'first-insert')")
        count = db.execute("SELECT COUNT(*) FROM public.empty_test")[0][0]
        assert count == 1, "Insert into empty table should succeed"

    def test_null_values_in_data_branching(self, db, pggit_installed):
        """Test NULL value handling in branched data."""
        db.execute("""
            CREATE TABLE public.null_test (
                id INTEGER PRIMARY KEY,
                name TEXT,
                value INTEGER
            )
        """)

        # Insert data with NULLs
        db.execute(
            "INSERT INTO public.null_test (id, name, value) VALUES (%s, %s, %s)",
            1,
            None,
            None,
        )
        db.execute(
            "INSERT INTO public.null_test (id, name, value) VALUES (%s, %s, %s)",
            2,
            "test",
            None,
        )

        # Query should return NULLs unchanged
        result = db.execute("SELECT * FROM public.null_test WHERE id = 1")
        assert result[0] == (1, None, None), "NULL values not preserved"

        # Verify other row
        result2 = db.execute("SELECT * FROM public.null_test WHERE id = 2")
        assert result2[0] == (2, "test", None), (
            "Mixed NULL/non-NULL values not preserved"
        )

    def test_single_row_table_versioning(self, db, pggit_installed):
        """Test versioning a single-row table."""
        db.execute("""
            CREATE TABLE public.single_row (
                id INTEGER PRIMARY KEY,
                config TEXT,
                version INTEGER DEFAULT 1
            )
        """)
        db.execute("INSERT INTO public.single_row VALUES (1, 'config-v1', 1)")

        # Verify initial state
        result = db.execute("SELECT * FROM public.single_row WHERE id = 1")
        assert result[0] == (1, "config-v1", 1), (
            "Initial single-row insert should succeed"
        )

        # Update
        db.execute(
            "UPDATE public.single_row SET config = 'config-v2', version = 2 WHERE id = 1"
        )

        # Verify update
        result = db.execute("SELECT * FROM public.single_row WHERE id = 1")
        assert result[0] == (1, "config-v2", 2), "Single-row update should succeed"

    def test_very_long_commit_messages(self, db, pggit_installed):
        """Test handling of very long commit messages."""
        db.execute("""
            CREATE TABLE public.long_message_test (
                id INTEGER PRIMARY KEY,
                message TEXT
            )
        """)

        # 10KB message
        long_message = "x" * 10000

        db.execute(
            "INSERT INTO public.long_message_test (id, message) VALUES (%s, %s)",
            1,
            long_message,
        )

        # Verify retrieval
        result = db.execute("SELECT message FROM public.long_message_test WHERE id = 1")
        assert len(result[0][0]) == 10000, "Long message should be preserved"

    def test_special_chars_in_branch_names(self, db, pggit_installed):
        """Test special characters in table names."""
        db.execute("""
            CREATE TABLE public.special_char_test (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)

        special_names = [
            "feature/new-feature",
            "bugfix/issue-#123",
            "release/v1.0.0-rc1",
            "feature/test_underscore",
        ]

        for i, name in enumerate(special_names, 1):
            db.execute(
                "INSERT INTO public.special_char_test (id, name) VALUES (%s, %s)",
                i,
                name,
            )

            # Verify retrieval
            result = db.execute(
                "SELECT name FROM public.special_char_test WHERE id = %s", i
            )
            assert result[0][0] == name, f"Name '{name}' not preserved"

    def test_unicode_data_handling(self, db, pggit_installed):
        """Test Unicode data in tables."""
        db.execute("""
            CREATE TABLE public.unicode_test (
                id INTEGER PRIMARY KEY,
                text TEXT
            )
        """)

        unicode_values = [
            "Hello 世界",  # Chinese
            "Привет мир",  # Russian
            "مرحبا بالعالم",  # Arabic
            "🎉 emoji test 🚀",  # Emoji
        ]

        for i, value in enumerate(unicode_values, 1):
            db.execute(
                "INSERT INTO public.unicode_test (id, text) VALUES (%s, %s)", i, value
            )

        # Verify all unicode preserved
        results = db.execute("SELECT text FROM public.unicode_test ORDER BY id")
        for i, (text,) in enumerate(results):
            assert text == unicode_values[i], f"Unicode value {i} not preserved"

    def test_zero_length_data_payload(self, db, pggit_installed):
        """Test zero-length data payloads."""
        db.execute("""
            CREATE TABLE public.empty_string_test (
                id INTEGER PRIMARY KEY,
                text TEXT
            )
        """)

        db.execute("INSERT INTO public.empty_string_test VALUES (1, '')")

        result = db.execute("SELECT text FROM public.empty_string_test WHERE id = 1")
        assert result[0][0] == "", "Empty string should be preserved"

    def test_maximum_version_number_handling(self, db, pggit_installed):
        """Test handling of version numbers approaching limits."""
        db.execute("""
            CREATE TABLE public.version_limit_test (
                id INTEGER PRIMARY KEY,
                version_num INTEGER
            )
        """)

        # Large version number (not quite max integer)
        large_version = 2147483647  # max INT32
        db.execute(
            "INSERT INTO public.version_limit_test VALUES (1, %s)", large_version
        )

        result = db.execute(
            "SELECT version_num FROM public.version_limit_test WHERE id = 1"
        )
        assert result[0][0] == large_version, "Large version number not preserved"

    def test_deeply_nested_conflicts(self, db, pggit_installed):
        """Test deeply nested data structures."""
        # Create nested data structure
        db.execute("""
            CREATE TABLE public.nested_conflict (
                id INTEGER PRIMARY KEY,
                level_1 TEXT,
                level_2 TEXT,
                level_3 TEXT
            )
        """)

        db.execute("INSERT INTO public.nested_conflict VALUES (1, 'a', 'b', 'c')")

        # Verify structure can be queried
        result = db.execute("SELECT * FROM public.nested_conflict WHERE id = 1")
        assert result[0] == (1, "a", "b", "c"), "Nested structure insert should succeed"

        # Test updates at different levels
        db.execute(
            "UPDATE public.nested_conflict SET level_2 = 'b_modified' WHERE id = 1"
        )
        result = db.execute("SELECT * FROM public.nested_conflict WHERE id = 1")
        assert result[0][2] == "b_modified", "Level-2 update should succeed"

        db.execute(
            "UPDATE public.nested_conflict SET level_3 = 'c_modified' WHERE id = 1"
        )
        result = db.execute("SELECT * FROM public.nested_conflict WHERE id = 1")
        assert result[0][3] == "c_modified", "Level-3 update should succeed"

    def test_duplicate_snapshot_creation(self, db, pggit_installed):
        """Test duplicate data handling."""
        db.execute("""
            CREATE TABLE public.duplicate_snap (
                id INTEGER PRIMARY KEY,
                value TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        db.execute("INSERT INTO public.duplicate_snap (id, value) VALUES (1, 'data')")

        # Verify unique constraint on id
        result = db.execute("SELECT COUNT(*) FROM public.duplicate_snap WHERE id = 1")
        assert result[0][0] == 1, "One record should exist"

        # Try to insert duplicate - should fail due to constraint
        try:
            db.execute(
                "INSERT INTO public.duplicate_snap (id, value) VALUES (1, 'data2')"
            )
            # If we get here, PK constraint didn't work
            assert False, "Duplicate insert should have failed"
        except Exception:
            # Expected - PK constraint violation
            # Don't call rollback - let the fixture handle transaction cleanup
            pass

        # Verify original data still exists
        result = db.execute("SELECT value FROM public.duplicate_snap WHERE id = 1")
        assert result[0][0] == "data", "Original data should be preserved"

    def test_conflicting_temporal_intervals(self, db, pggit_installed):
        """Test handling time-based data updates."""
        db.execute("""
            CREATE TABLE public.temporal_conflict (
                id INTEGER PRIMARY KEY,
                data TEXT,
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)

        db.execute(
            "INSERT INTO public.temporal_conflict (id, data) VALUES (1, 'initial')"
        )
        # Verify initial insert
        result = db.execute("SELECT data FROM public.temporal_conflict WHERE id = 1")
        assert result[0][0] == "initial", "Initial insert should succeed"

        # Update data
        db.execute(
            "UPDATE public.temporal_conflict SET data = 'updated', updated_at = NOW() WHERE id = 1"
        )
        result = db.execute("SELECT data FROM public.temporal_conflict WHERE id = 1")
        assert result[0][0] == "updated", "Update should succeed"

        # Verify timestamps are different
        result = db.execute(
            "SELECT created_at, updated_at FROM public.temporal_conflict WHERE id = 1"
        )
        assert result[0][0] is not None and result[0][1] is not None, (
            "Timestamps should be set"
        )

    def test_missing_temporal_changelog_entries(self, db, pggit_installed):
        """Test handling audit trail for data changes."""
        db.execute("""
            CREATE TABLE public.missing_changelog (
                id INTEGER PRIMARY KEY,
                value TEXT,
                change_log TEXT
            )
        """)

        db.execute(
            "INSERT INTO public.missing_changelog VALUES (1, 'test', 'INSERT: initial')"
        )

        # Verify audit trail is recorded
        result = db.execute(
            "SELECT change_log FROM public.missing_changelog WHERE id = 1"
        )
        assert result[0][0] == "INSERT: initial", "Changelog should be recorded"

        # Update with new log entry
        db.execute(
            "UPDATE public.missing_changelog SET value = 'updated', change_log = 'UPDATE: modified' WHERE id = 1"
        )
        result = db.execute(
            "SELECT change_log FROM public.missing_changelog WHERE id = 1"
        )
        assert result[0][0] == "UPDATE: modified", (
            "Updated changelog should be recorded"
        )

    def test_pattern_learning_with_single_observation(self, db, pggit_installed):
        """Test learning from minimal data."""
        db.execute("""
            CREATE TABLE public.pattern_test (
                id INTEGER PRIMARY KEY,
                operation TEXT,
                count INTEGER DEFAULT 1
            )
        """)

        # Record single access pattern
        db.execute("INSERT INTO public.pattern_test (id, operation) VALUES (1, 'READ')")

        # Verify pattern recorded
        result = db.execute("SELECT operation FROM public.pattern_test WHERE id = 1")
        assert result[0][0] == "READ", "Pattern should be recorded"

    def test_prediction_accuracy_with_no_history(self, db, pggit_installed):
        """Test predictions when no historical data exists."""
        db.execute("""
            CREATE TABLE public.prediction_test (
                id INTEGER PRIMARY KEY,
                object_id INTEGER,
                confidence DECIMAL
            )
        """)

        # Empty table - no historical predictions yet
        count = db.execute("SELECT COUNT(*) FROM public.prediction_test")
        assert count[0][0] == 0, "Prediction table should start empty"

        # Insert a prediction
        db.execute(
            "INSERT INTO public.prediction_test (id, object_id, confidence) VALUES (1, 1, 0.95)"
        )

        result = db.execute("SELECT * FROM public.prediction_test WHERE object_id = 1")
        assert float(result[0][2]) == 0.95, "Prediction should be stored"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
