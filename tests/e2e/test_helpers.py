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
    branch_id: Optional[int] = None,
    message: Optional[str] = None,
) -> str:
    """Create a test commit with proper error handling.

    Args:
        db: Database fixture
        hash_suffix: Unique suffix for commit hash
        branch_id: Branch ID to associate with commit (auto-find if None)
        message: Commit message (defaults to hash)

    Returns:
        Commit hash
    """
    commit_hash = f"test-commit-{hash_suffix}"

    # If no branch_id provided, find or create one
    if branch_id is None:
        # Try to find existing branch
        result = db.execute("SELECT id FROM pggit.branches LIMIT 1")
        if result and len(result) > 0:
            branch_id = result[0][0]
        else:
            # Create default branch if none exists
            try:
                db.execute(
                    "INSERT INTO pggit.branches (name, status) VALUES ('main', 'ACTIVE')"
                )
                result = db.execute("SELECT id FROM pggit.branches WHERE name = 'main'")
                branch_id = result[0][0] if result else 1
            except Exception:
                branch_id = 1  # Fallback

    try:
        db.execute(
            """
            INSERT INTO pggit.commits (hash, branch_id, message)
            VALUES (%s, %s, %s) ON CONFLICT (hash) DO NOTHING
            """,
            commit_hash,
            branch_id,
            message or f"Test {hash_suffix}",
        )
    except Exception as e:
        raise Exception(f"Failed to insert commit {commit_hash}: {str(e)}")
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
    # Create a test commit first (required by valid_commit constraint)
    commit_hash = create_test_commit(db, f"expired-{name}")

    # Register the backup via API (ensures all constraints are met)
    backup_id = register_and_complete_backup(
        db, name, backup_type, commit_hash, f"s3://bucket/{name}"
    )

    # Mark as expired
    db.execute(
        """
        UPDATE pggit.backups
        SET status = 'expired', expires_at = CURRENT_TIMESTAMP - INTERVAL '%s days'
        WHERE backup_id = %s::UUID
        """,
        days_ago,
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
    # Get the function definition by oid
    result = db.execute(
        """
        SELECT pg_get_functiondef(p.oid)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'pggit' AND p.proname = %s
        LIMIT 1
        """,
        function_name,
    )
    return result[0][0] if result else None
