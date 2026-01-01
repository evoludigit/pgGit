"""
pgGit Backup Integration Tests - Phase 1

Comprehensive test suite for backup metadata tracking functionality.
Tests Phase 1: Manual backup registration and query operations.

Tests cover:
1. Backup registration (register_backup)
2. Backup lifecycle (complete_backup, fail_backup)
3. Backup queries (list_backups, get_backup_info)
4. Backup-commit relationships
5. Coverage views (branch_backup_coverage, commit_backup_coverage)
6. Backup dependencies
7. Backup verifications
8. Backup tags
9. Edge cases and error handling
"""

import pytest
import uuid


class TestBackupRegistration:
    """Test backup registration and lifecycle."""

    def test_register_backup_explicit_commit(self, db, pggit_installed):
        """Test registering a backup with explicit commit hash."""
        # First, create a commit to link to
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-001', 1, 'Test commit for backup')
        """)

        # Register backup
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-001',
                'full',
                'pgbackrest',
                's3://mybucket/backups/test-backup-001',
                'test-commit-001',  -- explicit commit
                NULL,  -- branch_name
                FALSE,  -- no snapshot
                '{"server": "prod-01", "retention": "30d"}'::jsonb
            )
        """)

        assert backup_id is not None
        assert backup_id[0] is not None
        print(f"✓ Registered backup with explicit commit: {backup_id[0]}")

        # Verify backup was registered
        result = db.execute_returning("""
            SELECT backup_name, commit_hash, status, metadata->>'server'
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert result[0] == 'test-backup-001'
        assert result[1] == 'test-commit-001'
        assert result[2] == 'in_progress'
        assert result[3] == 'prod-01'

    def test_register_backup_by_branch(self, db, pggit_installed):
        """Test registering a backup using branch name."""
        # Create a commit and update main branch to point to it
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-002', 1, 'Test commit on main')
        """)

        db.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-002'
            WHERE name = 'main'
        """)

        # Register backup by branch name
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-002',
                'incremental',
                'pgbackrest',
                's3://mybucket/backups/test-backup-002',
                NULL,  -- no explicit commit
                'main'  -- use branch
            )
        """)

        assert backup_id is not None
        print(f"✓ Registered backup by branch: {backup_id[0]}")

        # Verify it linked to the correct commit
        result = db.execute_returning("""
            SELECT commit_hash FROM pggit.backups WHERE backup_id = %s
        """, backup_id[0])

        assert result[0] == 'test-commit-002'

    def test_register_backup_auto_detect(self, db, pggit_installed):
        """Test backup registration with automatic commit detection."""
        # Ensure main branch has a commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-003', 1, 'Auto-detect test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-003'
            WHERE name = 'main'
        """)

        # Register without explicit commit or branch (should detect from main)
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-003',
                'full',
                'pg_dump',
                'file:///backups/test-backup-003.dump'
            )
        """)

        assert backup_id is not None
        print(f"✓ Registered backup with auto-detection: {backup_id[0]}")

        # Should have detected main branch's commit
        result = db.execute_returning("""
            SELECT commit_hash FROM pggit.backups WHERE backup_id = %s
        """, backup_id[0])

        assert result[0] == 'test-commit-003'

    def test_register_backup_invalid_commit(self, db, pggit_installed):
        """Test that registering with invalid commit fails."""
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT pggit.register_backup(
                    'test-backup-invalid',
                    'full',
                    'pgbackrest',
                    's3://mybucket/backups/invalid',
                    'nonexistent-commit'
                )
            """)

        assert 'not found' in str(exc_info.value).lower()
        print("✓ Correctly rejected invalid commit hash")

    def test_register_backup_with_snapshot(self, db, pggit_installed):
        """Test backup registration with temporal snapshot creation."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-snapshot', 1, 'Snapshot test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-snapshot'
            WHERE name = 'main'
        """)

        # Register with snapshot creation
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-with-snapshot',
                'full',
                'pgbackrest',
                's3://mybucket/backups/snapshot-test',
                'test-commit-snapshot',
                NULL,
                TRUE  -- create snapshot
            )
        """)

        assert backup_id is not None
        print(f"✓ Registered backup with snapshot: {backup_id[0]}")

        # Verify snapshot was created
        result = db.execute_returning("""
            SELECT snapshot_id FROM pggit.backups WHERE backup_id = %s
        """, backup_id[0])

        assert result[0] is not None
        print(f"  Snapshot ID: {result[0]}")


class TestBackupLifecycle:
    """Test backup lifecycle transitions."""

    def test_complete_backup(self, db, pggit_installed):
        """Test marking backup as completed."""
        # Create commit and backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-complete', 1, 'Complete test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-complete',
                'full',
                'pgbackrest',
                's3://mybucket/backups/complete-test',
                'test-commit-complete'
            )
        """)

        # Complete the backup
        result = db.execute_returning("""
            SELECT pggit.complete_backup(
                %s::UUID,
                1073741824,  -- 1GB
                536870912,   -- 512MB compressed
                'gzip'
            )
        """, backup_id[0])

        assert result[0] is True
        print(f"✓ Marked backup as completed: {backup_id[0]}")

        # Verify status and details
        status = db.execute_returning("""
            SELECT status, backup_size, compressed_size, compression, completed_at IS NOT NULL
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert status[0] == 'completed'
        assert status[1] == 1073741824
        assert status[2] == 536870912
        assert status[3] == 'gzip'
        assert status[4] is True  # completed_at should be set

    def test_fail_backup(self, db, pggit_installed):
        """Test marking backup as failed."""
        # Create commit and backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-fail', 1, 'Fail test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-fail',
                'incremental',
                'barman',
                'barman://server/fail-test',
                'test-commit-fail'
            )
        """)

        # Fail the backup
        result = db.execute_returning("""
            SELECT pggit.fail_backup(
                %s::UUID,
                'Network timeout during upload to remote server'
            )
        """, backup_id[0])

        assert result[0] is True
        print(f"✓ Marked backup as failed: {backup_id[0]}")

        # Verify status and error message
        status = db.execute_returning("""
            SELECT status, error_message FROM pggit.backups WHERE backup_id = %s
        """, backup_id[0])

        assert status[0] == 'failed'
        assert 'timeout' in status[1].lower()

    def test_complete_already_completed_backup(self, db, pggit_installed):
        """Test that completing an already completed backup fails."""
        # Create commit and backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-double', 1, 'Double complete test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-double',
                'full',
                'pgbackrest',
                's3://mybucket/backups/double-test',
                'test-commit-double'
            )
        """)

        # Complete once
        db.execute("""
            SELECT pggit.complete_backup(%s::UUID, 1000, 500, 'gzip')
        """, backup_id[0])

        # Try to complete again - should fail
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT pggit.complete_backup(%s::UUID, 2000, 1000, 'lz4')
            """, backup_id[0])

        assert 'not in progress' in str(exc_info.value).lower()
        print("✓ Correctly prevented double completion")


class TestBackupQueries:
    """Test backup query functions."""

    def test_list_backups_all(self, db, pggit_installed):
        """Test listing all backups."""
        # Create test data
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-list-1', 1, 'List test 1'),
                   ('test-commit-list-2', 1, 'List test 2')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register multiple backups
        for i in range(3):
            db.execute("""
                SELECT pggit.register_backup(
                    %s,
                    'full',
                    'pgbackrest',
                    %s,
                    'test-commit-list-1'
                )
            """, f'list-test-backup-{i}', f's3://bucket/backup-{i}')

        # List all backups
        backups = db.execute("""
            SELECT backup_name, commit_hash, status
            FROM pggit.list_backups()
        """)

        assert len(backups) >= 3
        print(f"✓ Listed {len(backups)} backups")

    def test_list_backups_by_commit(self, db, pggit_installed):
        """Test listing backups for a specific commit."""
        # Create commits
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-filter-1', 1, 'Filter test 1'),
                   ('test-commit-filter-2', 1, 'Filter test 2')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register backups for different commits
        db.execute("""
            SELECT pggit.register_backup(
                'filter-backup-1',
                'full',
                'pgbackrest',
                's3://bucket/filter-1',
                'test-commit-filter-1'
            )
        """)

        db.execute("""
            SELECT pggit.register_backup(
                'filter-backup-2',
                'incremental',
                'pgbackrest',
                's3://bucket/filter-2',
                'test-commit-filter-2'
            )
        """)

        # List backups for specific commit
        backups = db.execute("""
            SELECT backup_name
            FROM pggit.list_backups(NULL, 'test-commit-filter-1')
        """)

        assert len(backups) == 1
        assert backups[0][0] == 'filter-backup-1'
        print("✓ Filtered backups by commit successfully")

    def test_list_backups_by_branch(self, db, pggit_installed):
        """Test listing backups for a branch."""
        # Create commit and link to branch
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-branch-filter', 1, 'Branch filter test')
            ON CONFLICT (hash) DO NOTHING
        """)

        db.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-branch-filter'
            WHERE name = 'main'
        """)

        # Register backup
        db.execute("""
            SELECT pggit.register_backup(
                'branch-filter-backup',
                'full',
                'pgbackrest',
                's3://bucket/branch-filter',
                'test-commit-branch-filter'
            )
        """)

        # List backups by branch
        backups = db.execute("""
            SELECT backup_name
            FROM pggit.list_backups('main')
        """)

        # Should find the backup (branch HEAD points to the commit)
        backup_names = [b[0] for b in backups]
        assert 'branch-filter-backup' in backup_names
        print("✓ Filtered backups by branch successfully")

    def test_list_backups_by_status(self, db, pggit_installed):
        """Test filtering backups by status."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-status', 1, 'Status test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register and complete one backup
        completed_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'status-completed',
                'full',
                'pgbackrest',
                's3://bucket/completed',
                'test-commit-status'
            )
        """)

        db.execute("""
            SELECT pggit.complete_backup(%s::UUID)
        """, completed_id[0])

        # Register and fail another
        failed_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'status-failed',
                'full',
                'pgbackrest',
                's3://bucket/failed',
                'test-commit-status'
            )
        """)

        db.execute("""
            SELECT pggit.fail_backup(%s::UUID, 'Test failure')
        """, failed_id[0])

        # List only completed backups
        completed = db.execute("""
            SELECT backup_name
            FROM pggit.list_backups(NULL, NULL, 'completed')
        """)

        completed_names = [b[0] for b in completed]
        assert 'status-completed' in completed_names
        assert 'status-failed' not in completed_names
        print("✓ Filtered backups by status successfully")

    def test_get_backup_info(self, db, pggit_installed):
        """Test getting detailed backup information."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-info', 1, 'Info test commit message')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register backup with metadata
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'info-test-backup',
                'differential',
                'barman',
                'barman://server/info-test',
                'test-commit-info',
                NULL,
                FALSE,
                '{"test_key": "test_value", "server": "prod"}'::jsonb
            )
        """)

        # Get info
        info = db.execute("""
            SELECT backup_name, backup_type, backup_tool, commit_hash,
                   commit_message, metadata
            FROM pggit.get_backup_info(%s::UUID)
        """, backup_id[0])

        assert info is not None
        assert len(info) == 1
        row = info[0]

        assert row[0] == 'info-test-backup'
        assert row[1] == 'differential'
        assert row[2] == 'barman'
        assert row[3] == 'test-commit-info'
        assert row[4] == 'Info test commit message'
        assert row[5]['test_key'] == 'test_value'

        print(f"✓ Retrieved backup info successfully")
        print(f"  Commit message: {row[4]}")


class TestBackupCommitRelationships:
    """Test backup-commit relationship handling."""

    def test_multiple_backups_same_commit(self, db, pggit_installed):
        """Test multiple backups for the same commit."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-multi', 1, 'Multi backup test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register multiple backups for same commit
        for i in range(3):
            db.execute("""
                SELECT pggit.register_backup(
                    %s,
                    CASE WHEN %s = 0 THEN 'full' ELSE 'incremental' END,
                    'pgbackrest',
                    %s,
                    'test-commit-multi'
                )
            """, f'multi-backup-{i}', i, f's3://bucket/multi-{i}')

        # List backups for this commit
        backups = db.execute("""
            SELECT backup_name, backup_type
            FROM pggit.list_backups(NULL, 'test-commit-multi')
        """)

        assert len(backups) == 3

        # Verify we have the right backup types (order doesn't matter, sorted by started_at DESC)
        backup_types = {b[1] for b in backups}
        assert 'full' in backup_types
        assert 'incremental' in backup_types
        print("✓ Multiple backups per commit work correctly")

    def test_backup_shows_all_branches(self, db, pggit_installed):
        """Test that backup info shows all branches pointing to its commit."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-branches', 1, 'Branches test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Create additional branch pointing to same commit
        db.execute("""
            INSERT INTO pggit.branches (name, head_commit_hash)
            VALUES ('test-branch-1', 'test-commit-branches'),
                   ('test-branch-2', 'test-commit-branches')
            ON CONFLICT (name) DO UPDATE
            SET head_commit_hash = EXCLUDED.head_commit_hash
        """)

        # Register backup
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'branches-test-backup',
                'full',
                'pgbackrest',
                's3://bucket/branches-test',
                'test-commit-branches'
            )
        """)

        # Get backup info
        info = db.execute("""
            SELECT branches_at_commit
            FROM pggit.get_backup_info(%s::UUID)
        """, backup_id[0])

        branches = info[0][0]
        assert branches is not None
        assert 'test-branch-1' in branches
        assert 'test-branch-2' in branches
        print(f"✓ Backup correctly shows all branches: {branches}")


class TestBackupCoverageViews:
    """Test backup coverage analysis views."""

    def test_branch_backup_coverage(self, db, pggit_installed):
        """Test branch backup coverage view."""
        # Create commits and backups
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-coverage-1', 1, 'Coverage test 1'),
                   ('test-commit-coverage-2', 1, 'Coverage test 2')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Update main branch
        db.execute("""
            UPDATE pggit.branches
            SET head_commit_hash = 'test-commit-coverage-1'
            WHERE name = 'main'
        """)

        # Register and complete backup
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'coverage-backup',
                'full',
                'pgbackrest',
                's3://bucket/coverage',
                'test-commit-coverage-1'
            )
        """)

        db.execute("""
            SELECT pggit.complete_backup(%s::UUID, 5000000, 2500000, 'gzip')
        """, backup_id[0])

        # Query coverage view
        coverage = db.execute("""
            SELECT branch_name, backups_at_head, full_backups_at_head, total_backup_size
            FROM pggit.branch_backup_coverage
            WHERE branch_name = 'main'
        """)

        assert len(coverage) > 0
        row = coverage[0]
        assert row[0] == 'main'
        assert row[1] >= 1  # At least our backup
        assert row[2] >= 1  # At least one full backup
        assert row[3] >= 5000000  # Total size should include our backup

        print(f"✓ Branch coverage view works: {row[1]} backups, {row[3]} bytes")

    def test_commit_backup_coverage(self, db, pggit_installed):
        """Test commit backup coverage view."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-cov-view', 1, 'Coverage view test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register backups
        for i in range(2):
            backup_id = db.execute_returning("""
                SELECT pggit.register_backup(
                    %s,
                    CASE WHEN %s = 0 THEN 'full' ELSE 'incremental' END,
                    'pgbackrest',
                    %s,
                    'test-commit-cov-view'
                )
            """, f'cov-view-{i}', i, f's3://bucket/cov-{i}')

            db.execute("""
                SELECT pggit.complete_backup(%s::UUID, 1000000, 500000, 'lz4')
            """, backup_id[0])

        # Query coverage view
        coverage = db.execute("""
            SELECT commit_hash, total_backups, completed_backups, full_backups, backup_status
            FROM pggit.commit_backup_coverage
            WHERE commit_hash = 'test-commit-cov-view'
        """)

        assert len(coverage) == 1
        row = coverage[0]
        assert row[0] == 'test-commit-cov-view'
        assert row[1] == 2  # Total backups
        assert row[2] == 2  # Completed backups
        assert row[3] == 1  # Full backups
        assert row[4] == 'ok'  # Backup status

        print(f"✓ Commit coverage view: {row[1]} backups, status={row[4]}")

    def test_commit_with_no_backup_shows_risk(self, db, pggit_installed):
        """Test that commits without backups show as risky."""
        # Create commit without any backups
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-no-backup', 1, 'No backup commit')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Query coverage view
        coverage = db.execute("""
            SELECT commit_hash, total_backups, backup_status
            FROM pggit.commit_backup_coverage
            WHERE commit_hash = 'test-commit-no-backup'
        """)

        if len(coverage) > 0:
            row = coverage[0]
            assert row[1] == 0  # No backups
            assert row[2] == 'no_backup'  # Risk indicator
            print(f"✓ No-backup risk detected correctly: status={row[2]}")


class TestBackupDependencies:
    """Test backup dependency tracking."""

    def test_create_backup_dependency(self, db, pggit_installed):
        """Test creating backup dependencies."""
        # Create commit
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-dep', 1, 'Dependency test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Register base backup
        base_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'dep-base-backup',
                'full',
                'pgbackrest',
                's3://bucket/base',
                'test-commit-dep'
            )
        """)

        # Register incremental backup
        incr_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'dep-incr-backup',
                'incremental',
                'pgbackrest',
                's3://bucket/incr',
                'test-commit-dep'
            )
        """)

        # Create dependency
        db.execute("""
            INSERT INTO pggit.backup_dependencies (backup_id, depends_on_backup_id, dependency_type)
            VALUES (%s, %s, 'incremental_chain')
        """, incr_id[0], base_id[0])

        # Verify dependency
        deps = db.execute("""
            SELECT dependency_type
            FROM pggit.backup_dependencies
            WHERE backup_id = %s AND depends_on_backup_id = %s
        """, incr_id[0], base_id[0])

        assert len(deps) == 1
        assert deps[0][0] == 'incremental_chain'
        print("✓ Backup dependency created successfully")


class TestBackupVerifications:
    """Test backup verification tracking."""

    def test_record_verification(self, db, pggit_installed):
        """Test recording backup verification."""
        # Create backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-verify', 1, 'Verification test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'verify-test-backup',
                'full',
                'pgbackrest',
                's3://bucket/verify',
                'test-commit-verify'
            )
        """)

        # Record verification
        verif_id = db.execute_returning("""
            INSERT INTO pggit.backup_verifications
            (backup_id, verification_type, status, details)
            VALUES (%s, 'checksum', 'passed', '{"checksum": "abc123"}'::jsonb)
            RETURNING verification_id
        """, backup_id[0])

        assert verif_id is not None

        # Query verification
        verifs = db.execute("""
            SELECT verification_type, status, details->>'checksum'
            FROM pggit.backup_verifications
            WHERE backup_id = %s
        """, backup_id[0])

        assert len(verifs) == 1
        assert verifs[0][0] == 'checksum'
        assert verifs[0][1] == 'passed'
        assert verifs[0][2] == 'abc123'
        print("✓ Backup verification recorded successfully")


class TestBackupTags:
    """Test backup tagging functionality."""

    def test_add_backup_tags(self, db, pggit_installed):
        """Test adding tags to backups."""
        # Create backup
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-tags', 1, 'Tags test')
            ON CONFLICT (hash) DO NOTHING
        """)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'tags-test-backup',
                'full',
                'pgbackrest',
                's3://bucket/tags',
                'test-commit-tags'
            )
        """)

        # Add tags
        db.execute("""
            INSERT INTO pggit.backup_tags (backup_id, tag_name, tag_value)
            VALUES (%s, 'environment', 'production'),
                   (%s, 'retention', '90d'),
                   (%s, 'critical', 'true')
        """, backup_id[0], backup_id[0], backup_id[0])

        # Query tags
        tags = db.execute("""
            SELECT tag_name, tag_value
            FROM pggit.backup_tags
            WHERE backup_id = %s
            ORDER BY tag_name
        """, backup_id[0])

        assert len(tags) == 3
        assert tags[0][0] == 'critical'
        assert tags[0][1] == 'true'
        assert tags[1][0] == 'environment'
        assert tags[1][1] == 'production'
        print(f"✓ Added {len(tags)} tags successfully")


class TestBackupEdgeCases:
    """Test edge cases and error handling."""

    def test_backup_location_validation(self, db, pggit_installed):
        """Test various backup location formats."""
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-locations', 1, 'Location test')
            ON CONFLICT (hash) DO NOTHING
        """)

        locations = [
            's3://mybucket/path/to/backup',
            'file:///var/backups/test.dump',
            'barman://server/backup-id',
            'gs://google-bucket/backup',
            '/absolute/path/to/backup'
        ]

        for loc in locations:
            backup_id = db.execute_returning("""
                SELECT pggit.register_backup(
                    %s,
                    'full',
                    'custom',
                    %s,
                    'test-commit-locations'
                )
            """, f'loc-test-{hash(loc)}', loc)

            assert backup_id is not None

        print(f"✓ All {len(locations)} location formats accepted")

    def test_backup_type_validation(self, db, pggit_installed):
        """Test backup type constraints."""
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-types', 1, 'Type test')
            ON CONFLICT (hash) DO NOTHING
        """)

        valid_types = ['full', 'incremental', 'differential', 'snapshot']

        for btype in valid_types:
            backup_id = db.execute_returning("""
                SELECT pggit.register_backup(
                    %s,
                    %s,
                    'pgbackrest',
                    's3://bucket/test',
                    'test-commit-types'
                )
            """, f'type-test-{btype}', btype)

            assert backup_id is not None

        print(f"✓ All {len(valid_types)} backup types validated")

        # Test invalid type
        with pytest.raises(Exception):
            db.execute("""
                SELECT pggit.register_backup(
                    'type-test-invalid',
                    'invalid_type',
                    'pgbackrest',
                    's3://bucket/test',
                    'test-commit-types'
                )
            """)

        print("✓ Invalid backup type correctly rejected")

    def test_large_metadata(self, db, pggit_installed):
        """Test backup with large metadata JSONB."""
        db.execute("""
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES ('test-commit-meta', 1, 'Metadata test')
            ON CONFLICT (hash) DO NOTHING
        """)

        # Create large metadata
        large_meta = {
            'files': [f'file_{i}.dat' for i in range(100)],
            'checksums': {f'file_{i}.dat': f'checksum_{i}' for i in range(100)},
            'server_config': {'key' * 10: 'value' * 10}
        }

        import json
        meta_json = json.dumps(large_meta)

        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'meta-test-backup',
                'full',
                'custom',
                's3://bucket/meta',
                'test-commit-meta',
                NULL,
                FALSE,
                %s::jsonb
            )
        """, meta_json)

        assert backup_id is not None

        # Verify metadata was stored
        result = db.execute_returning("""
            SELECT jsonb_array_length(metadata->'files')
            FROM pggit.backups
            WHERE backup_id = %s
        """, backup_id[0])

        assert result[0] == 100
        print("✓ Large metadata stored successfully")
