# Phase 7: Alert Runbooks

**Date**: 2025-12-27
**Version**: 1.0.0
**Status**: Critical implementation for operational readiness

---

## Table of Contents

1. [Overview](#overview)
2. [THRESHOLD_EXCEEDED Alerts](#threshold_exceeded-alerts)
3. [ANOMALY Detection Alerts](#anomaly-detection-alerts)
4. [DEGRADATION Alerts](#degradation-alerts)
5. [CORRELATION Alerts](#correlation-alerts)
6. [BASELINE_RECALC_ERROR Alerts](#baseline_recalc_error-alerts)
7. [Alert Escalation Process](#alert-escalation-process)
8. [On-Call Procedures](#on-call-procedures)
9. [Alert Suppression & Snoozin](#alert-suppression--snoozin)
10. [Metrics & Success Criteria](#metrics--success-criteria)

---

## Overview

### Purpose

Runbooks provide step-by-step procedures for responding to performance monitoring alerts from Phase 7. Each alert type has a specific investigation and remediation workflow to minimize system downtime and impact.

### Alert Severity Levels

| Level | Response Time | Action | Notification |
|-------|--------------|--------|--------------|
| **CRITICAL** | Immediate (< 5 min) | Page on-call engineer | Email + Slack + Mattermost |
| **WARNING** | 15-30 minutes | Create incident | Slack + Mattermost |
| **INFO** | 1-2 hours | Log for investigation | Mattermost only |

### Common Queries

```sql
-- View recent alerts
SELECT alert_id, operation_type, alert_type, severity, violation_multiplier,
       actual_duration_microseconds / 1000.0 as actual_ms, created_at
FROM pggit.performance_alerts
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
ORDER BY created_at DESC;

-- View snoozed alerts
SELECT * FROM pggit.alert_snooze
WHERE is_active = TRUE
  AND snooze_until > CURRENT_TIMESTAMP
ORDER BY snooze_until;

-- View recent baseline changes
SELECT operation_type, old_p99_microseconds / 1000.0 as old_p99_ms,
       new_p99_microseconds / 1000.0 as new_p99_ms,
       percent_change, sample_count, calculated_at
FROM pggit.performance_baseline_history
ORDER BY calculated_at DESC LIMIT 20;
```

---

## THRESHOLD_EXCEEDED Alerts

### Alert Characteristics

- **Type**: `THRESHOLD_EXCEEDED`
- **Trigger**: Operation duration exceeds baseline by alert threshold multiplier (default 2.0-2.5x)
- **Scope**: Single operation type
- **Frequency**: Per violation event
- **Typical Causes**:
  - Database lock contention
  - Table bloat (excessive dead tuples)
  - Missing indexes
  - Disk I/O bottleneck
  - Memory pressure
  - CPU saturation

### Severity Logic

| Violation Multiplier | Duration vs Baseline | Severity |
|----------------------|----------------------|----------|
| 2.0x - 3.0x | Minor exceedance | WARNING |
| 3.0x - 5.0x | Moderate exceedance | WARNING → CRITICAL |
| 5.0x+ | Severe exceedance | CRITICAL |

### Investigation Steps

#### Step 1: Acknowledge Alert (< 1 minute)

```bash
# Option 1: Slack reaction
# React with ✅ to acknowledge receipt

# Option 2: Create incident in your tracking system
# Include: alert_id, operation_type, duration, timestamp

# Option 3: Snooze if investigating known issue
SELECT pggit.snooze_alerts(
    p_operation_type => 'merge_branches',
    p_alert_type => 'THRESHOLD_EXCEEDED',
    p_snooze_minutes => 30,
    p_snooze_reason => 'Known table bloat - maintenance scheduled'
);
```

#### Step 2: Get Alert Details (< 2 minutes)

```sql
-- Get the specific alert that triggered
SELECT a.alert_id, a.operation_type, a.alert_type, a.severity,
       a.actual_duration_microseconds / 1000.0 as actual_ms,
       b.p99_microseconds / 1000.0 as baseline_p99_ms,
       a.violation_multiplier,
       a.alert_message, a.alert_data, a.created_at
FROM pggit.performance_alerts a
LEFT JOIN pggit.performance_baselines b
    ON a.operation_type = b.operation_type AND b.is_active = TRUE
WHERE a.alert_id = :alert_id;

-- Get recent trend for this operation (last 1 hour)
SELECT DATE_TRUNC('minute', recorded_at) as minute,
       COUNT(*) as metric_count,
       AVG(duration_microseconds) / 1000.0 as avg_ms,
       MAX(duration_microseconds) / 1000.0 as max_ms,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_microseconds) / 1000.0 as p99_ms
FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
GROUP BY DATE_TRUNC('minute', recorded_at)
ORDER BY minute DESC;

-- Check for concurrent slow operations
SELECT DISTINCT operation_type,
       COUNT(*) as count,
       AVG(duration_microseconds) / 1000.0 as avg_ms,
       MAX(duration_microseconds) / 1000.0 as max_ms
FROM pggit.performance_metrics
WHERE recorded_at >= CURRENT_TIMESTAMP - INTERVAL '10 minutes'
  AND duration_microseconds > (
    SELECT p99_microseconds * 1.5
    FROM pggit.performance_baselines
    WHERE is_active = TRUE LIMIT 1
  )
GROUP BY operation_type;
```

#### Step 3: Check System State (< 5 minutes)

**Action: Run these diagnostic queries against pgGit database**

```sql
-- 1. Check for long-running transactions
SELECT pid, usename, state, wait_event, query_start,
       EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - query_start)) as duration_sec,
       query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_sleep%'
ORDER BY query_start;

-- 2. Check for lock contention
SELECT l.pid, l.usesysid, l.relation, l.mode, l.granted,
       a.usename, a.query, a.query_start
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted
ORDER BY a.query_start;

-- 3. Check table bloat (for relevant tables)
SELECT schemaname, tablename,
       round(100 * pg_relation_size(schemaname||'.'||tablename) /
         pg_total_relation_size(schemaname||'.'||tablename)) AS ratio,
       pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
       round(100 * pg_relation_size(schemaname||'.'||tablename) /
         pg_total_relation_size(schemaname||'.'||tablename)) as ratio
FROM pg_tables
WHERE schemaname = 'pggit'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 4. Check index usage and missing indexes
SELECT schemaname, tablename, attname, n_distinct,
       inherited, null_frac
FROM pg_stats
WHERE schemaname = 'pggit'
  AND n_distinct > 100
ORDER BY tablename, attname;

-- 5. Check query cache statistics
SELECT query, calls, total_time, mean_time, max_time
FROM pg_stat_statements
WHERE query LIKE '%pggit%'
ORDER BY total_time DESC
LIMIT 10;
```

#### Step 4: Root Cause Analysis (< 15 minutes)

**Decision Tree**:

```
Is the operation consistently slow or just this instance?
├─ CONSISTENT SLOW (p99 baseline is high)
│  └─ Table bloat?
│     ├─ YES: Go to remediation step 1 (VACUUM)
│     └─ NO: Missing index?
│        ├─ YES: Go to remediation step 2 (CREATE INDEX)
│        └─ NO: Algorithmic issue (report to team)
│
├─ SUDDEN SPIKE (recent change to baseline)
│  └─ Check recent deployments/migrations
│     ├─ YES: Revert or optimize query
│     └─ NO: External system load?
│        ├─ YES: Scale or throttle
│        └─ NO: Database maintenance issue
│
└─ SINGLE INSTANCE (all other metrics normal)
   └─ Transient contention (lock, I/O wait)
      └─ Monitor and snooze if not repeating
```

### Remediation Steps

#### Remediation 1: VACUUM ANALYZE (Table Bloat)

```bash
# Step 1: Identify bloated tables
# (From diagnostic Step 3, check ratio > 30%)

# Step 2: Run VACUUM ANALYZE during maintenance window
psql -d pggit -c "VACUUM ANALYZE pggit.performance_metrics;"

# Step 3: Monitor impact
SELECT pggit.recalculate_all_baselines_rolling(
    p_lookback_days => 7,
    p_min_samples => 10,
    p_force_recalc => TRUE
);

# Step 4: Verify performance
# Re-run diagnostic queries from Step 2
```

#### Remediation 2: CREATE MISSING INDEX

```sql
-- Analyze slow query execution plan
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= :start_time;

-- Create index if sequential scan is detected
CREATE INDEX CONCURRENTLY idx_performance_metrics_operation_recorded
ON pggit.performance_metrics(operation_type, recorded_at DESC);

-- Verify index was created
SELECT * FROM pg_stat_user_indexes
WHERE relname LIKE '%performance_metrics%';

-- Test query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= :start_time;
```

#### Remediation 3: Optimize Query

```sql
-- If query is suboptimal, rewrite with CTE or different approach
-- Example: Replace N+1 pattern with JOIN
-- This requires application-level changes

-- Document in incident: What query needs optimization
-- Create ticket for development team
```

### Post-Remediation Verification

```sql
-- 1. Confirm baseline improvement
SELECT operation_type, old_p99_microseconds / 1000.0 as old_p99_ms,
       new_p99_microseconds / 1000.0 as new_p99_ms,
       percent_change, sample_count
FROM pggit.performance_baseline_history
WHERE operation_type = :operation_type
ORDER BY calculated_at DESC LIMIT 1;

-- 2. Check alert frequency
SELECT COUNT(*) as recent_alerts
FROM pggit.performance_alerts
WHERE operation_type = :operation_type
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- 3. Clear snooze if applied
UPDATE pggit.alert_snooze
SET is_active = FALSE
WHERE operation_type = :operation_type
  AND snooze_until < CURRENT_TIMESTAMP;
```

### Escalation Criteria

**Escalate to senior DBA if**:
- Remediation steps don't resolve issue
- Issue is part of larger degradation (>3 operations affected)
- Root cause requires schema change
- Suspected hardware issue (disk, memory, CPU)

**Escalate to development team if**:
- Query logic is inefficient (requires code change)
- New feature introduced regression
- Application load pattern has changed

---

## ANOMALY Detection Alerts

### Alert Characteristics

- **Type**: `ANOMALY`
- **Trigger**: Operation duration is statistical outlier (3σ from mean)
- **Scope**: Single operation instance
- **Frequency**: Per anomalous operation
- **Typical Causes**:
  - Transient lock contention
  - Memory reclaim (GC)
  - I/O subsystem hiccup
  - CPU cache miss
  - One-time large dataset

### Investigation Steps

#### Step 1: Understand Context (< 2 minutes)

```sql
-- Get the anomalous operation
SELECT m.metric_id, m.operation_type, m.operation_name,
       m.duration_microseconds / 1000.0 as duration_ms,
       b.p99_microseconds / 1000.0 as baseline_p99_ms,
       (m.duration_microseconds / 1000.0) / (b.p99_microseconds / 1000.0) as ratio,
       m.recorded_at, m.operation_metadata
FROM pggit.performance_metrics m
LEFT JOIN pggit.performance_baselines b
    ON m.operation_type = b.operation_type AND b.is_active = TRUE
WHERE m.metric_id = :metric_id;

-- Calculate z-score confirmation
WITH stats AS (
    SELECT AVG(duration_microseconds) as mean_us,
           STDDEV(duration_microseconds) as stddev_us
    FROM pggit.performance_metrics
    WHERE operation_type = :operation_type
      AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
)
SELECT (m.duration_microseconds - s.mean_us) / s.stddev_us as zscore,
       m.duration_microseconds / 1000.0 as actual_ms,
       s.mean_us / 1000.0 as mean_ms,
       s.stddev_us / 1000.0 as stddev_ms
FROM pggit.performance_metrics m, stats s
WHERE m.metric_id = :metric_id;
```

#### Step 2: Check Surrounding Operations (< 3 minutes)

```sql
-- Were there other slow operations at the same time?
SELECT operation_type, COUNT(*) as slow_count,
       MAX(duration_microseconds / 1000.0) as max_ms,
       AVG(duration_microseconds / 1000.0) as avg_ms
FROM pggit.performance_metrics
WHERE recorded_at >= (
    SELECT recorded_at - INTERVAL '5 minutes'
    FROM pggit.performance_metrics WHERE metric_id = :metric_id
  )
  AND recorded_at <= (
    SELECT recorded_at + INTERVAL '5 minutes'
    FROM pggit.performance_metrics WHERE metric_id = :metric_id
  )
GROUP BY operation_type;

-- Check if this is part of a batch/multi-operation transaction
-- (Look at trace_id if operation is part of distributed trace)
SELECT COUNT(*) as operations_in_trace,
       MIN(duration_microseconds) / 1000.0 as min_ms,
       MAX(duration_microseconds) / 1000.0 as max_ms,
       SUM(duration_microseconds) / 1000.0 as total_ms
FROM pggit.operation_traces
WHERE trace_id = (
    SELECT trace_id FROM pggit.operation_traces
    WHERE span_id = (
        SELECT COALESCE(operation_metadata->>'span_id', operation_name)
        FROM pggit.performance_metrics WHERE metric_id = :metric_id
    ) LIMIT 1
);
```

#### Step 3: Decision Tree

```
Is this a one-time anomaly?
├─ YES (surrounding operations normal)
│  └─ Very likely transient contention
│     └─ NO ACTION REQUIRED (monitor for repeat)
│
└─ NO (multiple slow operations at same time)
   └─ Check for resource contention
      ├─ Check system metrics (CPU, memory, disk I/O)
      └─ See DEGRADATION runbook if trend detected
```

### Action

- **One-Time Anomaly**: No action, monitor for repeat
- **Pattern Emerging**: Escalate to DEGRADATION runbook
- **Known Batch Operation**: Optional - snooze if expected

```sql
-- Snooze this operation type if known/expected
SELECT pggit.snooze_alerts(
    p_operation_type => :operation_type,
    p_alert_type => 'ANOMALY',
    p_snooze_minutes => 60,
    p_snooze_reason => 'Expected large dataset operation'
);
```

---

## DEGRADATION Alerts

### Alert Characteristics

- **Type**: `DEGRADATION`
- **Trigger**: Average performance has declined >20% in second half of observation window
- **Scope**: Single operation type, time-bound
- **Frequency**: Per degradation detection window
- **Typical Causes**:
  - Table/index bloat accumulating
  - Query plan changed (statistics stale)
  - Workload changed (more complex queries)
  - Hardware degradation
  - Resource exhaustion (filling up)

### Investigation Steps

#### Step 1: Get Degradation Details (< 2 minutes)

```sql
-- Get degradation alert and trigger metrics
SELECT a.alert_id, a.operation_type, a.alert_type, a.severity,
       a.alert_data->>'avg_ms_first_half' as avg_first_half_ms,
       a.alert_data->>'avg_ms_second_half' as avg_second_half_ms,
       a.alert_data->>'degradation_percent' as degradation_pct,
       a.created_at
FROM pggit.performance_alerts a
WHERE a.alert_id = :alert_id;

-- Get full degradation analysis
SELECT * FROM pggit.detect_performance_degradation(
    p_operation_type => :operation_type,
    p_window_hours => 24,
    p_degradation_percent => 20
);
```

#### Step 2: Analyze Trend (< 5 minutes)

```sql
-- Hourly trend showing degradation
SELECT DATE_TRUNC('hour', recorded_at) as hour,
       COUNT(*) as metrics,
       AVG(duration_microseconds) / 1000.0 as avg_ms,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_microseconds) / 1000.0 as p99_ms
FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL '48 hours'
GROUP BY DATE_TRUNC('hour', recorded_at)
ORDER BY hour DESC;

-- Check if change correlates with specific time/condition
-- (e.g., specific branch, specific user, data size change)
SELECT COALESCE(operation_metadata->>'branch_id', 'N/A') as branch,
       COUNT(*) as metrics,
       AVG(duration_microseconds) / 1000.0 as avg_ms
FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY COALESCE(operation_metadata->>'branch_id', 'N/A')
ORDER BY avg_ms DESC;
```

#### Step 3: Identify Root Cause (< 15 minutes)

**Possible causes and checks**:

```sql
-- 1. Is data volume growing?
SELECT DATE_TRUNC('day', recorded_at) as day,
       COUNT(*) as total_metrics,
       AVG(rows_affected) as avg_rows,
       MAX(operation_metadata->>'data_size_mb') as max_data_mb
FROM pggit.performance_metrics
WHERE operation_type = :operation_type
  AND recorded_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', recorded_at)
ORDER BY day DESC;

-- 2. Are query plans changing?
-- (Requires pg_stat_statements or similar)
SELECT query, calls, mean_time, max_time, stddev_time
FROM pg_stat_statements
WHERE query LIKE '%' || :operation_type || '%'
ORDER BY calls DESC LIMIT 5;

-- 3. Check index fragmentation
SELECT schemaname, tablename,
       pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'pggit'
ORDER BY pg_relation_size(schemaname||'.'||tablename) DESC;

-- 4. Check maintenance needs
SELECT schemaname, tablename,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'pggit'
ORDER BY last_vacuum DESC;
```

### Remediation Steps

#### Remediation 1: VACUUM + ANALYZE

```bash
# Run comprehensive maintenance
psql -d pggit << 'EOF'
-- For the affected table
VACUUM ANALYZE pggit.performance_metrics;

-- Recalculate statistics
ANALYZE pggit.performance_metrics;

-- Refresh baseline with new data
SELECT pggit.recalculate_all_baselines_rolling(7, 10, TRUE);
EOF

# Monitor improvement
sleep 60
# Re-run Step 2 queries to verify improvement
```

#### Remediation 2: CHECK CONFIGURATION

```sql
-- Verify PostgreSQL configuration for optimization
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW random_page_cost;
SHOW work_mem;

-- Typical recommendations:
-- shared_buffers: 25% of RAM
-- effective_cache_size: 75% of RAM
-- random_page_cost: 1.1 (for SSD)
```

#### Remediation 3: ADD INDEXES IF NEEDED

```sql
-- If trend coincides with new feature/query type
-- Analyze execution plans and add missing indexes
-- See THRESHOLD_EXCEEDED remediation step 2
```

### Post-Remediation

```sql
-- Verify improvement
SELECT operation_type, old_p99_microseconds / 1000.0 as old_p99_ms,
       new_p99_microseconds / 1000.0 as new_p99_ms,
       percent_change, calculated_at
FROM pggit.performance_baseline_history
WHERE operation_type = :operation_type
ORDER BY calculated_at DESC LIMIT 1;

-- If improvement <10%, escalate for further investigation
```

---

## CORRELATION Alerts

### Alert Characteristics

- **Type**: `CORRELATION`
- **Trigger**: Two operations are degrading together with >0.7 correlation
- **Scope**: Multiple operation types
- **Frequency**: Per correlation detection run
- **Typical Causes**:
  - Shared resource contention (table lock, index)
  - Same underlying query/data changed
  - Cascading slow operation (one slow operation blocks others)
  - Common database resource exhaustion

### Investigation Steps

#### Step 1: Identify Correlated Operations (< 2 minutes)

```sql
-- Get correlation analysis
SELECT * FROM pggit.detect_correlated_degradation(
    p_lookback_hours => 24,
    p_correlation_threshold => 0.7
);

-- Get shared resource analysis
SELECT op_a, op_b,
       'Check if operations access same table' as investigation
FROM pggit.detect_correlated_degradation(24, 0.7)
WHERE both_degrading = TRUE;
```

#### Step 2: Find Shared Resource (< 10 minutes)

```sql
-- Check if operations hit same table
-- (Requires analyzing operation_metadata or query source)

-- Example: Do both operations access performance_metrics?
SELECT DISTINCT operation_type
FROM pggit.performance_metrics
WHERE operation_metadata->>'table_accessed' IN (
    SELECT operation_metadata->>'table_accessed'
    FROM pggit.performance_metrics
    WHERE operation_type IN (:op_a, :op_b)
)
AND operation_type IN (:op_a, :op_b);
```

#### Step 3: Action

**If single shared table is identified**:
1. Follow DEGRADATION runbook for that table
2. Use VACUUM ANALYZE on shared table
3. Check indexes on shared table

**If dependency chain identified**:
1. Identify which operation is "root slow"
2. Apply THRESHOLD_EXCEEDED remediation to root operation
3. Monitor if dependent operations improve

---

## BASELINE_RECALC_ERROR Alerts

### Alert Characteristics

- **Type**: `BASELINE_RECALC_ERROR`
- **Trigger**: Error during automatic baseline recalculation
- **Scope**: All operation types affected
- **Frequency**: Per recalculation failure
- **Typical Causes**:
  - Database transaction timeout
  - Insufficient disk space
  - Corrupted performance metrics data
  - Temporal range validation failure
  - Permission issues

### Investigation Steps

```sql
-- Get error details
SELECT a.alert_id, a.alert_message, a.alert_data,
       a.created_at, a.alert_data->>'error_detail' as error_detail
FROM pggit.performance_alerts a
WHERE a.alert_type = 'BASELINE_RECALC_ERROR'
ORDER BY a.created_at DESC LIMIT 1;

-- Check baseline_recalc_execution logs
SELECT * FROM pggit.baseline_recalc_execution
WHERE status = 'FAILED'
ORDER BY start_time DESC LIMIT 5;
```

### Remediation

```sql
-- 1. Manual retry
SELECT pggit.recalculate_all_baselines_rolling(7, 10, FALSE);

-- 2. If still fails, check data integrity
SELECT COUNT(*) as total_metrics,
       COUNT(DISTINCT operation_type) as unique_operations,
       COUNT(NULL) as nulls_in_duration
FROM pggit.performance_metrics;

-- 3. If disk space issue:
-- Check PostgreSQL log for disk space errors
-- Run VACUUM FULL to reclaim space
VACUUM FULL ANALYZE pggit.performance_metrics;

-- 4. Check for corrupted data
SELECT operation_type, COUNT(*) as count,
       MIN(duration_microseconds) as min_us,
       MAX(duration_microseconds) as max_us,
       AVG(duration_microseconds) as avg_us
FROM pggit.performance_metrics
GROUP BY operation_type
HAVING AVG(duration_microseconds) < 0
   OR MAX(duration_microseconds) > 1000000000000 -- > 1000 seconds
ORDER BY count DESC;
```

---

## Alert Escalation Process

### Escalation Matrix

| Severity | Response Time | Escalation Level | Action |
|----------|--------------|------------------|--------|
| CRITICAL | < 5 min | Page on-call | Notify all relevant teams |
| WARNING | < 15 min | Create incident | Notify team in Slack |
| INFO | < 1 hour | Log for review | Mattermost channel |

### Escalation Rules

```sql
-- Implemented as trigger: If 3 similar alerts in 1 hour, escalate
-- View escalation history
SELECT operation_type, alert_type, severity, count(*) as recent_alerts,
       MIN(created_at) as first_alert, MAX(created_at) as last_alert
FROM pggit.performance_alerts
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
GROUP BY operation_type, alert_type, severity
HAVING count(*) >= 3
ORDER BY recent_alerts DESC;

-- Manual escalation
UPDATE pggit.performance_alerts
SET severity = 'CRITICAL'
WHERE alert_id = :alert_id
  AND severity = 'WARNING';
```

---

## On-Call Procedures

### Pre-Shift

```bash
# 1. Access to systems
# - VPN connection active
# - pgGit database access verified
# - Slack/Mattermost notifications on
# - Pager on and configured

# 2. Review recent alerts
psql -d pggit -c "
  SELECT operation_type, COUNT(*) as alert_count
  FROM pggit.performance_alerts
  WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  GROUP BY operation_type
  ORDER BY alert_count DESC;"

# 3. Check known issues
# - Review team Slack channel for ongoing incidents
# - Check if any alerts are snoozed and why
```

### During Shift

```bash
# 1. Alert received
# - Acknowledge in Slack (✅ reaction) or Mattermost
# - Note timestamp and create ticket

# 2. Investigate using provided runbooks
# - Follow alert type runbook
# - Document findings in incident ticket

# 3. Remediate or escalate
# - If clear remediation, execute
# - If unclear, snooze and escalate to primary
# - If complex, create war room

# 4. Verify resolution
# - Confirm metrics return to normal
# - Check that new baselines are reasonable
# - Document root cause
```

### Handoff

```bash
# 1. Document status
psql -d pggit -c "
  SELECT operation_type, severity, COUNT(*) as current_alerts
  FROM pggit.performance_alerts
  WHERE is_active = TRUE
  GROUP BY operation_type, severity;"

# 2. List snoozed alerts
psql -d pggit -c "
  SELECT operation_type, alert_type, snooze_until, snooze_reason
  FROM pggit.alert_snooze
  WHERE is_active = TRUE
  ORDER BY snooze_until;"

# 3. Communicate to incoming on-call
# - Active incidents and status
# - Snoozed alerts and when they expire
# - Any known issues or degradation
# - Recent changes or deployments
```

---

## Alert Suppression & Snoozin

### Use Cases

**Snooze during maintenance**:
```sql
-- Suppress all alerts during planned maintenance
SELECT pggit.snooze_alerts(
    p_operation_type => 'ALL',
    p_alert_type => 'ALL',
    p_snooze_minutes => 120,
    p_snooze_reason => 'Database maintenance window - table rebuild'
);
```

**Snooze known issue**:
```sql
-- Suppress alert while fix is being prepared
SELECT pggit.snooze_alerts(
    p_operation_type => 'get_history',
    p_alert_type => 'THRESHOLD_EXCEEDED',
    p_snooze_minutes => 480,
    p_snooze_reason => 'Table bloat known issue - VACUUM scheduled for 2025-12-28'
);
```

**Snooze transient behavior**:
```sql
-- Large batch operation that's expected to be slow
SELECT pggit.snooze_alerts(
    p_operation_type => 'merge_branches',
    p_alert_type => 'THRESHOLD_EXCEEDED',
    p_snooze_minutes => 60,
    p_snooze_reason => 'Large merge operation (1000+ files) - expected to run slow'
);
```

### Check Active Snoozes

```sql
SELECT snooze_id, operation_type, alert_type, snooze_until,
       snooze_reason, created_by, created_at
FROM pggit.alert_snooze
WHERE is_active = TRUE
  AND snooze_until > CURRENT_TIMESTAMP
ORDER BY snooze_until;
```

---

## Metrics & Success Criteria

### Alert Health Metrics

```sql
-- Alert resolution time (target: <30 min for CRITICAL)
WITH alert_times AS (
    SELECT a.alert_id, a.created_at,
           (SELECT created_at FROM pggit.alert_snooze
            WHERE operation_type = a.operation_type
              AND alert_type = a.alert_type
              AND created_at > a.created_at
            LIMIT 1) as snoozed_at,
           EXTRACT(EPOCH FROM (
               COALESCE(
                   (SELECT created_at FROM pggit.alert_snooze
                    WHERE operation_type = a.operation_type
                      AND alert_type = a.alert_type
                      AND created_at > a.created_at
                    LIMIT 1),
                   CURRENT_TIMESTAMP
               ) - a.created_at
           )) / 60 as resolution_minutes
    FROM pggit.performance_alerts a
    WHERE a.severity = 'CRITICAL'
      AND a.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
)
SELECT AVG(resolution_minutes) as avg_resolution_min,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY resolution_minutes) as p95_resolution_min,
       COUNT(*) as total_critical_alerts
FROM alert_times;

-- False positive rate (target: <10%)
SELECT
    (SELECT COUNT(*) FROM pggit.performance_alerts
     WHERE alert_type IN ('ANOMALY', 'DEGRADATION')
       AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    )::NUMERIC /
    (SELECT COUNT(*) FROM pggit.performance_alerts
     WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    ) * 100 as false_positive_percent;

-- Snooze usage (should be <5% of alerts snoozed at any time)
SELECT COUNT(*) as active_snoozes,
       (SELECT COUNT(*) FROM pggit.performance_alerts WHERE is_active = TRUE)
       as active_alerts,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM pggit.performance_alerts WHERE is_active = TRUE), 2)
       as snooze_percent
FROM pggit.alert_snooze
WHERE is_active = TRUE AND snooze_until > CURRENT_TIMESTAMP;
```

### Success Criteria

- ✅ **Alert response**: 95% of CRITICAL alerts acknowledged within 5 minutes
- ✅ **Resolution time**: Average CRITICAL resolution < 30 minutes
- ✅ **Accuracy**: False positive rate < 10%
- ✅ **Availability**: Alert system <0.1% downtime
- ✅ **Communication**: 100% of CRITICAL alerts routed to appropriate channel
- ✅ **Documentation**: All runbooks maintained and reviewed quarterly

---

## Appendix: Quick Reference

### Common Commands

```bash
# View all active alerts
psql -d pggit -c "SELECT * FROM pggit.performance_alerts WHERE is_active = TRUE;"

# Acknowledge alert via CLI
psql -d pggit -c "SELECT pggit.snooze_alerts('merge_branches', 'THRESHOLD_EXCEEDED', 60);"

# Check alert thresholds
psql -d pggit -c "SELECT operation_type, p99_microseconds / 1000 as p99_ms, alert_threshold_multiplier FROM pggit.performance_baselines WHERE is_active = TRUE;"

# Manual baseline recalc
psql -d pggit -c "SELECT * FROM pggit.recalculate_all_baselines_rolling(7, 10, FALSE);"
```

### Team Contact List

| Role | Escalation | Contact |
|------|------------|---------|
| DBA | Database issues | @dba-team (Slack) |
| Platform | Infrastructure | @platform-team (Slack) |
| Security | Access/encryption issues | @security-team (Slack) |
| Product | Performance requirements | @product-team (Slack) |

---

**Document Version**: 1.0.0
**Last Updated**: 2025-12-27
**Next Review**: 2026-03-27 (quarterly)
**Owner**: Phase 7 Development Team
