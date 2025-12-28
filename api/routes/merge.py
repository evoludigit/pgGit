"""
Merge Operations REST API Endpoints
===================================

REST endpoints for three-way merge operations with conflict detection and resolution.
Exposes Phase 4 merge functionality via HTTP API.

Features:
- Find merge base (LCA)
- Execute three-way merge
- Detect conflicts
- Resolve conflicts (manual/automatic)
- Merge status tracking

Endpoints:
- GET  /branches/{branch1_id}/merge-base/{branch2_id}  - Find common ancestor
- POST /branches/{target_id}/merge                     - Execute merge
- GET  /merge/{merge_id}                               - Get merge status
- GET  /merge/{merge_id}/conflicts                     - List conflicts
- POST /merge/{merge_id}/conflicts/{conflict_id}       - Resolve conflict
"""

import logging
from typing import Optional
from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status, Path
from pydantic import BaseModel, Field

from services.dependencies import get_current_user, get_db, rate_limit_dependency
from services.advisory_locks import acquire_merge_lock, acquire_conflict_resolution_lock
from api.exceptions import (
    DatabaseException,
    TransactionException,
    InvalidMergeException,
    MergeOperationException,
    ResourceNotFoundException,
    InvalidInputException,
)

logger = logging.getLogger(__name__)

router = APIRouter()


# ===== PYDANTIC MODELS =====

class MergeBaseResponse(BaseModel):
    """Response for merge base (LCA) query"""
    base_branch_id: int
    base_branch_name: str
    depth_from_branch1: int
    depth_from_branch2: int

    class Config:
        json_schema_extra = {
            "example": {
                "base_branch_id": 1,
                "base_branch_name": "main",
                "depth_from_branch1": 3,
                "depth_from_branch2": 5
            }
        }


class MergeRequest(BaseModel):
    """Request body for initiating a merge"""
    source_branch_id: int = Field(..., gt=0, description="Branch to merge from (must be > 0)")
    merge_message: str = Field(..., min_length=1, max_length=500, description="Commit message for merge")
    merge_strategy: str = Field(
        default="MANUAL_REVIEW",
        description="Strategy: ABORT_ON_CONFLICT, TARGET_WINS, SOURCE_WINS, UNION, MANUAL_REVIEW"
    )
    base_branch_id: Optional[int] = Field(None, gt=0, description="Merge base (auto-discovered if null, must be > 0 if provided)")

    class Config:
        json_schema_extra = {
            "example": {
                "source_branch_id": 3,
                "merge_message": "Merge feature/user-auth into main",
                "merge_strategy": "MANUAL_REVIEW",
                "base_branch_id": None
            }
        }


class MergeResponse(BaseModel):
    """Response for merge operation"""
    merge_id: str
    status: str
    conflicts_detected: int
    auto_resolvable_count: int
    manual_count: int
    merge_complete: bool
    result_commit_hash: Optional[str]
    merge_base_branch_id: int

    class Config:
        json_schema_extra = {
            "example": {
                "merge_id": "merge_20251228_123456",
                "status": "pending",
                "conflicts_detected": 5,
                "auto_resolvable_count": 2,
                "manual_count": 3,
                "merge_complete": False,
                "result_commit_hash": None,
                "merge_base_branch_id": 1
            }
        }


class ConflictResponse(BaseModel):
    """Individual conflict details"""
    conflict_id: int
    object_type: str
    schema_name: str
    object_name: str
    conflict_type: str
    base_hash: Optional[str]
    source_hash: Optional[str]
    target_hash: Optional[str]
    auto_resolvable: bool
    severity: str
    dependencies_count: int

    class Config:
        json_schema_extra = {
            "example": {
                "conflict_id": 1,
                "object_type": "TABLE",
                "schema_name": "public",
                "object_name": "users",
                "conflict_type": "BOTH_MODIFIED",
                "base_hash": "abc123",
                "source_hash": "def456",
                "target_hash": "ghi789",
                "auto_resolvable": False,
                "severity": "HIGH",
                "dependencies_count": 3
            }
        }


class ConflictListResponse(BaseModel):
    """List of conflicts for a merge"""
    merge_id: str
    conflicts: list[ConflictResponse]
    total_conflicts: int


class ResolveConflictRequest(BaseModel):
    """Request to resolve a conflict"""
    resolution: str = Field(..., min_length=1, max_length=50, description="Resolution type: SOURCE, TARGET, CUSTOM")
    custom_definition: Optional[str] = Field(None, max_length=10000, description="Custom SQL definition for CUSTOM resolution (max 10000 chars)")

    class Config:
        json_schema_extra = {
            "example": {
                "resolution": "SOURCE",
                "custom_definition": None
            }
        }


class ResolveConflictResponse(BaseModel):
    """Response after resolving a conflict"""
    merge_id: str
    conflict_id: int
    resolution_applied: str
    resolved_at: datetime
    merge_complete: bool


# ===== ENDPOINTS =====

@router.get(
    "/branches/{branch1_id}/merge-base/{branch2_id}",
    response_model=MergeBaseResponse,
    tags=["Merge Operations"]
)
async def find_merge_base(
    branch1_id: int = Path(..., description="First branch ID", gt=0),
    branch2_id: int = Path(..., description="Second branch ID", gt=0),
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Find the lowest common ancestor (merge base) between two branches.

    Uses recursive CTE to traverse branch ancestry and find the LCA.
    Returns the common ancestor with depth information.

    Path Parameters:
    - branch1_id: First branch ID (must be > 0)
    - branch2_id: Second branch ID (must be > 0)

    Returns:
        Merge base information with depths from each branch
    """
    # Input validation
    if branch1_id == branch2_id:
        exc = InvalidInputException(
            "Cannot find merge base between identical branches",
            field_name="branch_ids",
            field_value=f"{branch1_id}",
            expected_format="branch1_id != branch2_id"
        )
        logger.warning(
            "Invalid merge base request: identical branches",
            extra=exc.to_dict()
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message
        )

    try:
        result = await db.fetchrow(
            """
            SELECT base_branch_id, base_branch_name, depth_from_branch1, depth_from_branch2
            FROM pggit.find_merge_base($1, $2)
            """,
            branch1_id,
            branch2_id
        )

        if not result:
            exc = ResourceNotFoundException(
                f"No common ancestor found between branches {branch1_id} and {branch2_id}",
                resource_type="merge_base",
                resource_id=f"{branch1_id},{branch2_id}"
            )
            logger.info(
                "Merge base not found",
                extra=exc.to_dict()
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=exc.message
            )

        return MergeBaseResponse(
            base_branch_id=result['base_branch_id'],
            base_branch_name=result['base_branch_name'],
            depth_from_branch1=result['depth_from_branch1'],
            depth_from_branch2=result['depth_from_branch2']
        )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        exc = DatabaseException(
            "Failed to find merge base due to database error",
            original_error=e,
            context={
                "branch1_id": branch1_id,
                "branch2_id": branch2_id,
                "error_detail": str(e)
            }
        )
        logger.exception(
            "Database error finding merge base",
            extra=exc.to_dict()
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=exc.message
        )


@router.post(
    "/branches/{target_id}/merge",
    response_model=MergeResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Merge Operations"]
)
async def merge_branches(
    target_id: int = Path(..., description="Target branch ID (merge into)", gt=0),
    merge_request: MergeRequest = ...,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Execute a three-way merge between source and target branches.

    Performs conflict detection and applies the specified merge strategy.
    Creates a merge record and returns conflict information.

    Path Parameters:
    - target_id: Branch to merge into (must be > 0)

    Request Body:
    - source_branch_id: Branch to merge from (must be > 0)
    - merge_message: Commit message (max 500 chars)
    - merge_strategy: ABORT_ON_CONFLICT, TARGET_WINS, SOURCE_WINS, UNION, MANUAL_REVIEW
    - base_branch_id: Optional merge base (auto-discovered if not provided)

    Returns:
        Merge operation result with conflict counts and status
    """
    # Input validation
    if merge_request.source_branch_id <= 0:
        exc = InvalidInputException(
            "Source branch ID must be positive",
            field_name="source_branch_id",
            field_value=merge_request.source_branch_id,
            expected_format="positive integer"
        )
        logger.warning("Invalid source branch ID", extra=exc.to_dict())
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message
        )

    if merge_request.source_branch_id == target_id:
        exc = InvalidMergeException(
            "Cannot merge branch into itself",
            source_branch_id=merge_request.source_branch_id,
            target_branch_id=target_id
        )
        logger.warning("Self-merge attempt", extra=exc.to_dict())
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message
        )

    # Validate merge strategy
    valid_strategies = {'ABORT_ON_CONFLICT', 'TARGET_WINS', 'SOURCE_WINS', 'UNION', 'MANUAL_REVIEW'}
    if merge_request.merge_strategy not in valid_strategies:
        exc = InvalidInputException(
            f"Invalid merge strategy. Must be one of: {', '.join(valid_strategies)}",
            field_name="merge_strategy",
            field_value=merge_request.merge_strategy,
            expected_format=f"one of: {', '.join(valid_strategies)}"
        )
        logger.warning("Invalid merge strategy", extra=exc.to_dict())
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message
        )

    if merge_request.base_branch_id is not None and merge_request.base_branch_id <= 0:
        exc = InvalidInputException(
            "Base branch ID must be positive if provided",
            field_name="base_branch_id",
            field_value=merge_request.base_branch_id,
            expected_format="positive integer or null"
        )
        logger.warning("Invalid base branch ID", extra=exc.to_dict())
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message
        )

    try:
        # Execute merge operation within a transaction with advisory lock
        async with db.transaction():
            # Acquire advisory lock to prevent concurrent merges on same branches
            async with acquire_merge_lock(db, merge_request.source_branch_id, target_id):
                result = await db.fetchrow(
                    """
                    SELECT merge_id, status, conflicts_detected, auto_resolvable_count,
                           manual_count, merge_complete, result_commit_hash, merge_base_branch_id
                    FROM pggit.merge_branches($1, $2, $3, $4, $5)
                    """,
                    merge_request.source_branch_id,
                    target_id,
                    merge_request.merge_message,
                    merge_request.merge_strategy,
                    merge_request.base_branch_id
                )

                if not result:
                    exc = MergeOperationException(
                        "Merge operation failed to return result",
                        operation_step="execute_merge",
                        context={
                            "source_branch_id": merge_request.source_branch_id,
                            "target_branch_id": target_id,
                            "merge_strategy": merge_request.merge_strategy
                        }
                    )
                    logger.error("Merge operation failed", extra=exc.to_dict())
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail=exc.message
                    )

                logger.info(
                    "Merge operation initiated",
                    extra={
                        "merge_id": result['merge_id'],
                        "source_branch_id": merge_request.source_branch_id,
                        "target_branch_id": target_id,
                        "conflicts_detected": result['conflicts_detected'],
                        "auto_resolvable_count": result['auto_resolvable_count'],
                        "manual_count": result['manual_count'],
                        "merge_strategy": merge_request.merge_strategy
                    }
                )

                return MergeResponse(
                    merge_id=result['merge_id'],
                    status=result['status'],
                    conflicts_detected=result['conflicts_detected'],
                    auto_resolvable_count=result['auto_resolvable_count'],
                    manual_count=result['manual_count'],
                    merge_complete=result['merge_complete'],
                    result_commit_hash=result['result_commit_hash'],
                    merge_base_branch_id=result['merge_base_branch_id']
                )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        exc = TransactionException(
            "Merge operation failed due to database error",
            original_error=e,
            operation="merge_branches",
            context={
                "source_branch_id": merge_request.source_branch_id,
                "target_branch_id": target_id,
                "merge_strategy": merge_request.merge_strategy,
                "error_detail": str(e)
            }
        )
        logger.exception("Database error during merge", extra=exc.to_dict())
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=exc.message
        )


@router.get(
    "/merge/{merge_id}",
    response_model=MergeResponse,
    tags=["Merge Operations"]
)
async def get_merge_status(
    merge_id: str = Path(..., description="Merge operation ID"),
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get the status of a merge operation.

    Retrieves the current state of a merge including conflict counts
    and completion status.

    Path Parameters:
    - merge_id: Merge operation ID

    Returns:
        Current merge status and statistics
    """
    try:
        result = await db.fetchrow(
            """
            SELECT
                id as merge_id,
                status,
                (SELECT COUNT(*) FROM pggit.merge_conflict_resolutions WHERE merge_id = mo.id) as conflicts_detected,
                (SELECT COUNT(*) FROM pggit.merge_conflict_resolutions WHERE merge_id = mo.id AND resolution_type = 'AUTO') as auto_resolvable_count,
                (SELECT COUNT(*) FROM pggit.merge_conflict_resolutions WHERE merge_id = mo.id AND resolution_type IS NULL) as manual_count,
                (status = 'completed') as merge_complete,
                result_commit_hash,
                merge_base_branch_id
            FROM pggit.merge_operations mo
            WHERE id = $1
            """,
            merge_id
        )

        if not result:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Merge operation {merge_id} not found"
            )

        return MergeResponse(
            merge_id=result['merge_id'],
            status=result['status'],
            conflicts_detected=result['conflicts_detected'] or 0,
            auto_resolvable_count=result['auto_resolvable_count'] or 0,
            manual_count=result['manual_count'] or 0,
            merge_complete=result['merge_complete'],
            result_commit_hash=result['result_commit_hash'],
            merge_base_branch_id=result['merge_base_branch_id']
        )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching merge status: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch merge status: {str(e)}"
        )


@router.get(
    "/merge/{merge_id}/conflicts",
    response_model=ConflictListResponse,
    tags=["Merge Operations"]
)
async def list_merge_conflicts(
    merge_id: str = Path(..., description="Merge operation ID"),
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    List all conflicts for a merge operation.

    Returns detailed information about each conflict including
    type, severity, and auto-resolvability.

    Path Parameters:
    - merge_id: Merge operation ID

    Returns:
        List of conflicts with detailed information
    """
    try:
        # Verify merge exists
        merge_exists = await db.fetchval(
            "SELECT EXISTS(SELECT 1 FROM pggit.merge_operations WHERE id = $1)",
            merge_id
        )

        if not merge_exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Merge operation {merge_id} not found"
            )

        # Get conflicts by re-running detection
        # (In a real system, you'd store these in merge_conflict_resolutions table)
        merge_data = await db.fetchrow(
            "SELECT source_branch_id, target_branch_id, merge_base_branch_id FROM pggit.merge_operations WHERE id = $1",
            merge_id
        )

        conflicts_data = await db.fetch(
            """
            SELECT conflict_id, object_type, schema_name, object_name, conflict_type,
                   base_hash, source_hash, target_hash, auto_resolvable, severity, dependencies_count
            FROM pggit.detect_merge_conflicts($1, $2, $3)
            WHERE conflict_type != 'NO_CONFLICT'
            ORDER BY severity DESC, conflict_id
            """,
            merge_data['source_branch_id'],
            merge_data['target_branch_id'],
            merge_data['merge_base_branch_id']
        )

        conflicts = [
            ConflictResponse(
                conflict_id=row['conflict_id'],
                object_type=row['object_type'],
                schema_name=row['schema_name'],
                object_name=row['object_name'],
                conflict_type=row['conflict_type'],
                base_hash=row['base_hash'],
                source_hash=row['source_hash'],
                target_hash=row['target_hash'],
                auto_resolvable=row['auto_resolvable'],
                severity=row['severity'],
                dependencies_count=row['dependencies_count']
            )
            for row in conflicts_data
        ]

        return ConflictListResponse(
            merge_id=merge_id,
            conflicts=conflicts,
            total_conflicts=len(conflicts)
        )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error listing conflicts: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list conflicts: {str(e)}"
        )


@router.post(
    "/merge/{merge_id}/conflicts/{conflict_id}",
    response_model=ResolveConflictResponse,
    tags=["Merge Operations"]
)
async def resolve_conflict(
    merge_id: str = Path(..., description="Merge operation ID", min_length=1, max_length=100),
    conflict_id: int = Path(..., description="Conflict ID", gt=0),
    resolution: ResolveConflictRequest = ...,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Resolve a specific conflict in a merge operation.

    Applies the specified resolution strategy to the conflict.
    Updates merge status and checks if all conflicts are resolved.

    Path Parameters:
    - merge_id: Merge operation ID (1-100 chars)
    - conflict_id: Conflict ID to resolve (must be > 0)

    Request Body:
    - resolution: SOURCE (use source version), TARGET (use target version), CUSTOM (provide SQL)
    - custom_definition: SQL definition (required if resolution=CUSTOM)

    Returns:
        Resolution result and updated merge status
    """
    # Input validation
    valid_resolutions = {'SOURCE', 'TARGET', 'CUSTOM'}
    if resolution.resolution not in valid_resolutions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid resolution type. Must be one of: {', '.join(valid_resolutions)}"
        )

    if resolution.resolution == 'CUSTOM' and not resolution.custom_definition:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Custom definition is required when resolution type is CUSTOM"
        )

    if resolution.custom_definition and len(resolution.custom_definition) > 10000:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Custom definition exceeds maximum length of 10000 characters"
        )

    try:
        # Execute conflict resolution within a transaction
        async with db.transaction():
            result = await db.fetchrow(
                """
                SELECT merge_id, conflict_id, resolution_applied, resolved_at, merge_complete
                FROM pggit.resolve_conflict($1, $2, $3, $4)
                """,
                merge_id,
                conflict_id,
                resolution.resolution,
                resolution.custom_definition
            )

            if not result:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Conflict resolution failed to return result"
                )

            logger.info(
                f"Conflict resolved: {merge_id}/{conflict_id} - "
                f"resolution={resolution.resolution} - "
                f"merge_complete={result['merge_complete']}"
            )

            return ResolveConflictResponse(
                merge_id=result['merge_id'],
                conflict_id=result['conflict_id'],
                resolution_applied=result['resolution_applied'],
                resolved_at=result['resolved_at'],
                merge_complete=result['merge_complete']
            )

    except asyncpg.PostgresError as e:
        logger.error(f"Database error resolving conflict: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to resolve conflict: {str(e)}"
        )
