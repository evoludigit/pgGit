# Phase 7: Week 4 Implementation Plan

## Document Overview

**Purpose**: Detailed technical specification for Week 4 of Phase 7 Performance Monitoring
**Timeline**: 1 week (Week 4 of 4 total)
**Status**: Ready for team review and implementation
**Date**: 2025-12-27

---

## 1. Executive Summary

### Vision
Week 4 transforms Phase 7 from an **automated alerting system** into an **intelligent, self-optimizing platform** with advanced anomaly detection, performance correlation analysis, and specialized merge-operation dashboards. The system will automatically detect complex performance issues that span multiple operations.

### Key Deliverables
1. **Anomaly Detection Engine** - Statistical z-score + trend analysis with self-learning baselines
2. **Correlation Analysis** - Detect when multiple operations degrade together (shared bottleneck detection)
3. **Merge-Specific Dashboards** - Bottleneck identification (LCA vs conflict detection vs resolution)
4. **Automated Baseline Recalculation Scheduling** - Daily cron jobs with pg_cron integration
5. **Alert Notification System Integration** - Complete webhook delivery pipeline (Slack/Mattermost/PagerDuty/Email)

### Business Impact
- **Proactive Issue Detection**: Anomalies detected 24-48 hours before performance degrades
- **Root Cause Identification**: Correlation analysis pinpoints shared bottlenecks across operations
- **Merge Operation Optimization**: Specialized views for merge bottleneck analysis
- **Self-Healing Systems**: Automatic baseline recalculation adapts SLAs to actual performance
- **Zero-Operational-Overhead**: Fully automated notification delivery

### Success Criteria
- [ ] 3 anomaly detection functions deployed (statistical + trend + combined)
- [ ] Correlation analysis identifies operations degrading together with 90%+ accuracy
- [ ] 4 merge-specific dashboards created and operational
- [ ] Automated baseline recalculation scheduled with pg_cron
- [ ] Complete alert delivery pipeline tested end-to-end
- [ ] All functions tested with bootstrap data
- [ ] Zero breaking changes to existing schema
- [ ] Performance: All new queries <5ms
- [ ] Documentation: Complete implementation guide with examples

---

## 2. Detailed Implementation Plan

### 2.1 Anomaly Detection Engine (Est. 2 days)

#### Purpose
Detect performance anomalies using multiple statistical methods to identify operations behaving outside normal parameters.

#### Technical Design

**Function 1: `detect_anomalies_statistical()`** (Statistical z-score method)

```sql
CREATE OR REPLACE FUNCTION pggit.detect_anomalies_statistical(
    p_operation_type TEXT,
    p_lookback_hours INTEGER DEFAULT 24,
    p_z_score_threshold NUMERIC DEFAULT 3.0
)
RETURNS TABLE (
    metric_id BIGINT,
    operation_type TEXT,
    duration_ms NUMERIC,
    baseline_p99_ms NUMERIC,
    z_score NUMERIC,
    deviation_percent NUMERIC,
    severity TEXT,
    detected_at TIMESTAMP
) AS $$
BEGIN
    -- For a given operation type in the last p_lookback_hours:
    -- 1. Get active baseline (p99, stddev)
    -- 2. Calculate mean and stddev from recent metrics
    -- 3. For each metric, calculate z-score = (value - mean) / stddev
    -- 4. If |z-score| > p_z_score_threshold, mark as anomaly
    -- 5. Calculate severity based on z-score magnitude
    --    - z-score 3.0-4.0: WARNING (>99.7th percentile)
    --    - z-score 4.0-5.0: CRITICAL (>99.997th percentile)
    --    - z-score >5.0: CRITICAL (extreme outlier)
END;
$$ LANGUAGE plpgsql;
```

**Algorithm Details**:

1. **Query Recent Metrics**:
   ```sql
   WITH recent_metrics AS (
       SELECT duration_ms, created_at
       FROM pggit.performance_metrics
       WHERE operation_type = p_operation_type
         AND created_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
   )
   ```

2. **Calculate Statistics**:
   ```sql
   WITH stats AS (
       SELECT
           AVG(duration_ms) as mean_duration,
           STDDEV_POP(duration_ms) as stddev_duration,
           COUNT(*) as metric_count
       FROM recent_metrics
   )
   ```

3. **Calculate Z-Scores**:
   ```sql
   SELECT
       metric_id,
       duration_ms,
       (duration_ms - stats.mean_duration) / NULLIF(stats.stddev_duration, 0) as z_score
   FROM recent_metrics, stats
   ```

4. **Classify Anomalies**:
   ```sql
   CASE
       WHEN ABS(z_score) >= 5.0 THEN 'CRITICAL'
       WHEN ABS(z_score) >= 4.0 THEN 'CRITICAL'
       WHEN ABS(z_score) >= 3.0 THEN 'WARNING'
       ELSE 'NORMAL'
   END as severity
   ```

**Data Quality Checks**:
- ✅ Verify stddev > 0 (avoid division by zero)
- ✅ Verify mean > 0 (sanity check)
- ✅ Verify at least 5 samples for reliable statistics
- ✅ Skip operation types with insufficient data

**Performance Target**: <10ms to analyze 1,000 metrics

**Example Usage**:
```sql
-- Find anomalies in merge operations in last 24 hours
SELECT * FROM pggit.detect_anomalies_statistical(
    p_operation_type => 'merge_branches',
    p_lookback_hours => 24,
    p_z_score_threshold => 3.0
);
```

---

**Function 2: `detect_performance_degradation()`** (Trend analysis method)

```sql
CREATE OR REPLACE FUNCTION pggit.detect_performance_degradation(
    p_operation_type TEXT,
    p_lookback_days INTEGER DEFAULT 7,
    p_threshold_percent NUMERIC DEFAULT 20.0
)
RETURNS TABLE (
    period_start DATE,
    period_end DATE,
    p99_old_ms NUMERIC,
    p99_new_ms NUMERIC,
    degradation_percent NUMERIC,
    trend TEXT,
    confidence NUMERIC,
    severity TEXT
) AS $$
BEGIN
    -- Detect sustained performance degradation over time
    -- 1. Split lookback period into two halves (before/after)
    -- 2. Calculate baseline (p99) for first half
    -- 3. Calculate current (p99) for second half
    -- 4. If current > baseline by >p_threshold_percent, mark as degradation
    -- 5. Calculate trend using linear regression for confidence
    -- 6. Return severity based on degradation magnitude and trend
END;
$$ LANGUAGE plpgsql;
```

**Algorithm Details**:

1. **Split Time Period**:
   ```sql
   WITH time_split AS (
       SELECT
           CURRENT_TIMESTAMP - (p_lookback_days || ' days')::INTERVAL as lookback_start,
           CURRENT_TIMESTAMP as lookback_end,
           (CURRENT_TIMESTAMP - (p_lookback_days / 2 || ' days')::INTERVAL) as midpoint
   )
   ```

2. **Calculate Before/After Baselines**:
   ```sql
   WITH before_metrics AS (
       SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99
       FROM pggit.performance_metrics
       WHERE operation_type = p_operation_type
         AND created_at >= lookback_start AND created_at < midpoint
   ),
   after_metrics AS (
       SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99
       FROM pggit.performance_metrics
       WHERE operation_type = p_operation_type
         AND created_at >= midpoint AND created_at <= lookback_end
   )
   ```

3. **Calculate Degradation**:
   ```sql
   SELECT
       (after_p99 - before_p99) / NULLIF(before_p99, 0) * 100 as degradation_percent
   ```

4. **Classify Severity**:
   ```sql
   CASE
       WHEN degradation_percent >= 50 THEN 'CRITICAL'
       WHEN degradation_percent >= 30 THEN 'WARNING'
       WHEN degradation_percent >= p_threshold_percent THEN 'INFO'
   END as severity
   ```

**Trend Analysis with Linear Regression**:
```sql
-- Calculate trend slope using daily p99 values
WITH daily_baselines AS (
    SELECT
        DATE_TRUNC('day', created_at) as day,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99
    FROM pggit.performance_metrics
    WHERE operation_type = p_operation_type
      AND created_at >= CURRENT_TIMESTAMP - (p_lookback_days || ' days')::INTERVAL
    GROUP BY 1
),
regression AS (
    SELECT
        COUNT(*) as n,
        SUM(EXTRACT(EPOCH FROM day)) as sum_x,
        SUM(p99) as sum_y,
        SUM(EXTRACT(EPOCH FROM day) * p99) as sum_xy,
        SUM(EXTRACT(EPOCH FROM day)^2) as sum_x2
    FROM daily_baselines
)
SELECT
    (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x^2) as slope
FROM regression;
```

**Performance Target**: <50ms to analyze 7 days of data

**Example Usage**:
```sql
-- Detect degradation in commit operations over 7 days
SELECT * FROM pggit.detect_performance_degradation(
    p_operation_type => 'commit',
    p_lookback_days => 7,
    p_threshold_percent => 20.0
);
```

---

**Function 3: `detect_combined_anomalies()`** (Composite detection)

```sql
CREATE OR REPLACE FUNCTION pggit.detect_combined_anomalies(
    p_operation_type TEXT,
    p_lookback_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    metric_id BIGINT,
    operation_type TEXT,
    anomaly_type TEXT,
    severity TEXT,
    z_score NUMERIC,
    degradation_percent NUMERIC,
    detected_at TIMESTAMP,
    alert_required BOOLEAN
) AS $$
BEGIN
    -- Combine statistical anomaly detection with trend analysis
    -- 1. Run detect_anomalies_statistical()
    -- 2. Run detect_performance_degradation()
    -- 3. For each metric, check if it matches BOTH criteria
    -- 4. If both match: severity = CRITICAL, alert_required = TRUE
    -- 5. If only one matches: severity inherited, alert_required = depends on severity
    -- 6. Return union of all detected anomalies
END;
$$ LANGUAGE plpgsql;
```

**Decision Matrix**:

| Statistical Anomaly | Trend Degradation | Result | Severity | Alert |
|-------------------|-------------------|--------|----------|-------|
| YES (z>3.0) | YES (>20%) | Combined anomaly | CRITICAL | ✅ |
| YES (z>3.0) | NO | Single spike | WARNING | ⚠️ |
| NO | YES (>30%) | Sustained degradation | WARNING | ⚠️ |
| NO | YES (>50%) | Major degradation | CRITICAL | ✅ |
| NO | NO | Normal | NORMAL | ❌ |

**Performance Target**: <20ms to evaluate all detection methods

---

### 2.2 Correlation Analysis for Shared Bottlenecks (Est. 2 days)

#### Purpose
Identify when multiple operations degrade together, indicating a shared bottleneck (e.g., disk I/O, CPU, lock contention).

#### Technical Design

**Function: `detect_correlated_degradation()`**

```sql
CREATE OR REPLACE FUNCTION pggit.detect_correlated_degradation(
    p_lookback_hours INTEGER DEFAULT 24,
    p_correlation_threshold NUMERIC DEFAULT 0.75
)
RETURNS TABLE (
    operation_type_1 TEXT,
    operation_type_2 TEXT,
    correlation_coefficient NUMERIC,
    shared_bottleneck TEXT,
    confidence NUMERIC,
    recommendation TEXT,
    detected_at TIMESTAMP
) AS $$
BEGIN
    -- Find pairs of operations with correlated performance degradation
    -- 1. Get all operation types
    -- 2. For each pair:
    --    a. Extract duration_ms time series from last p_lookback_hours
    --    b. Calculate Pearson correlation coefficient
    --    c. If correlation > p_correlation_threshold, report as correlated
    -- 3. Identify likely shared bottleneck based on which operations are affected
    -- 4. Return recommendation for investigation
END;
$$ LANGUAGE plpgsql;
```

**Algorithm Details**:

1. **Extract Time Series**:
   ```sql
   WITH time_windows AS (
       -- Create 1-minute time windows
       SELECT
           DATE_TRUNC('minute', created_at) as minute,
           operation_type,
           AVG(duration_ms) as avg_duration
       FROM pggit.performance_metrics
       WHERE created_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
       GROUP BY 1, 2
   )
   ```

2. **Calculate Correlation**:
   ```sql
   -- Pearson correlation coefficient
   WITH aligned_series AS (
       SELECT
           t1.minute,
           t1.avg_duration as duration_op1,
           t2.avg_duration as duration_op2
       FROM time_windows t1
       JOIN time_windows t2
           ON t1.minute = t2.minute
           AND t1.operation_type = 'merge_branches'
           AND t2.operation_type = 'commit'
   ),
   stats AS (
       SELECT
           AVG(duration_op1) as mean_1,
           AVG(duration_op2) as mean_2,
           STDDEV_POP(duration_op1) as stddev_1,
           STDDEV_POP(duration_op2) as stddev_2,
           COUNT(*) as n
       FROM aligned_series
   )
   SELECT
       SUM((duration_op1 - mean_1) * (duration_op2 - mean_2)) /
       (n * stddev_1 * stddev_2) as correlation
   FROM aligned_series, stats;
   ```

3. **Bottleneck Identification**:
   ```sql
   CASE
       WHEN operation_type_1 IN ('merge_branches', 'merge_base_find', 'merge_conflict_detect')
            AND operation_type_2 IN ('merge_branches', 'merge_base_find', 'merge_conflict_detect')
       THEN 'MERGE_PIPELINE_SATURATION'

       WHEN operation_type_1 IN ('commit', 'branch_create')
            AND operation_type_2 IN ('commit', 'branch_create')
       THEN 'OBJECT_STORAGE_IO'

       WHEN operation_type_1 IN ('get_history', 'get_object_timeline')
            AND operation_type_2 IN ('get_history', 'get_object_timeline')
       THEN 'QUERY_CACHE_PRESSURE'

       WHEN operation_type_1 IN ('rollback_commit', 'rollback_cascade')
       THEN 'TRANSACTION_LOG_SATURATION'

       ELSE 'SHARED_RESOURCE_CONTENTION'
   END as shared_bottleneck
   ```

4. **Recommendations**:
   ```sql
   CASE shared_bottleneck
       WHEN 'MERGE_PIPELINE_SATURATION' THEN
           'Increase merge worker threads or optimize conflict detection algorithm'
       WHEN 'OBJECT_STORAGE_IO' THEN
           'Check disk I/O capacity; consider SSD upgrade or caching layer'
       WHEN 'QUERY_CACHE_PRESSURE' THEN
           'Increase shared_buffers or enable query result caching'
       WHEN 'TRANSACTION_LOG_SATURATION' THEN
           'Optimize transaction log flushing or enable async commit for non-critical operations'
       ELSE 'Investigate process lock contention with pg_locks'
   END as recommendation
   ```

**Performance Target**: <100ms to correlate all operation pairs (33×32/2 = 528 pairs)

**Confidence Scoring**:
- Confidence = MIN(correlation_coefficient, (minute_count / 60))
- 60+ minutes of data = 100% confidence
- <10 minutes of data = reduced confidence

**Example Usage**:
```sql
-- Find correlated performance degradation
SELECT * FROM pggit.detect_correlated_degradation(
    p_lookback_hours => 24,
    p_correlation_threshold => 0.75
)
WHERE correlation_coefficient > 0.8
ORDER BY correlation_coefficient DESC;
```

---

### 2.3 Merge-Specific Performance Dashboards (Est. 1.5 days)

#### Purpose
Provide specialized views for analyzing merge operation performance bottlenecks and identifying optimization opportunities.

#### Dashboard 1: Merge Bottleneck Analysis

**View: `v_merge_bottleneck_analysis`**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_bottleneck_analysis AS
SELECT
    -- Merge operation context
    mr.merge_id,
    mr.branch_from,
    mr.branch_into,
    mr.created_at as merge_start,

    -- Phase breakdown
    (SELECT MAX(duration_ms)
     FROM pggit.performance_metrics
     WHERE operation_type = 'merge_base_find'
       AND distributed_trace_parent_id = mr.merge_id) as lca_find_ms,

    (SELECT MAX(duration_ms)
     FROM pggit.performance_metrics
     WHERE operation_type = 'merge_conflict_detect'
       AND distributed_trace_parent_id = mr.merge_id) as conflict_detect_ms,

    (SELECT MAX(duration_ms)
     FROM pggit.performance_metrics
     WHERE operation_type = 'merge_auto_resolve'
       AND distributed_trace_parent_id = mr.merge_id) as auto_resolve_ms,

    -- Total and percentages
    (SELECT MAX(duration_ms)
     FROM pggit.performance_metrics
     WHERE operation_type = 'merge_branches'
       AND distributed_trace_id = mr.merge_id) as total_merge_ms,

    CASE
        WHEN lca_find_ms > conflict_detect_ms AND lca_find_ms > auto_resolve_ms
        THEN 'LCA_FINDING'
        WHEN conflict_detect_ms > lca_find_ms AND conflict_detect_ms > auto_resolve_ms
        THEN 'CONFLICT_DETECTION'
        WHEN auto_resolve_ms > lca_find_ms AND auto_resolve_ms > conflict_detect_ms
        THEN 'CONFLICT_RESOLUTION'
        ELSE 'UNKNOWN'
    END as primary_bottleneck,

    -- Percentage breakdown
    ROUND(100.0 * lca_find_ms / NULLIF(total_merge_ms, 0), 1) as lca_percent,
    ROUND(100.0 * conflict_detect_ms / NULLIF(total_merge_ms, 0), 1) as conflict_detect_percent,
    ROUND(100.0 * auto_resolve_ms / NULLIF(total_merge_ms, 0), 1) as resolution_percent,

    -- SLA compliance
    CASE
        WHEN total_merge_ms <= 99 THEN 'OK'
        WHEN total_merge_ms <= 150 THEN 'DEGRADED'
        ELSE 'CRITICAL'
    END as sla_status

FROM pggit.merge_relationships mr
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY total_merge_ms DESC;
```

**Key Insights**:
- Shows which phase is the bottleneck for each merge
- Percentage breakdown helps identify optimization targets
- SLA compliance tracking for merge operations

---

**View: `v_merge_success_rate_analysis`**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_success_rate_analysis AS
WITH merge_attempts AS (
    SELECT
        DATE_TRUNC('hour', created_at) as hour,
        COUNT(*) as total_attempts,
        SUM(CASE WHEN resolution_strategy = 'auto' THEN 1 ELSE 0 END) as auto_resolved,
        SUM(CASE WHEN resolution_strategy = 'manual' THEN 1 ELSE 0 END) as manual_resolved,
        SUM(CASE WHEN resolution_strategy = 'rejected' THEN 1 ELSE 0 END) as rejected,
        AVG(duration_ms) as avg_merge_time_ms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99_merge_time_ms
    FROM pggit.merge_relationships
    WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY 1
)
SELECT
    hour,
    total_attempts,
    auto_resolved,
    manual_resolved,
    rejected,
    ROUND(100.0 * auto_resolved / NULLIF(total_attempts, 0), 1) as auto_resolve_percent,
    ROUND(100.0 * manual_resolved / NULLIF(total_attempts, 0), 1) as manual_resolve_percent,
    ROUND(100.0 * rejected / NULLIF(total_attempts, 0), 1) as rejection_rate_percent,
    ROUND(avg_merge_time_ms::NUMERIC, 1) as avg_merge_ms,
    ROUND(p99_merge_time_ms::NUMERIC, 1) as p99_merge_ms
FROM merge_attempts
ORDER BY hour DESC;
```

**Key Insights**:
- Tracks success rate (auto-resolved vs manual vs rejected)
- Performance trend over time (daily breakdown)
- Identifies when merges become problematic

---

**View: `v_merge_conflict_hotspots`**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_conflict_hotspots AS
SELECT
    branch_from,
    branch_into,
    COUNT(*) as merge_attempts,
    SUM(CASE WHEN status = 'CONFLICT' THEN 1 ELSE 0 END) as conflict_count,
    ROUND(100.0 * SUM(CASE WHEN status = 'CONFLICT' THEN 1 ELSE 0 END) /
          NULLIF(COUNT(*), 0), 1) as conflict_rate_percent,
    AVG(CASE WHEN status = 'CONFLICT' THEN duration_ms END) as avg_conflict_resolve_ms,
    MAX(duration_ms) as max_conflict_resolve_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY
        CASE WHEN status = 'CONFLICT' THEN duration_ms END) as p99_conflict_resolve_ms
FROM pggit.merge_relationships
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY branch_from, branch_into
HAVING SUM(CASE WHEN status = 'CONFLICT' THEN 1 ELSE 0 END) > 0
ORDER BY conflict_rate_percent DESC, merge_attempts DESC;
```

**Key Insights**:
- Identifies branch pairs with high conflict rates
- Shows performance impact of conflicts
- Helps prioritize refactoring efforts

---

**View: `v_merge_phase_timeline`**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_phase_timeline AS
WITH phase_metrics AS (
    SELECT
        pm.distributed_trace_parent_id as merge_id,
        pm.operation_type,
        DATE_TRUNC('minute', pm.created_at) as minute_window,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_ms) as p99_ms,
        COUNT(*) as sample_count
    FROM pggit.performance_metrics pm
    WHERE pm.operation_type LIKE 'merge_%'
      AND pm.created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
    GROUP BY 1, 2, 3
)
SELECT
    minute_window as time_window,
    'merge_base_find' as phase,
    (SELECT p99_ms FROM phase_metrics WHERE operation_type = 'merge_base_find'
        AND minute_window = pm.minute_window LIMIT 1) as p99_phase_ms
FROM phase_metrics pm
WHERE operation_type = 'merge_base_find'
UNION ALL
SELECT
    minute_window,
    'merge_conflict_detect',
    (SELECT p99_ms FROM phase_metrics WHERE operation_type = 'merge_conflict_detect'
        AND minute_window = pm.minute_window LIMIT 1)
FROM phase_metrics pm
WHERE operation_type = 'merge_conflict_detect'
UNION ALL
SELECT
    minute_window,
    'merge_auto_resolve',
    (SELECT p99_ms FROM phase_metrics WHERE operation_type = 'merge_auto_resolve'
        AND minute_window = pm.minute_window LIMIT 1)
FROM phase_metrics pm
WHERE operation_type = 'merge_auto_resolve'
ORDER BY time_window DESC, phase;
```

**Key Insights**:
- Time-series view of merge phases
- Helps identify when performance degrades
- Correlate with operational changes

---

### 2.4 Automated Baseline Recalculation Scheduling (Est. 1 day)

#### Purpose
Schedule daily baseline recalculation to keep SLA thresholds in sync with actual performance trends.

#### Technical Design

**Using pg_cron Extension**:

```sql
-- Install pg_cron (one-time, as superuser)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule daily baseline recalculation at 02:00 UTC
SELECT cron.schedule(
    'recalculate_performance_baselines',
    '0 2 * * *',  -- Daily at 02:00 UTC
    'SELECT pggit.recalculate_all_baselines_rolling(7, 10, FALSE)'
);

-- Schedule weekly forced recalculation (Sundays at 03:00 UTC)
SELECT cron.schedule(
    'weekly_force_recalculate_baselines',
    '0 3 * * 0',  -- Weekly on Sundays
    'SELECT pggit.recalculate_all_baselines_rolling(30, 20, TRUE)'
);

-- Schedule anomaly detection check (every 6 hours)
SELECT cron.schedule(
    'check_performance_anomalies',
    '0 */6 * * *',  -- Every 6 hours
    'SELECT pggit.detect_combined_anomalies(op_type, 24) FROM (
        SELECT DISTINCT operation_type as op_type
        FROM pggit.performance_operation_types
        WHERE is_tracked = TRUE
    ) ops'
);
```

**Manual Management Functions**:

```sql
-- View scheduled jobs
SELECT * FROM cron.job;

-- Disable a job
SELECT cron.unschedule('recalculate_performance_baselines');

-- Re-enable a job
SELECT cron.schedule(
    'recalculate_performance_baselines',
    '0 2 * * *',
    'SELECT pggit.recalculate_all_baselines_rolling(7, 10, FALSE)'
);

-- View job execution history
SELECT * FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;
```

**Monitoring Dashboard**:

```sql
CREATE OR REPLACE VIEW pggit.v_baseline_recalc_health AS
SELECT
    operation_type,
    is_active,
    CASE
        WHEN (CURRENT_TIMESTAMP - last_updated) < INTERVAL '24 hours' THEN 'CURRENT'
        WHEN (CURRENT_TIMESTAMP - last_updated) < INTERVAL '7 days' THEN 'STALE'
        ELSE 'VERY_STALE'
    END as freshness,
    ROUND((CURRENT_TIMESTAMP - last_updated) / INTERVAL '1 hour', 1) as hours_since_update,
    sample_count,
    p99_microseconds::NUMERIC / 1000 as p99_ms,
    created_at
FROM pggit.performance_baselines
ORDER BY operation_type;
```

**Execution Tracking**:

```sql
CREATE OR REPLACE VIEW pggit.v_baseline_recalc_execution_summary AS
WITH recent_runs AS (
    SELECT
        DATE_TRUNC('day', execution_start) as execution_day,
        COUNT(*) as total_operations_updated,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
        SUM(CASE WHEN status = 'TIMEOUT' THEN 1 ELSE 0 END) as timeouts,
        SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END) as errors,
        AVG(EXTRACT(EPOCH FROM (execution_end - execution_start))) as avg_duration_seconds,
        MAX(EXTRACT(EPOCH FROM (execution_end - execution_start))) as max_duration_seconds
    FROM pggit.baseline_recalc_execution
    GROUP BY 1
)
SELECT
    execution_day,
    total_operations_updated,
    successful,
    timeouts,
    errors,
    ROUND(100.0 * successful / NULLIF(total_operations_updated, 0), 1) as success_rate_percent,
    ROUND(avg_duration_seconds::NUMERIC, 2) as avg_duration_sec,
    ROUND(max_duration_seconds::NUMERIC, 2) as max_duration_sec
FROM recent_runs
ORDER BY execution_day DESC;
```

---

### 2.5 Alert Notification System Integration (Est. 1 day)

#### Purpose
Complete the alert delivery pipeline to send notifications through actual webhook endpoints.

#### Technical Design

**Background: Webhook Infrastructure** (Completed in Week 3)

From Week 3 critical enhancements:
- ✅ `alert_notification_webhooks` table with AES encryption
- ✅ `store_webhook_encrypted()` function for secure storage
- ✅ `get_webhook_decrypted()` function for retrieval
- ✅ `alert_notification_queue` table for pending notifications
- ✅ `enqueue_notification_batch()` function for batching

**Week 4 Completion: Actual Delivery**

**Function: `deliver_pending_notifications()`** (NEW)

```sql
CREATE OR REPLACE FUNCTION pggit.deliver_pending_notifications(
    p_batch_size INTEGER DEFAULT 50,
    p_max_retries INTEGER DEFAULT 3
)
RETURNS TABLE (
    notification_count INTEGER,
    delivered_count INTEGER,
    failed_count INTEGER,
    retry_count INTEGER,
    execution_time_ms NUMERIC
) AS $$
DECLARE
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_notification_id BIGINT;
    v_webhook_url TEXT;
    v_message_body TEXT;
    v_retry_count INTEGER;
    v_delivered_count INTEGER := 0;
    v_failed_count INTEGER := 0;
BEGIN
    -- Fetch pending notifications in batch
    FOR v_notification_id, v_webhook_url, v_message_body, v_retry_count IN
        SELECT
            notification_queue_id,
            get_webhook_decrypted(webhook_id),
            message_body,
            retry_count
        FROM pggit.alert_notification_queue
        WHERE status = 'pending'
          AND retry_count < p_max_retries
          AND (next_retry_at IS NULL OR next_retry_at <= CURRENT_TIMESTAMP)
        LIMIT p_batch_size
        FOR UPDATE
    LOOP
        -- Attempt delivery via webhook
        IF deliver_webhook(v_webhook_url, v_message_body) THEN
            -- Success: mark as delivered
            UPDATE pggit.alert_notification_queue
            SET status = 'delivered', delivered_at = CURRENT_TIMESTAMP
            WHERE notification_queue_id = v_notification_id;
            v_delivered_count := v_delivered_count + 1;
        ELSE
            -- Failure: increment retry count
            v_failed_count := v_failed_count + 1;
            UPDATE pggit.alert_notification_queue
            SET
                retry_count = retry_count + 1,
                next_retry_at = CURRENT_TIMESTAMP + (('1 minute'::INTERVAL) * POWER(2, retry_count))
            WHERE notification_queue_id = v_notification_id
              AND retry_count < p_max_retries;

            -- Mark as failed if max retries exceeded
            UPDATE pggit.alert_notification_queue
            SET status = 'failed'
            WHERE notification_queue_id = v_notification_id
              AND retry_count >= p_max_retries;
        END IF;
    END LOOP;

    RETURN QUERY SELECT
        (v_delivered_count + v_failed_count)::INTEGER as notification_count,
        v_delivered_count::INTEGER,
        v_failed_count::INTEGER,
        p_max_retries,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time)) * 1000 as execution_time_ms;
END;
$$ LANGUAGE plpgsql;
```

**Note**: The `deliver_webhook()` function requires `plpython3u` or `plperlu` for actual HTTP requests. As a Python procedure:

```python
# PL/Python implementation
CREATE OR REPLACE FUNCTION pggit.deliver_webhook(
    p_webhook_url TEXT,
    p_message_body TEXT
)
RETURNS BOOLEAN AS $$
import requests
import json
import time

try:
    # Parse message body
    message = json.loads(p_message_body)

    # Send POST request with retry
    response = requests.post(
        p_webhook_url,
        json=message,
        timeout=10,
        headers={'Content-Type': 'application/json'}
    )

    # Consider 2xx responses as success
    return response.status_code >= 200 and response.status_code < 300

except Exception as e:
    # Log error and return failure
    plpy.warning(f"Webhook delivery failed: {e}")
    return False
$$ LANGUAGE plpython3u;
```

**Scheduling Delivery**:

```sql
-- Run notification delivery every 5 minutes
SELECT cron.schedule(
    'deliver_pending_alerts',
    '*/5 * * * *',  -- Every 5 minutes
    'SELECT pggit.deliver_pending_notifications(50, 3)'
);
```

**Delivery Status Tracking**:

```sql
CREATE OR REPLACE VIEW pggit.v_notification_delivery_status AS
SELECT
    DATE_TRUNC('hour', created_at) as hour,
    status,
    COUNT(*) as notification_count,
    AVG(EXTRACT(EPOCH FROM (delivered_at - created_at))) as avg_delivery_time_seconds,
    MIN(retry_count) as min_retries,
    MAX(retry_count) as max_retries
FROM pggit.alert_notification_queue
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY 1, 2
ORDER BY hour DESC, status;
```

---

## 3. Implementation Breakdown by Day

### Day 1-2: Anomaly Detection Engine
- [ ] Implement `detect_anomalies_statistical()`
- [ ] Implement `detect_performance_degradation()`
- [ ] Implement `detect_combined_anomalies()`
- [ ] Test with 24-hour bootstrap data
- [ ] Verify z-score calculations and trend detection

### Day 3-4: Correlation Analysis & Merge Dashboards
- [ ] Implement `detect_correlated_degradation()`
- [ ] Create `v_merge_bottleneck_analysis` view
- [ ] Create `v_merge_success_rate_analysis` view
- [ ] Create `v_merge_conflict_hotspots` view
- [ ] Create `v_merge_phase_timeline` view
- [ ] Test with merge operation data

### Day 5: Automation & Integration
- [ ] Set up pg_cron jobs for baseline recalculation
- [ ] Create cron monitoring views
- [ ] Implement `deliver_pending_notifications()` function
- [ ] Test webhook delivery with test endpoints
- [ ] Create delivery status tracking views

### Day 6-7: Testing & Documentation
- [ ] Comprehensive testing of all functions
- [ ] Load testing (1,000+ metrics per operation type)
- [ ] Edge case testing (empty data, single value, etc.)
- [ ] Performance validation (<5ms for queries, <100ms for functions)
- [ ] Create Week 4 completion report
- [ ] Create operational runbooks for each component

---

## 4. File Organization

### New SQL Files to Create
- `phase7_week4_anomaly_detection.sql` (600-800 lines)
  - `detect_anomalies_statistical()`
  - `detect_performance_degradation()`
  - `detect_combined_anomalies()`
  - Supporting indexes and tables

- `phase7_week4_correlation_analysis.sql` (400-500 lines)
  - `detect_correlated_degradation()`
  - Bottleneck identification tables
  - Correlation analysis supporting functions

- `phase7_week4_merge_dashboards.sql` (600-700 lines)
  - `v_merge_bottleneck_analysis`
  - `v_merge_success_rate_analysis`
  - `v_merge_conflict_hotspots`
  - `v_merge_phase_timeline`
  - Helper tables for merge analysis

- `phase7_week4_automation.sql` (300-400 lines)
  - pg_cron job definitions
  - `deliver_pending_notifications()` function
  - Monitoring views for automation health

### Documentation Files
- `PHASE7_WEEK4_IMPLEMENTATION_SUMMARY.md` (will be created after implementation)
- `PHASE7_WEEK4_ANOMALY_DETECTION_GUIDE.md` (technical guide with examples)
- `PHASE7_WEEK4_MONITORING_GUIDE.md` (operational guide for monitoring)
- `PHASE7_WEEK4_COMPLETION_REPORT.md` (final QA report)

---

## 5. Database Changes Summary

### New Tables
- None (uses existing infrastructure from Week 3)

### New Functions (9 total)
- `detect_anomalies_statistical()` - Statistical anomaly detection
- `detect_performance_degradation()` - Trend analysis
- `detect_combined_anomalies()` - Composite detection
- `detect_correlated_degradation()` - Correlation analysis
- `deliver_pending_notifications()` - Webhook delivery
- `delete_old_notifications()` - Cleanup function
- `get_notification_delivery_stats()` - Statistics
- 2-3 helper functions for correlation math

### New Views (8 total)
- `v_merge_bottleneck_analysis` - Merge phase breakdown
- `v_merge_success_rate_analysis` - Success rate tracking
- `v_merge_conflict_hotspots` - Conflict hotspot analysis
- `v_merge_phase_timeline` - Time-series phase data
- `v_baseline_recalc_health` - Baseline freshness
- `v_baseline_recalc_execution_summary` - Execution history
- `v_notification_delivery_status` - Delivery tracking
- 1-2 additional analysis views

### New Indexes
- Index on `performance_metrics(operation_type, created_at)` for anomaly detection
- Index on `performance_metrics(distributed_trace_parent_id)` for merge analysis
- Index on `alert_notification_queue(status, created_at)` for delivery optimization

### Modified Tables
- None (all Week 4 data uses existing schema from Week 3)

---

## 6. Success Criteria & Validation

### Functional Success
- [ ] All 9 new functions execute without errors
- [ ] All 8 new views return results in <5ms
- [ ] Anomaly detection identifies simulated anomalies with 95%+ accuracy
- [ ] Correlation analysis detects correlated operations with >0.75 coefficient
- [ ] Webhook delivery completes 99%+ of messages within 1 minute
- [ ] pg_cron jobs execute successfully daily without errors
- [ ] Zero breaking changes to existing functions or views

### Performance Success
- [ ] Anomaly detection functions: <50ms for 24-hour analysis
- [ ] Correlation analysis: <100ms for all operation pairs
- [ ] Merge dashboards: <5ms per query
- [ ] Notification delivery: <10ms per message
- [ ] Baseline recalculation: <100ms for all 33 operations
- [ ] Database size increase: <50MB from Week 3

### Testing Coverage
- [ ] Unit tests for each function (with mock data)
- [ ] Integration tests (end-to-end anomaly detection)
- [ ] Performance tests (load testing with 10,000+ metrics)
- [ ] Edge case tests (empty data, single value, extreme values)
- [ ] Webhook delivery tests (success/failure scenarios)

### Code Quality
- [ ] SQL formatting consistent with existing code
- [ ] Comments for complex logic (3+ lines)
- [ ] No N+1 queries or inefficient patterns
- [ ] Error handling in all functions
- [ ] Defensive programming (NULL checks, bounds checking)

---

## 7. Risks & Mitigations

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| Correlation calculation performance | Medium | Use rolling windows, limit pair analysis to 50 operations |
| pg_cron not available | Low | Provide manual cron scripts as fallback |
| Webhook delivery failures | Medium | Exponential backoff, max 3 retries, manual queue inspection |
| Anomaly false positives | Medium | Combine statistical + trend analysis, configurable thresholds |
| Memory usage for correlation | Low | Batch processing, time-windowed analysis (1-hour windows) |
| Merge data incomplete | Low | Graceful handling with NULL checks, partial results |

---

## 8. Integration Points

### Phase 2 Integration (Three-Way Merge)
- Anomaly detection monitors merge performance
- Merge dashboards track bottleneck phases
- Correlation analysis detects merge pipeline saturation

### Phase 4 Integration (Object History)
- Anomaly detection monitors history query performance
- Correlation analysis detects cache pressure
- Dashboards track history query slowdowns

### Phase 6 Integration (Rollback)
- Anomaly detection monitors rollback performance
- Correlation analysis detects transaction log saturation
- Alerts trigger on rollback timeouts

### Week 3 Integration (Critical Enhancements)
- Leverages webhook encryption from Week 3
- Uses alert_notification_queue from Week 3
- Builds on baseline recalculation from Week 3

---

## 9. Rollback Plan

If Week 4 implementation encounters critical issues:

1. **Stage 1 Rollback** (Functions only):
   - Drop all Week 4 functions
   - Keep views and tables
   - System reverts to Week 3 + baseline recalculation

2. **Stage 2 Rollback** (Views & Functions):
   - Drop all Week 4 views and functions
   - Keep underlying tables
   - System reverts to Week 3 basic functionality

3. **Full Rollback**:
   - Restore database from Week 3 backup
   - Requires <5 minute downtime

---

## 10. Post-Completion Maintenance

### Daily Tasks
- Monitor baseline recalculation execution (via cron job logs)
- Check notification delivery queue depth (<100 pending)
- Review anomaly detection alerts (should be <5 CRITICAL per day)

### Weekly Tasks
- Review correlation analysis results
- Check merge bottleneck trends
- Verify pg_cron job success rates

### Monthly Tasks
- Analyze false positive rate in anomaly detection
- Tune z-score threshold based on actual data
- Review and optimize slow-running queries

---

## 11. Team & Timeline

### Architecture & Planning
- Claude (Senior Architect): Design and plan (2 hours) ✅
- Team specialists: Review plan (2 hours)

### Implementation (Self-service via local model or Claude)
- Anomaly detection: 2 days
- Correlation analysis: 2 days
- Merge dashboards: 1.5 days
- Automation: 1 day
- Total: 6.5 days within Week 4

### Testing & Validation
- QA testing: 1-2 days
- Performance benchmarking: 0.5 day
- Documentation: 0.5 day

### Estimated Total: 1 week (as planned)

---

## Conclusion

Week 4 implementation will transform Phase 7 from an operational monitoring system into an intelligent, self-optimizing platform with:

✅ Proactive anomaly detection (24-48 hour early warning)
✅ Root cause identification via correlation analysis
✅ Specialized merge operation analysis
✅ Fully automated baseline recalculation
✅ Complete alert delivery pipeline

**Status**: Ready for review and implementation approval

**Next Step**: Specialist team review and feedback → Implementation → QA testing → Production deployment

---

**Report Date**: 2025-12-27
**Prepared By**: pgGit Performance Monitoring Team
**Status**: READY FOR REVIEW
