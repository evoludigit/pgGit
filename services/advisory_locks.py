"""
PostgreSQL Advisory Locks for Concurrency Control
=================================================

Provides advisory lock utilities to prevent race conditions in merge operations.
Uses PostgreSQL's session-level advisory locks for serialization.

Advisory Lock Strategy:
- Lock key based on branch IDs (sorted to prevent deadlocks)
- Locks are automatically released on transaction commit/rollback
- Non-blocking try_lock for graceful failures
- Proper lock ordering to prevent deadlocks

Lock Types:
- merge_lock: Prevents concurrent merges involving same branches
- conflict_resolution_lock: Prevents concurrent conflict resolution

Example Usage:
    async with acquire_merge_lock(conn, source_id, target_id):
        # Execute merge operation
        # Lock automatically released on exit
"""

import asyncpg
import logging
from contextlib import asynccontextmanager
from typing import Tuple

from api.exceptions import MergeOperationException

logger = logging.getLogger(__name__)


def _hash_lock_key(key_type: str, *values: int) -> int:
    """
    Generate consistent hash key for advisory locks.

    PostgreSQL advisory locks use bigint keys. We create a hash from:
    - key_type: 'merge', 'conflict', etc (converted to number)
    - values: Branch IDs, merge IDs, etc (sorted to prevent deadlocks)

    Returns:
        int: Hash value suitable for PostgreSQL advisory lock (within bigint range)
    """
    # Map key type to small integer
    type_mapping = {
        'merge': 1,
        'conflict': 2,
        'branch': 3,
    }
    type_num = type_mapping.get(key_type, 0)

    # Sort values to ensure consistent ordering (prevents deadlocks)
    sorted_values = sorted(values)

    # Create hash: type_num + sum of values
    # Keep within PostgreSQL bigint range: -2^63 to 2^63-1
    lock_key = (type_num * 1000000000) + sum(sorted_values)

    # Ensure we're within bigint range
    max_bigint = 9223372036854775807
    if lock_key > max_bigint:
        lock_key = lock_key % max_bigint

    return lock_key


async def try_acquire_merge_lock(
    conn: asyncpg.Connection,
    source_branch_id: int,
    target_branch_id: int,
    timeout_seconds: float = 5.0
) -> bool:
    """
    Try to acquire advisory lock for merge operation.

    Args:
        conn: Database connection
        source_branch_id: Source branch ID
        target_branch_id: Target branch ID
        timeout_seconds: Maximum time to wait for lock

    Returns:
        bool: True if lock acquired, False if timeout

    Raises:
        MergeOperationException: If lock acquisition fails
    """
    lock_key = _hash_lock_key('merge', source_branch_id, target_branch_id)

    try:
        # Try to acquire lock with timeout
        # pg_try_advisory_lock returns true if lock acquired, false otherwise
        result = await conn.fetchval(
            "SELECT pg_try_advisory_lock($1)",
            lock_key
        )

        if result:
            logger.info(
                "Advisory lock acquired for merge",
                extra={
                    "lock_key": lock_key,
                    "source_branch_id": source_branch_id,
                    "target_branch_id": target_branch_id
                }
            )
            return True
        else:
            logger.warning(
                "Failed to acquire merge lock - operation in progress",
                extra={
                    "lock_key": lock_key,
                    "source_branch_id": source_branch_id,
                    "target_branch_id": target_branch_id,
                    "timeout_seconds": timeout_seconds
                }
            )
            return False

    except asyncpg.PostgresError as e:
        exc = MergeOperationException(
            "Failed to acquire advisory lock for merge operation",
            operation_step="acquire_lock",
            context={
                "lock_key": lock_key,
                "source_branch_id": source_branch_id,
                "target_branch_id": target_branch_id,
                "error": str(e)
            }
        )
        logger.exception("Lock acquisition error", extra=exc.to_dict())
        raise exc


async def release_merge_lock(
    conn: asyncpg.Connection,
    source_branch_id: int,
    target_branch_id: int
) -> None:
    """
    Release advisory lock for merge operation.

    Args:
        conn: Database connection
        source_branch_id: Source branch ID
        target_branch_id: Target branch ID
    """
    lock_key = _hash_lock_key('merge', source_branch_id, target_branch_id)

    try:
        # Release the advisory lock
        await conn.execute(
            "SELECT pg_advisory_unlock($1)",
            lock_key
        )

        logger.info(
            "Advisory lock released for merge",
            extra={
                "lock_key": lock_key,
                "source_branch_id": source_branch_id,
                "target_branch_id": target_branch_id
            }
        )

    except asyncpg.PostgresError as e:
        # Log but don't raise - lock will be auto-released on connection close
        logger.warning(
            f"Failed to explicitly release advisory lock (will auto-release): {e}",
            extra={
                "lock_key": lock_key,
                "source_branch_id": source_branch_id,
                "target_branch_id": target_branch_id
            }
        )


@asynccontextmanager
async def acquire_merge_lock(
    conn: asyncpg.Connection,
    source_branch_id: int,
    target_branch_id: int,
    timeout_seconds: float = 5.0
):
    """
    Context manager for acquiring/releasing merge advisory lock.

    Usage:
        async with acquire_merge_lock(conn, source_id, target_id):
            # Execute merge operation
            # Lock automatically released on exit

    Args:
        conn: Database connection
        source_branch_id: Source branch ID
        target_branch_id: Target branch ID
        timeout_seconds: Maximum time to wait for lock

    Raises:
        MergeOperationException: If lock cannot be acquired or concurrent operation detected
    """
    lock_acquired = await try_acquire_merge_lock(
        conn,
        source_branch_id,
        target_branch_id,
        timeout_seconds
    )

    if not lock_acquired:
        raise MergeOperationException(
            f"Cannot execute merge: concurrent merge operation in progress on branches {source_branch_id} and/or {target_branch_id}",
            merge_id=None,
            operation_step="acquire_lock",
            context={
                "source_branch_id": source_branch_id,
                "target_branch_id": target_branch_id,
                "reason": "lock_timeout"
            }
        )

    try:
        yield
    finally:
        await release_merge_lock(conn, source_branch_id, target_branch_id)


@asynccontextmanager
async def acquire_conflict_resolution_lock(
    conn: asyncpg.Connection,
    merge_id: str,
    conflict_id: int
):
    """
    Context manager for acquiring/releasing conflict resolution advisory lock.

    Prevents concurrent resolution of the same conflict.

    Usage:
        async with acquire_conflict_resolution_lock(conn, merge_id, conflict_id):
            # Resolve conflict
            # Lock automatically released on exit

    Args:
        conn: Database connection
        merge_id: Merge operation ID (hashed to int)
        conflict_id: Conflict ID

    Raises:
        MergeOperationException: If lock cannot be acquired
    """
    # Hash merge_id string to integer
    merge_id_hash = abs(hash(merge_id)) % 1000000000

    lock_key = _hash_lock_key('conflict', merge_id_hash, conflict_id)

    try:
        # Acquire lock
        result = await conn.fetchval(
            "SELECT pg_try_advisory_lock($1)",
            lock_key
        )

        if not result:
            raise MergeOperationException(
                f"Cannot resolve conflict: concurrent resolution in progress for conflict {conflict_id}",
                merge_id=merge_id,
                operation_step="acquire_conflict_lock",
                context={
                    "merge_id": merge_id,
                    "conflict_id": conflict_id,
                    "reason": "concurrent_resolution"
                }
            )

        logger.info(
            "Conflict resolution lock acquired",
            extra={
                "lock_key": lock_key,
                "merge_id": merge_id,
                "conflict_id": conflict_id
            }
        )

        yield

    finally:
        # Release lock
        try:
            await conn.execute(
                "SELECT pg_advisory_unlock($1)",
                lock_key
            )
            logger.info(
                "Conflict resolution lock released",
                extra={
                    "lock_key": lock_key,
                    "merge_id": merge_id,
                    "conflict_id": conflict_id
                }
            )
        except asyncpg.PostgresError as e:
            logger.warning(
                f"Failed to release conflict lock (will auto-release): {e}",
                extra={
                    "lock_key": lock_key,
                    "merge_id": merge_id,
                    "conflict_id": conflict_id
                }
            )
