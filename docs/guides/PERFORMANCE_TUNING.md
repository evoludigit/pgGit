# Performance Tuning Guide

## Quick Diagnostics

### Performance Health Check
```sql
-- Check for slow queries (> 100ms)
SELECT * FROM pggit.analyze_slow_queries(100);

-- Verify index usage
SELECT * FROM pggit.check_index_usage();

-- Check vacuum health
SELECT * FROM pggit.vacuum_health();

-- Cache hit ratio (should be > 95%)
SELECT * FROM pggit.cache_hit_ratio();

-- System resource analysis
SELECT * FROM pggit.system_resources();
```

### Index Recommendations
```sql
-- Get index recommendations
SELECT * FROM pggit.recommend_indexes();

-- Check partitioning needs
SELECT * FROM pggit.partitioning_analysis();
```

## Common Optimizations

### 1. Index Optimization

#### Essential Indexes for pgGit
```sql
-- Index for object name lookups
CREATE INDEX IF NOT EXISTS idx_objects_name_version
    ON pggit.objects (object_name) INCLUDE (version);

-- Index for history queries by object
CREATE INDEX IF NOT EXISTS idx_history_object_time
    ON pggit.history (object_id, created_at DESC);

-- Index for time-based history queries
CREATE INDEX IF NOT EXISTS idx_history_created_at
    ON pggit.history (created_at DESC);

-- Partial index for failed operations
CREATE INDEX IF NOT EXISTS idx_upgrade_log_failed
    ON pggit.upgrade_log (started_at DESC)
    WHERE status = 'failed';
```

#### Covering Indexes
```sql
-- Covering index for common queries
CREATE INDEX IF NOT EXISTS idx_objects_composite
    ON pggit.objects (object_type, schema_name, object_name)
    INCLUDE (version, created_at);

-- Covering index for history summaries
CREATE INDEX IF NOT EXISTS idx_history_summary
    ON pggit.history (object_id, change_type, created_at)
    INCLUDE (created_by);
```

### 2. Partitioning Large Tables

If `pggit.history` exceeds 10M rows:

#### Monthly Partitioning
```sql
-- Create partitioned history table
CREATE TABLE pggit.history_new (
    LIKE pggit.history INCLUDING ALL
) PARTITION BY RANGE (created_at);

-- Create monthly partitions (last 12 months + future)
DO $$
DECLARE
    partition_date DATE := date_trunc('month', CURRENT_DATE - INTERVAL '11 months');
    end_date DATE;
BEGIN
    WHILE partition_date <= date_trunc('month', CURRENT_DATE + INTERVAL '3 months') LOOP
        end_date := partition_date + INTERVAL '1 month';

        EXECUTE format('CREATE TABLE pggit.history_%s PARTITION OF pggit.history_new
                       FOR VALUES FROM (%L) TO (%L)',
                      to_char(partition_date, 'YYYY_MM'),
                      partition_date,
                      end_date);

        partition_date := end_date;
    END LOOP;
END $$;

-- Migrate data
INSERT INTO pggit.history_new SELECT * FROM pggit.history;

-- Swap tables (requires exclusive lock)
BEGIN;
LOCK TABLE pggit.history IN ACCESS EXCLUSIVE MODE;
ALTER TABLE pggit.history RENAME TO history_old;
ALTER TABLE pggit.history_new RENAME TO history;
COMMIT;

-- Cleanup old table
DROP TABLE pggit.history_old;
```

#### Partition Maintenance
```sql
-- Create next month's partition
CREATE OR REPLACE FUNCTION pggit.create_next_partition()
RETURNS void AS $$
DECLARE
    next_month DATE := date_trunc('month', CURRENT_DATE + INTERVAL '1 month');
    partition_name TEXT;
BEGIN
    partition_name := 'history_' || to_char(next_month, 'YYYY_MM');

    EXECUTE format('CREATE TABLE IF NOT EXISTS pggit.%I PARTITION OF pggit.history
                   FOR VALUES FROM (%L) TO (%L)',
                  partition_name,
                  next_month,
                  next_month + INTERVAL '1 month');
END;
$$ LANGUAGE plpgsql;

-- Archive old partitions (older than 2 years)
CREATE OR REPLACE FUNCTION pggit.archive_old_partitions()
RETURNS void AS $$
DECLARE
    cutoff_date DATE := CURRENT_DATE - INTERVAL '2 years';
    partition_name TEXT;
BEGIN
    FOR partition_name IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'pggit'
        AND tablename LIKE 'history_%'
        AND substring(tablename from 9) < to_char(cutoff_date, 'YYYY_MM')
    LOOP
        -- Move to archive schema or export to file
        EXECUTE format('ALTER TABLE pggit.%I SET SCHEMA archive', partition_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 3. Memory Configuration

#### PostgreSQL Memory Tuning
```sql
-- Calculate based on system RAM (example for 16GB system)
ALTER SYSTEM SET shared_buffers = '4GB';        -- 25% of RAM
ALTER SYSTEM SET effective_cache_size = '12GB'; -- 75% of RAM
ALTER SYSTEM SET work_mem = '8MB';              -- Per-connection work memory
ALTER SYSTEM SET maintenance_work_mem = '256MB'; -- For maintenance operations

-- Restart PostgreSQL for shared_buffers to take effect
-- sudo systemctl restart postgresql
```

#### pgGit-Specific Memory Settings
```sql
-- Temporary settings for large operations
SET work_mem = '32MB';           -- Increase for complex queries
SET temp_buffers = '16MB';       -- Increase for temp table operations
SET maintenance_work_mem = '512MB'; -- For index creation
```

### 4. Connection Pooling

#### pgBouncer Configuration
```ini
# /etc/pgbouncer/pgbouncer.ini
[databases]
pggit_prod = host=localhost port=5432 dbname=pggit_prod

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 25
max_client_conn = 200
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 50
max_user_connections = 50
```

#### Connection Pool Monitoring
```sql
-- Monitor connection pool effectiveness
SELECT * FROM pggit.connection_stats();

-- Check for connection leaks
SELECT
    usename,
    client_addr,
    state,
    NOW() - state_change as connection_age
FROM pg_stat_activity
WHERE state = 'idle'
    AND NOW() - state_change > INTERVAL '1 hour'
ORDER BY connection_age DESC;
```

### 5. Query Optimization

#### Optimize Common pgGit Queries
```sql
-- Create optimized view for object history
CREATE OR REPLACE VIEW pggit.object_history AS
SELECT
    o.object_name,
    o.object_type,
    o.schema_name,
    h.change_type,
    h.created_at,
    h.created_by,
    h.metadata
FROM pggit.objects o
JOIN pggit.history h ON h.object_id = o.id
WHERE h.created_at > CURRENT_DATE - INTERVAL '30 days'
ORDER BY h.created_at DESC;

-- Materialized view for performance
CREATE MATERIALIZED VIEW pggit.daily_stats AS
SELECT
    DATE(created_at) as day,
    change_type,
    COUNT(*) as change_count,
    COUNT(DISTINCT object_id) as objects_affected
FROM pggit.history
WHERE created_at > CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE(created_at), change_type;

-- Refresh materialized view
REFRESH MATERIALIZED VIEW CONCURRENTLY pggit.daily_stats;
```

### 6. Vacuum and Maintenance

#### Automated Vacuum Tuning
```sql
-- Aggressive vacuum settings for high-write tables
ALTER TABLE pggit.history
    SET (autovacuum_vacuum_scale_factor = 0.05);

ALTER TABLE pggit.history
    SET (autovacuum_analyze_scale_factor = 0.02);

ALTER TABLE pggit.history
    SET (autovacuum_vacuum_cost_limit = 1000);

-- Manual vacuum when needed
VACUUM (VERBOSE, ANALYZE) pggit.history;
VACUUM (FULL, VERBOSE) pggit.upgrade_log;  -- Only when necessary
```

#### Maintenance Schedule
```bash
#!/bin/bash
# Weekly maintenance script

# Vacuum analyze all pgGit tables
psql -c "VACUUM ANALYZE pggit.*;"

# Reindex if fragmentation is high
psql -c "REINDEX SCHEMA CONCURRENTLY pggit;"

# Update table statistics
psql -c "ANALYZE pggit.objects, pggit.history, pggit.upgrade_log;"

# Check for unused indexes
psql -c "
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'pggit'
  AND idx_scan = 0
  AND indexname NOT LIKE 'idx_%'
ORDER BY idx_scan;
"
```

### 7. Hardware Optimization

#### Storage Configuration
```bash
# Use SSD storage for PostgreSQL data
# RAID 10 for redundancy and performance
# Separate tablespaces for pgGit data

# Create tablespace for pgGit
sudo mkdir -p /pgdata/pggit
sudo chown postgres:postgres /pgdata/pggit

psql -c "CREATE TABLESPACE pggit_tbs LOCATION '/pgdata/pggit';"
psql -c "ALTER TABLE pggit.history SET TABLESPACE pggit_tbs;"
```

#### I/O Optimization
```ini
# postgresql.conf
effective_io_concurrency = 200      # For SSD storage
random_page_cost = 1.1             # For SSD storage
seq_page_cost = 1.0                # For SSD storage
```

### 8. Monitoring and Alerting

#### Performance Monitoring Queries
```sql
-- Create monitoring function
CREATE OR REPLACE FUNCTION pggit.performance_report()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    value TEXT,
    recommendation TEXT
) AS $$
BEGIN
    -- Slow query check
    RETURN QUERY
    SELECT
        'slow_queries'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'warning' ELSE 'ok' END,
        COUNT(*)::TEXT,
        'Review queries taking >500ms'::TEXT
    FROM pggit.performance_metrics
    WHERE metric_type = 'ddl_tracking_ms'
      AND metric_value > 500
      AND recorded_at > NOW() - INTERVAL '1 hour';

    -- Index usage check
    RETURN QUERY
    SELECT
        'unused_indexes'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'warning' ELSE 'ok' END,
        COUNT(*)::TEXT,
        'Consider dropping unused indexes'::TEXT
    FROM pg_stat_user_indexes
    WHERE schemaname = 'pggit'
      AND idx_scan = 0;

    -- Cache hit ratio check
    RETURN QUERY
    SELECT
        'cache_hit_ratio'::TEXT,
        CASE WHEN avg(ratio) < 95 THEN 'warning' ELSE 'ok' END,
        round(avg(ratio), 1)::TEXT || '%',
        'Increase shared_buffers or effective_cache_size'::TEXT
    FROM (
        SELECT (heap_blks_hit::numeric * 100 / (heap_blks_hit + heap_blks_read)) as ratio
        FROM pg_statio_user_tables
        WHERE schemaname = 'pggit'
    ) t;

END;
$$ LANGUAGE plpgsql;
```

## Benchmarking

### Performance Benchmark Suite
```bash
#!/bin/bash
# scripts/performance/benchmark.sh

echo "=== pgGit Performance Benchmark ==="

# Create test database
createdb pggit_benchmark

# Install pgGit
psql -d pggit_benchmark -f sql/install.sql

# Install performance helpers
psql -d pggit_benchmark -f sql/pggit_performance.sql

echo "Running DDL benchmark (1000 operations)..."
START=$(date +%s%3N)
for i in {1..1000}; do
    psql -d pggit_benchmark -c "CREATE TABLE bench_test_$i (id INT PRIMARY KEY);" >/dev/null 2>&1
done
END=$(date +%s%3N)
DDL_TIME=$((END - START))
echo "DDL operations: ${DDL_TIME}ms total, $((DDL_TIME/1000))ms per operation"

echo "Running query benchmark..."
psql -d pggit_benchmark -c "
SELECT pggit.execute_with_timing(
    'SELECT * FROM pggit.objects WHERE object_name LIKE ''bench_test_%'''
);
"

# Cleanup
dropdb pggit_benchmark

echo "=== Benchmark complete ==="
```

### Load Testing
```bash
#!/bin/bash
# scripts/performance/load-test.sh

CONCURRENT_USERS=${1:-10}
DURATION=${2:-60}

echo "Load testing with $CONCURRENT_USERS concurrent users for ${DURATION}s"

# Function to simulate user activity
simulate_user() {
    local user_id=$1
    local end_time=$((SECONDS + DURATION))

    while [ $SECONDS -lt $end_time ]; do
        # Random DDL operations
        case $((RANDOM % 4)) in
            0) psql -c "CREATE TABLE load_test_${user_id}_$RANDOM (id INT);" ;;
            1) psql -c "ALTER TABLE load_test_${user_id}_$((RANDOM % 100)) ADD COLUMN col$RANDOM INT;" ;;
            2) psql -c "DROP TABLE IF EXISTS load_test_${user_id}_$((RANDOM % 100));" ;;
            3) psql -c "SELECT * FROM pggit.get_history('load_test_${user_id}_$((RANDOM % 100))');" ;;
        esac

        # Random delay
        sleep $((RANDOM % 5))
    done
}

# Start concurrent users
for i in $(seq 1 $CONCURRENT_USERS); do
    simulate_user $i &
done

# Wait for all to complete
wait

echo "Load test complete"
```

## Troubleshooting Performance Issues

### High Latency Diagnosis
```sql
-- Find slowest operations
SELECT * FROM pggit.analyze_slow_queries(1000);

-- Check for locks
SELECT
    relation::regclass,
    mode,
    granted,
    pid,
    usename,
    NOW() - state_change as waiting_since
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT granted
ORDER BY waiting_since DESC;

-- Check active queries
SELECT
    pid,
    usename,
    query_start,
    NOW() - query_start as duration,
    state,
    query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

### Memory Issues
```sql
-- Check memory usage
SELECT
    name,
    setting,
    unit
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem');

-- Check for memory-intensive queries
SELECT
    pid,
    usename,
    query,
    EXTRACT(epoch FROM NOW() - query_start) as seconds_running
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY seconds_running DESC;
```

### Storage Issues
```sql
-- Check table sizes
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) -
                   pg_relation_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables
WHERE schemaname = 'pggit'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check for bloat
SELECT
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    round(n_dead_tup::numeric * 100 / (n_live_tup + n_dead_tup), 2) as bloat_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'pggit'
ORDER BY n_dead_tup DESC;
```

## Maintenance Checklist

- [ ] Review slow query logs weekly
- [ ] Check index usage monthly
- [ ] Vacuum analyze tables weekly
- [ ] Update PostgreSQL minor versions
- [ ] Monitor disk space usage
- [ ] Review memory settings quarterly
- [ ] Benchmark performance quarterly
- [ ] Archive old data annually