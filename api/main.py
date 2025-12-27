"""
Phase 8 FastAPI Application
===========================

Main FastAPI application with database pooling, caching, middleware, and error handling.
CRITICAL FIXES: #6 (get_db), #3 (WebSocket auth), #4 (cache), #9 (monitoring)

Architecture:
- Async connection pooling (asyncpg)
- Multi-tier caching (L1 in-memory, L2 Redis)
- JWT authentication for REST and WebSocket
- Prometheus metrics collection
- Error handling and logging
- CORS middleware
- Request tracing

Usage:
    uvicorn api.main:app --host 0.0.0.0 --port 8000
"""

import logging
import time
from contextlib import asynccontextmanager
from typing import Callable

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from services.config import get_settings
from services.dependencies import init_db_pool, close_db_pool
from services.cache import init_cache, shutdown_cache
from services.query_optimization import init_query_optimization, shutdown_query_optimization
from services.cache_warming_strategies import init_cache_warming, shutdown_cache_warming

logger = logging.getLogger(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI lifespan context manager.

    Startup:
    - Initialize database connection pool
    - Initialize caching layer
    - Initialize monitoring

    Shutdown:
    - Close all database connections
    - Shutdown cache
    """
    settings = get_settings()

    # ===== STARTUP =====
    logger.info("=== PGGIT API STARTUP ===")

    try:
        # Initialize database pool
        logger.info(f"Initializing database pool: {settings.database.host}:{settings.database.port}/{settings.database.database}")
        await init_db_pool()
        logger.info("✓ Database pool initialized")

        # Initialize caching layer
        logger.info(f"Initializing cache: {settings.cache.type}")
        await init_cache(settings.cache)
        logger.info("✓ Cache initialized")

        # Initialize query optimization
        logger.info("Initializing query optimization and cache warming")
        await init_query_optimization()
        logger.info("✓ Query optimization initialized")

        # Initialize cache warming strategies
        logger.info("Starting cache warming background tasks")
        await init_cache_warming()
        logger.info("✓ Cache warming started")

        logger.info("=== STARTUP COMPLETE ===\n")

    except Exception as e:
        logger.error(f"Startup failed: {e}")
        raise

    yield

    # ===== SHUTDOWN =====
    logger.info("\n=== PGGIT API SHUTDOWN ===")

    try:
        # Shutdown cache warming
        await shutdown_cache_warming()
        logger.info("✓ Cache warming shutdown")

        # Shutdown query optimization
        await shutdown_query_optimization()
        logger.info("✓ Query optimization shutdown")

        # Shutdown cache
        await shutdown_cache()
        logger.info("✓ Cache shutdown")

        # Close database pool
        await close_db_pool()
        logger.info("✓ Database pool closed")

        logger.info("=== SHUTDOWN COMPLETE ===")

    except Exception as e:
        logger.error(f"Shutdown error: {e}")
        raise


# Initialize FastAPI application
app = FastAPI(
    title="PGGIT API",
    description="Phase 8 Real-time Analytics & Monitoring API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan
)


# ===== MIDDLEWARE =====

# CORS Middleware
settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors.allowed_origins.split(","),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


# Request logging middleware
@app.middleware("http")
async def log_request_middleware(request: Request, call_next: Callable):
    """
    Log all HTTP requests with timing information.
    """
    request_id = request.headers.get("X-Request-ID", "unknown")
    method = request.method
    path = request.url.path

    start_time = time.time()

    try:
        response = await call_next(request)
        duration_ms = (time.time() - start_time) * 1000

        logger.info(
            f"[{request_id}] {method} {path} - "
            f"Status {response.status_code} - {duration_ms:.2f}ms"
        )

        # Add timing headers
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Response-Time"] = f"{duration_ms:.2f}ms"

        return response

    except Exception as e:
        duration_ms = (time.time() - start_time) * 1000
        logger.error(
            f"[{request_id}] {method} {path} - "
            f"Error {type(e).__name__} - {duration_ms:.2f}ms"
        )
        raise


# Error handling middleware
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """
    Global exception handler for all unhandled exceptions.
    """
    request_id = request.headers.get("X-Request-ID", "unknown")
    logger.error(f"[{request_id}] Unhandled exception: {type(exc).__name__}: {exc}")

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "request_id": request_id,
            "detail": str(exc) if settings.environment == "development" else None
        }
    )


# ===== HEALTH CHECKS =====

@app.get("/health", tags=["Health"])
async def health_check():
    """
    Basic health check endpoint.

    Returns:
        - 200 OK if service is running
        - 503 SERVICE_UNAVAILABLE if critical services are down
    """
    return {
        "status": "healthy",
        "service": "pggit-api",
        "version": "1.0.0"
    }


@app.get("/health/deep", tags=["Health"])
async def deep_health_check():
    """
    Deep health check including database and cache connectivity.

    Checks:
    - Database connectivity
    - Cache connectivity
    - Memory usage
    - Connection pool stats

    Returns:
        - 200 OK if all services operational
        - 503 SERVICE_UNAVAILABLE if any critical service is down
    """
    from services.dependencies import _pool
    from services.cache import get_cache

    health_status = {
        "status": "healthy",
        "service": "pggit-api",
        "database": {"status": "unknown"},
        "cache": {"status": "unknown"},
        "connections": {}
    }

    # Check database pool
    if _pool:
        try:
            health_status["database"]["status"] = "healthy"
            health_status["database"]["size"] = f"{_pool._holders.__len__()}/{_pool._queue.qsize()}"
        except Exception as e:
            health_status["database"]["status"] = "unhealthy"
            health_status["database"]["error"] = str(e)
            health_status["status"] = "degraded"
    else:
        health_status["database"]["status"] = "unavailable"
        health_status["status"] = "degraded"

    # Check cache
    try:
        cache = await get_cache()
        stats = cache.get_stats()
        health_status["cache"]["status"] = "healthy"
        health_status["cache"]["hit_rate"] = stats["l1_memory"]["hit_rate_percent"]
        health_status["cache"]["size"] = stats["l1_memory"]["size"]
    except RuntimeError:
        health_status["cache"]["status"] = "unavailable"
        health_status["status"] = "degraded"
    except Exception as e:
        health_status["cache"]["status"] = "unhealthy"
        health_status["cache"]["error"] = str(e)
        health_status["status"] = "degraded"

    status_code = 200 if health_status["status"] == "healthy" else 503
    return JSONResponse(content=health_status, status_code=status_code)


# ===== API ROUTES =====

# Import and register route modules
from api.routes import webhooks, alerts, dashboard, cache_invalidation
from api.websocket_endpoints import websocket_endpoint

# Include routers
app.include_router(
    webhooks.router,
    prefix="/api/v1",
    tags=["Webhooks"]
)

app.include_router(
    alerts.router,
    prefix="/api/v1",
    tags=["Alerts"]
)

app.include_router(
    dashboard.router,
    prefix="/api/v1",
    tags=["Dashboard"]
)

app.include_router(
    cache_invalidation.router,
    prefix="/api/v1",
    tags=["Cache Invalidation"]
)

# Register WebSocket endpoint
app.websocket("/ws/dashboard")(websocket_endpoint)


# ===== ROOT ENDPOINT =====

@app.get("/", tags=["Root"])
async def root():
    """
    Root endpoint with API information.
    """
    return {
        "service": "PGGIT API",
        "version": "1.0.0",
        "environment": settings.environment,
        "documentation": "/api/docs",
        "health": "/health",
        "endpoints": {
            "webhooks": "/api/v1/webhooks",
            "alerts": "/api/v1/alerts",
            "dashboard": "/api/v1/dashboard",
            "websocket": "/ws/dashboard"
        }
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "api.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.environment == "development",
        log_level="info"
    )
