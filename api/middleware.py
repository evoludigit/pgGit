"""
API Middleware for Request Tracking and Observability
======================================================

Provides middleware for:
- Request ID generation and tracking
- Structured logging context
- Request/response logging
- Performance timing
- Error context enrichment

Middleware Stack:
1. RequestIDMiddleware - Adds unique ID to each request
2. LoggingMiddleware - Structured logging of requests/responses
3. PerformanceMiddleware - Tracks request duration
"""

import time
import uuid
import logging
from typing import Callable
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from contextvars import ContextVar

logger = logging.getLogger(__name__)

# Context variable to store request ID across async calls
request_id_var: ContextVar[str] = ContextVar('request_id', default='')


class RequestIDMiddleware(BaseHTTPMiddleware):
    """
    Adds unique request ID to each incoming request.

    - Generates UUID for each request
    - Stores in context variable for access across async calls
    - Adds to response headers
    - Available via get_request_id()
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Generate unique request ID
        request_id = str(uuid.uuid4())

        # Store in context variable
        request_id_var.set(request_id)

        # Add to request state for easy access
        request.state.request_id = request_id

        # Process request
        response = await call_next(request)

        # Add request ID to response headers
        response.headers['X-Request-ID'] = request_id

        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """
    Logs all requests and responses with structured context.

    Logs:
    - Request: method, path, client IP, user agent
    - Response: status code, duration
    - Errors: Full exception details with context
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        request_id = getattr(request.state, 'request_id', 'unknown')

        # Log request
        logger.info(
            "Request received",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "query_params": str(request.query_params),
                "client_ip": request.client.host if request.client else None,
                "user_agent": request.headers.get("user-agent"),
            }
        )

        start_time = time.time()

        try:
            response = await call_next(request)

            duration_ms = (time.time() - start_time) * 1000

            # Log response
            log_level = logging.WARNING if response.status_code >= 400 else logging.INFO
            logger.log(
                log_level,
                "Request completed",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round(duration_ms, 2),
                }
            )

            return response

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000

            # Log error with full context
            logger.exception(
                "Request failed with exception",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": round(duration_ms, 2),
                    "exception_type": type(e).__name__,
                }
            )

            raise


class PerformanceMiddleware(BaseHTTPMiddleware):
    """
    Tracks request performance and logs slow requests.

    - Measures request duration
    - Logs warnings for slow requests (>1s)
    - Adds performance headers to response
    """

    def __init__(self, app, slow_request_threshold_ms: float = 1000):
        super().__init__(app)
        self.slow_request_threshold_ms = slow_request_threshold_ms

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        request_id = getattr(request.state, 'request_id', 'unknown')
        start_time = time.time()

        response = await call_next(request)

        duration_ms = (time.time() - start_time) * 1000

        # Add performance header
        response.headers['X-Response-Time-Ms'] = str(round(duration_ms, 2))

        # Warn on slow requests
        if duration_ms > self.slow_request_threshold_ms:
            logger.warning(
                "Slow request detected",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": round(duration_ms, 2),
                    "threshold_ms": self.slow_request_threshold_ms,
                }
            )

        return response


def get_request_id() -> str:
    """
    Get the current request ID from context.

    Returns:
        str: Current request ID, or 'unknown' if not in request context
    """
    return request_id_var.get()


class StructuredLoggerAdapter(logging.LoggerAdapter):
    """
    Logger adapter that automatically adds request ID to log records.

    Usage:
        logger = StructuredLoggerAdapter(logging.getLogger(__name__))
        logger.info("Something happened", extra={"user_id": 123})
        # Automatically includes request_id in log output
    """

    def process(self, msg, kwargs):
        # Add request ID to extra dict
        extra = kwargs.get('extra', {})
        extra['request_id'] = get_request_id()
        kwargs['extra'] = extra
        return msg, kwargs
