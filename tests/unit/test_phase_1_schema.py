"""
Unit tests for Phase 1 Schema
Tests schema creation, tables, columns, constraints, and indexes
"""
import pytest


class TestSchemaExists:
    """Test that pggit schema exists"""

    def test_schema_created(self, execute_sql):
        """Verify pggit schema exists"""
        result = execute_sql(
            "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'pggit'"
        )
        assert len(result) > 0, "pggit schema does not exist"

    def test_schema_has_tables(self, execute_sql):
        """Verify schema has exactly 8 tables"""
        result = execute_sql(
            """
            SELECT COUNT(*) as table_count
            FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_type = 'BASE TABLE'
            """
        )
        assert result[0][0] == 8, f"Expected 8 tables, found {result[0][0]}"


class TestTableSchemaObjects:
    """Test schema_objects table structure"""

    def test_table_exists(self, execute_sql):
        """Verify schema_objects table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'schema_objects'
            """
        )
        assert len(result) > 0, "schema_objects table does not exist"

    def test_required_columns_exist(self, execute_sql):
        """Verify all required columns exist"""
        required_columns = [
            "object_id",
            "object_type",
            "schema_name",
            "object_name",
            "current_definition",
            "content_hash",
            "version_major",
            "version_minor",
            "version_patch",
            "is_active",
            "first_seen_commit_hash",
            "last_modified_commit_hash",
            "metadata",
            "created_at",
            "last_modified_at",
        ]

        result = execute_sql(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'pggit' AND table_name = 'schema_objects'
            """
        )
        columns = [row[0] for row in result]

        for col in required_columns:
            assert col in columns, f"Column {col} missing from schema_objects"

    def test_column_types(self, execute_sql):
        """Verify column data types"""
        result = execute_sql(
            """
            SELECT column_name, data_type
            FROM information_schema.columns
            WHERE table_schema = 'pggit' AND table_name = 'schema_objects'
            ORDER BY ordinal_position
            """
        )
        columns = {row[0]: row[1] for row in result}

        assert columns["object_id"] == "bigint"
        assert columns["object_type"] == "text"
        assert columns["schema_name"] == "text"
        assert columns["object_name"] == "text"
        assert columns["current_definition"] == "text"
        assert columns["content_hash"] == "character"
        assert columns["version_major"] == "integer"
        assert columns["metadata"] == "jsonb"

    def test_unique_constraint_exists(self, execute_sql):
        """Verify UNIQUE constraint on (object_type, schema_name, object_name)"""
        result = execute_sql(
            """
            SELECT constraint_name FROM information_schema.table_constraints
            WHERE table_schema = 'pggit'
              AND table_name = 'schema_objects'
              AND constraint_type = 'UNIQUE'
            """
        )
        assert len(result) > 0, "UNIQUE constraint missing from schema_objects"

    def test_check_constraint_exists(self, execute_sql):
        """Verify CHECK constraint on object_type"""
        result = execute_sql(
            """
            SELECT constraint_name FROM information_schema.table_constraints
            WHERE table_schema = 'pggit'
              AND table_name = 'schema_objects'
              AND constraint_type = 'CHECK'
            """
        )
        assert len(result) > 0, "CHECK constraint missing from schema_objects"


class TestTableCommits:
    """Test commits table structure"""

    def test_table_exists(self, execute_sql):
        """Verify commits table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'commits'
            """
        )
        assert len(result) > 0, "commits table does not exist"

    def test_required_columns_exist(self, execute_sql):
        """Verify all required columns exist"""
        required_columns = [
            "commit_id",
            "commit_hash",
            "parent_commit_hash",
            "branch_id",
            "object_changes",
            "tree_hash",
            "author_name",
            "author_time",
            "commit_message",
            "committer_name",
            "committer_time",
            "metadata",
            "created_at",
        ]

        result = execute_sql(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'pggit' AND table_name = 'commits'
            """
        )
        columns = [row[0] for row in result]

        for col in required_columns:
            assert col in columns, f"Column {col} missing from commits"


class TestTableBranches:
    """Test branches table structure"""

    def test_table_exists(self, execute_sql):
        """Verify branches table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'branches'
            """
        )
        assert len(result) > 0, "branches table does not exist"

    def test_main_branch_created(self, execute_sql):
        """Verify main branch was created during bootstrap"""
        result = execute_sql(
            "SELECT branch_name FROM pggit.branches WHERE branch_name = 'main'"
        )
        assert len(result) > 0, "main branch was not created"

    def test_main_branch_is_active(self, execute_sql):
        """Verify main branch is ACTIVE"""
        result = execute_sql(
            "SELECT status FROM pggit.branches WHERE branch_name = 'main'"
        )
        assert len(result) > 0
        assert result[0][0] == "ACTIVE", f"main branch status is {result[0][0]}, expected ACTIVE"


class TestTableObjectHistory:
    """Test object_history table structure"""

    def test_table_exists(self, execute_sql):
        """Verify object_history table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'object_history'
            """
        )
        assert len(result) > 0, "object_history table does not exist"

    def test_required_columns_exist(self, execute_sql):
        """Verify all required columns exist"""
        required_columns = [
            "history_id",
            "object_id",
            "change_type",
            "change_severity",
            "before_hash",
            "after_hash",
            "before_version",
            "after_version",
            "before_definition",
            "after_definition",
            "commit_hash",
            "branch_id",
            "change_reason",
            "change_metadata",
            "author_name",
            "author_time",
            "created_at",
        ]

        result = execute_sql(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'pggit' AND table_name = 'object_history'
            """
        )
        columns = [row[0] for row in result]

        for col in required_columns:
            assert col in columns, f"Column {col} missing from object_history"


class TestTableMergeOperations:
    """Test merge_operations table structure"""

    def test_table_exists(self, execute_sql):
        """Verify merge_operations table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'merge_operations'
            """
        )
        assert len(result) > 0, "merge_operations table does not exist"

    def test_required_columns_exist(self, execute_sql):
        """Verify merge_id is UUID"""
        result = execute_sql(
            """
            SELECT data_type FROM information_schema.columns
            WHERE table_schema = 'pggit'
              AND table_name = 'merge_operations'
              AND column_name = 'merge_id'
            """
        )
        assert len(result) > 0
        assert result[0][0] == "uuid", f"merge_id type is {result[0][0]}, expected uuid"


class TestTableObjectDependencies:
    """Test object_dependencies table structure"""

    def test_table_exists(self, execute_sql):
        """Verify object_dependencies table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'object_dependencies'
            """
        )
        assert len(result) > 0, "object_dependencies table does not exist"


class TestTableDataTables:
    """Test data_tables table structure"""

    def test_table_exists(self, execute_sql):
        """Verify data_tables table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'data_tables'
            """
        )
        assert len(result) > 0, "data_tables table does not exist"


class TestTableConfiguration:
    """Test configuration table structure"""

    def test_table_exists(self, execute_sql):
        """Verify configuration table exists"""
        result = execute_sql(
            """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = 'configuration'
            """
        )
        assert len(result) > 0, "configuration table does not exist"

    def test_configuration_initialized(self, execute_sql):
        """Verify configuration has bootstrap values"""
        result = execute_sql("SELECT COUNT(*) FROM pggit.configuration")
        assert result[0][0] >= 6, f"Configuration not fully initialized, found {result[0][0]} records"

    def test_track_ddl_configured(self, execute_sql):
        """Verify track_ddl configuration exists"""
        result = execute_sql(
            "SELECT config_value FROM pggit.configuration WHERE config_key = 'track_ddl'"
        )
        assert len(result) > 0, "track_ddl configuration not found"


class TestIndexes:
    """Test that all indexes are created"""

    def test_schema_objects_indexes(self, execute_sql):
        """Verify schema_objects indexes exist"""
        result = execute_sql(
            """
            SELECT indexname FROM pg_indexes
            WHERE schemaname = 'pggit' AND tablename = 'schema_objects'
            """
        )
        index_names = [row[0] for row in result]

        assert "idx_schema_objects_content_hash" in index_names
        assert "idx_schema_objects_type_name" in index_names
        assert "idx_schema_objects_is_active" in index_names

    def test_commits_indexes(self, execute_sql):
        """Verify commits indexes exist"""
        result = execute_sql(
            """
            SELECT indexname FROM pg_indexes
            WHERE schemaname = 'pggit' AND tablename = 'commits'
            """
        )
        index_names = [row[0] for row in result]

        assert "idx_commits_parent_hash" in index_names
        assert "idx_commits_branch_time" in index_names
        assert "idx_commits_author" in index_names

    def test_branches_indexes(self, execute_sql):
        """Verify branches indexes exist"""
        result = execute_sql(
            """
            SELECT indexname FROM pg_indexes
            WHERE schemaname = 'pggit' AND tablename = 'branches'
            """
        )
        index_names = [row[0] for row in result]

        assert "idx_branches_parent_id" in index_names
        assert "idx_branches_status" in index_names
        assert "idx_branches_created_at" in index_names


class TestForeignKeys:
    """Test that foreign keys are properly configured"""

    def test_commits_branch_fk(self, execute_sql):
        """Verify commits.branch_id references branches"""
        result = execute_sql(
            """
            SELECT constraint_name FROM information_schema.referential_constraints
            WHERE table_name = 'commits' AND column_name = 'branch_id'
            """
        )
        assert len(result) > 0, "Foreign key from commits.branch_id not found"

    def test_object_history_object_fk(self, execute_sql):
        """Verify object_history.object_id references schema_objects"""
        result = execute_sql(
            """
            SELECT constraint_name FROM information_schema.table_constraints
            WHERE table_schema = 'pggit'
              AND table_name = 'object_history'
              AND constraint_type = 'FOREIGN KEY'
            """
        )
        assert len(result) > 0, "Foreign keys not found in object_history"
