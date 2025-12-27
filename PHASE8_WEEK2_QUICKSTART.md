# Phase 8 Week 2: Hybrid Webhook Architecture - Quick Start Guide

## Overview

This guide walks you through setting up and testing the Phase 8 Week 2A implementation:
- **PostgreSQL Side**: Webhook health tracking and queue management
- **External Worker Side**: Async Python service that delivers webhooks
- **Observability**: Prometheus metrics and structured logging

## Files Created

### PostgreSQL Schema
- `sql/v1.0.0/phase8_week2_postgres_schema.sql` - Table, functions, views (560 lines)

### External Worker Service
- `services/webhook_worker.py` - Async HTTP delivery worker (850+ lines)
- `services/requirements.txt` - Python dependencies
- `services/Dockerfile` - Container image definition

### Docker Configuration
- `docker-compose.yml` - Local environment setup (3 workers + PostgreSQL)
- `.env.local` - Development environment variables

## Quick Start: Launch Local Environment

### Prerequisites
- Docker and Docker Compose installed
- Port 5432 (PostgreSQL), 8000-8002 (metrics) available

### 1. Start the Services

```bash
cd /home/lionel/code/pggit

# Build images and start services
docker-compose up --build

# In another terminal, verify PostgreSQL is ready
docker-compose exec postgres pg_isready
```

Expected output:
```
pggit-postgres is accepting connections
```

### 2. Verify PostgreSQL Schema

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres -d pggit

# List webhook health metrics table
\dt pggit.webhook_health_metrics

# List functions
\df pggit.

# Test get_webhook_decrypted function
SELECT pggit.get_webhook_decrypted(123);

# Exit
\q
```

### 3. Test Webhook Worker

Workers start automatically and begin polling for deliveries every 1 second.

```bash
# Check worker logs
docker-compose logs -f webhook-worker-1

# In another terminal, create test delivery
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

-- Insert a test alert into the queue
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
) VALUES (
    1, 100,
    jsonb_build_object('type', 'test', 'message', 'Hello webhook!'),
    'pending', 0, 3, CURRENT_TIMESTAMP
);

-- Check what's in the queue
SELECT * FROM pggit.alert_delivery_queue ORDER BY delivery_id DESC LIMIT 1;

-- Check worker health metrics
SELECT * FROM pggit.webhook_health_metrics WHERE webhook_id = 100;

EOF
```

### 4. Monitor Metrics

Workers expose Prometheus metrics on ports 8000-8002:

```bash
# Worker 1 metrics
curl http://localhost:8000/metrics | grep webhook_

# Worker 2 metrics
curl http://localhost:8001/metrics | grep webhook_

# Worker 3 metrics
curl http://localhost:8002/metrics | grep webhook_
```

Expected metrics:
- `webhook_deliveries_total{status="delivered",webhook_id="100"}` - Successful deliveries
- `webhook_delivery_duration_seconds{webhook_id="100"}` - Response time
- `webhook_queue_depth` - Pending deliveries
- `worker_health_status{worker_id="worker-1"}` - Worker health (1 = healthy)

## Architecture

### PostgreSQL Side (Database Queuing)

**Table: `webhook_health_metrics`**
- Tracks success rate, response time, consecutive failures per webhook
- Supports circuit breaker decisions

**Functions:**
- `get_webhook_decrypted(webhook_id)` - Retrieve webhook URL (stub for Week 2)
- `update_webhook_health()` - Record delivery results + update metrics
- `get_ready_deliveries(limit)` - Lock-free queue polling (FOR UPDATE SKIP LOCKED)
- `count_pending_by_status()` - Dashboard metric

### External Worker Side (Async HTTP)

**Features:**
- **Async I/O**: aiohttp + asyncpg for non-blocking operations
- **Rate Limiting**: Token bucket per webhook (10 req/sec default)
- **Circuit Breaker**: Opens after 5 consecutive failures (60s timeout)
- **Retry Logic**: Exponential backoff (5s, 10s, 20s, 40s)
- **SSRF Protection**: Validates URLs (HTTPS-only, no private IPs)
- **Metrics**: Prometheus counters, histograms, gauges

**Concurrency Model:**
- Multiple workers poll same queue without contention (FOR UPDATE SKIP LOCKED)
- Each worker processes batches independently
- Scales horizontally: add N workers for N x throughput

## Testing Scenarios

### Test 1: Single Delivery

```bash
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

-- Insert delivery
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
) VALUES (
    101, 200, jsonb_build_object('test', 'data'),
    'pending', 0, 3, CURRENT_TIMESTAMP
);

-- Wait 2 seconds for worker to process

-- Check result
SELECT * FROM pggit.v_webhook_performance WHERE webhook_id = 200;

-- Check health metrics
SELECT webhook_id, health_status, total_deliveries, successful_deliveries,
       avg_response_time_ms FROM pggit.webhook_health_metrics WHERE webhook_id = 200;

EOF
```

### Test 2: Rate Limiting

```bash
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

-- Insert 20 deliveries for same webhook (rate limited to 10 req/sec)
WITH delivery_ids AS (
    SELECT generate_series(1, 20) as seq
)
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
)
SELECT
    300 + seq, 300,
    jsonb_build_object('seq', seq),
    'pending', 0, 3, CURRENT_TIMESTAMP
FROM delivery_ids;

-- Wait 3 seconds for workers to process

-- Check delivery status (some may still be pending due to rate limit)
SELECT delivery_status, COUNT(*) as count
FROM pggit.alert_delivery_queue
WHERE webhook_id = 300
GROUP BY delivery_status;

EOF
```

### Test 3: Circuit Breaker (Simulated Failure)

Webhook workers detect HTTP status >= 500 as failures that open the circuit breaker:

```bash
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

-- Manually update webhook health to simulate 5 failures (opens circuit)
SELECT pggit.update_webhook_health(400, 500, 100, 'Server error');
SELECT pggit.update_webhook_health(400, 500, 100, 'Server error');
SELECT pggit.update_webhook_health(400, 500, 100, 'Server error');
SELECT pggit.update_webhook_health(400, 500, 100, 'Server error');
SELECT pggit.update_webhook_health(400, 500, 100, 'Server error');

-- Check health status (should be 'degraded' or 'unavailable')
SELECT webhook_id, health_status, consecutive_failures
FROM pggit.webhook_health_metrics
WHERE webhook_id = 400;

-- Check v_degraded_webhooks view
SELECT * FROM pggit.v_degraded_webhooks WHERE webhook_id = 400;

EOF
```

### Test 4: Multiple Workers (Concurrent Processing)

```bash
# Watch all three workers process deliveries simultaneously
docker-compose logs -f webhook-worker-1 webhook-worker-2 webhook-worker-3 | grep "delivery_id"
```

## Configuration

Edit `.env.local` to customize:

```bash
# Worker behavior
BATCH_SIZE=10              # Deliveries per poll
POLL_INTERVAL=1.0          # Seconds between polls
HTTP_TIMEOUT=5.0           # Seconds per HTTP request

# Rate limiting (per webhook)
RATE_LIMIT_RPS=10.0        # Requests per second

# Circuit breaker
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5      # Failures to open
CIRCUIT_BREAKER_TIMEOUT_SECONDS=60       # How long to stay open

# Logging
LOG_LEVEL=info             # debug, info, warning, error
```

Then restart services:
```bash
docker-compose down
docker-compose up --build
```

## Monitoring Dashboards

### PostgreSQL Metrics Dashboard

```bash
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

-- Queue status
SELECT * FROM pggit.count_pending_by_status();

-- Webhook health summary
SELECT * FROM pggit.v_webhook_health_dashboard;

-- Degraded webhooks (problems)
SELECT * FROM pggit.v_degraded_webhooks;

-- Performance overview
SELECT * FROM pggit.v_webhook_performance LIMIT 10;

EOF
```

### Worker Prometheus Metrics

```bash
# Summary of all workers
curl -s http://localhost:8000/metrics http://localhost:8001/metrics http://localhost:8002/metrics | grep "webhook_" | sort | uniq -c

# Success rate per worker
curl -s http://localhost:8000/metrics | grep "webhook_deliveries_total"
curl -s http://localhost:8001/metrics | grep "webhook_deliveries_total"
curl -s http://localhost:8002/metrics | grep "webhook_deliveries_total"
```

## Stopping Services

```bash
# Stop all services (keep data)
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v
```

## Troubleshooting

### Worker not processing deliveries

1. Check if PostgreSQL is healthy:
   ```bash
   docker-compose logs postgres
   ```

2. Check worker logs:
   ```bash
   docker-compose logs webhook-worker-1
   ```

3. Verify deliveries in queue:
   ```bash
   docker-compose exec postgres psql -U postgres -d pggit -c "SELECT COUNT(*) FROM pggit.alert_delivery_queue;"
   ```

### Metrics not appearing

1. Check metrics endpoint:
   ```bash
   curl http://localhost:8000/metrics
   ```

2. Verify worker is running:
   ```bash
   docker-compose ps
   ```

### PostgreSQL connection errors

1. Check PostgreSQL logs:
   ```bash
   docker-compose logs postgres
   ```

2. Verify database exists:
   ```bash
   docker-compose exec postgres psql -U postgres -l
   ```

## Next Steps

After verifying the local setup works:

1. **Phase 8 Week 2B: Integration Testing** - Test end-to-end workflows
2. **Phase 8 Week 2B: Load Testing** - Benchmark worker throughput
3. **Phase 8 Week 2C: Security Hardening** - Add URL encryption, authentication
4. **Deployment** - Move to staging/production environment

## References

- Architecture: `/home/lionel/code/pggit/PHASE8_WEEK2_ARCHITECTURE.md`
- PostgreSQL Schema: `/home/lionel/code/pggit/sql/v1.0.0/phase8_week2_postgres_schema.sql`
- Worker Service: `/home/lionel/code/pggit/services/webhook_worker.py`
- Docker Config: `/home/lionel/code/pggit/docker-compose.yml`
