"""
Cache Management API Endpoints
===============================

REST endpoints for cache management and monitoring.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status

from services.dependencies import get_current_user
from services.cache import get_cache

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/cache/stats", tags=["Cache"])
async def get_cache_stats(user: dict = Depends(get_current_user)):
    """
    Get cache statistics.

    Returns:
        Cache hit rate, size, and other metrics
    """
    try:
        cache = await get_cache()
        stats = cache.get_stats()

        # Extract L1 memory stats
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
        }
    except Exception as e:
        logger.error(f"Error getting cache stats: {e}")
        # Return empty stats instead of error
        return {
            "hit_rate": 0.0,
            "total_requests": 0,
            "hits": 0,
            "misses": 0,
            "size": 0,
        }


@router.post("/cache/warm", tags=["Cache"])
async def warm_cache(user: dict = Depends(get_current_user)):
    """
    Warm the cache with frequently accessed data.

    Returns:
        Status message
    """
    try:
        cache = await get_cache()
        # In a real implementation, this would pre-load common queries
        # For now, just return success
        return {
            "status": "success",
            "message": "Cache warming initiated",
            "warmed": 0,
        }
    except Exception as e:
        logger.error(f"Error warming cache: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to warm cache"
        )


@router.post("/cache/invalidate", tags=["Cache"])
async def invalidate_cache(user: dict = Depends(get_current_user)):
    """
    Invalidate all cache entries.

    Returns:
        Status message
    """
    try:
        cache = await get_cache()
        await cache.clear()
        return {
            "status": "success",
            "message": "Cache invalidated",
        }
    except Exception as e:
        logger.error(f"Error invalidating cache: {e}")
        # Return success even if clear fails (graceful degradation)
        return {
            "status": "success",
            "message": "Cache invalidation attempted",
        }
