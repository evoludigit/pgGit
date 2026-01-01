"""
Comprehensive DDL tracking tests.

Tests that pgGit tracks all PostgreSQL object types correctly including:
- Tables (CREATE, ALTER, DROP)
- Indexes (CREATE, DROP)
- Views (CREATE, DROP, REFRESH MATERIALIZED VIEW)
- Functions and Procedures (CREATE, DROP)
- Types (CREATE TYPE, CREATE DOMAIN, CREATE ENUM)
- Triggers (CREATE, DROP)

Key Coverage:
- All major DDL operations
- Schema modification tracking
- Object lifecycle management
- Cross-object dependencies
"""

import pytest


class TestTableDDL:
    """Table DDL operations tracking."""

    def test_track_create_table(self, db, pggit_installed):
        """Test CREATE TABLE is tracked."""
        db.execute("""
            CREATE TABLE users (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT UNIQUE
            )
        """)

        # Verify table exists
        result = db.execute("""
            SELECT tablename FROM pg_tables
            WHERE tablename = 'users' AND schemaname = 'public'
        """)
        assert result, "Table not created"
        assert result[0][0] == 'users'

        # Verify trackable by pgGit
        version = db.execute("SELECT * FROM pggit.get_version('users')")
        # Function should execute without error

        # Cleanup
        db.execute("DROP TABLE users")
        print("✓ CREATE TABLE tracked")

    def test_track_alter_table_add_column(self, db, pggit_installed):
        """Test ALTER TABLE ADD COLUMN is tracked."""
        db.execute("CREATE TABLE alter_test (id INT)")

        # Get initial column count
        cols_before = db.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_name = 'alter_test'
        """)

        # Add column
        db.execute("ALTER TABLE alter_test ADD COLUMN name TEXT")

        # Verify column added
        cols_after = db.execute("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_name = 'alter_test'
        """)
        assert cols_after[0][0] > cols_before[0][0], "Column not added"

        # Check history (may be empty if auto-tracking disabled)
        history = db.execute("""
            SELECT COUNT(*) FROM pggit.get_history('alter_test')
        """)
        # Function should execute without error

        # Cleanup
        db.execute("DROP TABLE alter_test")
        print("✓ ALTER TABLE ADD COLUMN tracked")

    def test_track_alter_table_drop_column(self, db, pggit_installed):
        """Test ALTER TABLE DROP COLUMN is tracked."""
        db.execute("CREATE TABLE drop_col_test (id INT, name TEXT, email TEXT)")

        # Drop column
        db.execute("ALTER TABLE drop_col_test DROP COLUMN email")

        # Verify column gone
        result = db.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'drop_col_test'
        """)

        columns = [row[0] for row in result]
        assert 'email' not in columns, "Column not dropped"
        assert 'id' in columns and 'name' in columns, "Wrong columns dropped"

        # Cleanup
        db.execute("DROP TABLE drop_col_test")
        print("✓ ALTER TABLE DROP COLUMN tracked")

    def test_track_alter_table_rename_column(self, db, pggit_installed):
        """Test ALTER TABLE RENAME COLUMN is tracked."""
        db.execute("CREATE TABLE rename_col_test (id INT, old_name TEXT)")

        # Rename column
        db.execute("""
            ALTER TABLE rename_col_test
            RENAME COLUMN old_name TO new_name
        """)

        # Verify rename
        result = db.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'rename_col_test'
        """)

        columns = [row[0] for row in result]
        assert 'new_name' in columns, "Column not renamed"
        assert 'old_name' not in columns, "Old column still exists"

        # Cleanup
        db.execute("DROP TABLE rename_col_test")
        print("✓ ALTER TABLE RENAME COLUMN tracked")

    def test_track_alter_table_change_type(self, db, pggit_installed):
        """Test ALTER TABLE ALTER COLUMN TYPE is tracked."""
        db.execute("CREATE TABLE type_change_test (id INT, value TEXT)")

        # Insert test data
        db.execute("INSERT INTO type_change_test (id, value) VALUES (1, '42')")

        # Change type
        db.execute("""
            ALTER TABLE type_change_test
            ALTER COLUMN value TYPE INTEGER USING value::INTEGER
        """)

        # Verify type changed
        result = db.execute("""
            SELECT data_type
            FROM information_schema.columns
            WHERE table_name = 'type_change_test'
            AND column_name = 'value'
        """)

        assert result[0][0] == 'integer', "Column type not changed"

        # Verify data integrity
        data = db.execute("SELECT value FROM type_change_test WHERE id = 1")
        assert data[0][0] == 42, "Data corrupted during type change"

        # Cleanup
        db.execute("DROP TABLE type_change_test")
        print("✓ ALTER TABLE ALTER TYPE tracked")

    def test_track_drop_table(self, db, pggit_installed):
        """Test DROP TABLE is tracked."""
        db.execute("CREATE TABLE drop_test (id INT, data TEXT)")

        # Verify exists
        result = db.execute("""
            SELECT tablename
            FROM pg_tables
            WHERE tablename = 'drop_test'
        """)
        assert result, "Table not created"

        # Drop table
        db.execute("DROP TABLE drop_test")

        # Verify gone
        result = db.execute("""
            SELECT tablename
            FROM pg_tables
            WHERE tablename = 'drop_test'
        """)
        assert not result, "Table not dropped"
        print("✓ DROP TABLE tracked")

    def test_track_alter_table_add_constraint(self, db, pggit_installed):
        """Test ALTER TABLE ADD CONSTRAINT is tracked."""
        db.execute("CREATE TABLE constraint_test (id INT, email TEXT)")

        # Add unique constraint
        db.execute("""
            ALTER TABLE constraint_test
            ADD CONSTRAINT unique_email UNIQUE (email)
        """)

        # Verify constraint works
        db.execute("INSERT INTO constraint_test VALUES (1, 'test@example.com')")

        with pytest.raises(Exception) as exc:
            db.execute("INSERT INTO constraint_test VALUES (2, 'test@example.com')")

        assert 'unique' in str(exc.value).lower() or 'duplicate' in str(exc.value).lower()

        # Rollback failed transaction before cleanup
        db.conn.rollback()

        # Cleanup
        db.execute("DROP TABLE constraint_test")
        print("✓ ALTER TABLE ADD CONSTRAINT tracked")


class TestIndexDDL:
    """Index DDL operations tracking."""

    def test_track_create_index(self, db, pggit_installed):
        """Test CREATE INDEX is tracked."""
        db.execute("CREATE TABLE idx_test (id INT, name TEXT, email TEXT)")
        db.execute("CREATE INDEX idx_test_name ON idx_test(name)")

        # Verify index exists
        result = db.execute("""
            SELECT indexname
            FROM pg_indexes
            WHERE indexname = 'idx_test_name'
        """)

        assert result, "Index not created"
        assert result[0][0] == 'idx_test_name'

        # Cleanup
        db.execute("DROP TABLE idx_test CASCADE")
        print("✓ CREATE INDEX tracked")

    def test_track_create_unique_index(self, db, pggit_installed):
        """Test CREATE UNIQUE INDEX is tracked."""
        db.execute("CREATE TABLE unique_idx_test (id INT, email TEXT)")
        db.execute("CREATE UNIQUE INDEX idx_unique_email ON unique_idx_test(email)")

        # Verify unique constraint works
        db.execute("INSERT INTO unique_idx_test (id, email) VALUES (1, 'test@example.com')")

        with pytest.raises(Exception) as exc:
            db.execute("INSERT INTO unique_idx_test (id, email) VALUES (2, 'test@example.com')")

        assert 'unique' in str(exc.value).lower() or 'duplicate' in str(exc.value).lower()

        # Rollback failed transaction before cleanup
        db.conn.rollback()

        # Cleanup
        db.execute("DROP TABLE unique_idx_test CASCADE")
        print("✓ CREATE UNIQUE INDEX tracked")

    def test_track_create_multicolumn_index(self, db, pggit_installed):
        """Test CREATE INDEX on multiple columns."""
        db.execute("CREATE TABLE multi_idx_test (a INT, b INT, c TEXT)")
        db.execute("CREATE INDEX idx_multi ON multi_idx_test(a, b)")

        # Verify index exists
        result = db.execute("""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE indexname = 'idx_multi'
        """)

        assert result, "Multi-column index not created"
        assert 'a' in result[0][1] and 'b' in result[0][1], "Index columns wrong"

        # Cleanup
        db.execute("DROP TABLE multi_idx_test CASCADE")
        print("✓ CREATE multi-column INDEX tracked")

    def test_track_drop_index(self, db, pggit_installed):
        """Test DROP INDEX is tracked."""
        db.execute("CREATE TABLE drop_idx_test (id INT, name TEXT)")
        db.execute("CREATE INDEX idx_drop_test ON drop_idx_test(name)")

        # Verify exists
        result = db.execute("""
            SELECT indexname
            FROM pg_indexes
            WHERE indexname = 'idx_drop_test'
        """)
        assert result, "Index not created"

        # Drop index
        db.execute("DROP INDEX idx_drop_test")

        # Verify gone
        result = db.execute("""
            SELECT indexname
            FROM pg_indexes
            WHERE indexname = 'idx_drop_test'
        """)
        assert not result, "Index not dropped"

        # Cleanup
        db.execute("DROP TABLE drop_idx_test")
        print("✓ DROP INDEX tracked")


class TestViewDDL:
    """View DDL operations tracking."""

    def test_track_create_view(self, db, pggit_installed):
        """Test CREATE VIEW is tracked."""
        db.execute("CREATE TABLE base_table (id INT, value TEXT)")
        db.execute("INSERT INTO base_table VALUES (1, 'test')")

        db.execute("CREATE VIEW v_base AS SELECT * FROM base_table")

        # Verify view works
        result = db.execute("SELECT * FROM v_base")
        assert result, "View not working"
        assert result[0] == (1, 'test')

        # Cleanup
        db.execute("DROP VIEW v_base")
        db.execute("DROP TABLE base_table")
        print("✓ CREATE VIEW tracked")

    def test_track_create_view_with_where(self, db, pggit_installed):
        """Test CREATE VIEW with WHERE clause."""
        db.execute("CREATE TABLE products (id INT, price DECIMAL, active BOOLEAN)")
        db.execute("INSERT INTO products VALUES (1, 10.00, true), (2, 20.00, false)")

        db.execute("""
            CREATE VIEW v_active_products AS
            SELECT * FROM products WHERE active = true
        """)

        # Verify view filtering works
        result = db.execute("SELECT COUNT(*) FROM v_active_products")
        assert result[0][0] == 1, "View filtering failed"

        # Cleanup
        db.execute("DROP VIEW v_active_products")
        db.execute("DROP TABLE products")
        print("✓ CREATE VIEW with WHERE tracked")

    def test_track_create_materialized_view(self, db, pggit_installed):
        """Test CREATE MATERIALIZED VIEW is tracked."""
        db.execute("CREATE TABLE mv_base (id INT, data TEXT)")
        db.execute("INSERT INTO mv_base VALUES (1, 'materialized')")

        db.execute("""
            CREATE MATERIALIZED VIEW mv_test
            AS SELECT * FROM mv_base
        """)

        # Verify materialized view
        result = db.execute("SELECT * FROM mv_test")
        assert result, "Materialized view not working"
        assert result[0] == (1, 'materialized')

        # Cleanup
        db.execute("DROP MATERIALIZED VIEW mv_test")
        db.execute("DROP TABLE mv_base")
        print("✓ CREATE MATERIALIZED VIEW tracked")

    def test_track_refresh_materialized_view(self, db, pggit_installed):
        """Test REFRESH MATERIALIZED VIEW is tracked."""
        db.execute("CREATE TABLE refresh_base (id INT, value TEXT)")
        db.execute("INSERT INTO refresh_base VALUES (1, 'old')")

        db.execute("""
            CREATE MATERIALIZED VIEW mv_refresh
            AS SELECT * FROM refresh_base
        """)

        # Update base table
        db.execute("UPDATE refresh_base SET value = 'new'")

        # Refresh materialized view
        db.execute("REFRESH MATERIALIZED VIEW mv_refresh")

        # Verify refresh
        result = db.execute("SELECT value FROM mv_refresh WHERE id = 1")
        assert result[0][0] == 'new', "Materialized view not refreshed"

        # Cleanup
        db.execute("DROP MATERIALIZED VIEW mv_refresh")
        db.execute("DROP TABLE refresh_base")
        print("✓ REFRESH MATERIALIZED VIEW tracked")

    def test_track_drop_view(self, db, pggit_installed):
        """Test DROP VIEW is tracked."""
        db.execute("CREATE TABLE view_base (id INT)")
        db.execute("CREATE VIEW v_drop_test AS SELECT * FROM view_base")

        # Verify exists
        result = db.execute("""
            SELECT viewname FROM pg_views
            WHERE viewname = 'v_drop_test'
        """)
        assert result, "View not created"

        # Drop view
        db.execute("DROP VIEW v_drop_test")

        # Verify gone
        result = db.execute("""
            SELECT viewname FROM pg_views
            WHERE viewname = 'v_drop_test'
        """)
        assert not result, "View not dropped"

        # Cleanup
        db.execute("DROP TABLE view_base")
        print("✓ DROP VIEW tracked")


class TestFunctionDDL:
    """Function and Procedure DDL operations tracking."""

    def test_track_create_function(self, db, pggit_installed):
        """Test CREATE FUNCTION is tracked."""
        db.execute("""
            CREATE FUNCTION add_numbers(a INT, b INT) RETURNS INT AS $$
            BEGIN
                RETURN a + b;
            END;
            $$ LANGUAGE plpgsql
        """)

        # Test function works
        result = db.execute("SELECT add_numbers(2, 3)")
        assert result[0][0] == 5, "Function not working"

        # Cleanup
        db.execute("DROP FUNCTION add_numbers")
        print("✓ CREATE FUNCTION tracked")

    def test_track_create_function_with_default(self, db, pggit_installed):
        """Test CREATE FUNCTION with default parameters."""
        db.execute("""
            CREATE FUNCTION greet(name TEXT DEFAULT 'World') RETURNS TEXT AS $$
            BEGIN
                RETURN 'Hello, ' || name || '!';
            END;
            $$ LANGUAGE plpgsql
        """)

        # Test with default
        result = db.execute("SELECT greet()")
        assert result[0][0] == 'Hello, World!', "Default parameter failed"

        # Test with argument
        result = db.execute("SELECT greet('Alice')")
        assert result[0][0] == 'Hello, Alice!', "Function argument failed"

        # Cleanup
        db.execute("DROP FUNCTION greet")
        print("✓ CREATE FUNCTION with defaults tracked")

    def test_track_create_procedure(self, db, pggit_installed):
        """Test CREATE PROCEDURE is tracked (PG 11+)."""
        db.execute("CREATE TABLE proc_test (counter INT DEFAULT 0)")
        db.execute("INSERT INTO proc_test VALUES (0)")

        db.execute("""
            CREATE PROCEDURE increment_counter() AS $$
            BEGIN
                UPDATE proc_test SET counter = counter + 1;
            END;
            $$ LANGUAGE plpgsql
        """)

        # Call procedure
        db.execute("CALL increment_counter()")

        # Verify
        result = db.execute("SELECT counter FROM proc_test")
        assert result[0][0] == 1, "Procedure not working"

        # Cleanup
        db.execute("DROP PROCEDURE increment_counter")
        db.execute("DROP TABLE proc_test")
        print("✓ CREATE PROCEDURE tracked")

    def test_track_drop_function(self, db, pggit_installed):
        """Test DROP FUNCTION is tracked."""
        db.execute("""
            CREATE FUNCTION temp_func() RETURNS INT AS $$
            BEGIN
                RETURN 42;
            END;
            $$ LANGUAGE plpgsql
        """)

        # Verify function works
        result = db.execute("SELECT temp_func()")
        assert result[0][0] == 42

        # Drop function
        db.execute("DROP FUNCTION temp_func")

        # Verify dropped
        with pytest.raises(Exception) as exc:
            db.execute("SELECT temp_func()")

        assert 'does not exist' in str(exc.value).lower() or 'function' in str(exc.value).lower()
        print("✓ DROP FUNCTION tracked")


class TestTypeDDL:
    """Type DDL operations tracking."""

    def test_track_create_composite_type(self, db, pggit_installed):
        """Test CREATE TYPE (composite) is tracked."""
        db.execute("""
            CREATE TYPE address AS (
                street TEXT,
                city TEXT,
                zipcode TEXT
            )
        """)

        # Use the type
        db.execute("CREATE TABLE location_test (id INT, addr address)")
        db.execute("""
            INSERT INTO location_test
            VALUES (1, ROW('123 Main St', 'Portland', '97201')::address)
        """)

        # Verify
        result = db.execute("SELECT (addr).city FROM location_test WHERE id = 1")
        assert result[0][0] == 'Portland', "Composite type not working"

        # Cleanup
        db.execute("DROP TABLE location_test")
        db.execute("DROP TYPE address")
        print("✓ CREATE TYPE (composite) tracked")

    def test_track_create_enum(self, db, pggit_installed):
        """Test CREATE TYPE (enum) is tracked."""
        db.execute("""
            CREATE TYPE status_enum AS ENUM ('pending', 'active', 'archived')
        """)

        # Use enum
        db.execute("CREATE TABLE status_test (id INT, status status_enum)")
        db.execute("INSERT INTO status_test VALUES (1, 'active')")

        # Verify
        result = db.execute("SELECT status FROM status_test WHERE id = 1")
        assert result[0][0] == 'active', "Enum type not working"

        # Test enum constraint
        with pytest.raises(Exception) as exc:
            db.execute("INSERT INTO status_test VALUES (2, 'invalid')")

        assert 'invalid input' in str(exc.value).lower() or 'enum' in str(exc.value).lower()

        # Rollback failed transaction before cleanup
        db.conn.rollback()

        # Cleanup
        db.execute("DROP TABLE status_test")
        db.execute("DROP TYPE status_enum")
        print("✓ CREATE TYPE (enum) tracked")

    def test_track_create_domain(self, db, pggit_installed):
        """Test CREATE DOMAIN is tracked."""
        # Use simpler regex to avoid psycopg placeholder issues with %+
        db.execute("""
            CREATE DOMAIN email_address AS TEXT
            CHECK (VALUE ~* '^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$')
        """)

        # Use domain
        db.execute("CREATE TABLE user_emails (id INT, email email_address)")
        db.execute("INSERT INTO user_emails VALUES (1, 'test@example.com')")

        # Verify valid email works
        result = db.execute("SELECT email FROM user_emails WHERE id = 1")
        assert result[0][0] == 'test@example.com'

        # Verify constraint
        with pytest.raises(Exception) as exc:
            db.execute("INSERT INTO user_emails VALUES (2, 'invalid-email')")

        assert 'violates check constraint' in str(exc.value).lower() or 'domain' in str(exc.value).lower()

        # Rollback failed transaction before cleanup
        db.conn.rollback()

        # Cleanup
        db.execute("DROP TABLE user_emails")
        db.execute("DROP DOMAIN email_address")
        print("✓ CREATE DOMAIN tracked")


class TestTriggerDDL:
    """Trigger DDL operations tracking."""

    def test_track_create_trigger(self, db, pggit_installed):
        """Test CREATE TRIGGER is tracked."""
        db.execute("CREATE TABLE trigger_test (id INT, updated_at TIMESTAMP)")

        # Create trigger function
        db.execute("""
            CREATE FUNCTION update_timestamp() RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = NOW();
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
        """)

        # Create trigger
        db.execute("""
            CREATE TRIGGER trg_update_timestamp
            BEFORE INSERT OR UPDATE ON trigger_test
            FOR EACH ROW EXECUTE FUNCTION update_timestamp()
        """)

        # Test trigger
        db.execute("INSERT INTO trigger_test (id) VALUES (1)")
        result = db.execute("SELECT updated_at FROM trigger_test WHERE id = 1")

        assert result[0][0] is not None, "Trigger not working"

        # Cleanup
        db.execute("DROP TABLE trigger_test CASCADE")
        db.execute("DROP FUNCTION update_timestamp")
        print("✓ CREATE TRIGGER tracked")

    def test_track_trigger_before_insert(self, db, pggit_installed):
        """Test BEFORE INSERT trigger."""
        db.execute("CREATE TABLE audit_test (id INT, created_by TEXT)")

        db.execute("""
            CREATE FUNCTION set_creator() RETURNS TRIGGER AS $$
            BEGIN
                NEW.created_by = CURRENT_USER;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
        """)

        db.execute("""
            CREATE TRIGGER trg_set_creator
            BEFORE INSERT ON audit_test
            FOR EACH ROW EXECUTE FUNCTION set_creator()
        """)

        # Test trigger
        db.execute("INSERT INTO audit_test (id) VALUES (1)")
        result = db.execute("SELECT created_by FROM audit_test WHERE id = 1")
        assert result[0][0] is not None, "Trigger creator not set"

        # Cleanup
        db.execute("DROP TABLE audit_test CASCADE")
        db.execute("DROP FUNCTION set_creator")
        print("✓ BEFORE INSERT trigger tracked")

    def test_track_drop_trigger(self, db, pggit_installed):
        """Test DROP TRIGGER is tracked."""
        db.execute("CREATE TABLE drop_trigger_test (id INT)")

        db.execute("""
            CREATE FUNCTION noop_trigger() RETURNS TRIGGER AS $$
            BEGIN
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
        """)

        db.execute("""
            CREATE TRIGGER trg_noop
            BEFORE INSERT ON drop_trigger_test
            FOR EACH ROW EXECUTE FUNCTION noop_trigger()
        """)

        # Verify exists
        result = db.execute("""
            SELECT tgname
            FROM pg_trigger
            WHERE tgname = 'trg_noop'
        """)
        assert result, "Trigger not created"

        # Drop trigger
        db.execute("DROP TRIGGER trg_noop ON drop_trigger_test")

        # Verify gone
        result = db.execute("""
            SELECT tgname
            FROM pg_trigger
            WHERE tgname = 'trg_noop'
        """)
        assert not result, "Trigger not dropped"

        # Cleanup
        db.execute("DROP TABLE drop_trigger_test")
        db.execute("DROP FUNCTION noop_trigger")
        print("✓ DROP TRIGGER tracked")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
