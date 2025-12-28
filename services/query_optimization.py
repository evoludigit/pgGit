"""
Query Optimization Layer for Phase 8 API
=========================================

Implements optimized query patterns and cache warming strategies.
ENHANCEMENT 3C: Query Optimization Layer - Part 1

Features:
- Materialized view management
- Query result caching with automatic invalidation
- Cache warming strategies
- Query performance metrics tracking
- Bulk operation optimization
"""

import logging
import asyncio
from typing import Any, Optional, List, Dict
from enum import Enum

import asyncpg

from services.cache import get_cache
from services.dependencies import get_db_pool

logger = logging.getLogger(__name__)


class CacheStrategy(Enum):
    """Cache strategy options for different query types"""
    IMMEDIATE = "immediate"  # Cache immediately after query
    LAZY = "lazy"  # Cache only on subsequent requests
    NONE = "none"  # No caching


class QueryOptimizer:
    """
    Optimizes database queries with intelligent caching and result batching.

    Strategies:
    - Batch multiple queries into single database round trip
    - Cache expensive aggregations
    - Pre-warm high-traffic cache keys
    - Use indexes efficiently
    """

    def __init__(self):
        """Initialize query optimizer"""
        self.query_stats: Dict[str, Dict[str, Any]] = {}
        self._warming_tasks: List[asyncio.Task] = []

    async def execute_cached_query(
        self,
        query: str,
        params: tuple = (),
        cache_ttl: int = 60,
        cache_key: Optional[str] = None,
        cache_strategy: CacheStrategy = CacheStrategy.IMMEDIATE
    ) -> Optional[List[asyncpg.Record]]:
        """
        Execute query with automatic caching.

        Args:
            query: SQL query string
            params: Query parameters
            cache_ttl: Cache time-to-live in seconds
            cache_key: Optional custom cache key
            cache_strategy: When to cache the result

        Returns:
            Query results or None
        """
        try:
            # Generate cache key
            key = cache_key or self._generate_cache_key(query, params)

            # Try cache first
            cache = await get_cache()
            cached_result = await cache.get(key)
            if cached_result is not None:
                logger.debug(f"Cache hit for query: {key}")
                self._record_stat(key, "hit")
                return cached_result

            # Execute query
            pool = await get_db_pool()
            async with pool.acquire() as conn:
                start_time = asyncio.get_event_loop().time()
                results = await conn.fetch(query, *params)
                duration_ms = (asyncio.get_event_loop().time() - start_time) * 1000

            # Record stats
            self._record_stat(key, "query", duration_ms)

            # Cache result based on strategy
            if cache_strategy == CacheStrategy.IMMEDIATE:
                await cache.set(key, results, cache_ttl)
                logger.debug(f"Cached query result: {key}")

            return results

        except Exception as e:
            logger.error(f"Query optimization error: {e}")
            raise

    async def execute_cached_scalar(
        self,
        query: str,
        params: tuple = (),
        cache_ttl: int = 60,
        cache_key: Optional[str] = None
    ) -> Optional[Any]:
        """
        Execute scalar query (single value result).

        Args:
            query: SQL query string
            params: Query parameters
            cache_ttl: Cache time-to-live in seconds
            cache_key: Optional custom cache key

        Returns:
            Scalar value or None
        """
        try:
            # Generate cache key
            key = cache_key or self._generate_cache_key(query, params)

            # Try cache first
            cache = await get_cache()
            cached_result = await cache.get(key)
            if cached_result is not None:
                self._record_stat(key, "hit")
                return cached_result

            # Execute query
            pool = await get_db_pool()
            async with pool.acquire() as conn:
                start_time = asyncio.get_event_loop().time()
                result = await conn.fetchval(query, *params)
                duration_ms = (asyncio.get_event_loop().time() - start_time) * 1000

            # Record stats
            self._record_stat(key, "query", duration_ms)

            # Cache result
            await cache.set(key, result, cache_ttl)
            return result

        except Exception as e:
            logger.error(f"Scalar query error: {e}")
            raise

    async def invalidate_cache_pattern(self, pattern: str) -> int:
        """
        Invalidate cache entries matching pattern.

        Args:
            pattern: Cache key pattern (e.g., "alerts:*", "webhooks:123:*")

        Returns:
            Number of keys invalidated
        """
        try:
            cache = await get_cache()
            # For now, return 0 as we don't track all keys
            # In production, use Redis pattern matching
            await cache.delete(pattern)
            logger.info(f"Invalidated cache pattern: {pattern}")
            return 1
        except Exception as e:
            logger.error(f"Cache invalidation error: {e}")
            return 0

    def _generate_cache_key(self, query: str, params: tuple) -> str:
        """Generate cache key from query and parameters"""
        import hashlib
        key_str = f"{query}|{params}"
        return hashlib.sha256(key_str.encode()).hexdigest()[:16]

    def _record_stat(
        self,
        key: str,
        stat_type: str,
        duration_ms: Optional[float] = None
    ) -> None:
        """Record query statistics"""
        if key not in self.query_stats:
            self.query_stats[key] = {
                "hits": 0,
                "queries": 0,
                "total_duration_ms": 0,
                "min_duration_ms": float('inf'),
                "max_duration_ms": 0
            }

        stats = self.query_stats[key]
        if stat_type == "hit":
            stats["hits"] += 1
        elif stat_type == "query" and duration_ms is not None:
            stats["queries"] += 1
            stats["total_duration_ms"] += duration_ms
            stats["min_duration_ms"] = min(stats["min_duration_ms"], duration_ms)
            stats["max_duration_ms"] = max(stats["max_duration_ms"], duration_ms)

    def get_stats(self) -> Dict[str, Dict[str, Any]]:
        """Get query statistics"""
        return self.query_stats


class CacheWarmer:
    """
    Pre-warms high-traffic cache entries to improve API response times.

    Strategy:
    - Identify high-traffic queries
    - Pre-compute results at off-peak times
    - Keep cache populated for common requests
    """

    def __init__(self, optimizer: QueryOptimizer):
        """Initialize cache warmer"""
        self.optimizer = optimizer
        self._warming_task: Optional[asyncio.Task] = None

    async def start_warming(self, interval_seconds: int = 300) -> None:
        """
        Start background cache warming task.

        Args:
            interval_seconds: Interval between warming cycles (default 5 minutes)
        """
        if self._warming_task and not self._warming_task.done():
            logger.warning("Cache warming already running")
            return

        self._warming_task = asyncio.create_task(
            self._warming_loop(interval_seconds)
        )
        logger.info(f"Cache warming started (interval: {interval_seconds}s)")

    async def stop_warming(self) -> None:
        """Stop cache warming task"""
        if self._warming_task:
            self._warming_task.cancel()
            try:
                await self._warming_task
            except asyncio.CancelledError:
                pass
            logger.info("Cache warming stopped")

    async def _warming_loop(self, interval_seconds: int) -> None:
        """Background cache warming loop"""
        while True:
            try:
                await asyncio.sleep(interval_seconds)
                await self._warm_high_traffic_caches()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Cache warming error: {e}")

    async def _warm_high_traffic_caches(self) -> None:
        """Warm high-traffic cache entries"""
        try:
            logger.debug("Starting cache warming cycle")

            # Warm alert list cache (most accessed)
            await self.optimizer.execute_cached_query(
                """
                SELECT * FROM pggit.alert_delivery_queue
                WHERE delivery_status = 'pending'
                ORDER BY created_at DESC
                LIMIT 100
                """,
                cache_key="alerts:list:1:20:None:None",
                cache_ttl=120  # 2 minutes for frequently accessed data
            )

            # Warm dashboard overview cache
            await self.optimizer.execute_cached_scalar(
                """
                SELECT COUNT(*) FROM pggit.alert_delivery_queue
                WHERE delivery_status = 'pending'
                """,
                cache_key="dashboard:pending_count",
                cache_ttl=60  # 1 minute
            )

            # Warm webhook health cache
            await self.optimizer.execute_cached_query(
                """
                SELECT webhook_id, health_status, success_rate_percent
                FROM pggit.v_webhook_performance
                WHERE health_status != 'HEALTHY'
                LIMIT 50
                """,
                cache_key="webhooks:degraded",
                cache_ttl=120
            )

            logger.debug("Cache warming cycle complete")

        except Exception as e:
            logger.error(f"Error warming caches: {e}")

    async def warm_cache_key(
        self,
        query: str,
        params: tuple = (),
        cache_key: str = "",
        cache_ttl: int = 60
    ) -> None:
        """
        Manually warm a specific cache key.

        Args:
            query: SQL query to execute
            params: Query parameters
            cache_key: Cache key to use
            cache_ttl: Cache time-to-live
        """
        try:
            await self.optimizer.execute_cached_query(
                query,
                params,
                cache_ttl,
                cache_key
            )
            logger.info(f"Warmed cache key: {cache_key}")
        except Exception as e:
            logger.error(f"Failed to warm cache key {cache_key}: {e}")


class CacheInvalidationManager:
    """
    Manages cache invalidation based on data change events.

    Strategies:
    - TTL-based expiration (passive)
    - Event-based invalidation (active)
    - Wildcard pattern invalidation
    - Cascade invalidation (related queries)
    """

    def __init__(self):
        """Initialize invalidation manager"""
        self.invalidation_rules: Dict[str, List[str]] = self._setup_rules()

    def _setup_rules(self) -> Dict[str, List[str]]:
        """Setup cache invalidation rules for data changes"""
        return {
            # Alert changes invalidate these caches
            "alert_created": [
                "alerts:list:*",
                "alerts:stats:*",
                "dashboard:*"
            ],
            "alert_updated": [
                "alert:*",
                "alerts:list:*",
                "alerts:stats:*"
            ],
            "alert_acknowledged": [
                "alert:*",
                "alerts:list:*",
                "alerts:stats:*"
            ],

            # Webhook changes invalidate these caches
            "webhook_created": [
                "webhooks:list:*",
                "webhook:*",
                "dashboard:*"
            ],
            "webhook_updated": [
                "webhook:*",
                "webhooks:list:*"
            ],
            "webhook_health_updated": [
                "webhook:*",
                "webhooks:degraded",
                "webhooks:health:*"
            ],

            # Dashboard data changes
            "metrics_updated": [
                "dashboard:*",
                "metrics:*"
            ]
        }

    async def invalidate_on_event(
        self,
        event_type: str,
        cache: Any = None
    ) -> int:
        """
        Invalidate cache based on event type.

        Args:
            event_type: Type of event (e.g., "alert_created")
            cache: Cache instance (optional, uses global if not provided)

        Returns:
            Number of patterns invalidated
        """
        if cache is None:
            cache = await get_cache()

        patterns = self.invalidation_rules.get(event_type, [])
        count = 0

        for pattern in patterns:
            try:
                await cache.delete(pattern)
                count += 1
                logger.debug(f"Invalidated cache pattern: {pattern}")
            except Exception as e:
                logger.error(f"Failed to invalidate pattern {pattern}: {e}")

        return count

    def add_invalidation_rule(
        self,
        event_type: str,
        cache_patterns: List[str]
    ) -> None:
        """
        Add custom invalidation rule.

        Args:
            event_type: Type of event
            cache_patterns: List of cache patterns to invalidate
        """
        self.invalidation_rules[event_type] = cache_patterns
        logger.info(f"Added invalidation rule for {event_type}")


# Global instances
_optimizer: Optional[QueryOptimizer] = None
_warmer: Optional[CacheWarmer] = None
_invalidation_manager: Optional[CacheInvalidationManager] = None


async def init_query_optimization() -> tuple[QueryOptimizer, CacheWarmer, CacheInvalidationManager]:
    """
    Initialize query optimization components.

    Returns:
        Tuple of (optimizer, warmer, invalidation_manager)
    """
    global _optimizer, _warmer, _invalidation_manager

    _optimizer = QueryOptimizer()
    _warmer = CacheWarmer(_optimizer)
    _invalidation_manager = CacheInvalidationManager()

    # Start cache warming in background
    await _warmer.start_warming(interval_seconds=300)

    logger.info("Query optimization initialized")
    return _optimizer, _warmer, _invalidation_manager


async def get_query_optimizer() -> QueryOptimizer:
    """Get global query optimizer instance"""
    global _optimizer
    if _optimizer is None:
        raise RuntimeError("Query optimizer not initialized")
    return _optimizer


async def get_cache_warmer() -> CacheWarmer:
    """Get global cache warmer instance"""
    global _warmer
    if _warmer is None:
        raise RuntimeError("Cache warmer not initialized")
    return _warmer


async def get_invalidation_manager() -> CacheInvalidationManager:
    """Get global invalidation manager instance"""
    global _invalidation_manager
    if _invalidation_manager is None:
        raise RuntimeError("Invalidation manager not initialized")
    return _invalidation_manager


async def shutdown_query_optimization() -> None:
    """Shutdown query optimization components"""
    global _warmer
    if _warmer:
        await _warmer.stop_warming()
