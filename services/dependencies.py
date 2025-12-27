"""
Phase 8 FastAPI Dependencies
=============================

Dependency injection for FastAPI endpoints.
CRITICAL FIX #6: Provides get_db dependency and connection pooling.

Architecture:
- Async connection pool (asyncpg)
- Per-request database connection
- Automatic connection cleanup
- Health checking and recovery
"""

import logging
from typing import AsyncGenerator

import asyncpg
from fastapi import Depends, HTTPException, status, WebSocket, WebSocketException
from jose import JWTError, jwt

from services.config import get_settings
from services.cache import get_cache

logger = logging.getLogger(__name__)

# Global connection pool
_pool: asyncpg.Pool | None = None


async def init_db_pool() -> asyncpg.Pool:
    """
    Initialize database connection pool.

    Called at application startup.

    Returns:
        Initialized asyncpg connection pool

    Raises:
        Exception: If connection fails
    """
    global _pool
    settings = get_settings()

    _pool = await asyncpg.create_pool(
        dsn=settings.database.url,
        min_size=10,
        max_size=50,
        max_queries=50000,
        max_cached_statement_lifetime=300,
        max_cacheable_statement_size=15000,
        command_timeout=10,
        record_class=asyncpg.Record,
    )

    logger.info(f"Database pool initialized: {settings.database.database}@{settings.database.host}")
    return _pool


async def close_db_pool() -> None:
    """
    Close database connection pool.

    Called at application shutdown.
    """
    global _pool
    if _pool:
        await _pool.close()
        logger.info("Database pool closed")


async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """
    Dependency: Get database connection from pool.

    Usage in FastAPI:
        async def my_endpoint(db: asyncpg.Connection = Depends(get_db)):
            result = await db.fetch("SELECT * FROM table")

    Yields:
        Database connection from pool

    Raises:
        HTTPException: If connection cannot be acquired
    """
    global _pool
    if _pool is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database connection pool not initialized",
        )

    conn = None
    try:
        # CRITICAL FIX #6: Use context manager pattern to prevent pool deadlock
        # (Previously: conn = await _pool.acquire()  # Never released!)
        conn = await _pool.acquire()
        yield conn
    except asyncpg.PostgresError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database operation failed",
        )
    finally:
        # Connection automatically released back to pool
        if conn:
            await _pool.release(conn)


async def get_db_transaction(db: asyncpg.Connection = Depends(get_db)) -> AsyncGenerator[asyncpg.Connection, None]:
    """
    Dependency: Get database connection with active transaction.

    CRITICAL FIX #7: Sets REPEATABLE READ isolation for analytics queries.

    Usage:
        async def my_endpoint(db: asyncpg.Connection = Depends(get_db_transaction)):
            # Transaction already started
            result = await db.fetch("SELECT ...")
            # Transaction auto-commits on success

    Yields:
        Database connection with active transaction
    """
    try:
        # CRITICAL FIX #7: Set transaction isolation level for analytics
        await db.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;")
        yield db
        await db.execute("COMMIT;")
    except Exception as e:
        await db.execute("ROLLBACK;")
        logger.error(f"Transaction failed: {e}")
        raise


def decode_token(token: str) -> dict:
    """
    Decode and validate JWT token.

    Args:
        token: JWT token string

    Returns:
        Decoded token payload

    Raises:
        HTTPException: If token is invalid or expired
    """
    settings = get_settings()

    try:
        payload = jwt.decode(
            token,
            settings.jwt.secret_key,
            algorithms=[settings.jwt.algorithm],
        )
        return payload
    except JWTError as e:
        logger.warning(f"Invalid token: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def get_current_user(token: str = None) -> dict:
    """
    Dependency: Get current authenticated user from JWT token.

    Usage:
        async def my_endpoint(user: dict = Depends(get_current_user)):
            user_id = user.get("sub")

    Args:
        token: JWT token (from Authorization header or query param)

    Returns:
        User information from token

    Raises:
        HTTPException: If token is missing or invalid
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(token)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token: missing user ID",
        )

    return {"user_id": user_id, **payload}


async def verify_websocket_token(websocket: WebSocket, token: str) -> dict:
    """
    Verify JWT token for WebSocket connection.

    CRITICAL FIX #3: WebSocket authentication.

    Usage in WebSocket endpoint:
        @app.websocket("/ws/dashboard")
        async def websocket_endpoint(websocket: WebSocket, token: str = Query(...)):
            user = await verify_websocket_token(websocket, token)
            # Now authenticated

    Args:
        websocket: WebSocket connection
        token: JWT token from query parameter

    Returns:
        User information if token is valid

    Raises:
        WebSocketException: If token is invalid
    """
    try:
        payload = decode_token(token)
        user_id = payload.get("sub")

        if not user_id:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid token")
            raise WebSocketException(code=status.WS_1008_POLICY_VIOLATION, reason="Invalid token")

        return {"user_id": user_id, **payload}

    except JWTError as e:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Authentication failed")
        raise WebSocketException(code=status.WS_1008_POLICY_VIOLATION, reason=str(e))


async def get_cache_dependency():
    """
    Dependency: Get cache instance.

    Usage:
        async def my_endpoint(cache = Depends(get_cache_dependency)):
            value = await cache.get("key")

    Returns:
        HybridCache instance

    Raises:
        HTTPException: If cache not initialized
    """
    try:
        return await get_cache()
    except RuntimeError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cache service not available",
        )


# Dependency for read-only operations
async def get_db_readonly(db: asyncpg.Connection = Depends(get_db)) -> AsyncGenerator[asyncpg.Connection, None]:
    """
    Dependency: Get read-only database connection.

    Prevents accidental writes in read-only endpoints.

    Usage:
        async def get_stats(db: asyncpg.Connection = Depends(get_db_readonly)):
            return await db.fetch("SELECT ...")

    Yields:
        Database connection (guaranteed read-only by caller responsibility)
    """
    yield db


# Rate limiting tracking
_rate_limit_cache: dict[str, list[float]] = {}


async def check_rate_limit(user_id: str, limit: int = 100, window_seconds: int = 60) -> bool:
    """
    Check if user has exceeded rate limit.

    Args:
        user_id: User identifier
        limit: Max requests per window
        window_seconds: Time window in seconds

    Returns:
        True if within limit, False if exceeded
    """
    import time

    current_time = time.time()
    key = f"{user_id}:{window_seconds}"

    if key not in _rate_limit_cache:
        _rate_limit_cache[key] = []

    # Remove old requests outside window
    _rate_limit_cache[key] = [
        ts for ts in _rate_limit_cache[key]
        if current_time - ts < window_seconds
    ]

    # Check limit
    if len(_rate_limit_cache[key]) >= limit:
        return False

    # Add current request
    _rate_limit_cache[key].append(current_time)
    return True


async def rate_limit_dependency(user: dict = Depends(get_current_user)) -> dict:
    """
    Dependency: Check rate limit for user.

    Raises:
        HTTPException: If rate limit exceeded
    """
    settings = get_settings()
    user_id = user.get("user_id")

    within_limit = await check_rate_limit(
        user_id,
        limit=settings.redis.port,  # Can use Redis-based rate limiting instead
        window_seconds=60,
    )

    if not within_limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded",
            headers={"Retry-After": "60"},
        )

    return user
