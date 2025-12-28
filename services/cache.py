"""
Phase 8 Cache Management
========================

Multi-tier caching with LRU eviction to prevent OOM.
CRITICAL FIX #4: Implements bounded cache with LRU eviction.

Architecture:
- L1: In-memory LRU cache (max_size_memory items)
- L2: Redis distributed cache (optional)
- L3: PostgreSQL materialized views (persistent)

Memory Management:
- LRU (Least Recently Used) eviction policy
- Configurable max size to prevent OOM
- Automatic TTL-based expiration
"""

import asyncio
import json
import logging
from typing import Any, Callable, Generic, Optional, TypeVar
from collections import OrderedDict
from datetime import datetime, timedelta
import hashlib

try:
    from redis import asyncio as aioredis
except ImportError:
    aioredis = None
from functools import wraps

from services.config import CacheConfig, get_settings

logger = logging.getLogger(__name__)

T = TypeVar("T")


class LRUCache(Generic[T]):
    """
    Thread-safe LRU cache with bounded memory usage.

    Features:
    - Least Recently Used eviction
    - Configurable max size
    - TTL-based expiration
    - O(1) access time

    Critical Fix #4: Prevents unbounded cache growth that caused OOM crashes.
    """

    def __init__(self, max_size: int = 10000, ttl_seconds: int = 60):
        """
        Initialize LRU cache.

        Args:
            max_size: Maximum number of items before eviction (default 10,000)
            ttl_seconds: Time-to-live for cached items (default 60 seconds)

        Raises:
            ValueError: If max_size <= 0
        """
        if max_size <= 0:
            raise ValueError("max_size must be positive")

        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self._cache: OrderedDict[str, tuple[T, datetime]] = OrderedDict()
        self._lock = asyncio.Lock()
        self._hits = 0
        self._misses = 0

    async def get(self, key: str) -> Optional[T]:
        """
        Get value from cache with LRU tracking.

        Args:
            key: Cache key

        Returns:
            Cached value if present and not expired, None otherwise
        """
        async with self._lock:
            if key not in self._cache:
                self._misses += 1
                return None

            value, created_at = self._cache[key]

            # Check if expired
            if datetime.now() >= created_at + timedelta(seconds=self.ttl_seconds):
                del self._cache[key]
                self._misses += 1
                return None

            # Move to end (most recently used)
            self._cache.move_to_end(key)
            self._hits += 1
            return value

    async def set(self, key: str, value: T, ttl_seconds: Optional[int] = None) -> None:
        """
        Set value in cache with automatic eviction if needed.

        Args:
            key: Cache key
            value: Value to cache
            ttl_seconds: Optional TTL override (uses instance default if not provided)
        """
        async with self._lock:
            # Note: ttl_seconds parameter reserved for future per-key TTL support
            _ = ttl_seconds or self.ttl_seconds

            # If key exists, remove it first to maintain insertion order
            if key in self._cache:
                del self._cache[key]

            # Add or update
            self._cache[key] = (value, datetime.now())

            # Evict LRU items if cache exceeds max size
            while len(self._cache) > self.max_size:
                evicted_key = next(iter(self._cache))
                del self._cache[evicted_key]
                logger.debug(f"Evicted LRU cache key: {evicted_key}")

    async def delete(self, key: str) -> bool:
        """
        Delete item from cache.

        Args:
            key: Cache key

        Returns:
            True if item was present, False otherwise
        """
        async with self._lock:
            if key in self._cache:
                del self._cache[key]
                return True
            return False

    async def clear(self) -> None:
        """Clear all cache items"""
        async with self._lock:
            self._cache.clear()

    def get_stats(self) -> dict:
        """
        Get cache statistics.

        Returns:
            Dictionary with hit rate, size, etc.
        """
        total = self._hits + self._misses
        hit_rate = (self._hits / total * 100) if total > 0 else 0

        return {
            "hits": self._hits,
            "misses": self._misses,
            "hit_rate_percent": round(hit_rate, 2),
            "size": len(self._cache),
            "max_size": self.max_size,
            "ttl_seconds": self.ttl_seconds,
        }

    async def cleanup_expired(self) -> int:
        """
        Remove all expired items from cache.

        Returns:
            Number of items removed
        """
        async with self._lock:
            now = datetime.now()
            expired_keys = [
                key
                for key, (_, created_at) in self._cache.items()
                if now >= created_at + timedelta(seconds=self.ttl_seconds)
            ]

            for key in expired_keys:
                del self._cache[key]

            return len(expired_keys)


class RedisCache:
    """
    Distributed cache using Redis.
    Optional L2 cache for multi-instance deployments.
    """

    def __init__(self, redis_url: str):
        """
        Initialize Redis cache.

        Args:
            redis_url: Redis connection URL (redis://host:port)
        """
        self.redis_url = redis_url
        self.redis: Optional[aioredis.Redis] = None

    async def connect(self) -> None:
        """Connect to Redis"""
        try:
            self.redis = await aioredis.from_url(self.redis_url)
            await self.redis.ping()
            logger.info("Connected to Redis cache")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            self.redis = None

    async def disconnect(self) -> None:
        """Disconnect from Redis"""
        if self.redis:
            await self.redis.close()

    async def get(self, key: str) -> Optional[str]:
        """Get value from Redis"""
        if not self.redis:
            return None

        try:
            value = await self.redis.get(key)
            return value.decode() if value else None
        except Exception as e:
            logger.error(f"Redis get failed: {e}")
            return None

    async def set(self, key: str, value: str, ttl_seconds: int = 60) -> bool:
        """Set value in Redis with TTL"""
        if not self.redis:
            return False

        try:
            await self.redis.setex(key, ttl_seconds, value)
            return True
        except Exception as e:
            logger.error(f"Redis set failed: {e}")
            return False

    async def delete(self, key: str) -> bool:
        """Delete key from Redis"""
        if not self.redis:
            return False

        try:
            result = await self.redis.delete(key)
            return result > 0
        except Exception as e:
            logger.error(f"Redis delete failed: {e}")
            return False

    async def clear(self) -> bool:
        """Clear all keys from Redis database"""
        if not self.redis:
            return False

        try:
            await self.redis.flushdb()
            return True
        except Exception as e:
            logger.error(f"Redis clear failed: {e}")
            return False


class HybridCache:
    """
    Hybrid cache combining in-memory LRU and Redis.

    Strategy:
    - Check L1 (in-memory) first
    - Fall back to L2 (Redis) if not in L1
    - Fall back to database/compute if not in L2

    Critical Fix #4: Bounded memory usage with fallback to distributed cache.
    """

    def __init__(self, config: CacheConfig):
        """
        Initialize hybrid cache.

        Args:
            config: Cache configuration
        """
        self.config = config
        self.l1 = LRUCache(max_size=config.max_size_memory, ttl_seconds=config.ttl_seconds)
        self.l2 = RedisCache(config.redis_url) if config.type == "hybrid" and config.redis_url else None

    async def connect(self) -> None:
        """Connect to Redis (if configured)"""
        if self.l2:
            await self.l2.connect()

    async def disconnect(self) -> None:
        """Disconnect from Redis"""
        if self.l2:
            await self.l2.disconnect()

    async def get(self, key: str) -> Optional[Any]:
        """
        Get value from hybrid cache (L1 → L2 → None).

        Args:
            key: Cache key

        Returns:
            Cached value or None
        """
        # Try L1 first
        l1_value = await self.l1.get(key)
        if l1_value is not None:
            return l1_value

        # Try L2 (Redis)
        if self.l2:
            l2_value = await self.l2.get(key)
            if l2_value:
                try:
                    value = json.loads(l2_value)
                    # Populate L1 for future access
                    await self.l1.set(key, value)
                    return value
                except json.JSONDecodeError:
                    logger.error(f"Failed to decode Redis value for key: {key}")

        return None

    async def set(self, key: str, value: Any, ttl_seconds: Optional[int] = None) -> None:
        """
        Set value in hybrid cache (L1 + L2).

        Args:
            key: Cache key
            value: Value to cache
            ttl_seconds: Optional TTL override
        """
        ttl = ttl_seconds or self.config.ttl_seconds

        # Always set L1
        await self.l1.set(key, value, ttl)

        # Also set L2 if available
        if self.l2:
            try:
                json_value = json.dumps(value)
                await self.l2.set(key, json_value, ttl)
            except (json.JSONEncodeError, Exception) as e:
                logger.error(f"Failed to set Redis cache: {e}")

    async def delete(self, key: str) -> bool:
        """
        Delete from both L1 and L2.

        Args:
            key: Cache key

        Returns:
            True if item was present in either cache
        """
        l1_deleted = await self.l1.delete(key)
        l2_deleted = False

        if self.l2:
            l2_deleted = await self.l2.delete(key)

        return l1_deleted or l2_deleted

    async def clear(self) -> None:
        """Clear both L1 and L2 caches"""
        await self.l1.clear()
        if self.l2:
            await self.l2.clear()

    def get_stats(self) -> dict:
        """Get cache statistics"""
        return {
            "l1_memory": self.l1.get_stats(),
            "cache_type": self.config.type,
            "max_size_memory": self.config.max_size_memory,
            "ttl_seconds": self.config.ttl_seconds,
        }


def cache_key(*args: Any, **kwargs: Any) -> str:
    """
    Generate cache key from function arguments.

    Args:
        *args: Positional arguments
        **kwargs: Keyword arguments

    Returns:
        SHA256 hash of arguments as cache key
    """
    key_parts = [str(arg) for arg in args] + [f"{k}={v}" for k, v in sorted(kwargs.items())]
    key_str = "|".join(key_parts)
    return hashlib.sha256(key_str.encode()).hexdigest()


def cached(ttl_seconds: Optional[int] = None):
    """
    Decorator for caching async function results.

    Args:
        ttl_seconds: Optional TTL override

    Example:
        @cached(ttl_seconds=60)
        async def expensive_operation(user_id: int):
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            settings = get_settings()
            cache = HybridCache(settings.cache)
            await cache.connect()

            try:
                key = cache_key(func.__name__, *args, **kwargs)

                # Try cache first
                cached_value = await cache.get(key)
                if cached_value is not None:
                    logger.debug(f"Cache hit for {func.__name__}")
                    return cached_value

                # Compute and cache
                result = await func(*args, **kwargs)
                await cache.set(key, result, ttl_seconds)
                logger.debug(f"Cached result for {func.__name__}")
                return result

            finally:
                await cache.disconnect()

        return wrapper

    return decorator


# Global cache instance
_cache: Optional[HybridCache] = None


async def init_cache(config: CacheConfig) -> HybridCache:
    """
    Initialize global cache instance.

    Args:
        config: Cache configuration

    Returns:
        Initialized HybridCache instance
    """
    global _cache
    _cache = HybridCache(config)
    await _cache.connect()
    return _cache


async def get_cache() -> HybridCache:
    """
    Get global cache instance.

    Returns:
        HybridCache instance

    Raises:
        RuntimeError: If cache not initialized
    """
    global _cache
    if _cache is None:
        raise RuntimeError("Cache not initialized. Call init_cache() first.")
    return _cache


async def shutdown_cache() -> None:
    """Shutdown global cache instance"""
    global _cache
    if _cache:
        await _cache.disconnect()
        _cache = None
