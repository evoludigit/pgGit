# Phase 8 Week 2: Webhook Delivery - Monitoring & Observability

## Overview

This document covers comprehensive monitoring and observability setup for Phase 8 Week 2B webhook delivery architecture:
- **PostgreSQL Metrics**: Queue depth, health status, delivery rates
- **Worker Metrics**: Prometheus + Grafana for async webhook processing
- **Dashboards**: Real-time visibility into system health
- **Alerting**: Automated alerts for degraded webhooks and failures

## Architecture

```
Webhook Workers (3x)          PostgreSQL
  ├─ Prometheus Metrics          ├─ webhook_health_metrics table
  ├─ aiohttp client metrics      ├─ alert_delivery_queue table
  └─ Rate limit tracking         └─ Views: health dashboard, degraded webhooks

           ↓
    Prometheus Server (scrape)
           ↓
    Grafana Dashboards
           ↓
    Alertmanager (optional)
```

## 1. Prometheus Metrics in Worker Service

The webhook worker service (`webhook_worker.py`) exposes the following metrics on port 8000 (worker-1), 8001 (worker-2), 8002 (worker-3):

### Delivery Metrics

**`webhook_deliveries_total`** (Counter)
- Total number of webhook deliveries attempted
- Labels: `status` (delivered, failed, timeout), `webhook_id`
- Example: `webhook_deliveries_total{status="delivered",webhook_id="1001"} 42`

**`webhook_delivery_duration_seconds`** (Histogram)
- HTTP request duration per delivery
- Buckets: 0.01s, 0.05s, 0.1s, 0.5s, 1.0s, 2.0s, 5.0s
- Labels: `webhook_id`
- Allows calculation of p50, p99 response times

### Queue Metrics

**`webhook_queue_depth`** (Gauge)
- Number of pending deliveries in the queue
- Tracked per poll iteration
- Indicates backpressure when > batch size

### Worker Health

**`worker_health_status`** (Gauge)
- Worker health indicator (1 = healthy, 0 = error)
- Labels: `worker_id`
- Updates on each poll cycle

### Rate Limiting & Circuit Breaker

**`rate_limit_hits_total`** (Counter)
- Number of times rate limit was triggered
- Labels: `webhook_id`
- Helps identify problematic webhooks

**`circuit_breaker_opens_total`** (Counter)
- Number of circuit breaker opens
- Labels: `webhook_id`
- Correlates with health status transitions

## 2. PostgreSQL Observability

### Table: `webhook_health_metrics`

Tracks all metrics per webhook:
```sql
SELECT
    webhook_id,
    health_status,           -- healthy, degraded, unavailable
    total_deliveries,
    successful_deliveries,
    failed_deliveries,
    ROUND(100.0 * successful_deliveries /
          NULLIF(total_deliveries, 0), 2) as success_rate_pct,
    avg_response_time_ms,
    consecutive_failures
FROM pggit.webhook_health_metrics
ORDER BY health_status DESC, consecutive_failures DESC;
```

### Views for Observability

**`v_webhook_health_dashboard`** - Aggregated health summary
```sql
SELECT
    health_status,
    webhook_count,
    avg_response_ms,
    failures_1h,
    failures_24h
FROM pggit.v_webhook_health_dashboard;
```
Expected columns: health status distribution, response time trends, failure rates

**`v_webhook_performance`** - Per-webhook performance
```sql
SELECT
    webhook_id,
    health_status,
    total_deliveries,
    success_rate_percent,
    avg_response_time_ms,
    consecutive_failures,
    success_freshness       -- minutes since last success
FROM pggit.v_webhook_performance
WHERE health_status != 'healthy'
ORDER BY health_status DESC;
```

**`v_degraded_webhooks`** - Problems only
```sql
SELECT
    webhook_id,
    health_status,
    consecutive_failures,
    minutes_since_check,
    hours_since_success
FROM pggit.v_degraded_webhooks
WHERE consecutive_failures > 0
ORDER BY consecutive_failures DESC;
```

## 3. Setting Up Prometheus

### Configuration File: `prometheus.yml`

Create `/home/lionel/code/pggit/prometheus.yml`:

```yaml
# ============================================================================
# Prometheus Configuration for Phase 8 Week 2 Webhook Delivery
# ============================================================================

global:
  scrape_interval: 15s      # Default: scrape targets every 15s
  evaluation_interval: 15s  # Evaluate rules every 15s
  external_labels:
    cluster: 'local-dev'
    environment: 'development'

# Alerting configuration (optional)
alerting:
  alertmanagers:
    - static_configs:
        - targets: []        # Configure alertmanager if using

# Load rules for alert conditions
rule_files:
  # - "webhook_alerts.yml"  # Uncomment when ready for alerting

# Scrape configurations
scrape_configs:
  # ========================================================================
  # Webhook Worker 1 Metrics
  # ========================================================================
  - job_name: 'webhook-worker-1'
    static_configs:
      - targets: ['localhost:8000']
        labels:
          worker_id: 'worker-1'
          service: 'webhook-delivery'
    scrape_interval: 10s
    scrape_timeout: 5s
    metrics_path: '/metrics'

  # ========================================================================
  # Webhook Worker 2 Metrics
  # ========================================================================
  - job_name: 'webhook-worker-2'
    static_configs:
      - targets: ['localhost:8001']
        labels:
          worker_id: 'worker-2'
          service: 'webhook-delivery'
    scrape_interval: 10s
    scrape_timeout: 5s
    metrics_path: '/metrics'

  # ========================================================================
  # Webhook Worker 3 Metrics
  # ========================================================================
  - job_name: 'webhook-worker-3'
    static_configs:
      - targets: ['localhost:8002']
        labels:
          worker_id: 'worker-3'
          service: 'webhook-delivery'
    scrape_interval: 10s
    scrape_timeout: 5s
    metrics_path: '/metrics'

  # ========================================================================
  # PostgreSQL (via pg_exporter - optional for future enhancement)
  # ========================================================================
  # Uncomment when pg_exporter is running
  # - job_name: 'postgres'
  #   static_configs:
  #     - targets: ['localhost:9187']
  #       labels:
  #         service: 'pggit-database'
```

### Running Prometheus

**Option 1: Docker Container**
```bash
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v /home/lionel/code/pggit/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:latest
```

**Option 2: Local Installation**
```bash
# Download Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.48.1/prometheus-2.48.1.linux-amd64.tar.gz
tar -xzf prometheus-2.48.1.linux-amd64.tar.gz
cd prometheus-2.48.1.linux-amd64

# Run with config
./prometheus --config.file=/home/lionel/code/pggit/prometheus.yml \
             --storage.tsdb.path=/tmp/prometheus
```

**Verify Scraping**:
```bash
# Check targets
curl http://localhost:9090/api/v1/targets

# Query a metric
curl 'http://localhost:9090/api/v1/query?query=webhook_deliveries_total'
```

## 4. Setting Up Grafana Dashboards

### Create Grafana Data Source

1. Open Grafana: `http://localhost:3000` (default credentials: admin/admin)
2. Configuration → Data Sources → Add Prometheus
3. URL: `http://localhost:9090`
4. Click "Save & Test"

### Dashboard 1: Webhook Delivery Overview

**Panels to Create**:

1. **Queue Depth (Gauge)**
   ```
   Query: webhook_queue_depth
   Threshold: 100 items (warning)
   ```

2. **Delivery Rate (Graph)**
   ```
   Query: rate(webhook_deliveries_total[5m])
   Legend: {{status}} (group by status)
   Y-axis: deliveries/sec
   ```

3. **Success Rate (Stat)**
   ```
   Query: sum(rate(webhook_deliveries_total{status="delivered"}[5m])) /
          sum(rate(webhook_deliveries_total[5m]))
   Format: percent
   Thresholds: > 99% = green, < 95% = red
   ```

4. **P99 Response Time (Graph)**
   ```
   Query: histogram_quantile(0.99,
          rate(webhook_delivery_duration_seconds_bucket[5m]))
   Y-axis: seconds
   Threshold: 2s (warning)
   ```

5. **Failed Deliveries (Timeseries)**
   ```
   Query: rate(webhook_deliveries_total{status="failed"}[5m])
   Alert: > 0.5 deliveries/sec = problem
   ```

### Dashboard 2: Worker Health

**Panels to Create**:

1. **Worker Status (Multi-stat)**
   ```
   Query: worker_health_status
   Legend: {{worker_id}}
   Thresholds: 1 = healthy, 0 = down
   ```

2. **Rate Limit Hits (Counter)**
   ```
   Query: increase(rate_limit_hits_total[5m])
   Group by: webhook_id
   Top 10 webhooks
   ```

3. **Circuit Breaker Opens (Counter)**
   ```
   Query: increase(circuit_breaker_opens_total[1h])
   Group by: webhook_id
   Alert if > 2 opens in 1 hour
   ```

### Dashboard 3: PostgreSQL Queue & Health

**Panels to Create**:

1. **Webhook Status Distribution (Pie)**
   ```sql
   SELECT health_status, COUNT(*) as count
   FROM pggit.webhook_health_metrics
   GROUP BY health_status
   ```

2. **Degraded Webhooks (Table)**
   ```sql
   SELECT webhook_id, health_status, consecutive_failures,
          ROUND(100.0 * successful_deliveries /
                NULLIF(total_deliveries, 0), 2) as success_rate_pct
   FROM pggit.webhook_health_metrics
   WHERE health_status IN ('degraded', 'unavailable')
   ORDER BY consecutive_failures DESC
   ```

3. **Average Response Time by Webhook (Bar)**
   ```sql
   SELECT webhook_id, ROUND(avg_response_time_ms, 1) as avg_ms
   FROM pggit.webhook_health_metrics
   WHERE total_deliveries > 0
   ORDER BY avg_response_time_ms DESC
   LIMIT 10
   ```

## 5. Query Examples

### High-Level Metrics Queries

**Overall System Health** (Prometheus):
```promql
# Overall success rate in last 5 minutes
sum(rate(webhook_deliveries_total{status="delivered"}[5m])) /
sum(rate(webhook_deliveries_total[5m]))

# Queue depth over time
webhook_queue_depth

# P99 latency per worker
histogram_quantile(0.99,
  rate(webhook_delivery_duration_seconds_bucket[5m]))
  by (webhook_id)

# Circuit breaker opens per hour
increase(circuit_breaker_opens_total[1h]) by (webhook_id)
```

**Webhook-Specific Queries** (PostgreSQL):
```sql
-- Find problematic webhooks
SELECT webhook_id, health_status, consecutive_failures,
       ROUND(100.0 * successful_deliveries /
             NULLIF(total_deliveries, 0), 2) as success_rate,
       ROUND(avg_response_time_ms, 1) as avg_ms
FROM pggit.webhook_health_metrics
WHERE health_status IN ('degraded', 'unavailable')
ORDER BY consecutive_failures DESC;

-- Compare worker throughput
SELECT worker_id,
       COUNT(*) as total_deliveries,
       SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) as successful,
       ROUND(100.0 * SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) /
             COUNT(*), 2) as success_rate_pct
FROM pggit.alert_delivery_queue
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY worker_id;

-- Queue backpressure (pending vs delivered)
SELECT
    COUNT(CASE WHEN delivery_status = 'pending' THEN 1 END) as pending,
    COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END) as delivered,
    COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END) as failed
FROM pggit.alert_delivery_queue
WHERE created_at > NOW() - INTERVAL '1 hour';
```

## 6. Alerting (Optional)

### Alert Rules: `webhook_alerts.yml`

Create `/home/lionel/code/pggit/prometheus/webhook_alerts.yml`:

```yaml
groups:
  - name: webhook_delivery
    interval: 30s
    rules:
      # ====================================================================
      # Worker Health Alerts
      # ====================================================================
      - alert: WorkerDown
        expr: worker_health_status == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Worker {{ $labels.worker_id }} is down"
          description: "Worker has not reported health in 2 minutes"

      # ====================================================================
      # Delivery Success Alerts
      # ====================================================================
      - alert: HighFailureRate
        expr: |
          (sum(rate(webhook_deliveries_total{status="failed"}[5m])) /
           sum(rate(webhook_deliveries_total[5m]))) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High webhook failure rate (>5%)"
          description: "Current failure rate: {{ $value | humanizePercentage }}"

      - alert: CriticalFailureRate
        expr: |
          (sum(rate(webhook_deliveries_total{status="failed"}[5m])) /
           sum(rate(webhook_deliveries_total[5m]))) > 0.20
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical webhook failure rate (>20%)"
          description: "Immediate investigation required"

      # ====================================================================
      # Response Time Alerts
      # ====================================================================
      - alert: HighP99Latency
        expr: |
          histogram_quantile(0.99,
            rate(webhook_delivery_duration_seconds_bucket[5m])) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High P99 webhook latency (>5s)"
          description: "P99: {{ $value | humanizeDuration }}"

      # ====================================================================
      # Circuit Breaker Alerts
      # ====================================================================
      - alert: CircuitBreakerOpen
        expr: increase(circuit_breaker_opens_total[1h]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Circuit breaker opened for webhook {{ $labels.webhook_id }}"
          description: "{{ $value }} opens in last hour"

      # ====================================================================
      # Queue Alerts
      # ====================================================================
      - alert: QueueBackpressure
        expr: webhook_queue_depth > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Webhook queue backup"
          description: "{{ $value }} deliveries pending"

      # ====================================================================
      # Rate Limiting Alerts
      # ====================================================================
      - alert: HighRateLimitHits
        expr: increase(rate_limit_hits_total[5m]) > 100
        labels:
          severity: info
        annotations:
          summary: "High rate limit hits"
          description: "{{ $value }} hits in last 5 minutes"
```

### Integrate with Prometheus

Update `prometheus.yml`:
```yaml
rule_files:
  - "/home/lionel/code/pggit/prometheus/webhook_alerts.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']  # Alertmanager
```

## 7. Monitoring Workflow

### Daily Health Check

Run daily to verify system health:

```sql
-- 1. Overall queue metrics
SELECT * FROM pggit.count_pending_by_status();

-- 2. Webhook health summary
SELECT health_status, COUNT(*) as webhook_count
FROM pggit.webhook_health_metrics
GROUP BY health_status
ORDER BY CASE
    WHEN health_status = 'unavailable' THEN 0
    WHEN health_status = 'degraded' THEN 1
    WHEN health_status = 'healthy' THEN 2
    ELSE 3 END;

-- 3. Degraded webhooks requiring attention
SELECT webhook_id, health_status, consecutive_failures,
       ROUND(100.0 * successful_deliveries /
             NULLIF(total_deliveries, 0), 2) as success_rate_pct,
       ROUND(avg_response_time_ms, 1) as avg_ms,
       hours_since_success
FROM pggit.v_degraded_webhooks
ORDER BY consecutive_failures DESC;

-- 4. Recent errors (last 1 hour)
SELECT COUNT(*) as errors_1h
FROM pggit.alert_delivery_queue
WHERE delivery_status = 'failed'
  AND created_at > NOW() - INTERVAL '1 hour';
```

### Incident Response Playbook

**Symptom**: High failure rate (> 20%)

1. **Check worker health**
   ```
   Prometheus: worker_health_status == 1 for all workers?
   ```

2. **Identify affected webhooks**
   ```sql
   SELECT webhook_id, consecutive_failures, health_status
   FROM pggit.webhook_health_metrics
   WHERE failed_deliveries > successful_deliveries
   ORDER BY failed_deliveries DESC LIMIT 10;
   ```

3. **Check queue depth**
   ```
   Prometheus: webhook_queue_depth - is it growing?
   ```

4. **Check external service**
   - Are target webhook endpoints responding?
   - Network connectivity issues?

5. **Recovery**
   ```sql
   -- Reset circuit breaker for a webhook
   UPDATE pggit.webhook_health_metrics
   SET consecutive_failures = 0,
       health_status = 'healthy',
       last_check_at = CURRENT_TIMESTAMP
   WHERE webhook_id = ?
     AND health_status != 'healthy';
   ```

## 8. Testing Dashboards

### Generate Test Load

```bash
# Insert 1000 test deliveries
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
)
SELECT
    1000 + seq,
    2000 + (seq % 50),
    jsonb_build_object('test', 'load-' || seq),
    'pending', 0, 3,
    CURRENT_TIMESTAMP - INTERVAL '5 seconds' * (seq % 10)
FROM generate_series(1, 1000) seq;

SELECT COUNT(*) as test_deliveries FROM pggit.alert_delivery_queue
WHERE alert_id > 1000;

EOF
```

### View Prometheus Metrics

```bash
# Check metrics endpoint
curl http://localhost:8000/metrics | head -50

# Query delivery count
curl 'http://localhost:9090/api/v1/query?query=webhook_deliveries_total'

# Query success rate (last 5 minutes)
curl 'http://localhost:9090/api/v1/query?query=rate(webhook_deliveries_total%5B5m%5D)'
```

## 9. Performance Baselines

These are the expected performance targets for Phase 8 Week 2:

| Metric | Target | Critical |
|--------|--------|----------|
| **Delivery Latency (P99)** | < 2s | > 5s |
| **Success Rate** | > 99% | < 95% |
| **Queue Depth** | < 100 items | > 1000 items |
| **Worker Health** | 100% (1.0) | Any 0 for 2min |
| **Circuit Breaker Opens** | 0/hour | > 2/hour |
| **Rate Limit Hits** | < 10/min | > 100/min |

## 10. Integration with External Monitoring

To integrate with external services (Datadog, New Relic, etc.):

### Datadog Integration

Add to `prometheus.yml`:
```yaml
remote_write:
  - url: https://api.datadoghq.com/api/v1/series
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'webhook_.*'
        action: keep
    bearer_token: ${DATADOG_API_KEY}
```

### Custom Metrics Export

For applications that consume pggit metrics:
```python
# Export as JSON for ingestion
import requests
import json

def export_webhook_metrics():
    response = requests.get('http://localhost:9090/api/v1/query',
                          params={'query': 'webhook_deliveries_total'})
    metrics = response.json()['data']['result']

    for metric in metrics:
        labels = metric['metric']
        value = float(metric['value'][1])

        # Send to external system
        requests.post('https://metrics.example.com/ingest',
                     json={
                         'name': 'webhook_deliveries',
                         'value': value,
                         'tags': labels
                     })
```

## References

- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **Alertmanager**: https://prometheus.io/docs/alerting/latest/overview/
- **Architecture**: `PHASE8_WEEK2_ARCHITECTURE.md`
- **Quick Start**: `PHASE8_WEEK2_QUICKSTART.md`

