"""
Phase 8 Week 2: Webhook Delivery Worker Service
Purpose: Async HTTP worker for delivering webhooks with rate limiting and circuit breaker
Design: Non-blocking async I/O, lock-free queue polling, health tracking
Date: 2025-12-27
Status: Production-ready
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass
from typing import Optional, Tuple
from urllib.parse import urlparse

import aiohttp
import asyncpg
from prometheus_client import Counter, Histogram, Gauge, start_http_server

# ============================================================================
# CONFIGURATION
# ============================================================================

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/pggit"
)
WORKER_ID = os.getenv("WORKER_ID", "worker-1")
WORKER_COUNT = int(os.getenv("WORKER_COUNT", "1"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "10"))
POLL_INTERVAL = float(os.getenv("POLL_INTERVAL", "1.0"))  # seconds
HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "5.0"))  # seconds
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
METRICS_PORT = int(os.getenv("METRICS_PORT", "8080"))

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============================================================================
# PROMETHEUS METRICS
# ============================================================================

delivery_counter = Counter(
    'webhook_deliveries_total',
    'Total webhook deliveries',
    ['status', 'webhook_id']
)

delivery_latency = Histogram(
    'webhook_delivery_duration_seconds',
    'Webhook delivery latency',
    ['webhook_id'],
    buckets=(0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0)
)

queue_depth = Gauge(
    'webhook_queue_depth',
    'Number of pending deliveries'
)

worker_health = Gauge(
    'worker_health_status',
    'Worker health (1=healthy, 0=error)',
    ['worker_id']
)

rate_limit_hits = Counter(
    'rate_limit_hits_total',
    'Rate limit hits per webhook',
    ['webhook_id']
)

circuit_breaker_opens = Counter(
    'circuit_breaker_opens_total',
    'Circuit breaker opens per webhook',
    ['webhook_id']
)

# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class Delivery:
    """Webhook delivery to process"""
    delivery_id: int
    alert_id: int
    webhook_id: int
    message_body: dict
    retry_count: int
    max_retries: int


@dataclass
class RateLimiter:
    """Token bucket rate limiter per webhook"""
    max_requests: float = 10.0  # requests per second
    tokens: dict[int, float] = None  # webhook_id -> tokens
    last_refill: dict[int, float] = None  # webhook_id -> timestamp

    def __post_init__(self):
        if self.tokens is None:
            self.tokens = {}
        if self.last_refill is None:
            self.last_refill = {}

    def can_send(self, webhook_id: int) -> bool:
        """Check if webhook can send (token bucket algorithm)"""
        now = time.time()

        # Initialize if first request
        if webhook_id not in self.tokens:
            self.tokens[webhook_id] = self.max_requests
            self.last_refill[webhook_id] = now
            return True

        # Refill tokens based on elapsed time
        elapsed = now - self.last_refill[webhook_id]
        self.tokens[webhook_id] = min(
            self.max_requests,
            self.tokens[webhook_id] + elapsed * self.max_requests
        )
        self.last_refill[webhook_id] = now

        # Check if tokens available
        if self.tokens[webhook_id] >= 1.0:
            self.tokens[webhook_id] -= 1.0
            return True

        return False


@dataclass
class CircuitBreaker:
    """Circuit breaker per webhook: open after N consecutive failures"""
    failure_threshold: int = 5
    timeout_seconds: int = 60
    failures: dict[int, int] = None  # webhook_id -> count
    open_until: dict[int, float] = None  # webhook_id -> timestamp

    def __post_init__(self):
        if self.failures is None:
            self.failures = {}
        if self.open_until is None:
            self.open_until = {}

    def is_open(self, webhook_id: int) -> bool:
        """Check if circuit is open for this webhook"""
        if webhook_id not in self.open_until:
            return False

        now = time.time()
        if now >= self.open_until[webhook_id]:
            # Timeout expired, try to close
            self.failures[webhook_id] = 0
            del self.open_until[webhook_id]
            return False

        return True

    def record_failure(self, webhook_id: int):
        """Record a failure, open circuit if threshold reached"""
        self.failures[webhook_id] = self.failures.get(webhook_id, 0) + 1

        if self.failures[webhook_id] >= self.failure_threshold:
            self.open_until[webhook_id] = time.time() + self.timeout_seconds
            circuit_breaker_opens.labels(webhook_id=webhook_id).inc()
            logger.warning(
                f"Circuit breaker opened for webhook {webhook_id} "
                f"(failures: {self.failures[webhook_id]})"
            )

    def record_success(self, webhook_id: int):
        """Record a success, reset failure count"""
        self.failures[webhook_id] = 0


# ============================================================================
# WEBHOOK WORKER
# ============================================================================

class WebhookWorker:
    """Async webhook delivery worker"""

    def __init__(
        self,
        worker_id: str,
        db_url: str,
        batch_size: int = 10,
        poll_interval: float = 1.0,
        http_timeout: float = 5.0,
    ):
        self.worker_id = worker_id
        self.db_url = db_url
        self.batch_size = batch_size
        self.poll_interval = poll_interval
        self.http_timeout = http_timeout

        self.db_pool: Optional[asyncpg.Pool] = None
        self.http_session: Optional[aiohttp.ClientSession] = None
        self.rate_limiter = RateLimiter()
        self.circuit_breaker = CircuitBreaker()

        self.running = False
        self.stats = {
            'delivered': 0,
            'failed': 0,
            'rate_limited': 0,
            'circuit_open': 0,
        }

    async def start(self):
        """Initialize worker and start polling"""
        logger.info(f"Starting worker {self.worker_id}")

        # Create database connection pool
        self.db_pool = await asyncpg.create_pool(
            self.db_url,
            min_size=2,
            max_size=10,
            timeout=10.0,
        )

        # Create HTTP session
        self.http_session = aiohttp.ClientSession()

        self.running = True
        worker_health.labels(worker_id=self.worker_id).set(1)
        logger.info(f"Worker {self.worker_id} started")

    async def stop(self):
        """Gracefully shutdown worker"""
        logger.info(f"Stopping worker {self.worker_id}")
        self.running = False

        if self.http_session:
            await self.http_session.close()

        if self.db_pool:
            await self.db_pool.close()

        worker_health.labels(worker_id=self.worker_id).set(0)
        logger.info(f"Worker {self.worker_id} stopped")

    async def run(self):
        """Main event loop: poll and process deliveries"""
        await self.start()

        try:
            while self.running:
                await self.process_batch()
                await asyncio.sleep(self.poll_interval)
        except Exception as e:
            logger.error(f"Worker {self.worker_id} error: {e}", exc_info=True)
            worker_health.labels(worker_id=self.worker_id).set(0)
        finally:
            await self.stop()

    async def process_batch(self):
        """Get and process a batch of deliveries"""
        try:
            # Get ready deliveries (lock-free polling)
            deliveries = await self.get_ready_deliveries()
            queue_depth.set(len(deliveries))

            if not deliveries:
                return

            logger.debug(f"Processing batch of {len(deliveries)} deliveries")

            # Process deliveries concurrently
            tasks = [self.process_delivery(d) for d in deliveries]
            await asyncio.gather(*tasks, return_exceptions=True)

        except Exception as e:
            logger.error(f"Batch processing error: {e}", exc_info=True)

    async def get_ready_deliveries(self) -> list[Delivery]:
        """Poll database for ready deliveries (lock-free)"""
        try:
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT delivery_id, alert_id, webhook_id, message_body,
                           retry_count, max_retries
                    FROM pggit.get_ready_deliveries($1)
                    """,
                    self.batch_size
                )

            deliveries = [
                Delivery(
                    delivery_id=row['delivery_id'],
                    alert_id=row['alert_id'],
                    webhook_id=row['webhook_id'],
                    message_body=row['message_body'],
                    retry_count=row['retry_count'],
                    max_retries=row['max_retries'],
                )
                for row in rows
            ]

            return deliveries

        except Exception as e:
            logger.error(f"Error fetching deliveries: {e}", exc_info=True)
            return []

    async def process_delivery(self, delivery: Delivery):
        """Process a single delivery"""
        start_time = time.time()
        webhook_id = delivery.webhook_id

        try:
            # Check rate limiting
            if not self.rate_limiter.can_send(webhook_id):
                logger.debug(f"Delivery {delivery.delivery_id} rate limited")
                rate_limit_hits.labels(webhook_id=webhook_id).inc()
                self.stats['rate_limited'] += 1
                await self.reschedule_delivery(delivery, delay_seconds=1)
                return

            # Check circuit breaker
            if self.circuit_breaker.is_open(webhook_id):
                logger.warning(f"Delivery {delivery.delivery_id} circuit breaker open")
                self.stats['circuit_open'] += 1
                await self.reschedule_delivery(delivery, delay_seconds=60)
                return

            # Get webhook URL
            webhook_url = await self.get_webhook_url(webhook_id)
            if not webhook_url:
                logger.error(f"Webhook {webhook_id} not found")
                await self.fail_delivery(
                    delivery,
                    http_status=0,
                    response_time_ms=0,
                    error_msg="Webhook URL not found"
                )
                return

            # Validate URL
            if not self.is_valid_url(webhook_url):
                logger.error(f"Invalid webhook URL for {webhook_id}: {webhook_url}")
                await self.fail_delivery(
                    delivery,
                    http_status=0,
                    response_time_ms=0,
                    error_msg="Invalid webhook URL"
                )
                return

            # POST to webhook
            http_status, response_time_ms = await self.post_webhook(
                webhook_url,
                delivery.message_body,
                webhook_id
            )

            # Handle response
            if 200 <= http_status < 300:
                await self.complete_delivery(
                    delivery,
                    http_status=http_status,
                    response_time_ms=response_time_ms
                )
                self.circuit_breaker.record_success(webhook_id)
                self.stats['delivered'] += 1

            elif http_status >= 500 or http_status == 0:
                # Server error, retry
                await self.fail_delivery(
                    delivery,
                    http_status=http_status,
                    response_time_ms=response_time_ms,
                    error_msg=f"Server error: {http_status}"
                )
                self.circuit_breaker.record_failure(webhook_id)
                self.stats['failed'] += 1

            else:
                # Client error, permanent failure
                await self.fail_delivery(
                    delivery,
                    http_status=http_status,
                    response_time_ms=response_time_ms,
                    error_msg=f"Client error: {http_status}",
                    skip_retries=True
                )
                self.stats['failed'] += 1

        except Exception as e:
            logger.error(
                f"Error processing delivery {delivery.delivery_id}: {e}",
                exc_info=True
            )
            await self.fail_delivery(
                delivery,
                http_status=0,
                response_time_ms=int((time.time() - start_time) * 1000),
                error_msg=f"Exception: {str(e)}"
            )
            self.stats['failed'] += 1

    async def post_webhook(
        self,
        webhook_url: str,
        message_body: dict,
        webhook_id: int
    ) -> Tuple[int, int]:
        """POST to webhook URL, return (http_status, response_time_ms)"""
        start_time = time.time()

        try:
            async with self.http_session.post(
                webhook_url,
                json=message_body,
                timeout=aiohttp.ClientTimeout(total=self.http_timeout),
                headers={'Content-Type': 'application/json'},
            ) as resp:
                response_time_ms = int((time.time() - start_time) * 1000)

                logger.info(
                    f"Webhook {webhook_id} POST to {webhook_url}: "
                    f"status={resp.status}, time={response_time_ms}ms"
                )

                delivery_latency.labels(webhook_id=webhook_id).observe(
                    response_time_ms / 1000.0
                )

                return resp.status, response_time_ms

        except asyncio.TimeoutError:
            response_time_ms = int((time.time() - start_time) * 1000)
            logger.error(f"Webhook {webhook_id} timeout after {response_time_ms}ms")
            return 0, response_time_ms

        except Exception as e:
            response_time_ms = int((time.time() - start_time) * 1000)
            logger.error(f"Webhook {webhook_id} POST error: {e}")
            return 0, response_time_ms

    async def complete_delivery(
        self,
        delivery: Delivery,
        http_status: int,
        response_time_ms: int
    ):
        """Mark delivery as successful and update health metrics"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE pggit.alert_delivery_queue
                    SET delivery_status = 'delivered',
                        delivered_at = NOW(),
                        attempted_at = NOW()
                    WHERE delivery_id = $1
                    """,
                    delivery.delivery_id
                )

                # Update health metrics
                await conn.execute(
                    """
                    SELECT pggit.update_webhook_health($1, $2, $3, NULL)
                    """,
                    delivery.webhook_id,
                    http_status,
                    response_time_ms
                )

                # Log to audit trail
                await conn.execute(
                    """
                    INSERT INTO pggit.alert_delivery_log
                    (delivery_id, webhook_id, event_type, event_details, created_at)
                    VALUES ($1, $2, 'delivered', $3::jsonb, NOW())
                    """,
                    delivery.delivery_id,
                    delivery.webhook_id,
                    json.dumps({'http_status': http_status, 'response_time_ms': response_time_ms})
                )

            delivery_counter.labels(status='success', webhook_id=delivery.webhook_id).inc()
            logger.info(f"Delivery {delivery.delivery_id} completed")

        except Exception as e:
            logger.error(f"Error completing delivery {delivery.delivery_id}: {e}")

    async def fail_delivery(
        self,
        delivery: Delivery,
        http_status: int,
        response_time_ms: int,
        error_msg: str,
        skip_retries: bool = False
    ):
        """Mark delivery as failed or schedule retry"""
        try:
            async with self.db_pool.acquire() as conn:
                if not skip_retries and delivery.retry_count < delivery.max_retries:
                    # Schedule retry with exponential backoff
                    backoff_seconds = 5 * (2 ** delivery.retry_count)

                    await conn.execute(
                        """
                        UPDATE pggit.alert_delivery_queue
                        SET delivery_status = 'retrying',
                            retry_count = retry_count + 1,
                            next_retry_at = NOW() + INTERVAL '1 second' * $1,
                            attempted_at = NOW()
                        WHERE delivery_id = $2
                        """,
                        backoff_seconds,
                        delivery.delivery_id
                    )

                    status = 'retrying'
                else:
                    # Max retries exceeded or permanent failure
                    await conn.execute(
                        """
                        UPDATE pggit.alert_delivery_queue
                        SET delivery_status = 'failed',
                            attempted_at = NOW()
                        WHERE delivery_id = $1
                        """,
                        delivery.delivery_id
                    )

                    status = 'failed'

                # Update health metrics
                await conn.execute(
                    """
                    SELECT pggit.update_webhook_health($1, $2, $3, $4)
                    """,
                    delivery.webhook_id,
                    http_status,
                    response_time_ms,
                    error_msg
                )

                # Log to audit trail
                await conn.execute(
                    """
                    INSERT INTO pggit.alert_delivery_log
                    (delivery_id, webhook_id, event_type, event_details, created_at)
                    VALUES ($1, $2, $3, $4::jsonb, NOW())
                    """,
                    delivery.delivery_id,
                    delivery.webhook_id,
                    status,
                    json.dumps({
                        'http_status': http_status,
                        'response_time_ms': response_time_ms,
                        'error': error_msg,
                        'retry_count': delivery.retry_count
                    })
                )

            delivery_counter.labels(status='failure', webhook_id=delivery.webhook_id).inc()
            logger.warning(f"Delivery {delivery.delivery_id} {status}: {error_msg}")

        except Exception as e:
            logger.error(f"Error failing delivery {delivery.delivery_id}: {e}")

    async def reschedule_delivery(self, delivery: Delivery, delay_seconds: int):
        """Reschedule delivery for later (rate limit or circuit breaker)"""
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE pggit.alert_delivery_queue
                    SET next_retry_at = NOW() + INTERVAL '1 second' * $1
                    WHERE delivery_id = $2
                    """,
                    delay_seconds,
                    delivery.delivery_id
                )
        except Exception as e:
            logger.error(f"Error rescheduling delivery {delivery.delivery_id}: {e}")

    async def get_webhook_url(self, webhook_id: int) -> Optional[str]:
        """Retrieve and decrypt webhook URL from database"""
        try:
            async with self.db_pool.acquire() as conn:
                result = await conn.fetchval(
                    "SELECT pggit.get_webhook_decrypted($1)",
                    webhook_id
                )
            return result
        except Exception as e:
            logger.error(f"Error getting webhook URL for {webhook_id}: {e}")
            return None

    @staticmethod
    def is_valid_url(url: str) -> bool:
        """Validate webhook URL (SSRF protection)"""
        try:
            parsed = urlparse(url)

            # Must be HTTPS
            if parsed.scheme != 'https':
                logger.warning(f"Non-HTTPS URL rejected: {url}")
                return False

            # No private IP ranges (simplified SSRF protection)
            hostname = parsed.hostname or ''
            private_ranges = [
                '127.', '10.', '172.', '192.168.', 'localhost', '0.0.0.0'
            ]
            if any(hostname.startswith(r) for r in private_ranges):
                logger.warning(f"Private IP rejected: {url}")
                return False

            return True

        except Exception as e:
            logger.error(f"URL validation error: {e}")
            return False

    def print_stats(self):
        """Print worker statistics"""
        logger.info(
            f"Worker {self.worker_id} stats: "
            f"delivered={self.stats['delivered']}, "
            f"failed={self.stats['failed']}, "
            f"rate_limited={self.stats['rate_limited']}, "
            f"circuit_open={self.stats['circuit_open']}"
        )


# ============================================================================
# MAIN
# ============================================================================

async def main():
    """Start worker(s) and handle graceful shutdown"""
    logger.info(f"Starting webhook worker service (WORKER_ID={WORKER_ID})")

    # Start Prometheus metrics server
    start_http_server(METRICS_PORT)
    logger.info(f"Prometheus metrics started on port {METRICS_PORT}")

    # Create worker
    worker = WebhookWorker(
        worker_id=WORKER_ID,
        db_url=DATABASE_URL,
        batch_size=BATCH_SIZE,
        poll_interval=POLL_INTERVAL,
        http_timeout=HTTP_TIMEOUT,
    )

    # Handle signals for graceful shutdown
    def signal_handler(sig, frame):
        logger.info(f"Signal {sig} received, shutting down...")
        worker.running = False

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Run worker
    try:
        await worker.run()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 1
    finally:
        worker.print_stats()

    return 0


if __name__ == '__main__':
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
