# Operations Guide

This guide covers production deployment, monitoring, and maintenance of pggit.

## 🚀 Production Deployment

### 1. Installation Steps
```bash
# Download and build
git clone https://github.com/evoludigit/pggit.git
cd pggit
make clean && make && sudo make install

# Verify installation
psql -c "CREATE EXTENSION pggit"
psql -c "SELECT pggit.get_version('pg_class')"
```

### 2. Initial Configuration
```sql
-- Configure tracking for production schemas
SELECT pggit.configure_tracking(
    'schemas' => ARRAY['public', 'orders', 'users', 'inventory'],
    'exclude_temp_tables' => true,
    'track_system_objects' => false
);

-- Set up performance monitoring
SELECT pggit.configure_monitoring(
    'alert_threshold_ms' => 1000,
    'batch_size' => 100,
    'cleanup_interval_hours' => 24
);
```

### 3. Enterprise Features Setup
```sql
-- Load enterprise modules
\i sql/040_enterprise_impact_analysis.sql
\i sql/041_zero_downtime_deployment.sql
\i sql/042_cost_optimization_dashboard.sql
\i sql/050_cicd_integration.sql
\i sql/051_enterprise_auth_rbac.sql
\i sql/052_compliance_reporting.sql

-- Verify all features are working
SELECT * FROM pggit.enterprise_health_check();
```

## 📊 Monitoring & Alerting

### 1. Key Metrics to Monitor
```sql
-- pggit health dashboard
SELECT 
    'Objects Tracked' as metric,
    COUNT(*)::TEXT as value
FROM pggit.objects
UNION ALL
SELECT 
    'History Records',
    COUNT(*)::TEXT
FROM pggit.history
UNION ALL
SELECT 
    'Storage Overhead %',
    ROUND((
        (SELECT SUM(pg_total_relation_size(schemaname||'.'||tablename)) 
         FROM pg_tables WHERE schemaname = 'pggit')::FLOAT /
        pg_database_size(current_database())::FLOAT
    ) * 100, 2)::TEXT;
```

### 2. Performance Monitoring
```sql
-- Monitor function performance
SELECT 
    funcname,
    calls,
    total_time,
    mean_time,
    self_time
FROM pg_stat_user_functions 
WHERE schemaname = 'pggit'
ORDER BY total_time DESC;

-- Event trigger overhead
SELECT 
    tgname,
    schemaname,
    tablename
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE tgname LIKE 'pggit%';
```

### 3. Automated Alerts
```sql
-- Set up performance alerts
CREATE OR REPLACE FUNCTION pggit.check_performance_alerts()
RETURNS TABLE(alert_type TEXT, message TEXT, severity TEXT) AS $$
BEGIN
    -- Check for slow operations
    RETURN QUERY
    SELECT 
        'PERFORMANCE'::TEXT,
        'Function ' || funcname || ' averaging ' || mean_time || 'ms'::TEXT,
        CASE WHEN mean_time > 1000 THEN 'CRITICAL'
             WHEN mean_time > 500 THEN 'WARNING'
             ELSE 'INFO' END::TEXT
    FROM pg_stat_user_functions 
    WHERE schemaname = 'pggit' AND mean_time > 100;

    -- Check storage growth
    RETURN QUERY
    SELECT 
        'STORAGE'::TEXT,
        'pggit using ' || 
        ROUND((
            (SELECT SUM(pg_total_relation_size(schemaname||'.'||tablename)) 
             FROM pg_tables WHERE schemaname = 'pggit')::FLOAT /
            pg_database_size(current_database())::FLOAT
        ) * 100, 2)::TEXT || '% of database',
        CASE WHEN (
            (SELECT SUM(pg_total_relation_size(schemaname||'.'||tablename)) 
             FROM pg_tables WHERE schemaname = 'pggit')::FLOAT /
            pg_database_size(current_database())::FLOAT
        ) * 100 > 10 THEN 'WARNING'
        ELSE 'INFO' END::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Run alerts check
SELECT * FROM pggit.check_performance_alerts();
```

## 🔧 Maintenance Tasks

### 1. Regular Cleanup
```sql
-- Clean old history records (keep last 90 days)
DELETE FROM pggit.history 
WHERE change_timestamp < NOW() - INTERVAL '90 days';

-- Vacuum pggit tables
VACUUM ANALYZE pggit.objects;
VACUUM ANALYZE pggit.history;
VACUUM ANALYZE pggit.dependencies;
```

### 2. Index Maintenance
```sql
-- Check index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE schemaname = 'pggit'
ORDER BY idx_scan DESC;

-- Rebuild indexes if needed
REINDEX SCHEMA pggit;
```

### 3. Statistics Updates
```sql
-- Update table statistics
ANALYZE pggit.objects;
ANALYZE pggit.history;
ANALYZE pggit.dependencies;

-- Check for missing statistics
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    last_analyze
FROM pg_stat_user_tables 
WHERE schemaname = 'pggit';
```

## 📈 Capacity Planning

### 1. Growth Projections
```sql
-- Analyze growth trends
WITH growth_data AS (
    SELECT 
        DATE_TRUNC('day', change_timestamp) as day,
        COUNT(*) as daily_changes
    FROM pggit.history 
    WHERE change_timestamp > NOW() - INTERVAL '30 days'
    GROUP BY DATE_TRUNC('day', change_timestamp)
)
SELECT 
    AVG(daily_changes) as avg_daily_changes,
    MAX(daily_changes) as peak_daily_changes,
    STDDEV(daily_changes) as change_variability
FROM growth_data;
```

### 2. Storage Projections
```sql
-- Project storage needs
WITH storage_trend AS (
    SELECT 
        pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))) as current_size,
        SUM(pg_total_relation_size(schemaname||'.'||tablename)) as size_bytes
    FROM pg_tables 
    WHERE schemaname = 'pggit'
)
SELECT 
    current_size,
    pg_size_pretty(size_bytes * 2) as projected_6_months,
    pg_size_pretty(size_bytes * 4) as projected_1_year
FROM storage_trend;
```

### 3. Performance Scaling
```sql
-- Identify scaling bottlenecks
SELECT 
    'Event Triggers' as component,
    COUNT(*) as current_load,
    CASE WHEN COUNT(*) > 1000 THEN 'Consider selective tracking'
         WHEN COUNT(*) > 500 THEN 'Monitor performance'
         ELSE 'OK' END as recommendation
FROM pg_trigger 
WHERE tgname LIKE 'pggit%'
UNION ALL
SELECT 
    'History Table',
    COUNT(*),
    CASE WHEN COUNT(*) > 100000 THEN 'Implement partitioning'
         WHEN COUNT(*) > 50000 THEN 'Schedule regular cleanup'
         ELSE 'OK' END
FROM pggit.history;
```

## 🚨 Disaster Recovery

### 1. Backup Strategy
```bash
# Full database backup including pggit
pg_dump -Fc -f backup_$(date +%Y%m%d).dump database_name

# pggit schema only backup
pg_dump -Fc -n pggit -f pggit_backup_$(date +%Y%m%d).dump database_name

# Point-in-time recovery setup
# Ensure WAL archiving is enabled
# archive_mode = on
# archive_command = 'cp %p /backup/wal/%f'
```

### 2. Recovery Procedures
```sql
-- Verify pggit integrity after restore
SELECT pggit.verify_database_integrity();

-- Check for missing dependencies
SELECT 
    d.dependent_object,
    d.dependency_object,
    CASE WHEN o1.id IS NULL THEN 'MISSING DEPENDENT'
         WHEN o2.id IS NULL THEN 'MISSING DEPENDENCY'
         ELSE 'OK' END as status
FROM pggit.dependencies d
LEFT JOIN pggit.objects o1 ON d.dependent_object = o1.full_name
LEFT JOIN pggit.objects o2 ON d.dependency_object = o2.full_name
WHERE o1.id IS NULL OR o2.id IS NULL;
```

### 3. Rollback Capabilities
```sql
-- Emergency rollback to specific point
SELECT pggit.rollback_to_timestamp('2024-06-15 10:00:00');

-- Selective rollback of specific object
SELECT pggit.rollback_object('public.users', '1.2.0');

-- Preview rollback impact
SELECT pggit.preview_rollback('2024-06-15 10:00:00');
```

## 🔄 CI/CD Integration

### 1. Jenkins Pipeline
```groovy
// Generated by pggit.generate_cicd_config('jenkins')
pipeline {
    agent any
    stages {
        stage('Database Migration') {
            steps {
                script {
                    // Run pggit migration analysis
                    sh 'psql -c "SELECT pggit.analyze_migration_with_ai(\'${BUILD_ID}\', \'${MIGRATION_SQL}\', \'jenkins\')"'
                    
                    // Check for breaking changes
                    def risks = sh(
                        script: 'psql -t -c "SELECT risk_score FROM pggit.assess_migration_risk(\'${MIGRATION_SQL}\')"',
                        returnStdout: true
                    ).trim()
                    
                    if (risks.toInteger() > 50) {
                        error "High risk migration detected: ${risks}"
                    }
                }
            }
        }
    }
}
```

### 2. GitHub Actions
```yaml
# Generated by pggit.generate_cicd_config('github')
name: Database Migration
on:
  push:
    paths: ['migrations/**']

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup PostgreSQL
        uses: harmon758/postgresql-action@v1
        with:
          postgresql version: '17'
      - name: Install pggit
        run: |
          make && sudo make install
          psql -c "CREATE EXTENSION pggit"
      - name: Analyze Migration
        run: |
          RISK=$(psql -t -c "SELECT risk_score FROM pggit.assess_migration_risk('${{ github.event.head_commit.message }}')")
          echo "Migration risk score: $RISK"
          [ "$RISK" -lt 50 ] || (echo "High risk migration!" && exit 1)
```

### 3. Monitoring Integration
```sql
-- Grafana metrics endpoint
CREATE OR REPLACE FUNCTION pggit.metrics_for_grafana()
RETURNS TABLE(
    metric_name TEXT,
    metric_value NUMERIC,
    timestamp TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'pggit_objects_tracked'::TEXT,
        COUNT(*)::NUMERIC,
        NOW()
    FROM pggit.objects
    UNION ALL
    SELECT 
        'pggit_history_records',
        COUNT(*)::NUMERIC,
        NOW()
    FROM pggit.history
    UNION ALL
    SELECT 
        'pggit_storage_mb',
        ROUND((SUM(pg_total_relation_size(schemaname||'.'||tablename)) / 1024.0 / 1024.0)::NUMERIC, 2),
        NOW()
    FROM pg_tables 
    WHERE schemaname = 'pggit';
END;
$$ LANGUAGE plpgsql;
```

## 📋 Operations Checklist

### Daily Tasks
- [ ] Check pggit performance alerts
- [ ] Review recent migration activity
- [ ] Monitor storage growth
- [ ] Verify backup completion

### Weekly Tasks
- [ ] Analyze performance trends
- [ ] Review security audit logs
- [ ] Check for schema drift
- [ ] Update capacity projections

### Monthly Tasks
- [ ] Clean old history records
- [ ] Rebuild indexes if needed
- [ ] Review user permissions
- [ ] Test disaster recovery procedures

### Quarterly Tasks
- [ ] Performance tuning review
- [ ] Security assessment
- [ ] Compliance audit
- [ ] Technology stack updates

## 📞 Operations Support

Need operational help?

- **24/7 Support**: ops@pggit.dev (Enterprise)
- **Community**: GitHub Discussions
- **Documentation**: [Troubleshooting Guide](../getting-started/Troubleshooting.md)
- **Metrics**: Use `pggit.generate_contribution_metrics()` for support cases

---

## 🎯 Key Operations Principles

1. **Monitor proactively**: Set up alerts before problems occur
2. **Automate routine tasks**: Use scripts and CI/CD for consistency
3. **Plan for growth**: Monitor trends and scale proactively  
4. **Test regularly**: Verify backups, recovery, and rollback procedures
5. **Document everything**: Keep runbooks and procedures updated

---

*Successful pggit operations require planning, monitoring, and regular maintenance. Follow these guidelines for a stable production environment.*