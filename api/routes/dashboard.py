"""
Dashboard REST API Endpoints
============================

REST endpoints for dashboard data and analytics.
Provides system overview, performance metrics, and real-time updates.

Features:
- Comprehensive dashboard data endpoint
- Performance metrics summary
- Webhook health status
- Anomaly detection
- Caching for performance
"""

import logging
from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel

from services.dependencies import get_current_user, get_db, rate_limit_dependency
from services.cache import get_cache

logger = logging.getLogger(__name__)

router = APIRouter()


# ===== PYDANTIC MODELS =====

class OverviewMetrics(BaseModel):
    """System overview metrics"""
    total_deliveries: int
    pending_deliveries: int
    failed_deliveries: int
    success_rate_percent: float
    active_webhooks: int
    degraded_webhooks: int
    updated_at: datetime


class PerformanceMetrics(BaseModel):
    """Performance metrics summary"""
    p50_latency_ms: float
    p95_latency_ms: float
    p99_latency_ms: float
    error_rate_percent: float
    cache_hit_rate_percent: float
    average_response_time_ms: float


class WebhookSummary(BaseModel):
    """Webhook health summary"""
    id: int
    name: str
    health_status: str
    total_deliveries: int
    successful_deliveries: int
    failed_deliveries: int
    success_rate_percent: float
    last_delivery_at: datetime | None = None


class AnomalySummary(BaseModel):
    """Anomaly detection summary"""
    total_anomalies: int
    critical_anomalies: int
    warning_anomalies: int
    affected_operations: list[str]
    recent_anomalies_count: int


class DashboardDataResponse(BaseModel):
    """Complete dashboard data response"""
    overview: OverviewMetrics
    performance: PerformanceMetrics
    webhooks: list[WebhookSummary]
    anomalies: AnomalySummary
    generated_at: datetime
    cache_hit: bool = False


# ===== ENDPOINTS =====

@router.get("/dashboard", response_model=DashboardDataResponse, tags=["Dashboard"])
async def get_dashboard(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get complete dashboard data.

    Includes:
    - Overview metrics (deliveries, success rate)
    - Performance metrics (latency, error rate)
    - Webhook health summary
    - Anomaly detection summary

    Returns:
        Complete dashboard data with all metrics
    """
    cache = await get_cache()
    cache_key = "dashboard:full"

    # Try cache first (cache miss is ok, we'll compute fresh data)
    cached_result = await cache.get(cache_key)
    if cached_result:
        cached_result.cache_hit = True
        return cached_result

    try:
        # Fetch overview metrics
        overview_data = await db.fetchrow(
            """
            SELECT
                COUNT(*) as total_deliveries,
                COUNT(CASE WHEN delivery_status = 'pending' THEN 1 END) as pending_deliveries,
                COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END) as failed_deliveries,
                ROUND(
                    100.0 * COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END) /
                    NULLIF(COUNT(*), 0),
                    2
                ) as success_rate_percent,
                CURRENT_TIMESTAMP as updated_at
            FROM pggit.alert_delivery_queue
            WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
            """
        )

        # Fetch webhook health
        webhooks_data = await db.fetch(
            """
            SELECT
                w.id,
                w.name,
                COALESCE(whm.health_status, 'UNKNOWN') as health_status,
                COALESCE(whm.total_deliveries, 0) as total_deliveries,
                COALESCE(whm.successful_deliveries, 0) as successful_deliveries,
                COALESCE(whm.failed_deliveries, 0) as failed_deliveries,
                COALESCE(
                    ROUND(
                        100.0 * COALESCE(whm.successful_deliveries, 0) /
                        NULLIF(COALESCE(whm.total_deliveries, 1), 0),
                        2
                    ),
                    0
                ) as success_rate_percent,
                whm.last_delivery_at
            FROM pggit.webhooks w
            LEFT JOIN pggit.webhook_health_metrics whm ON w.id = whm.webhook_id
            WHERE w.active = TRUE
            ORDER BY COALESCE(whm.health_status, 'UNKNOWN') DESC
            LIMIT 20
            """
        )

        # Fetch performance metrics
        perf_data = await db.fetchrow(
            """
            SELECT
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p50_latency_ms,
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p95_latency_ms,
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p99_latency_ms,
                ROUND(
                    100.0 * COUNT(CASE WHEN http_status >= 400 THEN 1 END) /
                    NULLIF(COUNT(*), 0),
                    2
                ) as error_rate_percent,
                ROUND(COALESCE(AVG(response_time_ms), 0), 2) as average_response_time_ms
            FROM pggit.api_request_log
            WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
            """
        )

        # Fetch anomaly summary
        anomaly_data = await db.fetchrow(
            """
            SELECT
                COUNT(*) as total_anomalies,
                COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) as critical_anomalies,
                COUNT(CASE WHEN severity = 'WARNING' THEN 1 END) as warning_anomalies,
                COUNT(DISTINCT operation_type) as affected_operations,
                COUNT(CASE WHEN detected_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 1 END) as recent_anomalies_count
            FROM pggit.v_recent_anomalies
            WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
            """
        )

        # Get distinct operations for anomalies
        affected_ops = await db.fetch(
            """
            SELECT DISTINCT operation_type
            FROM pggit.v_recent_anomalies
            WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
            LIMIT 10
            """
        )

        # Get active webhook count
        active_webhooks = await db.fetchval(
            """
            SELECT COUNT(*) FROM pggit.webhooks WHERE active = TRUE
            """
        )

        # Get degraded webhooks count
        degraded_webhooks = await db.fetchval(
            """
            SELECT COUNT(*) FROM pggit.v_degraded_webhooks
            """
        )

        # Get cache hit rate
        cache_stats = cache.get_stats()
        cache_hit_rate = cache_stats.get("l1_memory", {}).get("hit_rate_percent", 0)

        # Build response
        response = DashboardDataResponse(
            overview=OverviewMetrics(
                total_deliveries=overview_data['total_deliveries'] or 0,
                pending_deliveries=overview_data['pending_deliveries'] or 0,
                failed_deliveries=overview_data['failed_deliveries'] or 0,
                success_rate_percent=float(overview_data['success_rate_percent'] or 0),
                active_webhooks=active_webhooks or 0,
                degraded_webhooks=degraded_webhooks or 0,
                updated_at=overview_data['updated_at']
            ),
            performance=PerformanceMetrics(
                p50_latency_ms=float(perf_data['p50_latency_ms'] or 0),
                p95_latency_ms=float(perf_data['p95_latency_ms'] or 0),
                p99_latency_ms=float(perf_data['p99_latency_ms'] or 0),
                error_rate_percent=float(perf_data['error_rate_percent'] or 0),
                cache_hit_rate_percent=float(cache_hit_rate),
                average_response_time_ms=float(perf_data['average_response_time_ms'] or 0)
            ),
            webhooks=[
                WebhookSummary(
                    id=row['id'],
                    name=row['name'],
                    health_status=row['health_status'],
                    total_deliveries=row['total_deliveries'],
                    successful_deliveries=row['successful_deliveries'],
                    failed_deliveries=row['failed_deliveries'],
                    success_rate_percent=float(row['success_rate_percent']),
                    last_delivery_at=row['last_delivery_at']
                )
                for row in webhooks_data
            ],
            anomalies=AnomalySummary(
                total_anomalies=anomaly_data['total_anomalies'] or 0,
                critical_anomalies=anomaly_data['critical_anomalies'] or 0,
                warning_anomalies=anomaly_data['warning_anomalies'] or 0,
                affected_operations=[row['operation_type'] for row in affected_ops],
                recent_anomalies_count=anomaly_data['recent_anomalies_count'] or 0
            ),
            generated_at=datetime.now(),
            cache_hit=False
        )

        # Cache for 5 minutes
        await cache.set(cache_key, response, ttl_seconds=300)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching dashboard data: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch dashboard data"
        )


@router.get("/dashboard/overview", tags=["Dashboard"])
async def get_dashboard_overview(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get system overview metrics only.

    Returns:
        Overview metrics (deliveries, success rate)
    """
    cache = await get_cache()
    cache_key = "dashboard:overview"

    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        overview_data = await db.fetchrow(
            """
            SELECT
                COUNT(*) as total_deliveries,
                COUNT(CASE WHEN delivery_status = 'pending' THEN 1 END) as pending_deliveries,
                COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END) as failed_deliveries,
                ROUND(
                    100.0 * COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END) /
                    NULLIF(COUNT(*), 0),
                    2
                ) as success_rate_percent,
                CURRENT_TIMESTAMP as updated_at
            FROM pggit.alert_delivery_queue
            WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
            """
        )

        active_webhooks = await db.fetchval(
            "SELECT COUNT(*) FROM pggit.webhooks WHERE active = TRUE"
        )

        degraded_webhooks = await db.fetchval(
            "SELECT COUNT(*) FROM pggit.v_degraded_webhooks"
        )

        response = OverviewMetrics(
            total_deliveries=overview_data['total_deliveries'] or 0,
            pending_deliveries=overview_data['pending_deliveries'] or 0,
            failed_deliveries=overview_data['failed_deliveries'] or 0,
            success_rate_percent=float(overview_data['success_rate_percent'] or 0),
            active_webhooks=active_webhooks or 0,
            degraded_webhooks=degraded_webhooks or 0,
            updated_at=overview_data['updated_at']
        )

        await cache.set(cache_key, response, ttl_seconds=60)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching overview: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch overview"
        )


@router.get("/dashboard/performance", tags=["Dashboard"])
async def get_performance_metrics(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get performance metrics for the API.

    Returns:
        Performance metrics (latency percentiles, error rate, cache hit rate)
    """
    cache = await get_cache()
    cache_key = "dashboard:performance"

    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        perf_data = await db.fetchrow(
            """
            SELECT
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p50_latency_ms,
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p95_latency_ms,
                ROUND(COALESCE(
                    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY response_time_ms), 0
                ), 2) as p99_latency_ms,
                ROUND(
                    100.0 * COUNT(CASE WHEN http_status >= 400 THEN 1 END) /
                    NULLIF(COUNT(*), 0),
                    2
                ) as error_rate_percent,
                ROUND(COALESCE(AVG(response_time_ms), 0), 2) as average_response_time_ms
            FROM pggit.api_request_log
            WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
            """
        )

        cache_stats = cache.get_stats()
        cache_hit_rate = cache_stats.get("l1_memory", {}).get("hit_rate_percent", 0)

        response = PerformanceMetrics(
            p50_latency_ms=float(perf_data['p50_latency_ms'] or 0),
            p95_latency_ms=float(perf_data['p95_latency_ms'] or 0),
            p99_latency_ms=float(perf_data['p99_latency_ms'] or 0),
            error_rate_percent=float(perf_data['error_rate_percent'] or 0),
            cache_hit_rate_percent=float(cache_hit_rate),
            average_response_time_ms=float(perf_data['average_response_time_ms'] or 0)
        )

        await cache.set(cache_key, response, ttl_seconds=60)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching performance metrics: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch performance metrics"
        )


@router.get("/dashboard/webhooks", tags=["Dashboard"])
async def get_webhooks_summary(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency),
    limit: int = Query(20, ge=1, le=100)
):
    """
    Get webhook health summary.

    Query Parameters:
    - limit: Maximum number of webhooks to return

    Returns:
        List of webhooks with health status
    """
    cache = await get_cache()
    cache_key = f"dashboard:webhooks:{limit}"

    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        webhooks_data = await db.fetch(
            """
            SELECT
                w.id,
                w.name,
                COALESCE(whm.health_status, 'UNKNOWN') as health_status,
                COALESCE(whm.total_deliveries, 0) as total_deliveries,
                COALESCE(whm.successful_deliveries, 0) as successful_deliveries,
                COALESCE(whm.failed_deliveries, 0) as failed_deliveries,
                COALESCE(
                    ROUND(
                        100.0 * COALESCE(whm.successful_deliveries, 0) /
                        NULLIF(COALESCE(whm.total_deliveries, 1), 0),
                        2
                    ),
                    0
                ) as success_rate_percent,
                whm.last_delivery_at
            FROM pggit.webhooks w
            LEFT JOIN pggit.webhook_health_metrics whm ON w.id = whm.webhook_id
            WHERE w.active = TRUE
            ORDER BY COALESCE(whm.health_status, 'UNKNOWN') DESC
            LIMIT $1
            """,
            limit
        )

        response = [
            WebhookSummary(
                id=row['id'],
                name=row['name'],
                health_status=row['health_status'],
                total_deliveries=row['total_deliveries'],
                successful_deliveries=row['successful_deliveries'],
                failed_deliveries=row['failed_deliveries'],
                success_rate_percent=float(row['success_rate_percent']),
                last_delivery_at=row['last_delivery_at']
            )
            for row in webhooks_data
        ]

        await cache.set(cache_key, response, ttl_seconds=120)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching webhooks summary: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch webhooks summary"
        )


@router.get("/dashboard/anomalies", tags=["Dashboard"])
async def get_anomalies(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency),
    days: int = Query(7, ge=1, le=30)
):
    """
    Get active anomalies.

    Query Parameters:
    - days: Number of days to look back for anomalies

    Returns:
        Anomaly detection summary
    """
    cache = await get_cache()
    cache_key = f"dashboard:anomalies:{days}"

    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        anomaly_data = await db.fetchrow(
            """
            SELECT
                COUNT(*) as total_anomalies,
                COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) as critical_anomalies,
                COUNT(CASE WHEN severity = 'WARNING' THEN 1 END) as warning_anomalies,
                COUNT(DISTINCT operation_type) as affected_operations,
                COUNT(CASE WHEN detected_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 1 END) as recent_anomalies_count
            FROM pggit.v_recent_anomalies
            WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL $1 || ' days'::interval
            """,
            days
        )

        affected_ops = await db.fetch(
            """
            SELECT DISTINCT operation_type
            FROM pggit.v_recent_anomalies
            WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL $1 || ' days'::interval
            LIMIT 10
            """,
            days
        )

        response = AnomalySummary(
            total_anomalies=anomaly_data['total_anomalies'] or 0,
            critical_anomalies=anomaly_data['critical_anomalies'] or 0,
            warning_anomalies=anomaly_data['warning_anomalies'] or 0,
            affected_operations=[row['operation_type'] for row in affected_ops],
            recent_anomalies_count=anomaly_data['recent_anomalies_count'] or 0
        )

        await cache.set(cache_key, response, ttl_seconds=300)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching anomalies: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch anomalies"
        )
