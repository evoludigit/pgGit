"""
Cache Invalidation Triggers
===========================

REST endpoints for triggering cache invalidation on data changes.
Integrates with the cache invalidation manager to handle event-based
cache clearing.

Features:
- Webhook update invalidation
- Alert status change invalidation
- Dashboard cache refresh
- Cascade invalidation for related caches
- Manual invalidation endpoints
"""

import logging
from typing import Dict, Any

from fastapi import APIRouter, HTTPException, status, Query

from services.query_optimization import get_invalidation_manager
from services.cache import get_cache

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Cache Invalidation"])


@router.post("/cache/invalidate/alerts", status_code=204)
async def invalidate_alert_cache(
    alert_id: int = Query(..., description="Alert ID that changed"),
    event_type: str = Query(
        "alert_updated",
        description="Type of event: alert_created, alert_updated, alert_acknowledged"
    )
):
    """
    Invalidate cache entries related to alerts.

    Called when alert status changes to ensure clients get fresh data.

    Args:
        alert_id: ID of the alert that changed
        event_type: Type of event (alert_created, alert_updated, alert_acknowledged)

    Returns:
        204 No Content
    """
    try:
        manager = await get_invalidation_manager()
        cache = await get_cache()

        # Invalidate based on event type
        patterns_invalidated = await manager.invalidate_on_event(event_type, cache)

        logger.info(f"Invalidated {patterns_invalidated} cache patterns for {event_type} (alert_id={alert_id})")

        return None

    except Exception as e:
        logger.error(f"Cache invalidation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to invalidate cache"
        )


@router.post("/cache/invalidate/webhooks", status_code=204)
async def invalidate_webhook_cache(
    webhook_id: int = Query(..., description="Webhook ID that changed"),
    event_type: str = Query(
        "webhook_updated",
        description="Type of event: webhook_created, webhook_updated, webhook_health_updated"
    )
):
    """
    Invalidate cache entries related to webhooks.

    Called when webhook status, health, or configuration changes.

    Args:
        webhook_id: ID of the webhook that changed
        event_type: Type of event (webhook_created, webhook_updated, webhook_health_updated)

    Returns:
        204 No Content
    """
    try:
        manager = await get_invalidation_manager()
        cache = await get_cache()

        # Invalidate based on event type
        patterns_invalidated = await manager.invalidate_on_event(event_type, cache)

        logger.info(f"Invalidated {patterns_invalidated} cache patterns for {event_type} (webhook_id={webhook_id})")

        return None

    except Exception as e:
        logger.error(f"Cache invalidation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to invalidate cache"
        )


@router.post("/cache/invalidate/dashboard", status_code=204)
async def invalidate_dashboard_cache():
    """
    Invalidate all dashboard-related cache entries.

    Called when significant system-wide changes occur (metrics updates,
    major webhook/alert changes, etc.).

    Returns:
        204 No Content
    """
    try:
        _ = await get_invalidation_manager()  # Ensure manager is available
        cache = await get_cache()

        # Invalidate dashboard caches
        dashboard_patterns = [
            "dashboard:*",
            "metrics:*",
            "summary:*"
        ]

        count = 0
        for pattern in dashboard_patterns:
            try:
                await cache.delete(pattern)
                count += 1
                logger.debug(f"Invalidated cache pattern: {pattern}")
            except Exception as e:
                logger.warning(f"Failed to invalidate pattern {pattern}: {e}")

        logger.info(f"Invalidated {count} dashboard cache patterns")

        return None

    except Exception as e:
        logger.error(f"Dashboard cache invalidation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to invalidate dashboard cache"
        )


@router.post("/cache/invalidate/pattern", status_code=204)
async def invalidate_cache_pattern(
    pattern: str = Query(..., description="Cache key pattern to invalidate (e.g., 'alerts:*')")
):
    """
    Manually invalidate cache entries matching a pattern.

    Advanced endpoint for invalidating specific cache patterns. Supports
    wildcard patterns (e.g., 'alerts:list:*', 'webhooks:123:*').

    Args:
        pattern: Cache key pattern to invalidate

    Returns:
        204 No Content
    """
    try:
        if not pattern or "*" not in pattern:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Pattern must contain at least one wildcard (*)"
            )

        cache = await get_cache()
        await cache.delete(pattern)

        logger.info(f"Invalidated cache pattern: {pattern}")

        return None

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Cache pattern invalidation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to invalidate cache pattern"
        )


@router.post("/cache/invalidate/all", status_code=204)
async def invalidate_all_cache():
    """
    Clear entire cache (use with caution).

    Clears all cached data. This is a heavy operation and should be used
    sparingly, typically only during maintenance or after major system changes.

    Returns:
        204 No Content
    """
    try:
        cache = await get_cache()
        await cache.clear()

        logger.warning("Cleared entire cache")

        return None

    except Exception as e:
        logger.error(f"Full cache invalidation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to clear cache"
        )


@router.get("/cache/stats", response_model=Dict[str, Any])
async def get_cache_statistics():
    """
    Get cache statistics and performance metrics.

    Returns current cache hit rates, sizes, and performance data.

    Returns:
        Cache statistics dictionary with hit rates, sizes, and metrics
    """
    try:
        cache = await get_cache()
        stats = cache.get_stats()

        # Extract L1 memory stats for flat response
        l1_stats = stats.get("l1_memory", {})
        hits = l1_stats.get("hits", 0)
        misses = l1_stats.get("misses", 0)
        total_requests = hits + misses

        return {
            "hit_rate": l1_stats.get("hit_rate_percent", 0.0),
            "total_requests": total_requests,
            "hits": hits,
            "misses": misses,
            "size": l1_stats.get("size", 0),
            "cache_type": stats.get("cache_type", "in-memory"),
            "max_size": l1_stats.get("max_size", 0),
            "ttl_seconds": l1_stats.get("ttl_seconds", 0),
        }

    except Exception as e:
        logger.error(f"Failed to get cache statistics: {e}")
        # Return empty stats instead of error for graceful degradation
        return {
            "hit_rate": 0.0,
            "total_requests": 0,
            "hits": 0,
            "misses": 0,
            "size": 0,
            "cache_type": "unknown",
            "max_size": 0,
            "ttl_seconds": 0,
        }
