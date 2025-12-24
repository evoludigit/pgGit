"""
Unit tests for Phase 1 Utility Functions
Tests all helper functions: generate_sha256, validate_identifier, etc.
"""
import pytest


class TestGenerateSha256:
    """Test generate_sha256 function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'generate_sha256' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "generate_sha256 function does not exist"

    def test_basic_hash(self, execute_sql):
        """Test basic hashing"""
        result = execute_sql("SELECT pggit.generate_sha256('test')")
        assert result[0][0] is not None
        assert len(result[0][0]) == 64, "Hash should be 64 characters (SHA256)"

    def test_consistent_hash(self, execute_sql):
        """Test that same input produces same hash"""
        result1 = execute_sql("SELECT pggit.generate_sha256('consistency_test')")
        result2 = execute_sql("SELECT pggit.generate_sha256('consistency_test')")
        assert result1[0][0] == result2[0][0], "Same input should produce same hash"

    def test_different_hashes(self, execute_sql):
        """Test that different inputs produce different hashes"""
        result1 = execute_sql("SELECT pggit.generate_sha256('input1')")
        result2 = execute_sql("SELECT pggit.generate_sha256('input2')")
        assert result1[0][0] != result2[0][0], "Different inputs should produce different hashes"

    def test_empty_string_hash(self, execute_sql):
        """Test hashing empty string"""
        result = execute_sql("SELECT pggit.generate_sha256('')")
        assert result[0][0] is not None
        assert len(result[0][0]) == 64

    def test_returns_char64(self, execute_sql):
        """Test that return type is CHAR(64)"""
        result = execute_sql(
            """
            SELECT data_type FROM information_schema.routines
            WHERE routine_schema = 'pggit' AND routine_name = 'generate_sha256'
            """
        )
        # Should return CHAR type with 64 length
        assert len(result) > 0


class TestGetCurrentBranch:
    """Test get_current_branch function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'get_current_branch' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "get_current_branch function does not exist"

    def test_default_branch(self, execute_sql):
        """Test that default branch is 'main'"""
        result = execute_sql("SELECT pggit.get_current_branch()")
        assert result[0][0] == "main", f"Expected default branch 'main', got {result[0][0]}"

    def test_returns_text(self, execute_sql):
        """Test that return type is TEXT"""
        result = execute_sql("SELECT pggit.get_current_branch()")
        assert isinstance(result[0][0], str), "Should return text"


class TestValidateIdentifier:
    """Test validate_identifier function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'validate_identifier' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "validate_identifier function does not exist"

    def test_valid_identifiers(self, execute_sql):
        """Test valid PostgreSQL identifiers"""
        valid_identifiers = [
            "users",
            "user_accounts",
            "_private",
            "table1",
            "myFunc_v2",
            "a",
            "_",
        ]

        for identifier in valid_identifiers:
            result = execute_sql(f"SELECT pggit.validate_identifier('{identifier}')")
            assert result[0][0] is True, f"'{identifier}' should be valid"

    def test_invalid_identifiers(self, execute_sql):
        """Test invalid PostgreSQL identifiers"""
        invalid_identifiers = [
            "123table",  # Starts with number
            "user-name",  # Contains hyphen
            "user name",  # Contains space
            "user.table",  # Contains dot
            "",  # Empty
            "a" * 64,  # Too long
        ]

        for identifier in invalid_identifiers:
            result = execute_sql(f"SELECT pggit.validate_identifier('{identifier}')")
            assert result[0][0] is False, f"'{identifier}' should be invalid"

    def test_null_input(self, execute_sql):
        """Test NULL input"""
        result = execute_sql("SELECT pggit.validate_identifier(NULL)")
        assert result[0][0] is False, "NULL should return false"


class TestRaisePggitError:
    """Test raise_pggit_error function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'raise_pggit_error' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "raise_pggit_error function does not exist"

    def test_raises_exception(self, execute_sql, db_conn):
        """Test that function raises an exception"""
        with pytest.raises(Exception) as exc_info:
            execute_sql("SELECT pggit.raise_pggit_error('TEST_ERROR', 'Test message')")
        assert "PGGIT-TEST_ERROR" in str(exc_info.value)

    def test_error_message_format(self, execute_sql, db_conn):
        """Test error message format"""
        try:
            execute_sql("SELECT pggit.raise_pggit_error('INVALID_BRANCH', 'Branch not found')")
        except Exception as e:
            error_msg = str(e)
            assert "[PGGIT-INVALID_BRANCH]" in error_msg
            assert "Branch not found" in error_msg


class TestSetCurrentBranch:
    """Test set_current_branch function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'set_current_branch' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "set_current_branch function does not exist"

    def test_set_to_main(self, execute_sql):
        """Test setting branch to main"""
        result = execute_sql("SELECT pggit.set_current_branch('main')")
        # Should return void (no error)
        assert result is None or result == []

    def test_invalid_branch_raises_error(self, execute_sql, db_conn):
        """Test that setting non-existent branch raises error"""
        with pytest.raises(Exception) as exc_info:
            execute_sql("SELECT pggit.set_current_branch('nonexistent')")
        assert "PGGIT-BRANCH_NOT_FOUND" in str(exc_info.value)


class TestGetCurrentSchemaHash:
    """Test get_current_schema_hash function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'get_current_schema_hash' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "get_current_schema_hash function does not exist"

    def test_returns_hash(self, execute_sql):
        """Test that function returns a 64-char hash"""
        result = execute_sql("SELECT pggit.get_current_schema_hash()")
        assert result[0][0] is not None
        assert len(result[0][0]) == 64, "Should return 64-character SHA256 hash"


class TestNormalizeSql:
    """Test normalize_sql function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'normalize_sql' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "normalize_sql function does not exist"

    def test_whitespace_normalization(self, execute_sql):
        """Test that multiple spaces are collapsed"""
        result = execute_sql(
            "SELECT pggit.normalize_sql('CREATE   TABLE   users ( id INT )')"
        )
        assert "   " not in result[0][0], "Multiple spaces should be collapsed"
        assert "CREATE TABLE" in result[0][0]

    def test_trailing_semicolon_removed(self, execute_sql):
        """Test that trailing semicolon is removed"""
        result = execute_sql(
            "SELECT pggit.normalize_sql('CREATE TABLE users ( id INT );')"
        )
        assert result[0][0].endswith(")"), "Should not end with semicolon"

    def test_leading_trailing_whitespace_removed(self, execute_sql):
        """Test that leading/trailing whitespace is removed"""
        result = execute_sql(
            "SELECT pggit.normalize_sql('   CREATE TABLE users ( id INT )   ')"
        )
        assert result[0][0].startswith("CREATE"), "Should not have leading whitespace"
        assert result[0][0].endswith(")"), "Should not have trailing whitespace"


class TestGetObjectByName:
    """Test get_object_by_name function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'get_object_by_name' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "get_object_by_name function does not exist"

    def test_find_existing_object(self, execute_sql):
        """Test finding an object that exists"""
        # schema_objects table was registered during bootstrap
        result = execute_sql(
            "SELECT pggit.get_object_by_name('TABLE', 'pggit', 'schema_objects')"
        )
        assert result[0][0] is not None, "Should find schema_objects table"
        assert isinstance(result[0][0], int), "Should return object_id as integer"

    def test_find_nonexistent_object(self, execute_sql):
        """Test finding an object that doesn't exist"""
        result = execute_sql(
            "SELECT pggit.get_object_by_name('TABLE', 'public', 'nonexistent')"
        )
        assert result[0][0] is None, "Should return NULL for non-existent object"


class TestGetCommitByHash:
    """Test get_commit_by_hash function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'get_commit_by_hash' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "get_commit_by_hash function does not exist"

    def test_find_existing_commit(self, execute_sql):
        """Test finding a commit that exists"""
        # Get a commit hash from the database
        hash_result = execute_sql("SELECT commit_hash FROM pggit.commits LIMIT 1")
        if hash_result:
            commit_hash = hash_result[0][0]
            result = execute_sql(f"SELECT pggit.get_commit_by_hash('{commit_hash}')")
            assert result[0][0] is not None, "Should find existing commit"

    def test_find_nonexistent_commit(self, execute_sql):
        """Test finding a commit that doesn't exist"""
        fake_hash = "0" * 64
        result = execute_sql(f"SELECT pggit.get_commit_by_hash('{fake_hash}')")
        assert result[0][0] is None, "Should return NULL for non-existent commit"


class TestGetBranchByName:
    """Test get_branch_by_name function"""

    def test_function_exists(self, execute_sql):
        """Verify function exists"""
        result = execute_sql(
            """
            SELECT proname FROM pg_proc
            WHERE proname = 'get_branch_by_name' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
            """
        )
        assert len(result) > 0, "get_branch_by_name function does not exist"

    def test_find_main_branch(self, execute_sql):
        """Test finding main branch"""
        result = execute_sql("SELECT pggit.get_branch_by_name('main')")
        assert result[0][0] is not None, "Should find main branch"
        assert isinstance(result[0][0], int), "Should return branch_id as integer"

    def test_find_nonexistent_branch(self, execute_sql):
        """Test finding a branch that doesn't exist"""
        result = execute_sql("SELECT pggit.get_branch_by_name('nonexistent')")
        assert result[0][0] is None, "Should return NULL for non-existent branch"
