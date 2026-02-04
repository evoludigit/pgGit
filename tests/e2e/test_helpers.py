"""Helper functions for E2E tests.

Provides common patterns for creating test data using pggit API.
Prevents raw SQL mistakes and ensures consistent test setup.
"""

from typing import Optional
from uuid import UUID

from tests.fixtures.pooled_database import PooledDatabaseFixture


def create_test_commit(
    db: PooledDatabaseFixture,
    hash_suffix: str,
    branch_id: int = 1,
    message: Optional[str] = None,
) -> str:
    """Create a test commit with proper error handling.

    Args:
        db: Database fixture
        hash_suffix: Unique suffix for commit hash
        branch_id: Branch ID to associate with commit
        message: Commit message (defaults to hash)

    Returns:
        Commit hash
    """
    commit_hash = f"test-commit-{hash_suffix}"
    db.execute(
        """
        INSERT INTO pggit.commits (hash, branch_id, message)
        VALUES (%s, %s, %s) ON CONFLICT (hash) DO NOTHING
        """,
        commit_hash,
        branch_id,
        message or f"Test {hash_suffix}",
    )
    return commit_hash


def register_and_complete_backup(
    db: PooledDatabaseFixture,
    name: str,
    backup_type: str,
    commit_hash: str,
    location: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> UUID:
    """Register and complete a backup using the proper pggit API.

    Args:
        db: Database fixture
        name: Backup name
        backup_type: Type of backup (full, incremental)
        commit_hash: Associated commit hash
        location: Backup location (defaults to s3://bucket/{name})
        metadata: Optional metadata dict

    Returns:
        Backup ID
    """
    backup_id = db.execute_returning(
        """
        SELECT pggit.register_backup(%s, %s, 'pgbackrest', %s, %s)
        """,
        name,
        backup_type,
        location or f"s3://bucket/{name}",
        commit_hash,
    )[0]

    db.execute("SELECT pggit.complete_backup(%s::UUID)", backup_id)

    if metadata:
        db.execute(
            """
            UPDATE pggit.backups
            SET metadata = %s::JSONB
            WHERE backup_id = %s::UUID
            """,
            str(metadata),
            backup_id,
        )

    return backup_id


def create_expired_backup(
    db: PooledDatabaseFixture,
    name: str,
    backup_type: str = "full",
    days_ago: int = 40,
) -> UUID:
    """Create a backup marked as expired.

    Args:
        db: Database fixture
        name: Backup name
        backup_type: Type of backup
        days_ago: Days in the past to mark completion

    Returns:
        Backup ID
    """
    backup_id = db.execute_returning(
        """
        INSERT INTO pggit.backups (
            backup_name, backup_type, backup_tool, location,
            status, completed_at
        ) VALUES (
            %s, %s, 'pgbackrest', %s, 'completed',
            CURRENT_TIMESTAMP - INTERVAL '%s days'
        ) RETURNING backup_id
        """,
        name,
        backup_type,
        f"s3://bucket/{name}",
        days_ago,
    )[0]

    db.execute(
        """
        UPDATE pggit.backups
        SET status = 'expired', expires_at = CURRENT_TIMESTAMP - INTERVAL '1 day'
        WHERE backup_id = %s::UUID
        """,
        backup_id,
    )

    return backup_id


def verify_function_exists(db: PooledDatabaseFixture, function_name: str) -> bool:
    """Verify a pggit function exists in database.

    Args:
        db: Database fixture
        function_name: Name of function to check

    Returns:
        True if function exists
    """
    result = db.execute(
        """
        SELECT EXISTS (
            SELECT 1 FROM pg_proc
            WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit')
            AND proname = %s
        )
        """,
        function_name,
    )
    return result[0][0] if result else False


def get_function_source(db: PooledDatabaseFixture, function_name: str) -> Optional[str]:
    """Get the source code of a pggit function.

    Args:
        db: Database fixture
        function_name: Name of function

    Returns:
        Function source code or None if not found
    """
    result = db.execute(
        """
        SELECT pg_get_functiondef(
            'pggit.' || %s || '()'::regprocedure
        )
        """,
        function_name,
    )
    return result[0][0] if result else None
