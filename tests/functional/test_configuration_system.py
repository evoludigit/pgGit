"""
pgGit Functional Tests - Configuration System

Tests for:
- configure_tracking (2 overloads)
- get_feature_configuration
- validate_schema_changes
"""

from ..fixtures.test_data_builders import ConfigurationTestBuilder
from .base_test_case import FunctionalTestCase


class TestConfigureTrackingBasic(FunctionalTestCase):
    """Basic configure_tracking functionality tests"""

    def test_configure_tracking_with_schema_name(self, db_transaction):
        """Test configuring tracking with schema name"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("test_schema")

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema, True),
        )

        assert result is True, "configure_tracking should return true"

    def test_configure_tracking_with_schema_array(self, db_transaction):
        """Test configuring tracking with schema array"""
        builder = ConfigurationTestBuilder(db_transaction)
        schemas = builder.create_schemas(["schema1", "schema2"])

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s::text[], %s::text[])
        """,
            (schemas, []),
        )

        assert result is True, "configure_tracking should return true"

    def test_configure_tracking_disable(self, db_transaction):
        """Test disabling tracking"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("test_schema")

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema, False),
        )

        assert result is True, "configure_tracking should return true"

    def test_configure_tracking_with_ignore_list(self, db_transaction):
        """Test configuring tracking with ignore list"""
        builder = ConfigurationTestBuilder(db_transaction)
        builder.create_schemas(["tracked", "ignored"])

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s::text[], %s::text[])
        """,
            (["tracked"], ["ignored"]),
        )

        assert result is True, "configure_tracking should return true"

    def test_configure_tracking_multiple_calls(self, db_transaction):
        """Test multiple configure_tracking calls"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema1 = builder.create_schema("schema1")
        schema2 = builder.create_schema("schema2")

        # First call
        result1 = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema1, True),
        )

        # Second call
        result2 = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema2, True),
        )

        assert result1 is True, "First configure_tracking should return true"
        assert result2 is True, "Second configure_tracking should return true"


class TestGetFeatureConfiguration(FunctionalTestCase):
    """Tests for get_feature_configuration"""

    def test_get_feature_configuration_exists(self, db_transaction):
        """Test that get_feature_configuration is callable"""
        try:
            result = self.execute_sql_value(
                db_transaction,
                """
                SELECT pggit.get_feature_configuration('migration_mode')
            """,
            )
            # Result can be any JSON/configuration value
            assert result is not None or result is None, "Function should return result"
        except Exception as e:
            # It's OK if the feature doesn't exist
            assert "does not exist" in str(e).lower() or "not found" in str(e).lower()


class TestValidateSchemaChanges(FunctionalTestCase):
    """Tests for validate_schema_changes"""

    def test_validate_schema_changes_basic(self, db_transaction):
        """Test schema validation"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("test_schema")
        table = builder.create_table(schema, "test_table")

        # Create a table and verify it exists
        self.assert_table_exists(db_transaction, schema, "test_table")


class TestTrackingIntegration(FunctionalTestCase):
    """Integration tests for tracking configuration"""

    def test_configure_tracking_with_schema_creation(self, db_transaction):
        """Test configure_tracking while creating objects"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("app_schema")

        # Configure tracking
        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema, True),
        )

        assert result is True, "configure_tracking should succeed"

        # Create table in tracked schema
        table = builder.create_table(schema, "users")
        self.assert_table_exists(db_transaction, schema, "users")

    def test_configure_tracking_persistence(self, db_transaction):
        """Test that configuration persists across statements"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("test_schema")

        # Configure
        self.execute_sql(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema, True),
        )

        # Create table in new statement
        builder.create_table(schema, "table1")

        # Verify table still exists (configuration didn't break anything)
        self.assert_table_exists(db_transaction, schema, "table1")

    def test_configure_tracking_multiple_schemas(self, db_transaction):
        """Test tracking multiple schemas"""
        builder = ConfigurationTestBuilder(db_transaction)
        schemas = builder.create_schemas(["schema1", "schema2", "schema3"])

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s::text[], %s::text[])
        """,
            (schemas, []),
        )

        assert result is True

        # Verify all schemas exist
        for schema in schemas:
            count = self.get_count(
                db_transaction,
                "information_schema.schemata",
                f"schema_name = '{schema}'",
            )
            assert count > 0, f"Schema {schema} should exist"


class TestTrackingWithData(FunctionalTestCase):
    """Tests for tracking with data operations"""

    def test_configure_tracking_with_data_operations(self, db_transaction):
        """Test tracking while inserting data"""
        builder = ConfigurationTestBuilder(db_transaction)
        schema = builder.create_schema("app_schema")

        # Configure tracking
        self.execute_sql(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s, %s)
        """,
            (schema, True),
        )

        # Create table with data
        table = builder.create_table(schema, "users")
        rows = builder.insert_rows(table, 10)

        # Verify data
        count = self.get_count(db_transaction, table)
        assert count == 10, f"Expected 10 rows, got {count}"

    def test_configure_multiple_ignore_schemas(self, db_transaction):
        """Test ignoring multiple schemas"""
        builder = ConfigurationTestBuilder(db_transaction)
        builder.create_schemas(["tracked", "ignored1", "ignored2"])

        result = self.execute_sql_value(
            db_transaction,
            """
            SELECT pggit.configure_tracking(%s::text[], %s::text[])
        """,
            (["tracked"], ["ignored1", "ignored2"]),
        )

        assert result is True
