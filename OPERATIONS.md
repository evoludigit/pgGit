# Phase 8 Week 2 Operations Guide

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring and Alerting](#monitoring-and-alerting)
3. [Performance Optimization](#performance-optimization)
4. [Incident Response](#incident-response)
5. [Maintenance Tasks](#maintenance-tasks)
6. [Troubleshooting](#troubleshooting)
7. [Runbooks](#runbooks)

## Daily Operations

### Health Checks

Perform health checks every 4 hours:

```bash
#!/bin/bash
# Daily health check script

set -e

API_URL=${API_URL:-"http://localhost:8000"}

echo "=== API Health Check ==="

# Basic health check
HEALTH_RESPONSE=$(curl -s "$API_URL/health")
echo "Basic health: $HEALTH_RESPONSE"

# Deep health check
DEEP_HEALTH=$(curl -s "$API_URL/health/deep")
echo "Deep health: $DEEP_HEALTH"

# Cache stats
CACHE_STATS=$(curl -s "$API_URL/api/v1/cache/stats")
echo "Cache stats: $CACHE_STATS"

# Check database connectivity
psql -h localhost -U pggit -d pggit -c "SELECT 'DB connected' as status;" > /dev/null 2>&1 && echo "✓ Database connected" || echo "✗ Database connection failed"

# Check Redis connectivity (if using L2 cache)
redis-cli -p 6379 ping > /dev/null 2>&1 && echo "✓ Redis connected" || echo "✗ Redis connection failed"

echo "=== Health check complete ==="
```

### Startup Procedure

```bash
#!/bin/bash
# Startup procedure for Phase 8 Week 2 API

set -e

echo "Starting Phase 8 Week 2 API..."

# 1. Verify prerequisites
echo "1. Verifying prerequisites..."
command -v python3.10 > /dev/null || { echo "Python 3.10 not found"; exit 1; }
command -v psql > /dev/null || { echo "psql not found"; exit 1; }

# 2. Start database
echo "2. Starting PostgreSQL..."
sudo systemctl start postgresql || true

# 3. Start cache (if using Redis)
echo "3. Starting Redis..."
sudo systemctl start redis-server || true

# 4. Start API service
echo "4. Starting API service..."
sudo systemctl start pggit-api

# 5. Wait for service to be ready
echo "5. Waiting for service to be ready..."
sleep 5
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ API is ready"
        break
    fi
    echo "  Attempt $i/30: Waiting for API to start..."
    sleep 1
done

# 6. Warm cache
echo "6. Warming cache..."
curl -X POST http://localhost:8000/api/v1/cache/warm

# 7. Verify all systems
echo "7. Verifying all systems..."
curl -s http://localhost:8000/health/deep | python3 -m json.tool

echo "✓ Startup complete"
```

### Shutdown Procedure

```bash
#!/bin/bash
# Shutdown procedure for Phase 8 Week 2 API

echo "Shutting down Phase 8 Week 2 API..."

# 1. Stop accepting new requests
echo "1. Stopping request handler..."
sudo systemctl stop pggit-api

# 2. Wait for graceful shutdown
echo "2. Waiting for graceful shutdown (30 seconds)..."
sleep 30

# 3. Kill any remaining processes
echo "3. Killing any remaining processes..."
pkill -f "gunicorn.*pggit" || true
pkill -f "uvicorn.*api.main" || true

# 4. Stop Redis (if using)
echo "4. Stopping Redis..."
sudo systemctl stop redis-server || true

# 5. Stop PostgreSQL (optional - keep if other services need it)
# sudo systemctl stop postgresql

echo "✓ Shutdown complete"
```

## Monitoring and Alerting

### Key Metrics to Monitor

#### Request Metrics
```
- Request rate (RPS)
- P50, P95, P99 latencies
- Error rate (%)
- Request size distribution
```

#### Cache Metrics
```
- Cache hit rate (target: >80%)
- Cache miss rate
- Cache eviction rate
- Cache size usage
```

#### Database Metrics
```
- Connection pool usage
- Query duration (P95, P99)
- Slow query count
- Lock contention
```

#### Webhook Metrics
```
- Delivery success rate
- Webhook response time
- Retry count
- Queue depth
```

### Setting Up Prometheus Alerts

Create `prometheus-rules.yml`:

```yaml
groups:
  - name: api_alerts
    interval: 30s
    rules:
      # High request latency
      - alert: HighP99Latency
        expr: histogram_quantile(0.99, http_request_duration_seconds) > 0.5
        for: 5m
        annotations:
          summary: "High P99 latency detected"
          description: "P99 latency is {{ $value }}s, threshold is 0.5s"

      # Low cache hit rate
      - alert: LowCacheHitRate
        expr: rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m])) < 0.7
        for: 10m
        annotations:
          summary: "Cache hit rate below threshold"
          description: "Cache hit rate is {{ $value | humanizePercentage }}"

      # High error rate
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.01
        for: 5m
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      # Database connection pool exhausted
      - alert: DatabasePoolExhausted
        expr: db_connection_pool_available < 2
        for: 2m
        annotations:
          summary: "Database connection pool nearly exhausted"
          description: "Available connections: {{ $value }}"

      # Queue depth too high
      - alert: QueueDepthHigh
        expr: webhook_queue_depth > 1000
        for: 10m
        annotations:
          summary: "Webhook queue depth is very high"
          description: "Queue depth: {{ $value }}"
```

### Alertmanager Configuration

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      repeat_interval: 1h
    - match:
        severity: warning
      receiver: 'warning'
      repeat_interval: 4h

receivers:
  - name: 'default'
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: '#alerts'

  - name: 'critical'
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: '#critical-alerts'
    pagerduty_configs:
      - service_key: ${PAGERDUTY_SERVICE_KEY}

  - name: 'warning'
    slack_configs:
      - api_url: ${SLACK_WEBHOOK_URL}
        channel: '#warnings'
```

## Performance Optimization

### Cache Optimization

#### Check Cache Hit Rate

```bash
curl http://localhost:8000/api/v1/cache/stats | jq '.hit_rate'
```

#### Warm Cache Manually

```bash
curl -X POST http://localhost:8000/api/v1/cache/warm
```

#### Monitor Cache Performance

```python
import asyncio
import httpx
from datetime import datetime

async def monitor_cache():
    async with httpx.AsyncClient() as client:
        for _ in range(100):
            # Make a request
            start = datetime.now()
            response = await client.get('http://localhost:8000/api/v1/webhooks')
            duration = (datetime.now() - start).total_seconds()

            print(f"Request duration: {duration:.3f}s")
            await asyncio.sleep(1)

asyncio.run(monitor_cache())
```

### Query Optimization

#### Identify Slow Queries

```sql
-- Enable slow query logging
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- 1 second
SELECT pg_reload_conf();

-- Check slow queries
SELECT
    query,
    calls,
    mean_exec_time,
    max_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 1000
ORDER BY mean_exec_time DESC
LIMIT 10;
```

#### Add Missing Indexes

```sql
-- Check missing indexes
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY tablename;

-- Create indexes for frequently accessed columns
CREATE INDEX CONCURRENTLY idx_webhook_status ON webhooks(status);
CREATE INDEX CONCURRENTLY idx_alert_created ON alerts(created_at DESC);
CREATE INDEX CONCURRENTLY idx_delivery_status ON alert_delivery_queue(delivery_status, created_at);
```

#### Analyze Query Plans

```bash
# Analyze a query
psql pggit << 'EOF'
EXPLAIN ANALYZE
SELECT * FROM webhooks
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 20;
EOF
```

### Connection Pool Optimization

```python
# In api/main.py
from sqlalchemy.pool import QueuePool

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=20,              # Connection pool size
    max_overflow=10,           # Additional connections allowed
    pool_timeout=30,           # Timeout for getting a connection
    pool_recycle=3600,         # Recycle connections every hour
    echo=False,                # Disable SQL logging in production
)
```

## Incident Response

### Response Workflow

1. **Detection** (1-2 min)
   - Alert triggered by monitoring system
   - Page on-call engineer

2. **Diagnosis** (5-10 min)
   - Check logs and metrics
   - Identify root cause
   - Severity assessment

3. **Mitigation** (5-30 min)
   - Apply immediate fix (cache clear, restart, etc.)
   - Or escalate to rollback

4. **Resolution** (varies)
   - Implement permanent fix
   - Deploy and verify
   - Post-mortem analysis

### Common Incidents

#### High Latency

```bash
#!/bin/bash
# Incident: High API latency

# 1. Check current metrics
echo "Current P99 latency:"
curl -s http://localhost:8000/api/v1/cache/stats | jq '.cache_stats.p99_ms'

# 2. Check cache hit rate
curl -s http://localhost:8000/api/v1/cache/stats | jq '.hit_rate'

# 3. If cache hit rate is low, warm cache
curl -X POST http://localhost:8000/api/v1/cache/warm

# 4. Check database connections
psql pggit << 'EOF'
SELECT count(*) as active_connections
FROM pg_stat_activity;
EOF

# 5. Check slow queries
psql pggit << 'EOF'
SELECT query, mean_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 1000
ORDER BY mean_exec_time DESC
LIMIT 5;
EOF

# 6. If database is issue, check indexes
psql pggit << 'EOF'
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0;
EOF

# 7. Restart API if all else fails
sudo systemctl restart pggit-api
```

#### High Error Rate

```bash
#!/bin/bash
# Incident: High error rate

# 1. Check API logs
tail -100 /var/log/pggit/error.log | tail -20

# 2. Check database connectivity
psql pggit -c "SELECT 1;" || echo "Database connection failed"

# 3. Check available disk space
df -h | grep -E "pggit|/"

# 4. Check system resources
free -h
top -bn1 | head -n 20

# 5. Check webhook failures
curl -s http://localhost:8000/api/v1/alerts | jq '.items[] | select(.severity == "CRITICAL")'

# 6. Check recent deployments
git log --oneline -5

# 7. Restart service
sudo systemctl restart pggit-api

# 8. Monitor error rate recovery
watch -n 5 'curl -s http://localhost:8000/health'
```

#### Database Connection Pool Exhausted

```bash
#!/bin/bash
# Incident: Database connection pool exhausted

# 1. Check connection usage
psql pggit << 'EOF'
SELECT
    datname,
    count(*) as connections,
    max_conn
FROM pg_stat_activity
GROUP BY datname
ORDER BY count(*) DESC;
EOF

# 2. Identify long-running queries
psql pggit << 'EOF'
SELECT pid, usename, query, query_start
FROM pg_stat_activity
WHERE query != '<idle>'
ORDER BY query_start DESC;
EOF

# 3. Kill idle connections (if safe)
psql pggit << 'EOF'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND query_start < NOW() - INTERVAL '5 minutes';
EOF

# 4. Increase connection pool size in .env
# DATABASE_POOL_SIZE=30
# DATABASE_POOL_MAX_OVERFLOW=15

# 5. Restart API
sudo systemctl restart pggit-api
```

#### Webhook Queue Backlog

```bash
#!/bin/bash
# Incident: Large webhook queue backlog

# 1. Check queue depth
curl -s http://localhost:8000/api/v1/alerts | jq '.total'

# 2. Check webhook health
curl -s http://localhost:8000/api/v1/webhooks | jq '.items[] | {id, is_active}'

# 3. Identify problematic webhooks
psql pggit << 'EOF'
SELECT webhook_id, COUNT(*) as pending_count
FROM alert_delivery_queue
WHERE delivery_status = 'pending'
GROUP BY webhook_id
ORDER BY pending_count DESC
LIMIT 10;
EOF

# 4. Disable problematic webhooks (if necessary)
# psql pggit -c "UPDATE webhooks SET is_active = false WHERE id = 123;"

# 5. Manually retry deliveries
curl -X POST http://localhost:8000/api/v1/webhooks/retry-pending

# 6. Monitor recovery
watch -n 5 'psql pggit -c "SELECT COUNT(*) FROM alert_delivery_queue WHERE delivery_status = 'pending';"'
```

## Maintenance Tasks

### Daily Tasks (every 24 hours)

- [ ] Review error logs
- [ ] Check disk space usage
- [ ] Verify backups completed
- [ ] Review performance metrics
- [ ] Check webhook health status

```bash
#!/bin/bash
# Daily maintenance script

echo "=== Daily Maintenance Tasks ==="

# 1. Review errors
echo "Recent errors:"
tail -20 /var/log/pggit/error.log

# 2. Check disk space
echo ""
echo "Disk usage:"
df -h | grep -E "pggit|Filesystem"

# 3. Check backup status
echo ""
echo "Latest backup:"
ls -lh /backups/pggit/ | tail -1

# 4. Verify database integrity
echo ""
echo "Database integrity check:"
psql pggit -c "SELECT schemaname, COUNT(*) as table_count FROM pg_tables GROUP BY schemaname;"

# 5. Check webhook failures
echo ""
echo "Failed webhooks (last 24h):"
psql pggit << 'EOF'
SELECT webhook_id, COUNT(*) as failure_count
FROM alert_delivery_queue
WHERE delivery_status = 'failed'
AND created_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY webhook_id
ORDER BY failure_count DESC
LIMIT 5;
EOF

echo "=== Daily maintenance complete ==="
```

### Weekly Tasks (every 7 days)

- [ ] Run vacuum and analyze
- [ ] Review slow query logs
- [ ] Check backup restoration (test restore)
- [ ] Review performance trends
- [ ] Update dependencies

```bash
#!/bin/bash
# Weekly maintenance script

echo "=== Weekly Maintenance Tasks ==="

# 1. Vacuum and analyze all tables
echo "Running VACUUM and ANALYZE..."
psql pggit << 'EOF'
VACUUM ANALYZE;
EOF

# 2. Check table bloat
echo ""
echo "Table bloat check:"
psql pggit << 'EOF'
SELECT
    schemaname,
    tablename,
    round(100 * (otta - floor((cc*oppwidth)/(1 + cc/otta)))::numeric / otta) AS waste_ratio
FROM (
    SELECT *
    FROM pgstattuple_approx('webhooks')
) t;
EOF

# 3. Reindex if necessary
echo ""
echo "Reindexing..."
psql pggit -c "REINDEX INDEX CONCURRENTLY idx_webhook_status;"

# 4. Test restore from backup
echo ""
echo "Testing backup restoration..."
LATEST_BACKUP=$(ls -t /backups/pggit/pggit_*.sql.gz | head -1)
gunzip -c $LATEST_BACKUP | psql pggit_restore > /dev/null 2>&1 && echo "✓ Restore successful" || echo "✗ Restore failed"

# 5. Review performance trends
echo ""
echo "Performance summary:"
psql pggit << 'EOF'
SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
EOF

echo "=== Weekly maintenance complete ==="
```

### Monthly Tasks (every 30 days)

- [ ] Major security updates
- [ ] Database optimization (CLUSTER, etc.)
- [ ] Capacity planning review
- [ ] Documentation updates
- [ ] Disaster recovery drill

### Quarterly Tasks (every 90 days)

- [ ] Full system audit
- [ ] Performance baseline reset
- [ ] Dependency updates
- [ ] Security penetration testing
- [ ] Capacity planning

## Troubleshooting

### General Debugging Steps

1. **Check service status**
   ```bash
   sudo systemctl status pggit-api
   ```

2. **Review logs**
   ```bash
   sudo journalctl -u pggit-api -n 50 -f
   ```

3. **Check health endpoint**
   ```bash
   curl http://localhost:8000/health/deep
   ```

4. **Verify database connectivity**
   ```bash
   psql $DATABASE_URL -c "SELECT 1;"
   ```

5. **Check system resources**
   ```bash
   top -bn1 | head -20
   free -h
   df -h
   ```

### Common Issues and Solutions

#### Issue: "Connection refused" on localhost:8000

**Diagnosis:**
```bash
netstat -tlnp | grep 8000
ps aux | grep pggit-api
sudo systemctl status pggit-api
```

**Solutions:**
1. Check if service is running: `sudo systemctl start pggit-api`
2. Check if port 8000 is in use: `sudo lsof -i :8000`
3. Check logs: `sudo journalctl -u pggit-api -n 20`
4. Verify configuration: `cat .env`

#### Issue: "Could not connect to database"

**Diagnosis:**
```bash
psql postgresql://user:pass@localhost:5432/pggit -c "SELECT 1;"
```

**Solutions:**
1. Verify PostgreSQL is running: `sudo systemctl status postgresql`
2. Check database credentials: `cat .env | grep DATABASE_URL`
3. Verify database exists: `psql -l | grep pggit`
4. Check firewall rules: `sudo ufw status`

#### Issue: "Connection pool size exceeded"

**Diagnosis:**
```sql
SELECT count(*) as active_connections FROM pg_stat_activity;
```

**Solutions:**
1. Increase pool size: Update `DATABASE_POOL_SIZE` in `.env`
2. Check for long-running queries: See Incident Response section
3. Restart API service: `sudo systemctl restart pggit-api`
4. Enable connection pooling with PgBouncer

#### Issue: "Out of memory" errors

**Diagnosis:**
```bash
free -h
top -bn1 | head -20
```

**Solutions:**
1. Reduce worker count: Update `API_WORKERS` in `.env`
2. Reduce cache size in configuration
3. Restart service: `sudo systemctl restart pggit-api`
4. Scale vertically (increase server RAM)
5. Scale horizontally (add more servers)

#### Issue: "High disk usage"

**Diagnosis:**
```bash
df -h
du -sh /home/pggit/*
psql pggit -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database;"
```

**Solutions:**
1. Check log files: `du -sh /var/log/pggit/`
2. Rotate logs: `logrotate -f /etc/logrotate.d/pggit`
3. Clean up old backups: `find /backups/pggit -mtime +30 -delete`
4. Vacuum database: `psql pggit -c "VACUUM FULL;"`

## Runbooks

### Runbook: Cache Warming

```bash
#!/bin/bash
# Runbook: Cache Warming

set -e

echo "Starting cache warming..."

# 1. Verify API is accessible
API_URL=${API_URL:-"http://localhost:8000"}
if ! curl -s "$API_URL/health" > /dev/null; then
    echo "ERROR: API is not accessible at $API_URL"
    exit 1
fi

# 2. Get current cache stats
echo "Current cache stats:"
curl -s "$API_URL/api/v1/cache/stats" | jq '.hit_rate'

# 3. Warm the cache
echo "Warming cache..."
WARM_RESPONSE=$(curl -s -X POST "$API_URL/api/v1/cache/warm")
echo "$WARM_RESPONSE" | jq '.'

# 4. Wait a moment
sleep 2

# 5. Verify cache warming
echo "Verifying cache warming..."
NEW_STATS=$(curl -s "$API_URL/api/v1/cache/stats")
echo "$NEW_STATS" | jq '.hit_rate'

echo "✓ Cache warming complete"
```

### Runbook: Database Backup

```bash
#!/bin/bash
# Runbook: Manual Database Backup

set -e

BACKUP_DIR="/backups/pggit"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/pggit_manual_$TIMESTAMP.sql.gz"

echo "Starting database backup..."

# 1. Create backup directory if needed
mkdir -p "$BACKUP_DIR"

# 2. Create backup
echo "Backing up database to $BACKUP_FILE..."
pg_dump pggit | gzip > "$BACKUP_FILE"

# 3. Verify backup
if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "✓ Backup created successfully ($SIZE)"
else
    echo "✗ Backup failed"
    exit 1
fi

# 4. Test restore
echo "Testing restore..."
gunzip -c "$BACKUP_FILE" | psql pggit_test > /dev/null 2>&1 && \
    echo "✓ Restore test successful" || \
    echo "⚠ Restore test failed"
```

### Runbook: Service Restart

```bash
#!/bin/bash
# Runbook: Safe Service Restart

set -e

echo "Starting safe service restart..."

# 1. Verify current status
echo "Current status:"
sudo systemctl status pggit-api || true

# 2. Perform graceful shutdown
echo "Stopping service..."
sudo systemctl stop pggit-api

# 3. Wait for shutdown
echo "Waiting for graceful shutdown..."
sleep 10

# 4. Verify shutdown
if pgrep -f "gunicorn.*pggit" > /dev/null; then
    echo "Force killing remaining processes..."
    pkill -9 -f "gunicorn.*pggit" || true
fi

# 5. Start service
echo "Starting service..."
sudo systemctl start pggit-api

# 6. Wait for startup
echo "Waiting for service to start..."
sleep 5

# 7. Verify startup
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null; then
        echo "✓ Service started successfully"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 1
done

# 8. Final status
echo "Final status:"
sudo systemctl status pggit-api
```

