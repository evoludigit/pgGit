# Monitoring Guide

This guide covers pgGit's monitoring capabilities for deployments.

> **Note**: pgGit is primarily designed for development and staging. For production deployments, see [Production Considerations](../guides/PRODUCTION_CONSIDERATIONS.md) to determine if pgGit is appropriate for your compliance requirements.

## Overview

pgGit includes comprehensive monitoring functionality to ensure reliability and performance.

## Health Checks

### Basic Health Check

```sql
SELECT * FROM pggit.health_check();
```

Returns status for:
- **event_triggers**: Active DDL tracking triggers
- **recent_activity**: Recent schema changes
- **storage_size**: Database size with thresholds
- **object_count**: Number of tracked objects

### Status Values

- `healthy`: Everything working normally
- `warning`: Issues detected but not critical
- `unhealthy`: Critical issues requiring attention

## Performance Metrics

### Recording Metrics

```sql
-- Record a custom metric
SELECT pggit.record_metric('ddl_execution_ms', 150.5, '{"table": "users"}');

-- View recent metrics
SELECT * FROM pggit.metrics_summary;
```

### Available Metrics

- **ddl_execution_ms**: DDL operation execution time
- **object_count**: Number of tracked database objects
- **changes_per_hour**: Schema changes per hour
- **storage_bytes**: Total pgGit storage usage

## Prometheus Integration

### Metrics Export

```sql
-- Get Prometheus-formatted metrics
SELECT pggit.prometheus_metrics();
```

### Sample Output

```
# HELP pggit_objects_total Total number of tracked objects
# TYPE pggit_objects_total gauge
pggit_objects_total 42

# HELP pggit_changes_per_hour Changes in the last hour
# TYPE pggit_changes_per_hour gauge
pggit_changes_per_hour 12
```

### Grafana Dashboard

Import this dashboard JSON to monitor pgGit:

```json
{
  "dashboard": {
    "title": "pgGit Monitoring",
    "panels": [
      {
        "title": "Tracked Objects",
        "targets": [{
          "expr": "pggit_objects_total"
        }]
      },
      {
        "title": "Changes per Hour",
        "targets": [{
          "expr": "rate(pggit_changes_per_hour[5m])"
        }]
      },
      {
        "title": "Storage Usage",
        "targets": [{
          "expr": "pggit_storage_bytes / 1024 / 1024"
        }]
      }
    ]
  }
}
```

## Alerting

### Recommended Alerts

**Critical Alerts:**
- `pggit_health_status{check="event_triggers"} != 1` - DDL tracking broken
- `pggit_storage_bytes > 1e9` - Storage usage > 1GB

**Warning Alerts:**
- `rate(pggit_changes_per_hour[1h]) > 100` - High change frequency
- `pggit_health_status{check="recent_activity"} == 0` - No recent activity (possible issues)

## Troubleshooting

### Common Issues

**Health check fails:**
```sql
-- Check event triggers
SELECT * FROM pg_event_trigger WHERE evtname LIKE 'pggit%';

-- Verify pgGit schema exists
SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'pggit';
```

**Metrics not updating:**
```sql
-- Check if monitoring is enabled
SELECT COUNT(*) FROM pggit.performance_metrics
WHERE recorded_at > NOW() - INTERVAL '5 minutes';
```

**Storage growing too fast:**
```sql
-- Check what's taking space
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
WHERE schemaname = 'pggit'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Configuration

### Automatic Metrics Collection

Metrics are automatically collected for DDL operations. No additional configuration required.

### Retention

Metrics are retained for 1 hour by default. Adjust the `metrics_summary` view for different retention periods.

## Integration

### PostgreSQL Monitoring Tools

pgGit works with standard PostgreSQL monitoring tools:

- **pg_stat_statements**: Query performance
- **pg_stat_activity**: Active connections
- **pg_stat_user_tables**: Table statistics

### External Monitoring

- **Prometheus**: Use `/metrics` endpoint
- **Grafana**: Import provided dashboard
- **DataDog/New Relic**: Standard PostgreSQL integrations

---

*Monitor pgGit continuously to ensure optimal performance and reliability.*