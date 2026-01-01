import pytest
import psycopg


class TestInputValidation:
    """Test input validation for all backup functions."""

    def test_cleanup_old_jobs_null_retention(self, db, pggit_installed):
        """NULL retention_days should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.cleanup_old_jobs(NULL, TRUE)")

    def test_cleanup_old_jobs_negative_retention(self, db, pggit_installed):
        """Negative retention_days should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.cleanup_old_jobs(-5, TRUE)")

    def test_cleanup_old_jobs_excessive_retention(self, db, pggit_installed):
        """Retention > 10 years should raise warning but not fail."""
        # Should complete successfully but log warning
        result = db.execute("SELECT pggit.cleanup_old_jobs(10000, TRUE)")
        assert result is not None

    def test_cancel_stuck_jobs_null_timeout(self, db, pggit_installed):
        """NULL timeout_minutes should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.cancel_stuck_jobs(NULL, TRUE)")

    def test_cancel_stuck_jobs_negative_timeout(self, db, pggit_installed):
        """Negative timeout_minutes should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.cancel_stuck_jobs(-1, TRUE)")

    def test_cancel_stuck_jobs_excessive_timeout(self, db, pggit_installed):
        """Timeout > 1 week should raise warning but not fail."""
        result = db.execute("SELECT pggit.cancel_stuck_jobs(20000, TRUE)")
        assert result is not None

    def test_list_active_workers_null_since(self, db, pggit_installed):
        """NULL since_minutes should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.list_active_workers(NULL)")

    def test_list_active_workers_negative_since(self, db, pggit_installed):
        """Negative since_minutes should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.list_active_workers(-10)")

    def test_list_active_workers_excessive_since(self, db, pggit_installed):
        """Since > 1 day should raise warning but not fail."""
        result = db.execute("SELECT pggit.list_active_workers(2000)")
        assert result is not None

    def test_get_worker_stats_null_worker_id(self, db, pggit_installed):
        """NULL worker_id should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.get_worker_stats(NULL, 24)")

    def test_get_worker_stats_null_since_hours(self, db, pggit_installed):
        """NULL since_hours should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.get_worker_stats('worker-1', NULL)")

    def test_get_worker_stats_negative_since(self, db, pggit_installed):
        """Negative since_hours should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.get_worker_stats('worker-1', -5)")

    def test_get_worker_stats_excessive_since(self, db, pggit_installed):
        """Since > 30 days should raise warning but not fail."""
        result = db.execute("SELECT pggit.get_worker_stats('worker-1', 1000)")
        assert result is not None

    def test_get_backup_stats_null_since(self, db, pggit_installed):
        """NULL since_days should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.get_backup_stats(NULL)")

    def test_get_backup_stats_negative_since(self, db, pggit_installed):
        """Negative since_days should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.get_backup_stats(-30)")

    def test_get_backup_stats_excessive_since(self, db, pggit_installed):
        """Since > 1 year should raise warning but not fail."""
        result = db.execute("SELECT pggit.get_backup_stats(400)")
        assert result is not None

    def test_get_tool_usage_stats_null_since(self, db, pggit_installed):
        """NULL since_days should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.get_tool_usage_stats(NULL)")

    def test_get_tool_usage_stats_negative_since(self, db, pggit_installed):
        """Negative since_days should raise exception."""
        with pytest.raises(Exception, match="must be positive"):
            db.execute("SELECT pggit.get_tool_usage_stats(-30)")

    def test_get_tool_usage_stats_excessive_since(self, db, pggit_installed):
        """Since > 1 year should raise warning but not fail."""
        result = db.execute("SELECT pggit.get_tool_usage_stats(400)")
        assert result is not None

    def test_find_backup_null_commit(self, db, pggit_installed):
        """NULL commit hash should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.find_backup_for_commit(NULL)")

    def test_find_backup_empty_commit(self, db, pggit_installed):
        """Empty commit hash should raise exception."""
        with pytest.raises(Exception, match="cannot be empty"):
            db.execute("SELECT pggit.find_backup_for_commit('')")

    def test_generate_recovery_plan_null_commit(self, db, pggit_installed):
        """NULL target commit should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.generate_recovery_plan(NULL)")

    def test_generate_recovery_plan_empty_commit(self, db, pggit_installed):
        """Empty target commit should raise exception."""
        with pytest.raises(Exception, match="cannot be empty"):
            db.execute("SELECT pggit.generate_recovery_plan('')")

    def test_generate_recovery_plan_invalid_mode(self, db, pggit_installed):
        """Invalid recovery mode should raise exception."""
        with pytest.raises(Exception, match="Invalid recovery mode"):
            db.execute("SELECT pggit.generate_recovery_plan('abc123', 'invalid')")

    def test_apply_retention_invalid_jsonb(self, db, pggit_installed):
        """Invalid JSONB schema should raise exception."""
        with pytest.raises(Exception, match="missing required key"):
            db.execute("""
                SELECT pggit.apply_retention_policy('{"invalid": "schema"}'::JSONB)
            """)

    def test_apply_retention_null_jsonb(self, db, pggit_installed):
        """NULL JSONB should use defaults."""
        result = db.execute("SELECT pggit.apply_retention_policy(NULL)")
        assert result is not None

    def test_apply_retention_invalid_days(self, db, pggit_installed):
        """Invalid day values should raise exception."""
        with pytest.raises(Exception, match="out of range"):
            db.execute("""
                SELECT pggit.apply_retention_policy('{"full_days": 0, "incremental_days": 7}'::JSONB)
            """)

    def test_verify_backup_null_uuid(self, db, pggit_installed):
        """NULL backup_id should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.verify_backup(NULL)")

    def test_verify_backup_nonexistent_uuid(self, db, pggit_installed):
        """Non-existent backup_id should raise exception."""
        import uuid

        fake_id = str(uuid.uuid4())
        with pytest.raises(Exception, match="not found"):
            db.execute(f"SELECT pggit.verify_backup('{fake_id}'::UUID)")

    def test_test_backup_restore_null_uuid(self, db, pggit_installed):
        """NULL backup_id should raise exception."""
        with pytest.raises(Exception, match="cannot be NULL"):
            db.execute("SELECT pggit.test_backup_restore(NULL)")

    def test_test_backup_restore_nonexistent_uuid(self, db, pggit_installed):
        """Non-existent backup_id should raise exception."""
        import uuid

        fake_id = str(uuid.uuid4())
        with pytest.raises(Exception, match="not found"):
            db.execute(f"SELECT pggit.test_backup_restore('{fake_id}'::UUID)")

    def test_unicode_in_commit_hash(self, db, pggit_installed):
        """Unicode characters in commit hash should be handled."""
        # This should work fine as commit hashes are just strings
        unicode_hash = "abc123🎉测试"
        result = db.execute(f"SELECT pggit.find_backup_for_commit('{unicode_hash}')")
        assert result is not None  # Should return empty result set, not crash

    def test_max_integer_values(self, db, pggit_installed):
        """Very large integer values should be handled appropriately."""
        # PostgreSQL INTEGER max is 2147483647
        max_int = 2147483647

        # This should work for parameters that accept large integers
        result = db.execute(f"SELECT pggit.list_active_workers({max_int})")
        assert result is not None

    def test_special_jsonb_structures(self, db, pggit_installed):
        """Special JSONB structures should be validated properly."""
        # Test nested objects (should fail due to missing required keys)
        with pytest.raises(Exception, match="missing required key"):
            db.execute("""
                SELECT pggit.apply_retention_policy('{"nested": {"full_days": 30}}'::JSONB)
            """)

    def test_array_jsonb_values(self, db, pggit_installed):
        """Array values in JSONB should fail type conversion."""
        with pytest.raises(Exception, match="Invalid policy format"):
            db.execute("""
                SELECT pggit.apply_retention_policy('{"full_days": [30], "incremental_days": 7}'::JSONB)
            """)

    def test_extra_jsonb_keys(self, db, pggit_installed):
        """Extra keys in JSONB should be ignored."""
        result = db.execute("""
            SELECT pggit.apply_retention_policy('{"full_days": 30, "incremental_days": 7, "extra_key": "ignored"}'::JSONB)
        """)
        assert result is not None

    def test_extreme_range_values(self, db, pggit_installed):
        """Extreme range values should be handled at boundaries."""
        # Test exact boundary values
        result = db.execute("SELECT pggit.get_backup_stats(365)")  # Max allowed
        assert result is not None

        # Test values just outside boundary (raises warning, not exception)
        result = db.execute("SELECT pggit.get_backup_stats(366)")  # Just over max
        assert result is not None  # Should still work, just with warning

    def test_empty_jsonb_object(self, db, pggit_installed):
        """Empty JSONB object should fail validation."""
        with pytest.raises(Exception, match="missing required key"):
            db.execute("""
                SELECT pggit.apply_retention_policy('{}'::JSONB)
            """)
