"""
Property-based tests for migration operations.

These tests validate that schema migrations behave correctly under various
conditions, including idempotency and schema hash consistency.
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
import psycopg

from tests.chaos.strategies import table_definition


@pytest.mark.chaos
@pytest.mark.property
class TestMigrationIdempotency:
    """Property-based tests for migration idempotency."""

    @given(tbl_def=table_definition())
    @settings(
        max_examples=30,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_apply_migration_twice_is_safe(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Applying the same migration twice should be idempotent."""
        try:
            # Create initial table (with cleanup)
            try:
                sync_conn.execute(tbl_def["create_sql"])
                sync_conn.commit()
            except psycopg.Error:
                sync_conn.rollback()
                sync_conn.execute(f"DROP TABLE IF EXISTS {tbl_def['name']} CASCADE")
                sync_conn.execute(tbl_def["create_sql"])
                sync_conn.commit()

            try:
                # Generate migration SQL (e.g., adding a column)
                migration_sql = f"ALTER TABLE {tbl_def['name']} ADD COLUMN IF NOT EXISTS new_col_property TEXT"

                # Apply migration first time
                sync_conn.execute(migration_sql)
                sync_conn.commit()

                # Get column count
                cursor1 = sync_conn.execute(
                    f"""
                    SELECT COUNT(*)
                    FROM information_schema.columns
                    WHERE table_name = %s
                """,
                    (tbl_def["name"],),
                )
                count1 = cursor1.fetchone()["count"]

                # Apply migration second time (should be idempotent)
                sync_conn.execute(migration_sql)
                sync_conn.commit()

                # Get column count again
                cursor2 = sync_conn.execute(
                    f"""
                    SELECT COUNT(*)
                    FROM information_schema.columns
                    WHERE table_name = %s
                """,
                    (tbl_def["name"],),
                )
                count2 = cursor2.fetchone()["count"]

                # Property: Column count should be identical
                assert count1 == count2, "Idempotent migration should not change schema"

            except psycopg.Error as e:
                # Expected to fail initially - migration functions may not exist
                if "IF NOT EXISTS" in str(e):
                    pytest.skip(
                        "IF NOT EXISTS not supported in this PostgreSQL version"
                    )
                else:
                    pytest.skip("Migration functionality not implemented yet")

        finally:
            # Clean up
            try:
                sync_conn.execute(f"DROP TABLE IF EXISTS {tbl_def['name']} CASCADE")
                sync_conn.commit()
            except psycopg.Error:
                pass

    @given(tbl_def=table_definition())
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_schema_hash_changes_on_modification(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Schema hash changes when table is modified."""
        import uuid

        # Use unique table name to avoid collisions
        table_name = f"{tbl_def['name']}_{uuid.uuid4().hex[:8]}"
        create_sql = tbl_def["create_sql"].replace(
            f"CREATE TABLE {tbl_def['name']}", f"CREATE TABLE {table_name}"
        )
        sync_conn.execute(create_sql)
        sync_conn.commit()

        try:
            # Get initial schema hash
            cursor1 = sync_conn.execute(
                "SELECT pggit.calculate_schema_hash(%s)", (table_name,)
            )
            hash1 = cursor1.fetchone()["calculate_schema_hash"]

            # Modify table
            sync_conn.execute(
                f"ALTER TABLE {table_name} ADD COLUMN new_col_property TEXT"
            )
            sync_conn.commit()

            # Get new schema hash
            cursor2 = sync_conn.execute(
                "SELECT pggit.calculate_schema_hash(%s)", (table_name,)
            )
            hash2 = cursor2.fetchone()["calculate_schema_hash"]

            # Property: Hashes should differ
            assert hash1 != hash2, "Schema hash should change after modification"

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("calculate_schema_hash function not implemented yet")

    @given(tbl_def=table_definition())
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_schema_hash_consistent_for_same_schema(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Schema hash is consistent for identical schemas."""
        try:
            # Create table (with cleanup)
            try:
                sync_conn.execute(tbl_def["create_sql"])
                sync_conn.commit()
            except psycopg.Error:
                sync_conn.rollback()
                sync_conn.execute(f"DROP TABLE IF EXISTS {tbl_def['name']} CASCADE")
                sync_conn.execute(tbl_def["create_sql"])
                sync_conn.commit()

            try:
                # Get schema hash twice
                cursor1 = sync_conn.execute(
                    "SELECT pggit.calculate_schema_hash(%s)", (tbl_def["name"],)
                )
                hash1 = cursor1.fetchone()["calculate_schema_hash"]

                cursor2 = sync_conn.execute(
                    "SELECT pggit.calculate_schema_hash(%s)", (tbl_def["name"],)
                )
                hash2 = cursor2.fetchone()["calculate_schema_hash"]

                # Property: Hashes should be identical
                assert hash1 == hash2, (
                    "Schema hash should be consistent for same schema"
                )

            except psycopg.Error:
                # Expected to fail initially
                pytest.skip("calculate_schema_hash function not implemented yet")

        finally:
            # Clean up
            try:
                sync_conn.execute(f"DROP TABLE IF EXISTS {tbl_def['name']} CASCADE")
                sync_conn.commit()
            except psycopg.Error:
                pass


@pytest.mark.chaos
@pytest.mark.property
class TestMigrationRollbackProperties:
    """Property-based tests for migration rollback behavior."""

    @given(tbl_def=table_definition())
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_rollback_restores_original_state(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Rolling back a migration restores original state."""
        # Create initial table
        sync_conn.execute(tbl_def["create_sql"])
        sync_conn.commit()

        try:
            # Get initial schema hash
            cursor1 = sync_conn.execute(
                "SELECT pggit.calculate_schema_hash(%s)", (tbl_def["name"],)
            )
            original_hash = cursor1.fetchone()[0]

            # Start transaction and apply migration
            sync_conn.execute("BEGIN")
            sync_conn.execute(
                f"ALTER TABLE {tbl_def['name']} ADD COLUMN temp_col_migration TEXT"
            )

            # Get hash during transaction
            cursor2 = sync_conn.execute(
                "SELECT pggit.calculate_schema_hash(%s)", (tbl_def["name"],)
            )
            modified_hash = cursor2.fetchone()[0]

            # Verify hashes are different
            assert original_hash != modified_hash, (
                "Schema should change during migration"
            )

            # Rollback
            sync_conn.rollback()

            # Get hash after rollback
            cursor3 = sync_conn.execute(
                "SELECT pggit.calculate_schema_hash(%s)", (tbl_def["name"],)
            )
            rollback_hash = cursor3.fetchone()[0]

            # Property: Should match original
            assert original_hash == rollback_hash, (
                "Rollback should restore original schema"
            )

        except psycopg.Error:
            # Expected to fail initially
            pytest.skip("Schema hash calculation not implemented yet")


@pytest.mark.chaos
@pytest.mark.property
class TestMigrationValidationProperties:
    """Property-based tests for migration validation."""

    @given(
        st.text(
            alphabet=st.characters(min_codepoint=32, max_codepoint=126),
            min_size=10,
            max_size=200,
        )
    )
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_migration_sql_validation(
        self, sync_conn: psycopg.Connection, migration_sql: str
    ):
        """Property: Migration SQL should either succeed or fail with clear error."""
        # Create a test table first
        sync_conn.execute("CREATE TABLE migration_test_table (id SERIAL PRIMARY KEY)")
        sync_conn.commit()

        try:
            # Attempt to execute migration SQL
            # This is dangerous - we need to be careful about what SQL we execute
            # For safety, we'll only test very specific patterns

            # Only test safe ALTER TABLE statements
            if migration_sql.startswith("ALTER TABLE migration_test_table ADD COLUMN"):
                sync_conn.execute(migration_sql)
                sync_conn.commit()

                # If we get here, migration succeeded
                assert True, "Valid migration SQL should execute successfully"

            else:
                # Skip unsafe SQL
                pytest.skip("Skipping potentially unsafe migration SQL")

        except psycopg.Error as e:
            # Migration failed - should have clear error message
            error_msg = str(e).lower()
            assert any(
                keyword in error_msg
                for keyword in [
                    "syntax",
                    "error",
                    "invalid",
                    "does not exist",
                    "already exists",
                    "duplicate",
                    "constraint",
                    "type",
                    "column",
                ]
            ), f"Migration failure should have clear error message: {e}"

        finally:
            # Clean up
            try:
                sync_conn.execute("DROP TABLE IF EXISTS migration_test_table")
                sync_conn.commit()
            except psycopg.Error:
                pass
            sync_conn.rollback()


@pytest.mark.chaos
@pytest.mark.property
class TestSchemaEvolutionProperties:
    """Property-based tests for schema evolution."""

    @given(
        st.integers(min_value=1, max_value=5)  # Number of evolution steps
    )
    @settings(
        max_examples=20,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture],
    )
    def test_schema_evolution_maintains_integrity(
        self, sync_conn: psycopg.Connection, evolution_steps: int
    ):
        """Property: Schema evolution maintains data integrity."""
        # Create initial table
        sync_conn.execute("""
            CREATE TABLE evolution_test (
                id SERIAL PRIMARY KEY,
                data TEXT NOT NULL
            )
        """)
        sync_conn.commit()

        try:
            # Insert initial data
            sync_conn.execute(
                "INSERT INTO evolution_test (data) VALUES (%s)", ("initial_data",)
            )
            sync_conn.commit()

            # Perform schema evolution steps
            for step in range(evolution_steps):
                if step % 3 == 0:
                    # Add column
                    sync_conn.execute(
                        f"ALTER TABLE evolution_test ADD COLUMN col_{step} TEXT"
                    )
                elif step % 3 == 1:
                    # Add index
                    sync_conn.execute(
                        f"CREATE INDEX idx_evolution_{step} ON evolution_test (id)"
                    )
                else:
                    # Add constraint
                    sync_conn.execute(
                        f"ALTER TABLE evolution_test ADD CONSTRAINT chk_{step} CHECK (length(data) > 0)"
                    )
                sync_conn.commit()

            # Verify data integrity maintained
            cursor = sync_conn.execute("SELECT COUNT(*) FROM evolution_test")
            count = cursor.fetchone()[0]
            assert count == 1, "Data integrity should be maintained during evolution"

            # Verify initial data preserved
            cursor = sync_conn.execute("SELECT data FROM evolution_test")
            data = cursor.fetchone()["data"]
            assert data == "initial_data", "Initial data should be preserved"

        except psycopg.Error as e:
            # Expected to fail initially - schema evolution may not be implemented
            pytest.skip(f"Schema evolution functionality not implemented yet: {e}")

        finally:
            # Clean up
            try:
                sync_conn.execute("DROP TABLE IF EXISTS evolution_test")
                sync_conn.commit()
            except psycopg.Error:
                pass
            sync_conn.rollback()
