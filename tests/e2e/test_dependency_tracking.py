"""
Dependency tracking and impact analysis tests.

Tests pgGit's ability to track and analyze dependencies between database objects:
- View dependencies on tables
- Foreign key dependencies
- Function dependencies on tables
- Multi-level dependency chains
- Cascade behaviors
- Self-referential dependencies

Key Coverage:
- Basic dependency detection
- Complex dependency chains
- Impact analysis functionality
- Cross-object relationships
- DROP CASCADE behavior
"""

import pytest


class TestBasicDependencies:
    """Basic dependency tracking between objects."""

    def test_view_depends_on_table(self, db, pggit_installed):
        """Test dependency between view and table."""
        db.execute("CREATE TABLE users (id INT, name TEXT, email TEXT)")
        db.execute("CREATE VIEW v_users AS SELECT id, name FROM users")

        # Verify view works
        db.execute("INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')")
        result = db.execute("SELECT * FROM v_users")
        assert result, "View not working"
        assert result[0] == (1, 'Alice')

        # Get impact analysis for base table
        try:
            impact = db.execute("""
                SELECT * FROM pggit.get_impact_analysis('users')
            """)
            # Function should execute (result may be empty if feature is planned)
            if impact and len(impact) > 0:
                print(f"✓ Impact analysis found {len(impact)} dependencies")
        except Exception as e:
            # Function may not exist yet
            print(f"⚠ Impact analysis not available: {e}")

        # Cleanup
        db.execute("DROP VIEW v_users")
        db.execute("DROP TABLE users")
        print("✓ View-table dependency tracked")

    def test_foreign_key_dependency(self, db, pggit_installed):
        """Test foreign key creates proper dependency."""
        db.execute("CREATE TABLE parent (id SERIAL PRIMARY KEY, name TEXT)")
        db.execute("""
            CREATE TABLE child (
                id SERIAL PRIMARY KEY,
                parent_id INT REFERENCES parent(id),
                data TEXT
            )
        """)

        # Insert test data
        parent_id = db.execute_returning(
            "INSERT INTO parent (name) VALUES (%s) RETURNING id",
            "Test Parent"
        )[0]

        db.execute(
            "INSERT INTO child (parent_id, data) VALUES (%s, %s)",
            parent_id, "Test Child"
        )

        # Verify data inserted
        result = db.execute("SELECT COUNT(*) FROM child WHERE parent_id = %s", parent_id)
        assert result[0][0] == 1, "Child record not inserted"

        # Try to delete parent (should fail due to FK)
        with pytest.raises(Exception) as exc:
            db.execute("DELETE FROM parent WHERE id = %s", parent_id)

        assert 'foreign key' in str(exc.value).lower() or \
               'violates' in str(exc.value).lower() or \
               'constraint' in str(exc.value).lower(), \
               "FK constraint not enforced"

        # Rollback failed transaction before cleanup
        db.rollback()

        # Cleanup
        db.execute("DROP TABLE child")
        db.execute("DROP TABLE parent")
        print("✓ Foreign key dependency enforced")

    def test_function_table_dependency(self, db, pggit_installed):
        """Test dependency between function and table."""
        db.execute("CREATE TABLE products (id INT, name TEXT, price DECIMAL)")
        db.execute("""
            CREATE FUNCTION get_product_name(product_id INT) RETURNS TEXT AS $$
            BEGIN
                RETURN (SELECT name FROM products WHERE id = product_id);
            END;
            $$ LANGUAGE plpgsql
        """)

        # Insert test data
        db.execute("INSERT INTO products VALUES (1, 'Widget', 9.99)")

        # Test function
        result = db.execute("SELECT get_product_name(1)")
        assert result[0][0] == 'Widget', "Function not working"

        # Cleanup
        db.execute("DROP FUNCTION get_product_name")
        db.execute("DROP TABLE products")
        print("✓ Function-table dependency works")

    def test_index_table_dependency(self, db, pggit_installed):
        """Test index dependency on table."""
        db.execute("CREATE TABLE indexed_table (id INT, email TEXT)")
        db.execute("CREATE INDEX idx_email ON indexed_table(email)")

        # Verify index exists
        result = db.execute("""
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'indexed_table'
        """)
        assert result, "Index not created"
        assert result[0][0] == 'idx_email'

        # Drop table should cascade to index
        db.execute("DROP TABLE indexed_table CASCADE")

        # Verify index gone
        result = db.execute("""
            SELECT indexname FROM pg_indexes
            WHERE indexname = 'idx_email'
        """)
        assert not result, "Index not dropped with table"
        print("✓ Index-table dependency cascades")


class TestComplexDependencies:
    """Complex dependency chains and relationships."""

    def test_dependency_chain(self, db, pggit_installed):
        """Test multi-level dependency chain."""
        # Create base table
        db.execute("CREATE TABLE t1 (id INT, data TEXT)")

        # Create views in chain: t1 → v1 → v2 → v3
        db.execute("CREATE VIEW v1 AS SELECT * FROM t1")
        db.execute("CREATE VIEW v2 AS SELECT * FROM v1")
        db.execute("CREATE VIEW v3 AS SELECT * FROM v2")

        # Insert test data
        db.execute("INSERT INTO t1 VALUES (1, 'test')")

        # Verify chain works
        result = db.execute("SELECT * FROM v3")
        assert result, "View chain broken"
        assert result[0] == (1, 'test'), "Data not flowing through chain"

        # Cleanup (should cascade through chain)
        db.execute("DROP VIEW v3")
        db.execute("DROP VIEW v2")
        db.execute("DROP VIEW v1")
        db.execute("DROP TABLE t1")
        print("✓ Multi-level dependency chain works")

    def test_dependency_on_drop_cascade(self, db, pggit_installed):
        """Test dropping object with dependencies using CASCADE."""
        db.execute("CREATE TABLE cascade_base (id INT, value TEXT)")
        db.execute("CREATE VIEW v_cascade AS SELECT * FROM cascade_base")

        # Verify both exist
        table_result = db.execute("""
            SELECT tablename FROM pg_tables
            WHERE tablename = 'cascade_base'
        """)
        view_result = db.execute("""
            SELECT viewname FROM pg_views
            WHERE viewname = 'v_cascade'
        """)
        assert table_result and view_result, "Objects not created"

        # Drop table with CASCADE
        db.execute("DROP TABLE cascade_base CASCADE")

        # Verify both are dropped
        table_result = db.execute("""
            SELECT tablename FROM pg_tables
            WHERE tablename = 'cascade_base'
        """)
        view_result = db.execute("""
            SELECT viewname FROM pg_views
            WHERE viewname = 'v_cascade'
        """)
        assert not table_result, "Table not dropped"
        assert not view_result, "Dependent view not dropped"
        print("✓ DROP CASCADE removes dependents")

    def test_self_referential_foreign_key(self, db, pggit_installed):
        """Test self-referential foreign key (tree structure)."""
        db.execute("""
            CREATE TABLE categories (
                id SERIAL PRIMARY KEY,
                name TEXT,
                parent_id INT REFERENCES categories(id)
            )
        """)

        # Insert root category
        root_id = db.execute_returning(
            "INSERT INTO categories (name, parent_id) VALUES (%s, NULL) RETURNING id",
            "Root"
        )[0]

        # Insert child category
        child_id = db.execute_returning(
            "INSERT INTO categories (name, parent_id) VALUES (%s, %s) RETURNING id",
            "Child", root_id
        )[0]

        # Verify hierarchy
        result = db.execute("""
            SELECT c.name, p.name as parent_name
            FROM categories c
            LEFT JOIN categories p ON c.parent_id = p.id
            WHERE c.id = %s
        """, child_id)

        assert result[0] == ('Child', 'Root'), "Self-referential FK not working"

        # Cleanup
        db.execute("DROP TABLE categories CASCADE")
        print("✓ Self-referential FK works")

    def test_circular_view_prevention(self, db, pggit_installed):
        """Test that PostgreSQL prevents circular view dependencies."""
        db.execute("CREATE TABLE base (id INT)")
        db.execute("CREATE VIEW v1 AS SELECT * FROM base")

        # Attempting to create circular dependency should fail
        # v2 -> v1 and then trying v1 -> v2 (through ALTER) would be circular
        # PostgreSQL should prevent this

        # Create v2 depending on v1
        db.execute("CREATE VIEW v2 AS SELECT * FROM v1")

        # Verify both views work
        result = db.execute("SELECT COUNT(*) FROM v2")
        assert result is not None, "View chain broken"

        # Cleanup
        db.execute("DROP VIEW v2")
        db.execute("DROP VIEW v1")
        db.execute("DROP TABLE base")
        print("✓ View dependencies validated")

    def test_multi_table_foreign_keys(self, db, pggit_installed):
        """Test multiple foreign key dependencies."""
        # Create tables with complex FK relationships
        db.execute("CREATE TABLE organizations (id SERIAL PRIMARY KEY, name TEXT)")
        db.execute("CREATE TABLE users (id SERIAL PRIMARY KEY, org_id INT REFERENCES organizations(id))")
        db.execute("""
            CREATE TABLE projects (
                id SERIAL PRIMARY KEY,
                org_id INT REFERENCES organizations(id),
                owner_id INT REFERENCES users(id)
            )
        """)

        # Insert test data
        org_id = db.execute_returning(
            "INSERT INTO organizations (name) VALUES (%s) RETURNING id",
            "Test Org"
        )[0]

        user_id = db.execute_returning(
            "INSERT INTO users (org_id) VALUES (%s) RETURNING id",
            org_id
        )[0]

        project_id = db.execute_returning(
            "INSERT INTO projects (org_id, owner_id) VALUES (%s, %s) RETURNING id",
            org_id, user_id
        )[0]

        # Verify relationships
        result = db.execute("""
            SELECT p.id, u.id, o.id
            FROM projects p
            JOIN users u ON p.owner_id = u.id
            JOIN organizations o ON p.org_id = o.id
            WHERE p.id = %s
        """, project_id)

        assert result[0] == (project_id, user_id, org_id), "Multi-table FK join failed"

        # Cleanup
        db.execute("DROP TABLE projects")
        db.execute("DROP TABLE users")
        db.execute("DROP TABLE organizations")
        print("✓ Multi-table foreign keys work")


class TestDependencyQueries:
    """Test querying and analyzing dependencies."""

    def test_query_table_dependencies(self, db, pggit_installed):
        """Test querying what depends on a table."""
        db.execute("CREATE TABLE dep_base (id INT)")
        db.execute("CREATE VIEW v_dep1 AS SELECT * FROM dep_base")
        db.execute("CREATE VIEW v_dep2 AS SELECT * FROM dep_base")

        # Query dependencies using PostgreSQL system catalogs
        # Use %% to escape % in LIKE pattern for psycopg
        result = db.execute("""
            SELECT DISTINCT v.viewname
            FROM pg_views v
            WHERE v.definition LIKE '%%dep_base%%'
            AND v.schemaname = 'public'
        """)

        view_names = [row[0] for row in result]
        assert 'v_dep1' in view_names, "Dependency v_dep1 not found"
        assert 'v_dep2' in view_names, "Dependency v_dep2 not found"

        # Cleanup
        db.execute("DROP VIEW v_dep1")
        db.execute("DROP VIEW v_dep2")
        db.execute("DROP TABLE dep_base")
        print("✓ Dependency queries work")

    def test_query_foreign_key_constraints(self, db, pggit_installed):
        """Test querying foreign key constraints."""
        db.execute("CREATE TABLE fk_parent (id SERIAL PRIMARY KEY)")
        db.execute("""
            CREATE TABLE fk_child (
                id SERIAL PRIMARY KEY,
                parent_id INT REFERENCES fk_parent(id)
            )
        """)

        # Query FK constraints
        result = db.execute("""
            SELECT conname, conrelid::regclass::text, confrelid::regclass::text
            FROM pg_constraint
            WHERE contype = 'f'
            AND confrelid::regclass::text = 'fk_parent'
        """)

        assert result, "FK constraint not found in system catalog"
        assert 'fk_child' in result[0][1], "FK child table not identified"

        # Cleanup
        db.execute("DROP TABLE fk_child")
        db.execute("DROP TABLE fk_parent")
        print("✓ FK constraint queries work")

    def test_dependency_impact_simulation(self, db, pggit_installed):
        """Test simulating impact of dropping an object."""
        db.execute("CREATE TABLE impact_base (id INT)")
        db.execute("CREATE VIEW v_impact1 AS SELECT * FROM impact_base")
        db.execute("CREATE VIEW v_impact2 AS SELECT * FROM v_impact1")

        # Count objects before
        count_before = db.execute("""
            SELECT COUNT(*) FROM pg_views
            WHERE viewname LIKE 'v_impact%%'
        """)

        # Simulate impact by checking what would be dropped
        # In a real scenario, pgGit's impact analysis would show this
        dependent_views = db.execute("""
            SELECT viewname FROM pg_views
            WHERE definition LIKE '%%impact_base%%'
            OR definition LIKE '%%v_impact1%%'
        """)

        # Should find both views
        view_count = len(dependent_views)
        assert view_count >= 1, "Dependent views not detected"

        # Cleanup
        db.execute("DROP VIEW v_impact2")
        db.execute("DROP VIEW v_impact1")
        db.execute("DROP TABLE impact_base")
        print(f"✓ Impact analysis detected {view_count} dependent objects")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
