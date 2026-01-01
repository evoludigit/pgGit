import pytest
import psycopg
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class TestReliability:
    """Test reliability features: idempotency, error handling, audit logging."""

    def test_retention_policy_idempotent(self, db, pggit_installed):
        """Retention policy should be idempotent - running twice produces same result."""
        # Create commits and backups
        for i in range(3):
            db.execute(f"""
                INSERT INTO pggit.commits (hash, branch_id, message)
                VALUES ('retention-commit-{i}', 1, 'Retention test commit {i}')
                ON CONFLICT (hash) DO NOTHING
            """)

            backup_id = db.execute_returning(f"""
                SELECT pggit.register_backup(
                    'retention-backup-{i}', 'full', 'pgbackrest',
                    's3://bucket/retention-{i}', 'retention-commit-{i}'
                )
            """)[0]

            # Mark as completed 40 days ago
            db.execute(
                """
                UPDATE pggit.backups
                SET status = 'completed', completed_at = CURRENT_TIMESTAMP - INTERVAL '40 days'
                WHERE backup_id = %s::UUID
            """,
                backup_id,
            )

        # Run retention policy first time
        result1 = db.execute("""
            SELECT backup_id, backup_name, reason
            FROM pggit.apply_retention_policy('{"full_days": 30, "incremental_days": 7}'::JSONB)
            ORDER BY backup_id
        """)

        # Run retention policy second time - should return empty (idempotent)
        result2 = db.execute("""
            SELECT backup_id, backup_name, reason
            FROM pggit.apply_retention_policy('{"full_days": 30, "incremental_days": 7}'::JSONB)
            ORDER BY backup_id
        """)

        # First run should have marked backups, second should be empty
        assert len(result1) > 0, "First retention run should mark backups"
        assert len(result2) == 0, "Second retention run should be empty (idempotent)"

        # Verify backups were actually marked with consistent timestamps
        marked_backups = db.execute("""
            SELECT backup_id, expires_at
            FROM pggit.backups
            WHERE status = 'expired' AND expires_at IS NOT NULL
            ORDER BY backup_id
        """)

        assert len(marked_backups) == len(result1), (
            "All marked backups should have expires_at set"
        )
        print("✓ Retention policy is idempotent - same results on multiple runs")

    def test_verify_backup_idempotent(self, db, pggit_installed):
        """Backup verification should be idempotent - don't queue duplicate verifications."""
        # Create a backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('verify-commit', 1, 'Verify test commit')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'verify-test-backup', 'full', 'pgbackrest',
                's3://bucket/verify', 'verify-commit'
            )
        """)[0]

        # First verification should create new record
        verification_id1 = db.execute_returning(
            """
            SELECT pggit.verify_backup(%s::UUID, 'checksum')
        """,
            backup_id,
        )[0]

        # Second verification of same backup/type should return same ID
        verification_id2 = db.execute_returning(
            """
            SELECT pggit.verify_backup(%s::UUID, 'checksum')
        """,
            backup_id,
        )[0]

        # Should be the same verification ID (idempotent)
        assert verification_id1 == verification_id2, (
            "Same verification should return same ID"
        )

        # Should only be one verification record
        verification_count = db.execute(
            """
            SELECT COUNT(*) FROM pggit.backup_verifications
            WHERE backup_id = %s::UUID AND verification_type = 'checksum'
        """,
            backup_id,
        )[0][0]

        assert verification_count == 1, "Should only create one verification record"
        print("✓ Backup verification is idempotent - no duplicate verifications")

    def test_reset_job_idempotent(self, db, pggit_installed):
        """Job reset should be idempotent - don't reset already queued jobs."""
        # Create a failed job
        job_id = db.execute_returning("""
            INSERT INTO pggit.backup_jobs (
                backup_id, job_type, command, tool, status
            ) VALUES (
                gen_random_uuid(), 'backup', 'test command', 'pgbackrest', 'failed'
            ) RETURNING job_id
        """)[0]

        # First reset should succeed
        result1 = db.execute(
            """
            SELECT pggit.reset_job(%s::UUID)
        """,
            job_id,
        )[0][0]

        assert result1 == True, "First reset should succeed"

        # Second reset should succeed but be idempotent (already queued)
        result2 = db.execute(
            """
            SELECT pggit.reset_job(%s::UUID)
        """,
            job_id,
        )[0][0]

        assert result2 == True, "Second reset should also succeed (idempotent)"

        # Verify job is in queued state
        job_status = db.execute(
            """
            SELECT status FROM pggit.backup_jobs WHERE job_id = %s::UUID
        """,
            job_id,
        )[0][0]

        assert job_status == "queued", "Job should remain in queued state"
        print("✓ Job reset is idempotent - no duplicate resets")

    def test_audit_logging_captures_operations(self, db, pggit_installed):
        """Audit logging should capture all operations with proper metadata."""
        # Clear any existing audit logs for clean test
        db.execute(
            "DELETE FROM pggit.operation_audit WHERE operation_name = 'cleanup_expired_backups'"
        )

        # Perform an operation that gets audited
        result = db.execute("""
            SELECT COUNT(*) FROM pggit.cleanup_expired_backups(TRUE)
        """)

        # Check audit log
        audit_records = db.execute("""
            SELECT operation_name, operation_type, success, parameters, rows_affected, duration_ms
            FROM pggit.operation_audit
            WHERE operation_name = 'cleanup_expired_backups'
            ORDER BY started_at DESC
            LIMIT 1
        """)

        assert len(audit_records) == 1, "Should have one audit record"
        record = audit_records[0]

        assert record[0] == "cleanup_expired_backups", "Operation name should match"
        assert record[1] == "read", "Should be read operation (dry-run)"
        assert record[2] == True, "Operation should succeed"
        assert record[3] is not None, "Parameters should be logged"
        assert record[4] is not None, "Rows affected should be logged"
        assert record[5] is not None and record[5] > 0, "Duration should be recorded"

        print("✓ Audit logging captures operation details correctly")

    def test_audit_logging_captures_failures(self, db, pggit_installed):
        """Audit logging should capture operation failures."""
        # Clear audit logs
        db.execute(
            "DELETE FROM pggit.operation_audit WHERE operation_name = 'cleanup_expired_backups'"
        )

        # Try an operation that should fail (transaction required for non-dry-run)
        try:
            db.execute("SELECT pggit.cleanup_expired_backups(FALSE)")
        except Exception:
            pass  # Expected to fail

        # Check audit log for failure
        audit_records = db.execute("""
            SELECT success, error_code, error_message
            FROM pggit.operation_audit
            WHERE operation_name = 'cleanup_expired_backups' AND success = false
            ORDER BY started_at DESC
            LIMIT 1
        """)

        assert len(audit_records) >= 1, "Should have failure audit record"
        record = audit_records[0]

        assert record[0] == False, "Should record failure"
        assert record[1] is not None, "Should capture error code"
        assert record[2] is not None, "Should capture error message"

        print("✓ Audit logging captures operation failures correctly")

    def test_error_message_quality(self, db, pggit_installed):
        """Error messages should be clear and actionable."""
        # Test NULL parameter error
        try:
            db.execute("SELECT pggit.get_worker_stats(NULL, 24)")
        except Exception as e:
            error_msg = str(e).lower()
            assert "null" in error_msg or "cannot be null" in error_msg, (
                f"Error should mention NULL: {error_msg}"
            )
            assert "provide" in error_msg or "hint" in error_msg, (
                f"Error should provide guidance: {error_msg}"
            )

        # Test range error
        try:
            db.execute("SELECT pggit.get_backup_stats(-1)")
        except Exception as e:
            error_msg = str(e).lower()
            assert "positive" in error_msg or "range" in error_msg, (
                f"Error should mention range: {error_msg}"
            )
            assert "between" in error_msg or "use" in error_msg, (
                f"Error should provide bounds: {error_msg}"
            )

        print("✓ Error messages are clear and actionable")

    def test_audit_log_data_integrity(self, db, pggit_installed):
        """Audit log should maintain data integrity and relationships."""
        # Clear and perform operations
        db.execute("DELETE FROM pggit.operation_audit")

        # Perform several operations
        operations = [
            "SELECT COUNT(*) FROM pggit.cleanup_expired_backups(TRUE)",
            "SELECT COUNT(*) FROM pggit.list_active_workers(10)",
            "SELECT COUNT(*) FROM pggit.get_backup_stats(30)",
        ]

        for op in operations:
            db.execute(op)

        # Verify audit log integrity
        audit_records = db.execute("""
            SELECT operation_name, success, started_at, completed_at, duration_ms
            FROM pggit.operation_audit
            ORDER BY started_at
        """)

        for record in audit_records:
            assert record[1] == True, f"Operation {record[0]} should have succeeded"
            assert record[2] is not None, "Started time should be recorded"
            assert record[3] is not None, "Completed time should be recorded"
            assert record[4] is not None and record[4] >= 0, "Duration should be valid"

            # Completed should be after started
            assert record[3] >= record[2], "Completed time should be after started time"

        print("✓ Audit log maintains data integrity")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
