# Phase 8: Week 2 - Real HTTP Delivery Architecture

**Date**: December 27, 2025
**Status**: Architecture Design Phase
**Objective**: Design production-grade HTTP webhook delivery system with external worker service

---

## Executive Summary

This document redesigns Phase 8 Week 2 based on expert review feedback. The key architectural change replaces **in-database HTTP calls** with a **hybrid PostgreSQL + External Worker pattern** that:

- ✅ **Non-blocking**: PostgreSQL never waits for HTTP
- ✅ **Scalable**: Run N workers independently, horizontal scaling
- ✅ **Resilient**: Worker crashes don't affect database
- ✅ **Observable**: Full metrics, logging, tracing
- ✅ **Production-ready**: Handles failures, retries, rate limiting

This architecture solves the **critical blocking HTTP issue** identified by PostgreSQL experts.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Proposed Architecture](#proposed-architecture)
3. [System Components](#system-components)
4. [Data Flow](#data-flow)
5. [External Worker Service Design](#external-worker-service-design)
6. [PostgreSQL Schema & Functions](#postgresql-schema--functions)
7. [Deployment Architecture](#deployment-architecture)
8. [Failure Modes & Recovery](#failure-modes--recovery)
9. [Implementation Plan](#implementation-plan)
10. [Performance Targets](#performance-targets)

---

## Problem Statement

### Week 1 Limitation

Week 1 implemented simulated HTTP delivery:
```sql
-- Week 1: Simulation (fast, no network)
v_http_status := 200;
```

### Week 2 Challenge: In-Database HTTP (Problematic)

Original Week 2 plan proposed in-database HTTP via pgnet/pl/python:

**Critical Issues with In-Database HTTP:**

```sql
-- ❌ PROBLEM: Synchronous HTTP blocks transaction
CREATE OR REPLACE FUNCTION pggit.observer_deliver_alert(p_delivery_id BIGINT) AS $$
BEGIN
    SELECT * INTO v_http_response FROM pggit.http_post_webhook(
        v_webhook_url,
        v_message_body,
        5000  -- BLOCKS for up to 5 seconds
    );

    UPDATE pggit.alert_delivery_queue
    SET delivery_status = 'delivered'
    WHERE delivery_id = p_delivery_id;
END;
$$ LANGUAGE plpgsql;
```

**Consequences:**
- 100 alerts → 100 connections blocked for 5+ seconds
- Connection pool exhaustion → system-wide deadlock
- Slow webhooks (>5s) fail with timeout
- No way to prioritize critical webhooks
- Scaling limited by PostgreSQL connection pool

### Expert Consensus

All 5 expert reviewers agreed:
> "Synchronous HTTP calls inside PostgreSQL transactions are unsuitable for production webhook delivery. Use external worker pattern instead."

---

## Proposed Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│ PostgreSQL Database (Non-Blocking)                              │
│                                                                  │
│  ┌──────────────────────┐        ┌─────────────────────────┐   │
│  │ Alert Generators     │        │ alert_delivery_queue    │   │
│  │ (Week 4, Week 7)     │───────▶│ (pending, retrying)     │   │
│  └──────────────────────┘        └─────────────────────────┘   │
│                                           │                      │
│                                           │ FOR UPDATE SKIP LOCKED
│                                           ▼                      │
│                                  ┌─────────────────────┐        │
│                                  │ Delivery Status     │        │
│                                  │ Health Metrics      │        │
│                                  │ Audit Log           │        │
│                                  └─────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
        ▲                                       │
        │                                       │ Poll + Update
        │                                       │ (Atomic)
        │                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ External Worker Service (Async HTTP)                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Worker Pool (N processes/goroutines)                    │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│  │  │ Worker 1     │  │ Worker 2     │  │ Worker N     │  │   │
│  │  │              │  │              │  │              │  │   │
│  │  │ 1. Poll DB   │  │ 1. Poll DB   │  │ 1. Poll DB   │  │   │
│  │  │ 2. GET LOCK  │  │ 2. GET LOCK  │  │ 2. GET LOCK  │  │   │
│  │  │ 3. POST HTTP │  │ 3. POST HTTP │  │ 3. POST HTTP │  │   │
│  │  │ 4. Update    │  │ 4. Update    │  │ 4. Update    │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │   │
│  │                                                          │   │
│  │ Rate Limiter:                                           │   │
│  │   Per-webhook rate limits (requests/sec)                │   │
│  │   Exponential backoff with jitter                       │   │
│  │   Circuit breaker (stop-on-failure)                     │   │
│  │                                                          │   │
│  │ Observability:                                          │   │
│  │   Metrics (Prometheus)                                  │   │
│  │   Logs (structured JSON)                                │   │
│  │   Traces (correlation IDs)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
        │
        │ HTTP POST
        ▼
┌─────────────────────────────┐
│ Webhook Endpoints (External)│
│                             │
│  ┌──────────────────────┐   │
│  │ Slack, Mattermost,   │   │
│  │ PagerDuty, Custom    │   │
│  │ Endpoints            │   │
│  └──────────────────────┘   │
│                             │
└─────────────────────────────┘
```

### Key Architectural Principles

1. **Separation of Concerns**
   - Database: Queuing, state management, audit trail
   - Worker: HTTP delivery, retry logic, health tracking
   - No HTTP calls inside PostgreSQL transactions

2. **Non-Blocking Design**
   - Database queries return immediately
   - Workers process in parallel, independently
   - Failures isolated to individual workers

3. **Horizontal Scalability**
   - Add workers by starting new processes/containers
   - No coordination needed (lock-free via FOR UPDATE SKIP LOCKED)
   - Throughput scales linearly with worker count

4. **Resilience**
   - Worker crashes don't affect database
   - Incomplete deliveries automatically re-queued
   - Circuit breaker prevents thundering herd

5. **Observability**
   - Full audit trail in database
   - Prometheus metrics from workers
   - Structured logging with correlation IDs

---

## System Components

### A. PostgreSQL Components (Minimal Changes)

**New Tables:**
- `webhook_health_metrics` - Track webhook health (success rate, response time)
- `delivery_config` - Tunable parameters (timeouts, retry strategy, rate limits)

**Modified Tables:**
- `alert_delivery_queue` - Already exists from Week 1 ✓
- `alert_delivery_log` - Already exists from Week 1 ✓

**New Functions:**
- `pggit.acquire_delivery_for_worker()` - Lock and return next delivery
- `pggit.complete_delivery()` - Mark delivery complete with metrics
- `pggit.fail_delivery()` - Mark delivery failed, schedule retry
- `pggit.update_webhook_health()` - Update health metrics after attempt
- `pggit.get_webhook_decrypted()` - Decrypt webhook URL

**No HTTP functions in PostgreSQL** ← Key difference from original plan

### B. External Worker Service

**Language Choices:**
1. **Python** (easiest prototyping, requests library)
2. **Go** (best performance, goroutines native)
3. **Node.js** (good balance, async/await)

**Core Components:**

```
External Worker Service
├─ Connection Pool
│  ├─ PostgreSQL connection pool (10-20 connections)
│  └─ HTTP client with connection pooling
├─ Worker Pool
│  ├─ N concurrent workers (default 10)
│  └─ Queue processing (pull, process, update)
├─ Rate Limiter
│  ├─ Per-webhook rate limits
│  ├─ Token bucket algorithm
│  └─ Backoff strategy (exponential, jitter)
├─ Circuit Breaker
│  ├─ Track webhook failures
│  ├─ Open circuit on threshold
│  └─ Half-open recovery window
├─ Metrics Exporter
│  ├─ Prometheus metrics
│  ├─ Delivery latency distribution
│  └─ Error rate per webhook
├─ Structured Logging
│  ├─ JSON format (for log aggregation)
│  ├─ Correlation IDs
│  └─ Severity levels (DEBUG, INFO, WARN, ERROR)
└─ Health Check
   ├─ Liveness probe (is worker running?)
   ├─ Readiness probe (can accept deliveries?)
   └─ Startup probe (initialization complete?)
```

---

## Data Flow

### Complete Delivery Workflow

```
1. ALERT GENERATION (Week 4)
   └─ INSERT into alert_notification_queue
      └─ TRIGGER fires (Week 1 integration)
         └─ pggit.observer_queue_alert()
            └─ INSERT into alert_delivery_queue (status='pending')

2. DATABASE READY
   alert_delivery_queue has alerts waiting:
   ┌─────────────────────────────────────┐
   │ delivery_id │ webhook_id │ status  │
   ├─────────────────────────────────────┤
   │ 1           │ 42         │ pending │
   │ 2           │ 43         │ pending │
   │ 3           │ 42         │ pending │
   └─────────────────────────────────────┘

3. WORKER POLL (Every 1 second, 10 workers)

   Worker 1:
   ┌─────────────────────────────────────────────────────┐
   │ SELECT * FROM alert_delivery_queue                  │
   │ WHERE delivery_status = 'pending'                   │
   │ ORDER BY created_at ASC                             │
   │ FOR UPDATE SKIP LOCKED                              │
   │ LIMIT 1;                                            │
   │                                                      │
   │ ✓ Gets delivery_id=1 (webhook_id=42)                │
   │ ✓ LOCK acquired (other workers skip this row)       │
   └─────────────────────────────────────────────────────┘

   Worker 2:
   ┌─────────────────────────────────────────────────────┐
   │ SELECT * FROM alert_delivery_queue ...              │
   │ FOR UPDATE SKIP LOCKED LIMIT 1;                     │
   │                                                      │
   │ ✓ Gets delivery_id=2 (webhook_id=43)                │
   │ ✓ LOCK acquired (delivery_id=1 locked by Worker 1)  │
   └─────────────────────────────────────────────────────┘

   Worker 3:
   ┌─────────────────────────────────────────────────────┐
   │ SELECT * FROM alert_delivery_queue ...              │
   │ FOR UPDATE SKIP LOCKED LIMIT 1;                     │
   │                                                      │
   │ ✓ Gets delivery_id=3 (webhook_id=42)                │
   │ ✓ LOCK acquired                                     │
   └─────────────────────────────────────────────────────┘

4. WORKER PROCESS (In Parallel)

   Worker 1: HTTP POST to webhook 42
   ├─ Decrypt webhook URL: https://slack.com/hooks/...
   ├─ Build request: POST JSON payload
   ├─ Send HTTP: 200 OK in 150ms
   ├─ Log attempt: alert_delivery_log (event='delivered')
   └─ Update status: alert_delivery_queue (status='delivered')

   Worker 2: HTTP POST to webhook 43
   ├─ Decrypt webhook URL: https://mattermost.com/hooks/...
   ├─ Build request: POST JSON payload
   ├─ Send HTTP: 500 Internal Server Error in 5000ms
   ├─ Check retry_count: 0 < max_retries (3)
   ├─ Log attempt: alert_delivery_log (event='retrying')
   ├─ Calculate next_retry_at: NOW() + 5 minutes
   └─ Update status: alert_delivery_queue (status='retrying', retry_count=1)

   Worker 3: HTTP POST to webhook 42
   ├─ Similar to Worker 1 (concurrent, independent)

5. DATABASE UPDATED (Atomic from worker perspective)

   ┌─────────────────────────────────────────────┐
   │ delivery_id │ status     │ retry_count       │
   ├─────────────────────────────────────────────┤
   │ 1           │ delivered  │ 0 (no retries)    │
   │ 2           │ retrying   │ 1 (retry 1/3)     │
   │ 3           │ delivered  │ 0 (no retries)    │
   └─────────────────────────────────────────────┘

6. HEALTH METRICS UPDATED (Per-webhook tracking)

   ┌──────────────────────────────────────────────┐
   │ webhook_id │ successful │ failed │ avg_ms   │
   ├──────────────────────────────────────────────┤
   │ 42         │ 2          │ 0      │ 160      │
   │ 43         │ 0          │ 1      │ 5000     │
   └──────────────────────────────────────────────┘

7. RETRY PROCESSOR (Runs every 5 minutes, workers can also trigger)

   SELECT * FROM alert_delivery_queue
   WHERE delivery_status = 'retrying'
     AND next_retry_at <= NOW()
   ORDER BY next_retry_at ASC
   LIMIT 50;

   ✓ delivery_id=2 is ready (next_retry_at = NOW() - 0.5min)

   Worker 4 picks it up, retries HTTP POST
   ├─ 2nd attempt: 200 OK
   ├─ Update: status='delivered', retry_count=1
   └─ Log: alert_delivery_log (event='delivered', attempt_number=2)

8. FINAL STATE

   ┌────────────────────────────────────────────┐
   │ delivery_id │ status     │ delivered_at    │
   ├────────────────────────────────────────────┤
   │ 1           │ delivered  │ 2025-12-27 ...  │
   │ 2           │ delivered  │ 2025-12-27 ...  │
   │ 3           │ delivered  │ 2025-12-27 ...  │
   └────────────────────────────────────────────┘

   Audit trail in alert_delivery_log:
   ┌────────────┬────────────┬──────────────┐
   │ delivery_id│ event_type │ created_at   │
   ├────────────┼────────────┼──────────────┤
   │ 1          │ attempt    │ 2025-12-27 1 │
   │ 1          │ delivered  │ 2025-12-27 1 │
   │ 2          │ attempt    │ 2025-12-27 2 │
   │ 2          │ retrying   │ 2025-12-27 2 │
   │ 2          │ attempt    │ 2025-12-27 7 │
   │ 2          │ delivered  │ 2025-12-27 7 │
   │ 3          │ attempt    │ 2025-12-27 3 │
   │ 3          │ delivered  │ 2025-12-27 3 │
   └────────────┴────────────┴──────────────┘
```

---

## External Worker Service Design

### Implementation Language Recommendation

**Recommendation: Python (asyncio) or Go (goroutines)**

**Python Advantages:**
- Fast to implement (async/await is elegant)
- requests-httpx libraries mature
- Familiar to most teams
- Easy debugging (excellent stack traces)
- Smaller binary size

**Python Example:**

```python
# webhooks_worker.py
import asyncio
import aiohttp
import psycopg
from datetime import datetime, timedelta
import logging
import json

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

class WebhookWorker:
    def __init__(self, worker_id: int, db_url: str, num_workers: int = 10):
        self.worker_id = worker_id
        self.db_url = db_url
        self.num_workers = num_workers
        self.db_conn = None
        self.http_session = None

        # Rate limiting
        self.rate_limiters = {}  # per-webhook token buckets
        self.circuit_breakers = {}  # per-webhook circuit state

    async def initialize(self):
        """Initialize connections"""
        self.db_conn = await psycopg.AsyncConnection.connect(self.db_url)
        self.http_session = aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(limit=10),  # connection pool
            timeout=aiohttp.ClientTimeout(total=5.0)  # 5 second timeout
        )
        logger.info(f"Worker {self.worker_id} initialized")

    async def acquire_delivery(self):
        """Get next delivery from queue (lock-free via SKIP LOCKED)"""
        async with self.db_conn.cursor() as cur:
            await cur.execute("""
                SELECT
                    delivery_id,
                    alert_id,
                    webhook_id,
                    message_body,
                    retry_count,
                    max_retries
                FROM pggit.alert_delivery_queue
                WHERE delivery_status = 'pending'
                   OR (delivery_status = 'retrying' AND next_retry_at <= NOW())
                ORDER BY created_at ASC
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            """)
            return await cur.fetchone()

    async def get_webhook_url(self, webhook_id: int) -> str:
        """Decrypt webhook URL from database"""
        async with self.db_conn.cursor() as cur:
            await cur.execute(
                "SELECT pggit.get_webhook_decrypted(%s)",
                (webhook_id,)
            )
            url = await cur.fetchone()
            return url[0] if url else None

    async def rate_limit_check(self, webhook_id: int) -> bool:
        """Check if webhook is rate limited"""
        # Get webhook's rate limit config from database
        # Implement token bucket algorithm
        # Return True if allowed, False if rate limited

        if webhook_id not in self.rate_limiters:
            # Initialize: 10 requests per second, max burst 20
            self.rate_limiters[webhook_id] = {
                'limit': 10,  # requests per second
                'burst': 20,  # max queued
                'tokens': 20,
                'last_refill': datetime.now()
            }

        limiter = self.rate_limiters[webhook_id]
        now = datetime.now()
        elapsed = (now - limiter['last_refill']).total_seconds()

        # Refill tokens
        limiter['tokens'] = min(
            limiter['burst'],
            limiter['tokens'] + (elapsed * limiter['limit'])
        )
        limiter['last_refill'] = now

        # Check token availability
        if limiter['tokens'] >= 1:
            limiter['tokens'] -= 1
            return True
        return False

    async def circuit_breaker_check(self, webhook_id: int) -> bool:
        """Check circuit breaker status (prevent thundering herd)"""
        if webhook_id not in self.circuit_breakers:
            self.circuit_breakers[webhook_id] = {
                'state': 'closed',  # closed, open, half_open
                'failure_count': 0,
                'opened_at': None
            }

        breaker = self.circuit_breakers[webhook_id]

        # If open, check if cooldown expired
        if breaker['state'] == 'open':
            opened_at = breaker['opened_at']
            if (datetime.now() - opened_at) > timedelta(minutes=5):
                breaker['state'] = 'half_open'  # Try recovery
                logger.info(f"Circuit breaker entering half-open for webhook {webhook_id}")
            else:
                return False  # Still open, skip delivery

        return True  # closed or half_open

    async def post_webhook(self, webhook_url: str, message_body: dict,
                          webhook_id: int, delivery_id: int) -> tuple[int, str, int]:
        """POST to webhook endpoint, return (http_status, response_body, response_time_ms)"""

        try:
            start = datetime.now()

            async with self.http_session.post(
                webhook_url,
                json=message_body,
                headers={
                    'Content-Type': 'application/json',
                    'User-Agent': 'pggit-webhook-worker/1.0',
                    'X-PGGit-Delivery-ID': str(delivery_id),
                    'X-PGGit-Idempotency-Key': f"{delivery_id}-attempt-{message_body.get('retry_count', 0)}"
                }
            ) as response:
                response_body = await response.text()
                elapsed_ms = int((datetime.now() - start).total_seconds() * 1000)

                logger.info(f"Webhook {webhook_id} returned {response.status} in {elapsed_ms}ms")

                return response.status, response_body, elapsed_ms

        except asyncio.TimeoutError:
            elapsed_ms = int((datetime.now() - start).total_seconds() * 1000)
            logger.warning(f"Webhook {webhook_id} timeout after {elapsed_ms}ms")
            return 0, "Timeout", elapsed_ms
        except Exception as e:
            elapsed_ms = int((datetime.now() - start).total_seconds() * 1000)
            logger.error(f"Webhook {webhook_id} error: {str(e)}")
            return 0, str(e), elapsed_ms

    async def complete_delivery(self, delivery_id: int, http_status: int,
                               response_time_ms: int, webhook_id: int):
        """Mark delivery successful"""
        async with self.db_conn.cursor() as cur:
            # Update delivery status
            await cur.execute("""
                UPDATE pggit.alert_delivery_queue
                SET delivery_status = 'delivered',
                    delivered_at = NOW(),
                    attempted_at = NOW()
                WHERE delivery_id = %s
            """, (delivery_id,))

            # Update health metrics
            await cur.execute("""
                SELECT pggit.update_webhook_health(%s, %s, %s, NULL)
            """, (webhook_id, http_status, response_time_ms))

            # Log to audit trail
            await cur.execute("""
                INSERT INTO pggit.alert_delivery_log
                (delivery_id, webhook_id, event_type, event_details, created_at)
                VALUES (%s, %s, 'delivered',
                    %s::jsonb,
                    NOW())
            """, (delivery_id, webhook_id,
                  json.dumps({'http_status': http_status, 'response_time_ms': response_time_ms})))

            await self.db_conn.commit()

    async def fail_delivery(self, delivery_id: int, http_status: int,
                           response_time_ms: int, webhook_id: int,
                           retry_count: int, max_retries: int, error_msg: str):
        """Mark delivery failed or schedule retry"""
        async with self.db_conn.cursor() as cur:
            if retry_count < max_retries:
                # Schedule retry with exponential backoff
                backoff_seconds = 5 * (2 ** retry_count)  # 5s, 10s, 20s...

                await cur.execute("""
                    UPDATE pggit.alert_delivery_queue
                    SET delivery_status = 'retrying',
                        retry_count = retry_count + 1,
                        next_retry_at = NOW() + INTERVAL '%s seconds',
                        attempted_at = NOW()
                    WHERE delivery_id = %s
                """, (backoff_seconds, delivery_id))

                status = 'retrying'
            else:
                # Max retries exceeded
                await cur.execute("""
                    UPDATE pggit.alert_delivery_queue
                    SET delivery_status = 'failed',
                        attempted_at = NOW()
                    WHERE delivery_id = %s
                """, (delivery_id,))

                status = 'failed'

            # Update health metrics
            await cur.execute("""
                SELECT pggit.update_webhook_health(%s, %s, %s, %s)
            """, (webhook_id, http_status, response_time_ms, error_msg))

            # Log to audit trail
            await cur.execute("""
                INSERT INTO pggit.alert_delivery_log
                (delivery_id, webhook_id, event_type, event_details, created_at)
                VALUES (%s, %s, %s,
                    %s::jsonb,
                    NOW())
            """, (delivery_id, webhook_id, status,
                  json.dumps({
                      'http_status': http_status,
                      'response_time_ms': response_time_ms,
                      'error': error_msg,
                      'retry_count': retry_count + (1 if status == 'retrying' else 0),
                      'max_retries': max_retries
                  })))

            await self.db_conn.commit()

    async def process_delivery(self, delivery: tuple):
        """Process a single delivery"""
        delivery_id, alert_id, webhook_id, message_body, retry_count, max_retries = delivery

        logger.info(f"Worker {self.worker_id} processing delivery {delivery_id} to webhook {webhook_id}")

        try:
            # Check rate limiting
            if not await self.rate_limit_check(webhook_id):
                logger.warning(f"Delivery {delivery_id} rate limited, rescheduling")
                # Reschedule for later
                async with self.db_conn.cursor() as cur:
                    await cur.execute("""
                        UPDATE pggit.alert_delivery_queue
                        SET next_retry_at = NOW() + INTERVAL '1 second'
                        WHERE delivery_id = %s
                    """, (delivery_id,))
                    await self.db_conn.commit()
                return

            # Check circuit breaker
            if not await self.circuit_breaker_check(webhook_id):
                logger.warning(f"Circuit breaker open for webhook {webhook_id}")
                # Reschedule
                async with self.db_conn.cursor() as cur:
                    await cur.execute("""
                        UPDATE pggit.alert_delivery_queue
                        SET next_retry_at = NOW() + INTERVAL '1 minute'
                        WHERE delivery_id = %s
                    """, (delivery_id,))
                    await self.db_conn.commit()
                return

            # Get webhook URL
            webhook_url = await self.get_webhook_url(webhook_id)
            if not webhook_url:
                logger.error(f"Webhook {webhook_id} not found for delivery {delivery_id}")
                await self.fail_delivery(delivery_id, 0, 0, webhook_id,
                                        retry_count, max_retries,
                                        "Webhook URL not found")
                return

            # POST to webhook
            http_status, response_body, response_time_ms = await self.post_webhook(
                webhook_url, message_body, webhook_id, delivery_id
            )

            # Determine next state based on HTTP status
            if 200 <= http_status < 300:
                # Success
                await self.complete_delivery(delivery_id, http_status,
                                            response_time_ms, webhook_id)
                logger.info(f"Delivery {delivery_id} completed successfully")

            elif http_status >= 500 or http_status == 0:
                # Server error or timeout - retry
                await self.fail_delivery(delivery_id, http_status,
                                        response_time_ms, webhook_id,
                                        retry_count, max_retries,
                                        f"Server error: {response_body[:100]}")
                logger.warning(f"Delivery {delivery_id} will retry (status {http_status})")

            else:
                # Client error - permanent failure
                await self.fail_delivery(delivery_id, http_status,
                                        response_time_ms, webhook_id,
                                        max_retries, max_retries,  # Skip retries
                                        f"Client error: {response_body[:100]}")
                logger.error(f"Delivery {delivery_id} failed permanently (status {http_status})")

        except Exception as e:
            logger.error(f"Error processing delivery {delivery_id}: {str(e)}")
            await self.fail_delivery(delivery_id, 0, 0, webhook_id,
                                    retry_count, max_retries,
                                    str(e))

    async def run(self):
        """Main worker loop"""
        await self.initialize()

        logger.info(f"Worker {self.worker_id} started")

        while True:
            try:
                # Acquire next delivery
                delivery = await self.acquire_delivery()

                if delivery:
                    # Process it
                    await self.process_delivery(delivery)
                else:
                    # No deliveries, sleep briefly before polling again
                    await asyncio.sleep(1)

            except Exception as e:
                logger.error(f"Worker {self.worker_id} error: {str(e)}")
                await asyncio.sleep(1)  # Back off on error

async def main():
    """Run N workers concurrently"""
    db_url = "postgresql://user:password@localhost/pggit"
    num_workers = 10

    workers = [
        WebhookWorker(i, db_url, num_workers)
        for i in range(num_workers)
    ]

    tasks = [worker.run() for worker in workers]
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
```

### Go Implementation

```go
// webhooks_worker.go
package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
)

type WebhookWorker struct {
	id        int
	dbPool    *pgx.ConnPool
	httpClient *http.Client
	rateLimiters map[int]*TokenBucket
	circuitBreakers map[int]*CircuitBreaker
	mu        sync.Mutex
}

func (w *WebhookWorker) acquireDelivery(ctx context.Context) (*Delivery, error) {
	row := w.dbPool.QueryRow(ctx, `
		SELECT
			delivery_id,
			alert_id,
			webhook_id,
			message_body,
			retry_count,
			max_retries
		FROM pggit.alert_delivery_queue
		WHERE delivery_status = 'pending'
		   OR (delivery_status = 'retrying' AND next_retry_at <= NOW())
		ORDER BY created_at ASC
		FOR UPDATE SKIP LOCKED
		LIMIT 1
	`)

	var delivery Delivery
	err := row.Scan(&delivery.ID, &delivery.AlertID, &delivery.WebhookID,
		&delivery.MessageBody, &delivery.RetryCount, &delivery.MaxRetries)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil // No deliveries available
		}
		return nil, err
	}

	return &delivery, nil
}

func (w *WebhookWorker) postWebhook(ctx context.Context, url string,
	message interface{}, webhookID int, deliveryID int) (int, string, int) {

	start := time.Now()

	// Implementation...
	// Returns (status, body, time_ms)
}

func (w *WebhookWorker) run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
			// Acquire delivery with timeout
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			delivery, err := w.acquireDelivery(ctx)
			cancel()

			if err != nil {
				log.Printf("Worker %d: error acquiring delivery: %v", w.id, err)
				time.Sleep(1 * time.Second)
				continue
			}

			if delivery == nil {
				// No deliveries, sleep before polling again
				time.Sleep(1 * time.Second)
				continue
			}

			// Process delivery (non-blocking, async)
			go w.processDelivery(ctx, delivery)
		}
	}
}

// Simpler to implement with goroutines!
```

### Key Worker Features

1. **Connection Pooling**
   - PostgreSQL: 10-20 connections, auto-reuse
   - HTTP: Keep-alive, connection pooling

2. **Rate Limiting**
   - Per-webhook token bucket (N requests/sec)
   - Prevents webhook overload
   - Configurable per webhook

3. **Circuit Breaker**
   - Auto-disable failing webhooks
   - Prevents cascading failures
   - Auto-recovery with health checks

4. **Retry Strategy**
   - Exponential backoff: 5s, 10s, 20s, 40s (capped at 30 min)
   - Jitter to prevent thundering herd
   - Configurable per webhook

5. **Observability**
   - Prometheus metrics: requests/sec, latency, errors
   - Structured JSON logging (correlation IDs)
   - Liveness/readiness probes

---

## PostgreSQL Schema & Functions

### Required PostgreSQL Functions (Minimal)

```sql
-- Function 1: Decrypt webhook URL
CREATE OR REPLACE FUNCTION pggit.get_webhook_decrypted(
    p_webhook_id BIGINT
)
RETURNS TEXT AS $$
BEGIN
    -- Week 2: Stub (returns dummy URL)
    -- Week 3: Implement actual PGP decryption
    RETURN 'https://hooks.example.com/webhook/' || p_webhook_id::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Function 2: Update webhook health metrics
CREATE OR REPLACE FUNCTION pggit.update_webhook_health(
    p_webhook_id BIGINT,
    p_http_status INT,
    p_response_time_ms INT,
    p_error_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Insert or update health metrics
    INSERT INTO pggit.webhook_health_metrics (
        webhook_id, total_deliveries, successful_deliveries,
        failed_deliveries, avg_response_time_ms, health_status,
        last_check_at, last_success_at, last_failure_at,
        consecutive_failures, created_at, updated_at
    ) VALUES (
        p_webhook_id,
        1,  -- total_deliveries
        CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN 1 ELSE 0 END,
        CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN 0 ELSE 1 END,
        p_response_time_ms,
        CASE
            WHEN p_http_status >= 200 AND p_http_status < 300 THEN 'healthy'
            WHEN p_http_status >= 500 OR p_http_status = 0 THEN 'degraded'
            ELSE 'unavailable'
        END,
        NOW(), NOW(),
        CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN NULL ELSE NOW() END,
        CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN 0 ELSE 1 END,
        NOW(), NOW()
    )
    ON CONFLICT (webhook_id) DO UPDATE SET
        total_deliveries = webhook_health_metrics.total_deliveries + 1,
        successful_deliveries = webhook_health_metrics.successful_deliveries +
            CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN 1 ELSE 0 END,
        failed_deliveries = webhook_health_metrics.failed_deliveries +
            CASE WHEN p_http_status >= 200 AND p_http_status < 300 THEN 0 ELSE 1 END,
        avg_response_time_ms = (
            webhook_health_metrics.avg_response_time_ms * webhook_health_metrics.total_deliveries +
            p_response_time_ms
        ) / (webhook_health_metrics.total_deliveries + 1),
        health_status = CASE
            WHEN p_http_status >= 200 AND p_http_status < 300 THEN 'healthy'
            WHEN p_http_status >= 500 OR p_http_status = 0 THEN 'degraded'
            ELSE 'unavailable'
        END,
        last_check_at = NOW(),
        last_success_at = CASE WHEN p_http_status >= 200 AND p_http_status < 300
            THEN NOW() ELSE webhook_health_metrics.last_success_at END,
        last_failure_at = CASE WHEN p_http_status >= 200 AND p_http_status < 300
            THEN webhook_health_metrics.last_failure_at ELSE NOW() END,
        consecutive_failures = CASE
            WHEN p_http_status >= 200 AND p_http_status < 300 THEN 0
            ELSE webhook_health_metrics.consecutive_failures + 1
        END,
        updated_at = NOW();

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### No In-Database HTTP Functions

**Key Point**: Week 2 PostgreSQL has **NO HTTP functions**.

All HTTP logic is in the external worker service.

---

## Deployment Architecture

### Single Node Deployment

```
┌──────────────────────────────┐
│ Server (VM / Bare Metal)     │
│                              │
│  ┌────────────────────────┐  │
│  │ PostgreSQL             │  │
│  │ :5432                  │  │
│  │                        │  │
│  │ - alert_delivery_queue │  │
│  │ - webhook_health_*     │  │
│  │ - alert_delivery_log   │  │
│  └────────────────────────┘  │
│           ▲                   │
│           │ Port 5432         │
│           │                   │
│  ┌────────┴────────────────┐  │
│  │ Webhook Worker Service  │  │
│  │ (Python/Go)             │  │
│  │ :8080 (metrics)         │  │
│  │                         │  │
│  │ ┌─────────────────────┐ │  │
│  │ │ Worker Pool (N=10)  │ │  │
│  │ │                     │ │  │
│  │ │ - Rate limiter      │ │  │
│  │ │ - Circuit breaker   │ │  │
│  │ │ - Async HTTP client │ │  │
│  │ └─────────────────────┘ │  │
│  └─────────────────────────┘  │
│                              │
└──────────────────────────────┘
        │
        │ HTTP POST
        ▼
   Webhook Endpoints
   (Slack, Mattermost, etc.)
```

### Kubernetes Deployment (Production)

```
┌──────────────────────────────────────────────────┐
│ Kubernetes Cluster                               │
│                                                  │
│  ┌─────────────────────────────────────────┐   │
│  │ Persistent Volume: PostgreSQL Data      │   │
│  └─────────────────────────────────────────┘   │
│           ▲                                      │
│           │ (mounted)                            │
│           │                                      │
│  ┌────────┴──────────────────────────────────┐  │
│  │ StatefulSet: PostgreSQL                  │  │
│  │ Replicas: 1 (primary) + 1 (replica)      │  │
│  │ Service: postgres-service:5432            │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ Deployment: Webhook Workers               │  │
│  │ Replicas: 10 (autoscaled 5-20)            │  │
│  │ Image: webhook-worker:latest              │  │
│  │ Resources:                                 │  │
│  │   - CPU: 100m per pod                     │  │
│  │   - Memory: 256Mi per pod                 │  │
│  │                                           │  │
│  │ ┌──────────────────────────────────────┐ │  │
│  │ │ Pod 1: Webhook Worker               │ │  │
│  │ │ - Liveness probe: /health           │ │  │
│  │ │ - Readiness probe: /ready           │ │  │
│  │ │ - Startup probe: /startup           │ │  │
│  │ │ - Metrics: :8080/metrics            │ │  │
│  │ └──────────────────────────────────────┘ │  │
│  │ ┌──────────────────────────────────────┐ │  │
│  │ │ Pod 2: Webhook Worker               │ │  │
│  │ │ ... (N more pods)                   │ │  │
│  │ └──────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ Service: webhook-worker-service:8080      │  │
│  │ (ClusterIP for internal access)            │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ ConfigMap: worker-config                  │  │
│  │ - DB connection string                     │  │
│  │ - Rate limit defaults                      │  │
│  │ - Circuit breaker thresholds               │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ Service Monitor (Prometheus Operator)      │  │
│  │ - Scrape metrics from workers              │  │
│  │ - Alert on failure rates                   │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
└──────────────────────────────────────────────────┘
```

### Docker Configuration

```dockerfile
# Dockerfile for webhook worker
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY webhooks_worker.py .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8080/health', timeout=1)"

EXPOSE 8080

CMD ["python", "webhooks_worker.py"]
```

```yaml
# docker-compose.yml for local development
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: pggit
      POSTGRES_USER: pggit
      POSTGRES_PASSWORD: pggit
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pggit"]
      interval: 10s
      timeout: 5s
      retries: 5

  webhook-worker-1:
    build: .
    environment:
      DATABASE_URL: postgresql://pggit:pggit@postgres:5432/pggit
      WORKER_ID: 1
      NUM_WORKERS: 3
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8001:8080"

  webhook-worker-2:
    build: .
    environment:
      DATABASE_URL: postgresql://pggit:pggit@postgres:5432/pggit
      WORKER_ID: 2
      NUM_WORKERS: 3
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8002:8080"

  webhook-worker-3:
    build: .
    environment:
      DATABASE_URL: postgresql://pggit:pggit@postgres:5432/pggit
      WORKER_ID: 3
      NUM_WORKERS: 3
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8003:8080"

volumes:
  postgres_data:
```

---

## Failure Modes & Recovery

### Failure Mode 1: Worker Crashes

**Scenario**: Worker process dies while processing delivery

**Automatic Recovery**:
- PostgreSQL lock released immediately (worker disconnection)
- `FOR UPDATE SKIP LOCKED` prevents other workers from acquiring locked row
- Next worker poll picks up the delivery (max 1 second delay)

```
Worker 1: SELECT ... FOR UPDATE → Gets delivery_id=5
          (processing in progress)

❌ Worker 1 crashes

PostgreSQL automatically releases lock

Worker 2: SELECT ... FOR UPDATE → Gets delivery_id=5 (retry)
          Completes delivery successfully
```

### Failure Mode 2: PostgreSQL Connection Lost

**Scenario**: Worker loses DB connection mid-delivery

**Recovery**:
```python
try:
    await self.complete_delivery(...)
except Exception as e:
    logger.error(f"DB connection error: {e}")
    # Reconnect and retry
    await self.db_conn.close()
    self.db_conn = await psycopg.AsyncConnection.connect(self.db_url)
    # Retry the delivery (since it wasn't committed)
```

### Failure Mode 3: Webhook Endpoint Down for Hours

**Scenario**: External webhook service down, many deliveries queued

**Automatic Handling**:
1. **Circuit Breaker Opens** after 10 consecutive failures
2. **Deliveries Rescheduled** to next_retry_at (5min, 10min, 20min intervals)
3. **Health Status** marked as 'unavailable'
4. **Alerts Generated** (from Phase 7) when webhook unavailable >30 min
5. **Workers Don't Waste Resources** (circuit breaker prevents attempts)

```sql
SELECT COUNT(*) FROM pggit.alert_delivery_queue
WHERE webhook_id = 42 AND delivery_status IN ('retrying', 'pending');
-- Result: 1,247 deliveries waiting for webhook 42

SELECT * FROM pggit.webhook_health_metrics
WHERE webhook_id = 42;
-- health_status: unavailable
-- consecutive_failures: 47
-- last_check_at: 2025-12-27 14:30:00
```

### Failure Mode 4: Rate Limiting

**Scenario**: Webhook endpoint returns HTTP 429 (Too Many Requests)

**Worker Response**:
```python
if http_status == 429:
    # Parse Retry-After header if present
    retry_after = response.headers.get('Retry-After', 60)  # seconds

    # Reschedule with respect to Retry-After
    next_retry_at = datetime.now() + timedelta(seconds=int(retry_after))

    # Don't count against max_retries (it's not a failure)
    await db.execute("""
        UPDATE alert_delivery_queue
        SET next_retry_at = %s,
            delivery_status = 'retrying'
        WHERE delivery_id = %s
    """, (next_retry_at, delivery_id))
```

---

## Implementation Plan

### Phase 8 Week 2A: Architecture & Setup (3-4 hours)

**Task 1: Create PostgreSQL Minimal Schema** (1 hour)
- Add `webhook_health_metrics` table
- Add `update_webhook_health()` function
- Add `get_webhook_decrypted()` stub
- Fix `alert_delivery_queue` constraints

**Task 2: Implement External Worker Service** (2 hours)
- Choose language (Python asyncio recommended)
- Implement worker pool (N concurrent workers)
- Implement rate limiter (token bucket)
- Implement circuit breaker
- Implement metrics exporter (Prometheus)

**Task 3: Docker Setup** (0.5-1 hour)
- Create Dockerfile for worker service
- Create docker-compose.yml for local development
- Test worker service locally

### Phase 8 Week 2B: Integration & Testing (4-6 hours)

**Task 4: Integration with Week 1** (1 hour)
- Verify Week 1 trigger still queues deliveries
- Test end-to-end flow: alert → queue → worker → delivered

**Task 5: Testing** (2-3 hours)
- Unit tests: rate limiter, circuit breaker
- Integration tests: full delivery workflow
- Load tests: 100+ concurrent deliveries
- Failure scenario tests: worker crash, DB disconnect, webhook timeout

**Task 6: Monitoring & Observability** (1-2 hours)
- Set up Prometheus metrics collection
- Create Grafana dashboard
- Create alerting rules (failure rate > 5%)
- Structured logging (JSON format)

### Phase 8 Week 2C: Production Hardening (2-3 hours)

**Task 7: Security Hardening** (1 hour)
- SSRF protection (URL validation)
- Connection pool limits
- Response body redaction in logs
- Secret management for webhook URLs

**Task 8: Deployment Guide** (1 hour)
- Local development guide
- Docker Compose deployment
- Kubernetes deployment guide
- Troubleshooting guide

**Task 9: Documentation** (0.5-1 hour)
- API documentation for workers
- Configuration guide
- Operational runbooks

### Total Revised Estimate: **9-13 hours** (vs original 3-5 hours)

---

## Performance Targets

### Delivery Latency

| Metric | Target | Notes |
|--------|--------|-------|
| Queue to Worker | <100ms | Worker poll every 1 second |
| HTTP POST | <1 second | Mostly network time |
| Database Update | <50ms | Single UPDATE + health metrics |
| Total E2E | <2 seconds | P95 latency |

### Throughput

| Metric | Target | Notes |
|--------|--------|-------|
| Single Worker | 10 deliveries/sec | 100ms per delivery |
| 10 Workers | 100 deliveries/sec | Linear scaling |
| 20 Workers | 200 deliveries/sec | Kubernetes autoscaling |
| Max Sustained | 500+ deliveries/sec | DB connection pool limit |

### Resource Usage

| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| PostgreSQL | 20% avg | 500MB | ~10 deliveries/sec |
| Worker Pod | 100m | 256MB | Single worker |
| 10 Workers | 1000m | 2.5GB | Typical deployment |

### Reliability

| Metric | Target |
|--------|--------|
| Uptime | 99.9% |
| Delivery Success Rate | >99% (after retries) |
| P99 Latency | <5 seconds |
| Worker Restarts | <1 per day |

---

## Next Steps

### Immediate Actions (This Week)

1. **Review & Approve Architecture**
   - Confirm external worker pattern is acceptable
   - Choose preferred language (Python/Go)
   - Discuss deployment strategy (Docker Compose vs Kubernetes)

2. **Create Implementation Roadmap**
   - Break down Week 2A/2B/2C tasks
   - Assign team members
   - Set delivery milestones

3. **Prepare PostgreSQL Schema**
   - Design `webhook_health_metrics` table
   - Create `get_webhook_decrypted()` function
   - Fix constraints in `alert_delivery_queue`

### Week 2 Implementation

- Week 2A: PostgreSQL schema + worker service framework (3-4 hours)
- Week 2B: Integration testing + load testing (4-6 hours)
- Week 2C: Production hardening + documentation (2-3 hours)

### Post-Week 2

- Week 3: Advanced features (rate limiting per webhook, encryption key rotation, HMAC signing)
- Week 4: Multi-region deployment, disaster recovery
- Week 5+: Analytics, ML-based retry optimization, webhook health prediction

---

## Appendix: Comparison Matrix

| Aspect | Week 1 (Simulation) | Original Week 2 Plan | Revised Architecture |
|--------|-------------------|---------------------|----------------------|
| **HTTP Calls** | None (simulated) | In PostgreSQL | External Worker |
| **Blocking** | No | Yes (5s per call) | No |
| **Scalability** | N/A (simulated) | Limited by DB connections | Linear (add workers) |
| **Retry Logic** | Exponential backoff | In PostgreSQL | In Worker |
| **Health Tracking** | None | In Database | Both DB + Worker |
| **Rate Limiting** | None | None | Token bucket per webhook |
| **Circuit Breaker** | None | None | Yes (auto-disable failing webhooks) |
| **Production Ready** | POC only | No (blocking issue) | Yes |
| **Deployment Complexity** | Simple | Medium | Medium (more components) |
| **Observability** | Basic | Audit logs | Prometheus + structured logs |
| **Development Time** | 3-5 hours | 11-18 hours (with fixes) | 9-13 hours (revised scope) |

---

## Sign-Off

**Architecture Status**: ✅ **READY FOR REVIEW & APPROVAL**

This architecture document proposes a **hybrid PostgreSQL + External Worker** design that:

- ✅ Solves the blocking HTTP issue (expert consensus)
- ✅ Provides production-grade reliability, scalability, observability
- ✅ Requires realistic implementation timeline (9-13 hours)
- ✅ Supports operational needs (metrics, alerts, health checks)
- ✅ Enables horizontal scaling (add workers as demand grows)

**Ready for Week 2 implementation upon approval.**

