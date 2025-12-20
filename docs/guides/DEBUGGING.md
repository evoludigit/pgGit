# Advanced Debugging Techniques

This guide covers advanced debugging techniques for pgGit development and troubleshooting.

## SQL Debugging

### Enable Query Logging

```sql
-- Enable detailed logging
SET log_statement = 'all';
SET log_duration = on;
SET log_min_duration_statement = 0;

-- View pgGit internal queries
SET pggit.debug = on;  -- If implemented
```

### Query Analysis

```sql
-- Analyze slow queries
SELECT
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements
WHERE query LIKE '%pggit%'
ORDER BY total_time DESC
LIMIT 10;

-- Check active queries
SELECT
    pid,
    usename,
    client_addr,
    query_start,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_stat_activity%';
```

### Event Trigger Debugging

```sql
-- View all event triggers
SELECT
    evtname,
    evtevent,
    evtowner::regrole,
    evtenabled,
    evttags
FROM pg_event_trigger;

-- Debug trigger execution
CREATE OR REPLACE FUNCTION debug_trigger()
RETURNS event_trigger AS $$
BEGIN
    RAISE LOG 'Event trigger fired: %, Command: %',
        tg_event, tg_tag;

    -- Log DDL commands
    FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        RAISE LOG 'DDL Command: % %',
            cmd.command_tag, cmd.object_identity;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Temporarily replace trigger
DROP EVENT TRIGGER pggit_ddl_trigger;
CREATE EVENT TRIGGER debug_ddl_trigger
    ON ddl_command_start
    EXECUTE FUNCTION debug_trigger();
```

## Performance Debugging

### Identify Bottlenecks

```sql
-- Check index usage
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'pggit'
ORDER BY n_distinct DESC;

-- Analyze table bloat
SELECT
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    round(n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100, 2) as bloat_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'pggit'
  AND n_dead_tup > 0
ORDER BY bloat_ratio DESC;
```

### Memory and Cache Analysis

```sql
-- Check cache hit ratios
SELECT
    'index hit rate' as metric,
    round(sum(idx_blks_hit)::numeric / (sum(idx_blks_hit) + sum(idx_blks_read)) * 100, 2) as ratio
FROM pg_statio_user_indexes
WHERE schemaname = 'pggit'

UNION ALL

SELECT
    'table hit rate' as metric,
    round(sum(heap_blks_hit)::numeric / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100, 2) as ratio
FROM pg_statio_user_tables
WHERE schemaname = 'pggit';
```

## Transaction Debugging

### Transaction State Analysis

```sql
-- View active transactions
SELECT
    xact_start,
    query_start,
    state_change,
    state,
    query
FROM pg_stat_activity
WHERE pid IN (
    SELECT pid FROM pg_locks WHERE mode = 'ExclusiveLock'
);

-- Check for locks
SELECT
    locktype,
    relation::regclass,
    mode,
    granted,
    pid,
    usename
FROM pg_locks
WHERE database = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY locktype, relation;
```

### Deadlock Detection

```sql
-- Enable deadlock logging
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '1s';

-- View recent deadlocks
SELECT
    *
FROM pg_stat_database_conflicts
WHERE datname = current_database();
```

## Function Debugging

### Step-through Debugging

```sql
-- Add debug logging to functions
CREATE OR REPLACE FUNCTION pggit.debug_function(func_name text, debug_info jsonb)
RETURNS void AS $$
BEGIN
    INSERT INTO pggit.debug_log (function_name, debug_data, logged_at)
    VALUES (func_name, debug_info, clock_timestamp());
END;
$$ LANGUAGE plpgsql;

-- Use in functions
CREATE OR REPLACE FUNCTION pggit.some_function()
RETURNS void AS $$
BEGIN
    PERFORM pggit.debug_function('some_function', jsonb_build_object('step', 1));

    -- ... function logic ...

    PERFORM pggit.debug_function('some_function', jsonb_build_object('step', 2, 'result', 'success'));
END;
$$ LANGUAGE plpgsql;
```

### Function Call Tracing

```sql
-- Enable function profiling (requires pg_stat_statements)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT
    funcname,
    calls,
    total_time,
    self_time,
    mean_time
FROM pg_stat_user_functions
WHERE schemaname = 'pggit'
ORDER BY total_time DESC;
```

## Extension Debugging

### Load Issues

```sql
-- Check extension loading
SELECT
    name,
    default_version,
    installed_version,
    comment
FROM pg_available_extensions
WHERE name LIKE '%pggit%';

-- Check for missing dependencies
SELECT
    obj_description(oid, 'pg_extension') as extension,
    obj_description(dep.objid, 'pg_extension') as dependency
FROM pg_depend dep
JOIN pg_extension ext ON dep.refobjid = ext.oid
WHERE dep.classid = 'pg_extension'::regclass;
```

### Event Trigger Conflicts

```sql
-- Check for conflicting triggers
SELECT
    evtname,
    evtevent,
    evttags,
    obj_description(oid, 'pg_event_trigger') as description
FROM pg_event_trigger
ORDER BY evtname;

-- Temporarily disable triggers for debugging
ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE;
-- ... debug ...
ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
```

## VS Code Debugging

### Attach to PostgreSQL

1. Install PostgreSQL debugger extension
2. Configure launch.json:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug PostgreSQL Function",
      "type": "postgres",
      "request": "launch",
      "host": "localhost",
      "port": 5432,
      "database": "pggit_dev",
      "username": "postgres",
      "function": "pggit.get_history"
    }
  ]
}
```

### SQL Query Debugging

- Set breakpoints in SQL files
- Step through complex queries
- Inspect variable values
- View execution plans

## Log Analysis

### pgGit Debug Logs

```bash
# Enable debug logging
psql -c "ALTER DATABASE pggit_dev SET log_statement = 'all';"
psql -c "ALTER DATABASE pggit_dev SET log_min_duration_statement = 0;"

# View logs
tail -f /var/log/postgresql/postgresql-*.log | grep pggit
```

### Log Parsing

```bash
# Extract pgGit operations from logs
grep "pggit" /var/log/postgresql/postgresql-*.log | \
grep -E "(CREATE|ALTER|DROP)" | \
sort -k1,2
```

## Testing Debug Scenarios

### Chaos Testing

```bash
# Simulate network issues
tc qdisc add dev lo root netem delay 100ms

# Test pgGit resilience
psql -c "SELECT * FROM pggit.health_check();"

# Remove network simulation
tc qdisc del dev lo root netem
```

### Load Testing

```bash
# Generate concurrent DDL operations
for i in {1..10}; do
    psql -c "CREATE TABLE test_$i (id INT);" &
done
wait

# Check pgGit performance under load
psql -c "SELECT * FROM pggit.analyze_slow_queries();"
```

## Common Issues & Solutions

### Issue: Event triggers not firing

**Solution:**
```sql
-- Check trigger status
SELECT evtname, evtenabled FROM pg_event_trigger;

-- Re-enable if disabled
ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
```

### Issue: Performance degradation

**Solution:**
```sql
-- Analyze and vacuum
VACUUM ANALYZE pggit.history;

-- Check for missing indexes
SELECT * FROM pggit.check_index_usage();
```

### Issue: Functions returning unexpected results

**Solution:**
```sql
-- Add debug logging
CREATE OR REPLACE FUNCTION pggit.debug_function(func_name text, data jsonb)
RETURNS void AS $$
BEGIN
    RAISE LOG 'DEBUG %: %', func_name, data;
END;
$$ LANGUAGE plpgsql;
```

## Advanced Tools

### pgBadger for Log Analysis

```bash
# Install pgBadger
wget https://github.com/darold/pgBadger/archive/master.zip
unzip master.zip
cd pgBadger-master
perl Makefile.PL
make && sudo make install

# Analyze PostgreSQL logs
pgbadger /var/log/postgresql/postgresql-*.log -o report.html
```

### pg_stat_monitor

```sql
-- Advanced query monitoring
CREATE EXTENSION pg_stat_monitor;

SELECT
    query,
    calls,
    total_time,
    mean_time,
    min_time,
    max_time
FROM pg_stat_monitor
WHERE query LIKE '%pggit%'
ORDER BY total_time DESC;
```

Remember to disable debug logging in production and clean up temporary debug functions after troubleshooting.