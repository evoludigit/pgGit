# Monitoring Setup Guide - Phase 8 Week 2B

Quick reference for setting up and running monitoring infrastructure for webhook delivery system.

## Quick Start (5 minutes)

### 1. Start Services with Monitoring

```bash
cd /home/lionel/code/pggit

# Start all services (PostgreSQL + 3 workers)
docker-compose up --build -d

# Wait for services to be ready
sleep 10

# Verify workers are reporting metrics
curl http://localhost:8000/metrics | head -20
```

### 2. Start Prometheus (Option A: Docker)

```bash
# Start Prometheus container
docker run -d \
  --name pggit-prometheus \
  --network pggit-network \
  -p 9090:9090 \
  -v /home/lionel/code/pggit/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus
```

Verify: `curl http://localhost:9090/-/healthy`

### 2. Start Prometheus (Option B: Local Binary)

```bash
# Download if not already installed
wget https://github.com/prometheus/prometheus/releases/download/v2.48.1/prometheus-2.48.1.linux-amd64.tar.gz
tar -xzf prometheus-2.48.1.linux-amd64.tar.gz
cd prometheus-2.48.1.linux-amd64

# Run Prometheus
./prometheus --config.file=/home/lionel/code/pggit/prometheus.yml \
             --storage.tsdb.path=/tmp/prometheus \
             --web.enable-lifecycle
```

### 3. Access Prometheus UI

```bash
# Open in browser
http://localhost:9090

# Or verify via curl
curl http://localhost:9090/api/v1/targets
```

## Monitoring Architecture

```
┌─────────────────────────┐
│  Webhook Workers (3x)   │
│  Port 8000-8002         │
│  Prometheus Metrics     │
└────────────┬────────────┘
             │ (scrape every 10s)
             ↓
┌─────────────────────────┐
│   Prometheus Server     │
│   Port 9090             │
│   prometheus.yml config │
└────────────┬────────────┘
             │
      ┌──────┼──────┐
      ↓      ↓      ↓
    UI  Queries  Alerts
```

## Metrics Available

### Worker Metrics (Prometheus)

All metrics are collected from ports 8000, 8001, 8002:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `webhook_deliveries_total` | Counter | status, webhook_id | Total delivery attempts |
| `webhook_delivery_duration_seconds` | Histogram | webhook_id | HTTP request latency |
| `webhook_queue_depth` | Gauge | - | Pending deliveries |
| `worker_health_status` | Gauge | worker_id | Worker health (1=up, 0=down) |
| `rate_limit_hits_total` | Counter | webhook_id | Rate limit triggers |
| `circuit_breaker_opens_total` | Counter | webhook_id | Circuit breaker activations |

### Database Metrics (PostgreSQL)

Query via SQL:

```sql
-- Overall queue status
SELECT * FROM pggit.count_pending_by_status();

-- Webhook health summary
SELECT health_status, COUNT(*) as count
FROM pggit.webhook_health_metrics
GROUP BY health_status;

-- Degraded webhooks
SELECT * FROM pggit.v_degraded_webhooks
ORDER BY consecutive_failures DESC;
```

## Common Queries

### Prometheus Query Language (PromQL)

**Success Rate (Last 5 minutes)**
```promql
sum(rate(webhook_deliveries_total{status="delivered"}[5m])) /
sum(rate(webhook_deliveries_total[5m]))
```

**Delivery Latency (P99)**
```promql
histogram_quantile(0.99,
  rate(webhook_delivery_duration_seconds_bucket[5m]))
```

**Queue Depth Over Time**
```promql
webhook_queue_depth
```

**Failed Deliveries Per Second**
```promql
rate(webhook_deliveries_total{status="failed"}[5m])
```

**Circuit Breaker Opens**
```promql
increase(circuit_breaker_opens_total[1h])
```

## Testing Monitoring

### 1. Generate Test Load

Insert test deliveries:

```bash
docker-compose exec postgres psql -U postgres -d pggit << 'EOF'

INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
)
SELECT
    5000 + seq,
    5000 + (seq % 50),
    jsonb_build_object('seq', seq, 'type', 'test'),
    'pending', 0, 3, CURRENT_TIMESTAMP
FROM generate_series(1, 500) seq;

-- Verify insertion
SELECT COUNT(*) as pending FROM pggit.alert_delivery_queue
WHERE delivery_status = 'pending';

EOF
```

### 2. Watch Metrics in Prometheus

1. Open `http://localhost:9090`
2. Go to "Graph" tab
3. Enter query: `webhook_deliveries_total`
4. Click "Execute"
5. Watch the graph update as workers process deliveries

### 3. Monitor Queue Depth

```bash
# Watch queue depth change in real-time
watch -n 1 'curl -s http://localhost:9090/api/v1/query?query=webhook_queue_depth | jq .'
```

### 4. Check Worker Health

```bash
# All workers healthy (should return 1 for each)
curl -s http://localhost:9090/api/v1/query?query=worker_health_status | jq '.data.result'
```

## Dashboard Setup (Grafana)

### Quick Grafana Setup

```bash
# Run Grafana
docker run -d \
  --name grafana \
  --network pggit-network \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:latest
```

Access: `http://localhost:3000` (admin/admin)

### Add Prometheus Data Source

1. Configuration → Data Sources
2. Click "Add data source"
3. Select "Prometheus"
4. URL: `http://pggit-prometheus:9090`
5. Click "Save & Test"

### Create Dashboard Panel

Example: Delivery Rate

1. Create New Dashboard → Add Panel
2. Query: `rate(webhook_deliveries_total[5m])`
3. Visualization: Graph
4. Title: "Delivery Rate"
5. Save

## Troubleshooting

### Prometheus not scraping workers

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'

# Expected: 4 targets (prometheus itself + 3 workers)

# If workers missing, check:
# 1. Workers are running: docker ps
# 2. Metrics endpoint is accessible: curl http://localhost:8000/metrics
# 3. Prometheus config is correct: cat /home/lionel/code/pggit/prometheus.yml
```

### Query returning no data

```bash
# Check what metrics exist
curl http://localhost:9090/api/v1/label/__name__/values | jq '.data | grep webhook'

# If empty, workers may not have any deliveries yet
# Generate test load (see section above)
```

### High memory usage

```bash
# Prometheus stores data in memory
# Reduce retention:
docker kill pggit-prometheus
docker run -d \
  --name pggit-prometheus \
  --network pggit-network \
  -p 9090:9090 \
  -v /home/lionel/code/pggit/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=7d
```

## Files Reference

- **Prometheus Config**: `/home/lionel/code/pggit/prometheus.yml`
- **Monitoring Guide**: `/home/lionel/code/pggit/PHASE8_WEEK2_MONITORING.md`
- **Quick Start**: `/home/lionel/code/pggit/PHASE8_WEEK2_QUICKSTART.md`
- **Architecture**: `/home/lionel/code/pggit/PHASE8_WEEK2_ARCHITECTURE.md`

## Next Steps

1. **Configure Alertmanager** (optional)
   - Set up alert rules in `prometheus/webhook_alerts.yml`
   - Configure Alertmanager for notifications

2. **Setup Grafana Dashboards** (optional)
   - Create visual dashboards for team visibility
   - Set up dashboard variables for filtering

3. **Integrate with External Systems**
   - Datadog, New Relic, Splunk, etc.
   - Configure remote_write in prometheus.yml

4. **Production Deployment**
   - Move from docker-compose to Kubernetes
   - Use persistent volumes for metrics
   - Set up proper retention policies

