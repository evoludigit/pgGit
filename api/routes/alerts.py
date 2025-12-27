"""
Alert REST API Endpoints
=======================

REST endpoints for alert management.
Endpoints: GET, POST alerts with acknowledgment support.

Features:
- JWT authentication
- Response caching
- Pagination support
- Alert acknowledgment
- Alert statistics
"""

import logging
from typing import Optional
from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field

from services.dependencies import get_current_user, get_db, rate_limit_dependency
from services.cache import get_cache

logger = logging.getLogger(__name__)

router = APIRouter()


# ===== PYDANTIC MODELS =====

class AlertResponse(BaseModel):
    """Model for alert response"""
    id: int
    queue_id: int
    webhook_id: int
    alert_type: str
    severity: str
    message: str
    delivery_status: str
    created_at: datetime
    acknowledged: bool = False
    acknowledged_at: Optional[datetime] = None

    class Config:
        json_schema_extra = {
            "example": {
                "id": 1,
                "queue_id": 101,
                "webhook_id": 5,
                "alert_type": "anomaly_detected",
                "severity": "WARNING",
                "message": "Statistical anomaly detected in commit operation",
                "delivery_status": "pending",
                "created_at": "2024-01-01T12:00:00Z",
                "acknowledged": False,
                "acknowledged_at": None
            }
        }


class AlertListResponse(BaseModel):
    """Model for paginated alert list response"""
    alerts: list[AlertResponse]
    total: int
    page: int
    page_size: int
    pages: int


class AlertStatisticsResponse(BaseModel):
    """Model for alert statistics"""
    total_alerts: int
    pending_alerts: int
    acknowledged_alerts: int
    failed_alerts: int
    critical_count: int
    warning_count: int
    info_count: int
    avg_pending_hours: float
    oldest_pending_alert: Optional[datetime] = None


class AcknowledgeAlertRequest(BaseModel):
    """Model for acknowledging an alert"""
    notes: Optional[str] = Field(None, max_length=500)


# ===== ENDPOINTS =====

@router.get("/alerts", response_model=AlertListResponse, tags=["Alerts"])
async def list_alerts(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status_filter: Optional[str] = Query(None, description="Filter by delivery status"),
    severity_filter: Optional[str] = Query(None, description="Filter by severity")
):
    """
    List all alerts with pagination and filtering.

    Query Parameters:
    - page: Page number (1-indexed)
    - page_size: Items per page (1-100)
    - status_filter: Filter by delivery status (pending, delivered, failed)
    - severity_filter: Filter by severity (CRITICAL, WARNING, INFO)

    Returns:
        List of alerts with pagination metadata
    """
    cache = await get_cache()
    cache_key = f"alerts:list:{page}:{page_size}:{status_filter}:{severity_filter}"

    # Try cache first
    cached_result = await cache.get(cache_key)
    if cached_result:
        logger.debug(f"Cache hit for {cache_key}")
        return cached_result

    try:
        # Build filter query
        where_clauses = []
        params = []

        if status_filter:
            where_clauses.append("adq.delivery_status = $1")
            params.append(status_filter)

        if severity_filter:
            where_clauses.append("adq.severity = $2" if params else "adq.severity = $1")
            params.append(severity_filter)

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

        # Get total count
        count_query = f"SELECT COUNT(*) FROM pggit.alert_delivery_queue adq WHERE {where_sql}"
        total_result = await db.fetchval(count_query, *params)
        total = total_result or 0

        # Calculate pagination
        offset = (page - 1) * page_size
        pages = (total + page_size - 1) // page_size

        # Fetch alerts
        alerts_query = f"""
            SELECT
                adq.alert_id as id,
                adq.queue_id,
                adq.webhook_id,
                adq.alert_type,
                adq.severity,
                adq.message,
                adq.delivery_status,
                adq.created_at,
                adq.acknowledged,
                adq.acknowledged_at
            FROM pggit.alert_delivery_queue adq
            WHERE {where_sql}
            ORDER BY adq.created_at DESC
            LIMIT ${ len(params) + 1} OFFSET ${len(params) + 2}
        """

        alerts_data = await db.fetch(alerts_query, *params, page_size, offset)

        alerts = [
            AlertResponse(
                id=row['id'],
                queue_id=row['queue_id'],
                webhook_id=row['webhook_id'],
                alert_type=row['alert_type'],
                severity=row['severity'],
                message=row['message'],
                delivery_status=row['delivery_status'],
                created_at=row['created_at'],
                acknowledged=row['acknowledged'],
                acknowledged_at=row['acknowledged_at']
            )
            for row in alerts_data
        ]

        response = AlertListResponse(
            alerts=alerts,
            total=total,
            page=page,
            page_size=page_size,
            pages=pages
        )

        # Cache for 30 seconds
        await cache.set(cache_key, response, ttl_seconds=30)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error listing alerts: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list alerts"
        )


@router.get("/alerts/{alert_id}", response_model=AlertResponse, tags=["Alerts"])
async def get_alert(
    alert_id: int,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get alert details by ID.

    Path Parameters:
    - alert_id: ID of the alert

    Returns:
        Alert details with delivery status
    """
    cache = await get_cache()
    cache_key = f"alert:{alert_id}"

    # Try cache first
    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        alert_data = await db.fetchrow(
            """
            SELECT
                adq.alert_id as id,
                adq.queue_id,
                adq.webhook_id,
                adq.alert_type,
                adq.severity,
                adq.message,
                adq.delivery_status,
                adq.created_at,
                adq.acknowledged,
                adq.acknowledged_at
            FROM pggit.alert_delivery_queue adq
            WHERE adq.alert_id = $1
            """,
            alert_id
        )

        if not alert_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Alert {alert_id} not found"
            )

        response = AlertResponse(
            id=alert_data['id'],
            queue_id=alert_data['queue_id'],
            webhook_id=alert_data['webhook_id'],
            alert_type=alert_data['alert_type'],
            severity=alert_data['severity'],
            message=alert_data['message'],
            delivery_status=alert_data['delivery_status'],
            created_at=alert_data['created_at'],
            acknowledged=alert_data['acknowledged'],
            acknowledged_at=alert_data['acknowledged_at']
        )

        # Cache for 60 seconds
        await cache.set(cache_key, response, ttl_seconds=60)
        return response

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching alert {alert_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch alert"
        )


@router.post("/alerts/{alert_id}/ack", response_model=AlertResponse, tags=["Alerts"])
async def acknowledge_alert(
    alert_id: int,
    request: AcknowledgeAlertRequest,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Acknowledge an alert.

    Path Parameters:
    - alert_id: ID of the alert to acknowledge

    Request Body:
    - notes: Optional notes about the acknowledgment

    Returns:
        Updated alert with acknowledgment timestamp
    """
    try:
        # Update alert as acknowledged
        alert_data = await db.fetchrow(
            """
            UPDATE pggit.alert_delivery_queue
            SET
                acknowledged = TRUE,
                acknowledged_at = CURRENT_TIMESTAMP,
                acknowledged_by = $2,
                notes = $3
            WHERE alert_id = $1
            RETURNING
                alert_id as id,
                queue_id,
                webhook_id,
                alert_type,
                severity,
                message,
                delivery_status,
                created_at,
                acknowledged,
                acknowledged_at
            """,
            alert_id,
            user.get("user_id"),
            request.notes
        )

        if not alert_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Alert {alert_id} not found"
            )

        # Invalidate cache
        cache = await get_cache()
        await cache.delete(f"alert:{alert_id}")
        await cache.delete("alerts:list:*")

        logger.info(f"Acknowledged alert: {alert_id}")

        return AlertResponse(
            id=alert_data['id'],
            queue_id=alert_data['queue_id'],
            webhook_id=alert_data['webhook_id'],
            alert_type=alert_data['alert_type'],
            severity=alert_data['severity'],
            message=alert_data['message'],
            delivery_status=alert_data['delivery_status'],
            created_at=alert_data['created_at'],
            acknowledged=alert_data['acknowledged'],
            acknowledged_at=alert_data['acknowledged_at']
        )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error acknowledging alert {alert_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to acknowledge alert"
        )


@router.get("/alerts/stats/summary", response_model=AlertStatisticsResponse, tags=["Alerts"])
async def get_alert_statistics(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get alert statistics summary.

    Returns:
        Alert statistics including counts and averages
    """
    cache = await get_cache()
    cache_key = "alerts:stats:summary"

    # Try cache first
    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        stats_data = await db.fetchrow(
            """
            SELECT
                COUNT(*) as total_alerts,
                COUNT(CASE WHEN delivery_status = 'pending' THEN 1 END) as pending_alerts,
                COUNT(CASE WHEN acknowledged = TRUE THEN 1 END) as acknowledged_alerts,
                COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END) as failed_alerts,
                COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) as critical_count,
                COUNT(CASE WHEN severity = 'WARNING' THEN 1 END) as warning_count,
                COUNT(CASE WHEN severity = 'INFO' THEN 1 END) as info_count,
                COALESCE(
                    AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - created_at)) / 3600),
                    0
                ) as avg_pending_hours,
                MIN(CASE WHEN delivery_status = 'pending' THEN created_at END) as oldest_pending_alert
            FROM pggit.alert_delivery_queue
            WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
            """
        )

        response = AlertStatisticsResponse(
            total_alerts=stats_data['total_alerts'] or 0,
            pending_alerts=stats_data['pending_alerts'] or 0,
            acknowledged_alerts=stats_data['acknowledged_alerts'] or 0,
            failed_alerts=stats_data['failed_alerts'] or 0,
            critical_count=stats_data['critical_count'] or 0,
            warning_count=stats_data['warning_count'] or 0,
            info_count=stats_data['info_count'] or 0,
            avg_pending_hours=float(stats_data['avg_pending_hours'] or 0),
            oldest_pending_alert=stats_data['oldest_pending_alert']
        )

        # Cache for 5 minutes
        await cache.set(cache_key, response, ttl_seconds=300)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching alert statistics: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch alert statistics"
        )
