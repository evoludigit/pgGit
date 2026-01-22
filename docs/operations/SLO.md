# Service Level Objectives (SLOs)

## Overview

pgGit Service Level Objectives define the reliability and performance targets for deployments.

> **Note**: These SLOs apply to environments where pgGit is deployed. For production, see [Production Considerations](../guides/PRODUCTION_CONSIDERATIONS.md) to determine if pgGit is appropriate for your compliance requirements.

## Availability

**Target**: 99.9% uptime (8.76 hours downtime/year)

### Measurement
- Monitor: `pggit.health_check()` returns 'healthy' status
- Alert: If 'critical' or 'unhealthy' for > 5 minutes

### Budget
- Monthly error budget: 43.8 minutes
- Quarterly error budget: 2.19 hours

## Performance

### DDL Tracking Latency
- **P50**: < 10ms
- **P95**: < 50ms
- **P99**: < 100ms

### Version Query Latency
- **P50**: < 5ms
- **P95**: < 20ms
- **P99**: < 50ms

### Measurement Query
```sql
SELECT
    metric_type,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY metric_value) as p50,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY metric_value) as p95,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY metric_value) as p99
FROM pggit.performance_metrics
WHERE metric_type IN ('ddl_tracking_ms', 'version_query_ms')
    AND recorded_at > NOW() - INTERVAL '1 hour'
GROUP BY metric_type;
```

## Scalability

### Storage Growth
- **Target**: Support 100GB+ pggit schema size
- **Measurement**: Monitor `pg_total_relation_size('pggit.history')`
- **Alert**: If > 90GB

### Object Count
- **Target**: Support 10,000+ tracked objects
- **Measurement**: `SELECT COUNT(*) FROM pggit.objects`
- **Alert**: If approaching 9,000

## Error Rate

### DDL Tracking Errors
- **Target**: < 0.1% error rate
- **Measurement**: Monitor upgrade_log failures
- **Alert**: If > 0.5%

### Error Rate Query
```sql
SELECT
    COUNT(*) FILTER (WHERE status = 'failed') * 100.0 / COUNT(*) as error_rate_pct
FROM pggit.upgrade_log
WHERE started_at > NOW() - INTERVAL '1 day';
```

## Monitoring Setup

### Health Check Function
```sql
CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    message TEXT,
    duration_ms NUMERIC
) AS $$
DECLARE
    check_start TIMESTAMP;
    check_duration INTERVAL;
BEGIN
    -- Basic connectivity check
    check_start := clock_timestamp();
    PERFORM 1;
    check_duration := clock_timestamp() - check_start;

    RETURN QUERY SELECT
        'connectivity'::TEXT,
        'healthy'::TEXT,
        'Database connection successful'::TEXT,
        EXTRACT(millisecond FROM check_duration);

    -- Schema existence check
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit') THEN
        RETURN QUERY SELECT
            'schema'::TEXT,
            'critical'::TEXT,
            'pgGit schema does not exist'::TEXT,
            0::NUMERIC;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        'schema'::TEXT,
        'healthy'::TEXT,
        'pgGit schema exists'::TEXT,
        0::NUMERIC;

    -- Table accessibility check
    BEGIN
        PERFORM COUNT(*) FROM pggit.objects LIMIT 1;
        RETURN QUERY SELECT
            'tables'::TEXT,
            'healthy'::TEXT,
            'Core tables are accessible'::TEXT,
            0::NUMERIC;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'tables'::TEXT,
            'critical'::TEXT,
            format('Table access failed: %s', SQLERRM)::TEXT,
            0::NUMERIC;
    END;

    -- Recent activity check
    IF NOT EXISTS (
        SELECT 1 FROM pggit.history
        WHERE created_at > NOW() - INTERVAL '24 hours'
        LIMIT 1
    ) THEN
        RETURN QUERY SELECT
            'activity'::TEXT,
            'warning'::TEXT,
            'No recent activity detected'::TEXT,
            0::NUMERIC;
    ELSE
        RETURN QUERY SELECT
            'activity'::TEXT,
            'healthy'::TEXT,
            'Recent activity detected'::TEXT,
            0::NUMERIC;
    END IF;

END;
$$ LANGUAGE plpgsql;
```

### Prometheus Integration
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'pggit'
    static_configs:
      - targets: ['localhost:5432']
    metrics_path: /metrics
    params:
      format: [prometheus]
```

### Alert Manager Rules
```yaml
# alert_rules.yml
groups:
  - name: pggit
    rules:
      - alert: pgGitUnhealthy
        expr: pggit_health_status != 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "pgGit health check failed"
          description: "pgGit has been unhealthy for more than 5 minutes"

      - alert: pgGitHighLatency
        expr: histogram_quantile(0.95, rate(pggit_ddl_latency_bucket[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "pgGit DDL latency is high"
          description: "95th percentile DDL latency > 100ms"
```

## SLO Dashboard

### Grafana Dashboard JSON
```json
{
  "dashboard": {
    "title": "pgGit SLO Dashboard",
    "panels": [
      {
        "title": "Availability",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"pggit\"}",
            "legendFormat": "Uptime"
          }
        ]
      },
      {
        "title": "DDL Latency P95",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(pggit_ddl_latency_bucket[5m]))",
            "legendFormat": "P95 Latency"
          }
        ]
      }
    ]
  }
}
```

## Quarterly Review Process

1. **Collect Metrics**: Gather SLO data for the quarter
2. **Calculate Compliance**: Compare actual vs target performance
3. **Identify Issues**: Root cause analysis for SLO violations
4. **Plan Improvements**: Define actions to improve reliability
5. **Update Targets**: Adjust SLOs based on business requirements

### Compliance Calculation
```sql
-- Quarterly SLO compliance
SELECT
    date_trunc('quarter', recorded_at) as quarter,
    metric_type,
    AVG(CASE WHEN metric_value <= target_value THEN 1 ELSE 0 END) * 100 as compliance_pct
FROM pggit.slo_measurements
WHERE recorded_at >= date_trunc('quarter', CURRENT_DATE - INTERVAL '3 months')
GROUP BY date_trunc('quarter', recorded_at), metric_type
ORDER BY quarter, metric_type;
```

## Error Budget Policy

- **Burn Rate**: Track how quickly error budget is consumed
- **Alerts**: Notify when 50%, 80%, 100% of budget consumed
- **Actions**:
  - 50%: Investigate potential issues
  - 80%: Consider reducing release velocity
  - 100%: Stop deployments until budget resets

```sql
-- Error budget tracking
SELECT
    EXTRACT(month FROM started_at) as month,
    COUNT(*) FILTER (WHERE status = 'failed') as failures,
    COUNT(*) as total_operations,
    (COUNT(*) FILTER (WHERE status = 'failed')::numeric / COUNT(*)::numeric) * 100 as error_rate,
    0.1 as target_error_rate, -- 0.1%
    CASE
        WHEN (COUNT(*) FILTER (WHERE status = 'failed')::numeric / COUNT(*)::numeric) > 0.005
        THEN 'BUDGET_EXCEEDED'
        ELSE 'WITHIN_BUDGET'
    END as budget_status
FROM pggit.upgrade_log
WHERE started_at >= date_trunc('month', CURRENT_DATE)
GROUP BY EXTRACT(month FROM started_at);
```