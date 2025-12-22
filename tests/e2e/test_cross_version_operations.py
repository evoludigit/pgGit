"""
E2E tests for cross-version operations and compatibility.

Tests backward compatibility and version resilience:
- Version compatibility checks
- Backward compatibility queries
- Schema introspection compatibility

Key Coverage:
- Table existence validation
- Query pattern compatibility
- Schema introspection accuracy
- Version resilience
"""

import pytest


class TestE2ECrossVersionOperations:
    """Test cross-version operations."""

    def test_version_compatibility_check(self, db, pggit_installed):
        """Test checking compatibility across versions"""
        # Get current tables
        tables = db.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit'
            ORDER BY table_name
        """)

        table_names = [t[0] for t in tables]
        assert 'branches' in table_names, "branches table should exist"
        assert 'commits' in table_names, "commits table should exist"

    def test_backward_compatibility_queries(self, db, pggit_installed):
        """Test that old query patterns still work"""
        # Simple SELECT on main branch
        result = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE name = 'main'"
        )
        assert result[0][0] >= 1, "Main branch should exist"

        # Query with JOIN
        result = db.execute("""
            SELECT COUNT(*) FROM pggit.branches b
            LEFT JOIN pggit.commits c ON b.id = c.branch_id
            WHERE b.name = 'main'
        """)
        assert result is not None, "JOIN queries should work"

    def test_schema_introspection_compatibility(self, db, pggit_installed):
        """Test that schema introspection queries work correctly"""
        # Get column information
        columns = db.execute("""
            SELECT column_name, data_type FROM information_schema.columns
            WHERE table_schema = 'pggit' AND table_name = 'branches'
            ORDER BY ordinal_position
        """)

        column_names = [c[0] for c in columns]
        assert 'id' in column_names, "id column should exist"
        assert 'name' in column_names, "name column should exist"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
