"""
pgGit Backup Automation Tests - Phase 2

Comprehensive test suite for automated backup execution via job queue.
Tests Phase 2: Backup automation, job queue, and tool integration.

Tests cover:
1. Job queue operations (enqueue, get_next, complete, fail)
2. Retry logic with exponential backoff
3. pgBackRest automated backups
4. Barman automated backups
5. pg_dump automated backups
6. Job monitoring and views
7. Error handling and edge cases
"""

import pytest
import time


class TestJobQueue:
    """Test job queue operations."""

    def test_enqueue_job(self, db_e2e, pggit_installed):
        """Test enqueueing a backup job."""
        # Create commit and backup
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-queue', 1, 'Queue test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'queue-test-backup',
                'full',
                'pgbackrest',
                's3://bucket/queue-test',
                'test-commit-queue'
            )
        """)

        # Enqueue job
        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "test command"',
                'custom',
                3,
                '{"test": "metadata"}'::jsonb
            )
        """, backup_id[0])

        assert job_id is not None
        print(f"✓ Enqueued job: {job_id[0]}")

        # Verify job exists
        result = db_e2e.execute_returning("""
            SELECT status, command, tool, max_attempts
            FROM pggit.backup_jobs
            WHERE job_id = %s
        """, job_id[0])

        assert result[0] == 'queued'
        assert result[1] == 'echo "test command"'
        assert result[2] == 'custom'
        assert result[3] == 3

    def test_get_next_job(self, db_e2e, pggit_installed):
        """Test getting next job from queue."""
        # Create commit and backup
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-next', 1, 'Next job test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'next-job-test',
                'full',
                'pgbackrest',
                's3://bucket/next-test',
                'test-commit-next'
            )
        """)

        # Enqueue job
        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "next job test"',
                'custom'
            )
        """, backup_id[0])

        # Get next job
        job = db_e2e.execute("""
            SELECT job_id, backup_id, command, tool, attempts
            FROM pggit.get_next_backup_job('test-worker-1')
        """)

        assert len(job) == 1
        assert job[0][0] == job_id[0]
        assert job[0][2] == 'echo "next job test"'
        assert job[0][4] == 1  # First attempt

        print(f"✓ Got next job: {job[0][0]}")

        # Verify status changed to running
        status = db_e2e.execute_returning("""
            SELECT status FROM pggit.backup_jobs WHERE job_id = %s
        """, job_id[0])

        assert status[0] == 'running'

    def test_complete_job(self, db_e2e, pggit_installed):
        """Test marking job as completed."""
        # Create commit, backup, and job
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-complete-job', 1, 'Complete job test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'complete-job-test',
                'full',
                'pgbackrest',
                's3://bucket/complete-test',
                'test-commit-complete-job'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "complete test"',
                'custom'
            )
        """, backup_id[0])

        # Get the job (marks as running)
        db_e2e.execute("""
            SELECT * FROM pggit.get_next_backup_job('test-worker')
        """)

        # Complete it
        result = db_e2e.execute_returning("""
            SELECT pggit.complete_backup_job(%s::UUID, 'Job output here')
        """, job_id[0])

        assert result[0] is True
        print(f"✓ Completed job: {job_id[0]}")

        # Verify status
        status = db_e2e.execute_returning("""
            SELECT status, completed_at IS NOT NULL
            FROM pggit.backup_jobs
            WHERE job_id = %s
        """, job_id[0])

        assert status[0] == 'completed'
        assert status[1] is True  # completed_at should be set

    def test_fail_job_with_retry(self, db_e2e, pggit_installed):
        """Test marking job as failed with retry."""
        # Create commit, backup, and job
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-fail-retry', 1, 'Fail retry test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'fail-retry-test',
                'full',
                'pgbackrest',
                's3://bucket/fail-retry',
                'test-commit-fail-retry'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "fail retry test"',
                'custom',
                3  -- max 3 attempts
            )
        """, backup_id[0])

        # Get job (attempt 1)
        db_e2e.execute("""
            SELECT * FROM pggit.get_next_backup_job('test-worker')
        """)

        # Fail it
        db_e2e.execute("""
            SELECT pggit.fail_backup_job(%s::UUID, 'Test error message', 1)
        """, job_id[0])

        # Verify status and retry schedule
        result = db_e2e.execute_returning("""
            SELECT status, attempts, next_retry_at IS NOT NULL, last_error
            FROM pggit.backup_jobs
            WHERE job_id = %s
        """, job_id[0])

        assert result[0] == 'failed'
        assert result[1] == 1
        assert result[2] is True  # next_retry_at should be set
        assert 'Test error message' in result[3]

        print("✓ Job failed with retry scheduled")

    def test_fail_job_max_retries(self, db_e2e, pggit_installed):
        """Test job failure after max retries."""
        # Create commit, backup, and job
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-max-retry', 1, 'Max retry test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'max-retry-test',
                'full',
                'pgbackrest',
                's3://bucket/max-retry',
                'test-commit-max-retry'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "max retry test"',
                'custom',
                2  -- max 2 attempts
            )
        """, backup_id[0])

        # Attempt 1: Get and fail
        db_e2e.execute("SELECT * FROM pggit.get_next_backup_job('test-worker')")
        db_e2e.execute("SELECT pggit.fail_backup_job(%s::UUID, 'Attempt 1 failed', 0)", job_id[0])

        # Attempt 2: Get and fail (max retries reached)
        db_e2e.execute("SELECT * FROM pggit.get_next_backup_job('test-worker')")
        db_e2e.execute("SELECT pggit.fail_backup_job(%s::UUID, 'Attempt 2 failed', 0)", job_id[0])

        # Verify permanently failed
        result = db_e2e.execute_returning("""
            SELECT status, attempts, completed_at IS NOT NULL
            FROM pggit.backup_jobs
            WHERE job_id = %s
        """, job_id[0])

        assert result[0] == 'failed'
        assert result[1] == 2
        assert result[2] is True  # completed_at set when permanently failed

        # Verify backup also marked as failed
        backup_status = db_e2e.execute_returning("""
            SELECT status, error_message
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert backup_status[0] == 'failed'
        assert 'attempts' in backup_status[1].lower()

        print("✓ Job permanently failed after max retries")


class TestAutomatedBackups:
    """Test automated backup functions."""

    def test_backup_pgbackrest(self, db_e2e, pggit_installed):
        """Test automated pgBackRest backup."""
        # Create commit
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-pgbackrest', 1, 'pgBackRest test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db_e2e.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-pgbackrest'
            WHERE name = 'main'
        """)

        # Trigger automated backup
        backup_id = db_e2e.execute_returning("""
            SELECT pggit.backup_pgbackrest(
                'full',
                'main',
                'prod-stanza',
                '{"repo": "1"}'::jsonb
            )
        """)

        assert backup_id is not None
        print(f"✓ Created pgBackRest backup: {backup_id[0]}")

        # Verify backup was registered
        backup = db_e2e.execute_returning("""
            SELECT backup_name, backup_type, backup_tool, status, commit_hash
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert backup[0].startswith('pgbackrest-full-')
        assert backup[1] == 'full'
        assert backup[2] == 'pgbackrest'
        assert backup[3] == 'in_progress'
        assert backup[4] == 'test-commit-pgbackrest'

        # Verify job was enqueued
        job = db_e2e.execute("""
            SELECT job_id, command, tool, status
            FROM pggit.backup_jobs
            WHERE backup_id = %s
        """, backup_id[0])

        assert len(job) == 1
        assert 'pgbackrest' in job[0][1]
        assert '--stanza=prod-stanza' in job[0][1]
        assert '--type=full' in job[0][1]
        assert job[0][2] == 'pgbackrest'
        assert job[0][3] == 'queued'

    def test_backup_barman(self, db_e2e, pggit_installed):
        """Test automated Barman backup."""
        # Create commit
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-barman', 1, 'Barman test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db_e2e.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-barman'
            WHERE name = 'main'
        """)

        # Trigger automated backup
        backup_id = db_e2e.execute_returning("""
            SELECT pggit.backup_barman(
                'prod-server',
                'main',
                '{"wait": true}'::jsonb
            )
        """)

        assert backup_id is not None
        print(f"✓ Created Barman backup: {backup_id[0]}")

        # Verify backup
        backup = db_e2e.execute_returning("""
            SELECT backup_name, backup_tool, status
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert backup[0].startswith('barman-prod-server-')
        assert backup[1] == 'barman'
        assert backup[2] == 'in_progress'

        # Verify job
        job = db_e2e.execute("""
            SELECT command, tool
            FROM pggit.backup_jobs
            WHERE backup_id = %s
        """, backup_id[0])

        assert len(job) == 1
        assert 'barman backup prod-server' in job[0][0]
        assert '--wait' in job[0][0]
        assert job[0][1] == 'barman'

    def test_backup_pg_dump(self, db_e2e, pggit_installed):
        """Test automated pg_dump backup."""
        # Create commit
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-pgdump', 1, 'pg_dump test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db_e2e.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-pgdump'
            WHERE name = 'main'
        """)

        # Trigger automated backup
        backup_id = db_e2e.execute_returning("""
            SELECT pggit.backup_pg_dump(
                'main',
                'public',
                'custom',
                '/tmp/backups',
                '{"compression_level": "9"}'::jsonb
            )
        """)

        assert backup_id is not None
        print(f"✓ Created pg_dump backup: {backup_id[0]}")

        # Verify backup
        backup = db_e2e.execute_returning("""
            SELECT backup_name, backup_type, backup_tool, location
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert backup[0].startswith('pg_dump-public-')
        assert backup[1] == 'snapshot'
        assert backup[2] == 'pg_dump'
        assert backup[3].startswith('file:///tmp/backups/')

        # Verify job
        job = db_e2e.execute("""
            SELECT command
            FROM pggit.backup_jobs
            WHERE backup_id = %s
        """, backup_id[0])

        assert len(job) == 1
        assert 'pg_dump' in job[0][0]
        assert '--format=c' in job[0][0]
        assert '--schema=public' in job[0][0]
        assert '/tmp/backups' in job[0][0]


class TestJobMonitoring:
    """Test job monitoring and views."""

    def test_backup_job_queue_view(self, db_e2e, pggit_installed):
        """Test backup job queue monitoring view."""
        # Create some test jobs
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-monitor', 1, 'Monitor test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'monitor-test',
                'full',
                'pgbackrest',
                's3://bucket/monitor',
                'test-commit-monitor'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(
                %s::UUID,
                'echo "monitor test"',
                'custom'
            )
        """, backup_id[0])

        # Query monitoring view
        view_data = db_e2e.execute("""
            SELECT job_id, backup_name, tool, status, job_state, attempts
            FROM pggit.backup_job_queue
            WHERE job_id = %s
        """, job_id[0])

        assert len(view_data) == 1
        assert view_data[0][0] == job_id[0]
        assert view_data[0][1] == 'monitor-test'
        assert view_data[0][2] == 'custom'
        assert view_data[0][3] == 'queued'
        assert view_data[0][4] == 'ready'
        assert view_data[0][5] == 0  # No attempts yet

        print("✓ Job queue monitoring view works correctly")

    def test_job_queue_states(self, db_e2e, pggit_installed):
        """Test different job states in monitoring view."""
        # Create test data
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-states', 1, 'States test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'states-test',
                'full',
                'custom',
                'file:///test',
                'test-commit-states'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(%s::UUID, 'echo test', 'custom', 3)
        """, backup_id[0])

        # Check initial state (queued -> ready)
        state = db_e2e.execute_returning("""
            SELECT job_state FROM pggit.backup_job_queue WHERE job_id = %s
        """, job_id[0])
        assert state[0] == 'ready'

        # Get job (running -> in_progress)
        db_e2e.execute("SELECT * FROM pggit.get_next_backup_job('test-worker')")

        state = db_e2e.execute_returning("""
            SELECT job_state FROM pggit.backup_job_queue WHERE job_id = %s
        """, job_id[0])
        assert state[0] == 'in_progress'

        # Fail job (failed + retries left -> will_retry)
        db_e2e.execute("SELECT pggit.fail_backup_job(%s::UUID, 'Test error', 60)", job_id[0])

        state = db_e2e.execute_returning("""
            SELECT job_state, attempts FROM pggit.backup_job_queue WHERE job_id = %s
        """, job_id[0])
        assert state[0] == 'will_retry'
        assert state[1] == 1

        print("✓ Job state transitions work correctly")


class TestErrorHandling:
    """Test error handling and edge cases."""

    def test_backup_invalid_branch(self, db_e2e, pggit_installed):
        """Test that backup with invalid branch fails gracefully."""
        with pytest.raises(Exception) as exc_info:
            db_e2e.execute("""
                SELECT pggit.backup_pgbackrest('full', 'nonexistent-branch')
            """)

        assert 'not found' in str(exc_info.value).lower()
        print("✓ Correctly rejected invalid branch")

    def test_backup_branch_no_commits(self, db_e2e, pggit_installed):
        """Test backup on branch with no commits fails."""
        # Create branch without commits
        db_e2e.execute("""
            INSERT INTO pggit.branches (name, head_commit_hash)
            VALUES ('empty-branch', NULL)
            ON CONFLICT (name) DO UPDATE
            SET head_commit_hash = NULL
        """)

        with pytest.raises(Exception) as exc_info:
            db_e2e.execute("""
                SELECT pggit.backup_pgbackrest('full', 'empty-branch')
            """)

        assert 'no commits' in str(exc_info.value).lower()
        print("✓ Correctly rejected branch with no commits")

    def test_concurrent_job_fetch(self, db_e2e, pggit_installed):
        """Test that SKIP LOCKED prevents concurrent job fetching."""
        # Create job
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-concurrent', 1, 'Concurrent test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'concurrent-test',
                'full',
                'custom',
                'file:///test',
                'test-commit-concurrent'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(%s::UUID, 'echo test', 'custom')
        """, backup_id[0])

        # Worker 1 gets the job
        job1 = db_e2e.execute("""
            SELECT job_id FROM pggit.get_next_backup_job('worker-1')
        """)
        assert len(job1) == 1
        assert job1[0][0] == job_id[0]

        # Worker 2 should NOT get the same job (SKIP LOCKED)
        job2 = db_e2e.execute("""
            SELECT job_id FROM pggit.get_next_backup_job('worker-2')
        """)
        assert len(job2) == 0

        print("✓ Concurrent job fetching prevented by SKIP LOCKED")

    def test_exponential_backoff(self, db_e2e, pggit_installed):
        """Test exponential backoff for retry delays."""
        # Create job
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-backoff', 1, 'Backoff test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db_e2e.execute_returning("""
            SELECT pggit.register_backup(
                'backoff-test',
                'full',
                'custom',
                'file:///test',
                'test-commit-backoff'
            )
        """)

        job_id = db_e2e.execute_returning("""
            SELECT pggit.enqueue_backup_job(%s::UUID, 'echo test', 'custom', 5)
        """, backup_id[0])

        # Attempt 1: Fail with 60 second base delay
        db_e2e.execute("SELECT * FROM pggit.get_next_backup_job('worker')")
        db_e2e.execute("SELECT pggit.fail_backup_job(%s::UUID, 'Error 1', 60)", job_id[0])

        delay1 = db_e2e.execute_returning("""
            SELECT EXTRACT(EPOCH FROM (next_retry_at - CURRENT_TIMESTAMP))
            FROM pggit.backup_jobs WHERE job_id = %s
        """, job_id[0])

        # Should be ~60 seconds (2^0 * 60)
        assert 50 < delay1[0] < 70

        # Wait for retry window and force immediate retry by setting next_retry_at to past
        db_e2e.execute("""
            UPDATE pggit.backup_jobs
            SET next_retry_at = CURRENT_TIMESTAMP - INTERVAL '1 second'
            WHERE job_id = %s
        """, job_id[0])

        # Attempt 2: Exponential backoff (2^1 * 60 = 120)
        db_e2e.execute("SELECT * FROM pggit.get_next_backup_job('worker')")
        db_e2e.execute("SELECT pggit.fail_backup_job(%s::UUID, 'Error 2', 60)", job_id[0])

        delay2 = db_e2e.execute_returning("""
            SELECT EXTRACT(EPOCH FROM (next_retry_at - CURRENT_TIMESTAMP))
            FROM pggit.backup_jobs WHERE job_id = %s
        """, job_id[0])

        # Should be ~120 seconds (2^1 * 60)
        assert 110 < delay2[0] < 130

        print(f"✓ Exponential backoff working: {delay1[0]:.1f}s -> {delay2[0]:.1f}s")


class TestIntegration:
    """Integration tests for complete workflows."""

    def test_full_backup_workflow(self, db_e2e, pggit_installed):
        """Test complete backup workflow: schedule -> execute -> complete."""
        # Setup
        db_e2e.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-workflow', 1, 'Workflow test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db_e2e.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-workflow'
            WHERE name = 'main'
        """)

        # 1. Schedule backup
        backup_id = db_e2e.execute_returning("""
            SELECT pggit.backup_pgbackrest('full', 'main')
        """)
        print(f"1. Scheduled backup: {backup_id[0]}")

        # 2. Get job (simulating worker)
        job = db_e2e.execute("""
            SELECT job_id, command FROM pggit.get_next_backup_job('integration-worker')
        """)
        assert len(job) == 1
        job_id = job[0][0]
        print(f"2. Worker got job: {job_id}")

        # 3. Simulate successful execution
        db_e2e.execute("""
            SELECT pggit.complete_backup_job(%s::UUID, 'Backup completed successfully')
        """, job_id)
        print("3. Job marked as completed")

        # 4. Complete backup
        db_e2e.execute("""
            SELECT pggit.complete_backup(%s::UUID, 1000000, 500000, 'gzip')
        """, backup_id[0])
        print("4. Backup marked as completed")

        # 5. Verify final state
        backup_status = db_e2e.execute_returning("""
            SELECT b.status, b.backup_size, j.status
            FROM pggit.backups b
            JOIN pggit.backup_jobs j ON b.backup_id = j.backup_id
            WHERE b.backup_id = %s
        """, backup_id[0])

        assert backup_status[0] == 'completed'
        assert backup_status[1] == 1000000
        assert backup_status[2] == 'completed'

        print("✓ Full workflow completed successfully")
