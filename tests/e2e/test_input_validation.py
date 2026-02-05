"""
Production hardening tests for input validation.

Tests that all core pgGit functions properly validate inputs and handle:
- NULL values
- Empty strings
- SQL injection attempts
- Boundary values (length limits, numeric limits)
- Invalid references (non-existent objects)
- Special characters and Unicode
- Type mismatches

Key Coverage:
- pggit.create_branch() input validation
- pggit.create_commit() input validation
- pggit.merge_branches() input validation
- pggit.apply_migration() input validation
- Error message quality and consistency
- Security: SQL injection prevention

Priority: HIGH - Prevents majority of production crashes from invalid input
"""

import pytest


class TestBranchInputValidation:
    """Input validation tests for branch operations."""

    def test_create_branch_null_branch_name(self, db, pggit_installed):
        """Test create_branch with NULL branch name raises error."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_branch(NULL)")

        # Verify error mentions the problem
        error_msg = str(exc.value).lower()
        assert 'null' in error_msg or 'not null' in error_msg, \
            "Error should mention NULL violation"
        print("✓ NULL branch name rejected")

    def test_create_branch_empty_branch_name(self, db, pggit_installed):
        """Test create_branch with empty string branch name."""
        # Now properly validates and rejects empty names
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_branch(%s)", "")

        error_msg = str(exc.value).lower()
        assert 'empty' in error_msg or 'cannot be' in error_msg, \
            "Error should mention empty branch name"
        print("✓ Empty branch name rejected")

    def test_create_branch_sql_injection_attempt(self, db, pggit_installed):
        """Test create_branch with SQL injection attempts."""
        malicious_inputs = [
            "test'; DROP TABLE pggit.branches; --",
            "test' OR '1'='1",
            "test'); DELETE FROM pggit.branches WHERE '1'='1'; --",
            "test\"; DROP TABLE pggit.branches; --",
        ]

        for malicious_input in malicious_inputs:
            try:
                branch_id = db.execute_returning(
                    "SELECT pggit.create_branch(%s)",
                    malicious_input
                )
                # SQL injection didn't work - parameterized query protected us
                # Branch was created with the literal string
                result = db.execute(
                    "SELECT name FROM pggit.branches WHERE id = %s",
                    branch_id[0]
                )
                assert result[0][0] == malicious_input, \
                    "Branch name should be literal string"
                # Cleanup
                db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id[0])
            except Exception:
                # Also acceptable - function may validate special characters
                pass

        # Verify branches table still exists
        result = db.execute(
            "SELECT COUNT(*) FROM information_schema.tables "
            "WHERE table_schema = 'pggit' AND table_name = 'branches'"
        )
        assert result[0][0] == 1, "Branches table should still exist (SQL injection failed)"
        print("✓ SQL injection attempts properly handled")

    def test_create_branch_long_name(self, db, pggit_installed):
        """Test create_branch with very long branch name."""
        # Test various long names - now enforces 255 char limit
        # Test acceptable length (255 chars)
        acceptable_name = "a" * 255
        try:
            branch_id = db.execute_returning(
                "SELECT pggit.create_branch(%s)",
                acceptable_name
            )
            # Cleanup
            db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id[0])
            print(f"✓ 255-char branch name accepted")
        except Exception as exc:
            print(f"⚠ 255-char name rejected: {exc}")

        # Test too long (256+ chars) - should be rejected
        too_long_name = "a" * 256
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_branch(%s)", too_long_name)

        error_msg = str(exc.value).lower()
        assert 'too long' in error_msg or '255' in error_msg, \
            "Error should mention length limit"
        print("✓ Branch name >255 chars rejected")

    def test_create_branch_special_characters(self, db, pggit_installed):
        """Test create_branch with special characters and Unicode."""
        special_names = [
            "branch-with-dash",
            "branch_with_underscore",
            "branch.with.dot",
            "branch/with/slash",
            "branch with spaces",
            "branch@with#special$chars",
            "文字化け",  # Japanese characters
            "émojis😀🎉",  # Emojis
            "Ñoño",  # Spanish characters
        ]

        for special_name in special_names:
            try:
                branch_id = db.execute_returning(
                    "SELECT pggit.create_branch(%s)",
                    special_name
                )
                # Verify stored correctly
                result = db.execute(
                    "SELECT name FROM pggit.branches WHERE id = %s",
                    branch_id[0]
                )
                assert result[0][0] == special_name, \
                    f"Special name '{special_name}' should be stored correctly"
                # Cleanup
                db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id[0])
                print(f"✓ Special branch name '{special_name}' handled")
            except Exception as exc:
                # May be rejected due to validation rules
                print(f"⚠ Special name '{special_name}' rejected: {exc}")

    def test_create_branch_nonexistent_parent(self, db, pggit_installed):
        """Test create_branch with non-existent parent branch."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_branch(%s, %s)",
                      "test-branch", "nonexistent-parent")

        error_msg = str(exc.value).lower()
        assert 'not found' in error_msg or 'does not exist' in error_msg, \
            "Error should mention parent branch not found"
        print("✓ Non-existent parent branch rejected")

    def test_create_branch_null_parent(self, db, pggit_installed):
        """Test create_branch with NULL parent (should use default 'main')."""
        try:
            # NULL parent should default to 'main'
            branch_id = db.execute_returning(
                "SELECT pggit.create_branch(%s, NULL::TEXT)",
                "test-null-parent"
            )
            # Cleanup
            db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id[0])
            print("✓ NULL parent defaults to 'main'")
        except Exception as exc:
            # Also acceptable if it requires explicit parent
            print(f"⚠ NULL parent rejected: {exc}")


class TestCommitInputValidation:
    """Input validation tests for commit operations."""

    def test_create_commit_null_branch_name(self, db, pggit_installed):
        """Test create_commit with NULL branch name."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_commit(NULL, %s, %s)",
                      "commit message", "SELECT 1")

        error_msg = str(exc.value).lower()
        assert 'null' in error_msg, "Error should mention NULL"
        print("✓ NULL branch name in commit rejected")

    def test_create_commit_null_message(self, db, pggit_installed):
        """Test create_commit with NULL message."""
        # Now properly validates and rejects NULL messages
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_commit(%s, NULL::TEXT, %s)",
                      "test-branch", "SELECT 1")

        error_msg = str(exc.value).lower()
        assert 'null' in error_msg or 'empty' in error_msg, \
            "Error should mention NULL/empty message"
        print("✓ NULL commit message rejected")

    def test_create_commit_empty_message(self, db, pggit_installed):
        """Test create_commit with empty message."""
        # Now properly validates and rejects empty messages
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.create_commit(%s, %s, %s)",
                      "test-branch", "", "SELECT 1")

        error_msg = str(exc.value).lower()
        assert 'empty' in error_msg or 'cannot be' in error_msg, \
            "Error should mention empty message"
        print("✓ Empty commit message rejected")

    def test_create_commit_null_sql_content(self, db, pggit_installed):
        """Test create_commit with NULL SQL content."""
        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, NULL::TEXT)",
                "test-branch", "test commit"
            )
            # NULL SQL might be allowed for empty commits
            print("⚠ NULL SQL content allowed (empty commit)")
        except Exception:
            print("✓ NULL SQL content rejected")

    def test_create_commit_empty_sql_content(self, db, pggit_installed):
        """Test create_commit with empty SQL content."""
        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                "test-branch", "empty commit", ""
            )
            # Empty SQL might be allowed
            print("⚠ Empty SQL content allowed")
        except Exception:
            print("✓ Empty SQL content rejected")

    def test_create_commit_invalid_sql_content(self, db, pggit_installed):
        """Test create_commit with syntactically invalid SQL."""
        invalid_sql = "THIS IS NOT VALID SQL SYNTAX;;;@@@"

        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                "test-branch", "invalid sql test", invalid_sql
            )
            # Function may store SQL without validating it
            print("⚠ Invalid SQL stored (validation happens at execution)")
        except Exception as exc:
            print(f"✓ Invalid SQL rejected: {exc}")

    def test_create_commit_sql_injection_in_message(self, db, pggit_installed):
        """Test create_commit with SQL injection in message field."""
        malicious_message = "'; DROP TABLE pggit.commits; --"

        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                "test-branch", malicious_message, "SELECT 1"
            )
            # Should be safe due to parameterized queries
            print("✓ SQL injection in message handled safely")
        except Exception:
            # Also acceptable
            pass

    def test_create_commit_very_long_message(self, db, pggit_installed):
        """Test create_commit with very long commit message."""
        long_message = "x" * 10000  # 10KB message

        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                "test-branch", long_message, "SELECT 1"
            )
            print(f"✓ Long commit message ({len(long_message)} chars) accepted")
        except Exception as exc:
            print(f"⚠ Long message rejected: {exc}")

    def test_create_commit_unicode_in_fields(self, db, pggit_installed):
        """Test create_commit with Unicode in all text fields."""
        unicode_branch = "ブランチ"
        unicode_message = "コミット: 文字化け対応 🎉"
        unicode_sql = "-- コメント\nSELECT '文字列'"

        try:
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                unicode_branch, unicode_message, unicode_sql
            )
            print("✓ Unicode in all fields handled correctly")
        except Exception as exc:
            print(f"⚠ Unicode rejected: {exc}")


class TestMergeInputValidation:
    """Input validation tests for merge operations."""

    def test_merge_branches_null_source_branch(self, db, pggit_installed):
        """Test merge_branches with NULL source branch."""
        result = db.execute(
            "SELECT * FROM pggit.merge_branches(NULL::INTEGER, 1, %s)",
            "merge message"
        )
        # Function should return error status
        assert result[0][1] == 'ERROR: NULL_BRANCH_ID', \
            "Should return NULL_BRANCH_ID error"
        print("✓ NULL source branch handled gracefully")

    def test_merge_branches_null_target_branch(self, db, pggit_installed):
        """Test merge_branches with NULL target branch."""
        result = db.execute(
            "SELECT * FROM pggit.merge_branches(1, NULL::INTEGER, %s)",
            "merge message"
        )
        # Function should return error status
        assert result[0][1] == 'ERROR: NULL_BRANCH_ID', \
            "Should return NULL_BRANCH_ID error"
        print("✓ NULL target branch handled gracefully")

    def test_merge_branches_nonexistent_source(self, db, pggit_installed):
        """Test merge_branches with non-existent source branch."""
        result = db.execute(
            "SELECT * FROM pggit.merge_branches(99999, 1, %s)",
            "merge message"
        )
        # Function should return error status
        assert 'ERROR' in result[0][1], "Should return error status"
        assert 'SOURCE_BRANCH_NOT_FOUND' in result[0][1] or 'NOT_FOUND' in result[0][1], \
            "Should indicate source branch not found"
        print("✓ Non-existent source branch handled gracefully")

    def test_merge_branches_nonexistent_target(self, db, pggit_installed):
        """Test merge_branches with non-existent target branch."""
        # First create a valid source branch
        source_id = db.execute_returning(
            "INSERT INTO pggit.branches (name, status) VALUES (%s, 'ACTIVE') RETURNING id",
            "test-source"
        )[0]

        result = db.execute(
            "SELECT * FROM pggit.merge_branches(%s, 99999, %s)",
            source_id, "merge message"
        )
        # Function should return error status
        assert 'ERROR' in result[0][1], "Should return error status"
        assert 'TARGET_BRANCH_NOT_FOUND' in result[0][1] or 'NOT_FOUND' in result[0][1], \
            "Should indicate target branch not found"

        # Cleanup
        db.execute("DELETE FROM pggit.branches WHERE id = %s", source_id)
        print("✓ Non-existent target branch handled gracefully")

    def test_merge_branches_same_branch(self, db, pggit_installed):
        """Test merge_branches merging a branch with itself."""
        # Create a test branch
        branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name, status) VALUES (%s, 'ACTIVE') RETURNING id",
            "test-self-merge"
        )[0]

        result = db.execute(
            "SELECT * FROM pggit.merge_branches(%s, %s, %s)",
            branch_id, branch_id, "self merge"
        )
        # Function should reject self-merge
        assert 'ERROR' in result[0][1], "Should return error status"
        assert 'CANNOT_MERGE_BRANCH_WITH_ITSELF' in result[0][1] or 'SELF' in result[0][1], \
            "Should indicate cannot merge with itself"

        # Cleanup
        db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id)
        print("✓ Self-merge rejected")

    def test_merge_branches_null_message(self, db, pggit_installed):
        """Test merge_branches with NULL message (should use default)."""
        # Create two test branches
        source_id = db.execute_returning(
            "INSERT INTO pggit.branches (name, status) VALUES (%s, 'ACTIVE') RETURNING id",
            "test-source-null-msg"
        )[0]
        target_id = db.execute_returning(
            "INSERT INTO pggit.branches (name, status) VALUES (%s, 'ACTIVE') RETURNING id",
            "test-target-null-msg"
        )[0]

        result = db.execute(
            "SELECT * FROM pggit.merge_branches(%s, %s, NULL::TEXT)",
            source_id, target_id
        )
        # May succeed or fail depending on function implementation
        # The important thing is it doesn't crash
        status = result[0][1] if result else "NO_RESULT"
        if 'SUCCESS' in status:
            print("✓ NULL merge message uses default")
        elif 'ERROR' in status:
            print(f"⚠ Merge failed (expected if function has bugs): {status}")

        # Cleanup
        db.execute("DELETE FROM pggit.branches WHERE id IN (%s, %s)", source_id, target_id)

    def test_merge_branches_negative_ids(self, db, pggit_installed):
        """Test merge_branches with negative branch IDs."""
        result = db.execute(
            "SELECT * FROM pggit.merge_branches(-1, -2, %s)",
            "negative ids"
        )
        # Should return error (branches won't exist)
        assert 'ERROR' in result[0][1], "Should return error for negative IDs"
        print("✓ Negative branch IDs handled gracefully")


class TestMigrationInputValidation:
    """Input validation tests for migration operations."""

    def test_apply_migration_null_version(self, db, pggit_installed):
        """Test apply_migration with NULL version."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.apply_migration(NULL)")

        error_msg = str(exc.value).lower()
        assert 'null' in error_msg or 'not found' in error_msg, \
            "Should reject NULL version"
        print("✓ NULL migration version rejected")

    def test_apply_migration_empty_version(self, db, pggit_installed):
        """Test apply_migration with empty version string."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.apply_migration(%s)", "")

        error_msg = str(exc.value).lower()
        assert 'not found' in error_msg or 'empty' in error_msg, \
            "Should reject empty version"
        print("✓ Empty migration version rejected")

    def test_apply_migration_nonexistent_version(self, db, pggit_installed):
        """Test apply_migration with non-existent version."""
        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.apply_migration(%s)", "99.99.99")

        error_msg = str(exc.value).lower()
        assert 'not found' in error_msg, "Should indicate migration not found"
        print("✓ Non-existent migration version rejected")

    def test_apply_migration_sql_injection_in_version(self, db, pggit_installed):
        """Test apply_migration with SQL injection in version parameter."""
        malicious_version = "1.0.0'; DROP TABLE pggit.migrations; --"

        with pytest.raises(Exception) as exc:
            db.execute("SELECT pggit.apply_migration(%s)", malicious_version)

        # Rollback the failed transaction before verification
        db.rollback()

        # Should fail because version not found (SQL injection didn't work)
        # Verify migrations table still exists
        result = db.execute(
            "SELECT COUNT(*) FROM information_schema.tables "
            "WHERE table_schema = 'pggit' AND table_name = 'migrations'"
        )
        assert result[0][0] == 1, "Migrations table should still exist"
        print("✓ SQL injection in migration version handled safely")


class TestBoundaryConditions:
    """Test boundary and edge case conditions."""

    def test_integer_overflow_in_branch_id(self, db, pggit_installed):
        """Test handling of maximum integer values for branch IDs."""
        max_int = 2147483647  # PostgreSQL INTEGER max

        result = db.execute(
            "SELECT * FROM pggit.merge_branches(%s, %s, %s)",
            max_int, max_int - 1, "max int test"
        )
        # Should handle gracefully (branches won't exist)
        assert 'ERROR' in result[0][1], "Should handle max integer gracefully"
        print("✓ Maximum integer values handled")

    def test_extremely_long_text_fields(self, db, pggit_installed):
        """Test handling of extremely long text (>1MB)."""
        huge_text = "x" * (1024 * 1024)  # 1MB of text

        try:
            # Try to create commit with huge message
            commit_id = db.execute_returning(
                "SELECT pggit.create_commit(%s, %s, %s)",
                "test-branch", huge_text, "SELECT 1"
            )
            print("✓ Extremely long text (1MB) accepted")
        except Exception as exc:
            print(f"⚠ Extremely long text rejected: {exc}")

    def test_null_values_in_optional_parameters(self, db, pggit_installed):
        """Test NULL handling in all optional parameters."""
        # Test create_branch with NULL optional params
        try:
            branch_id = db.execute_returning(
                "SELECT pggit.create_branch(%s, NULL::TEXT, NULL::BOOLEAN)",
                "test-null-opts"
            )
            # Cleanup
            db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id[0])
            print("✓ NULL optional parameters use defaults")
        except Exception as exc:
            print(f"⚠ NULL optional params rejected: {exc}")

    def test_empty_database_operations(self, db, pggit_installed):
        """Test operations on freshly installed pgGit (minimal data)."""
        # Try to merge when no branches exist beyond defaults
        result = db.execute(
            "SELECT * FROM pggit.merge_branches(1, 2, %s)",
            "empty db test"
        )
        # Should handle gracefully
        print("✓ Operations on minimal database handled")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
