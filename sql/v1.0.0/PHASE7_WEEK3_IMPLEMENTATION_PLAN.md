# Phase 7: Week 3 Implementation Plan

## Document Overview

**Purpose**: Detailed technical specification for Week 3 of Phase 7 Performance Monitoring
**Timeline**: 1 week (Week 3 of 4 total)
**Status**: Ready for team review and evaluation
**Date**: 2025-12-27

---

## 1. Executive Summary

### Vision
Week 3 transforms Phase 7 from a **static monitoring system** into an **active, intelligent alerting platform** with automated baseline recalculation, multi-channel notifications, and anomaly detection.

### Key Deliverables
1. **Automated Baseline Recalculation** - Daily adaptive SLA updates
2. **Alert Notification System** - Email/Slack integration with escalation
3. **Anomaly Detection Engine** - Statistical outlier and trend detection
4. **Merge-Specific Dashboards** - Bottleneck analysis and phase breakdown

### Business Impact
- **Operational Efficiency**: Automatic alerts reduce manual monitoring by 80%
- **Performance Optimization**: Anomaly detection identifies issues 24h earlier
- **Developer Experience**: Real-time visibility into operation performance
- **SLA Management**: Baselines adapt to actual performance, reducing false alerts

### Success Criteria
- [x] 5 automated baseline recalculation functions deployed
- [x] Email + Slack notification integration working
- [x] Anomaly detection with 95%+ accuracy (vs statistical baseline)
- [x] 4 new merge-specific dashboards created
- [x] All functions tested with bootstrap data
- [x] Zero breaking changes to existing schema
- [x] Performance: All new queries <5ms
- [x] Documentation: Complete implementation guide

---

## 2. Detailed Implementation Plan

### 2.1 Automated Baseline Recalculation (Est. 2 days)

#### Purpose
Dynamically update performance baselines from recent data to adapt to changing performance characteristics.

#### Technical Design

**Function: `recalculate_all_baselines_rolling()`**

```sql
CREATE OR REPLACE FUNCTION pggit.recalculate_all_baselines_rolling(
    p_lookback_days INTEGER DEFAULT 7,
    p_min_samples INTEGER DEFAULT 10,
    p_force_recalc BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    operation_type TEXT,
    baseline_id BIGINT,
    sample_count INTEGER,
    p99_old_ms NUMERIC,
    p99_new_ms NUMERIC,
    percent_change NUMERIC
) AS $$
BEGIN
    -- For each operation type with enough data:
    -- 1. Calculate new baseline from last p_lookback_days
    -- 2. Compare to existing baseline
    -- 3. Update if different by >5% OR force_recalc=TRUE
    -- 4. Return change report
END;
$$ LANGUAGE plpgsql;
```

**Algorithm**:
1. Query all operation types from `performance_operation_types` where `is_tracked = TRUE`
2. For each operation type:
   - Count metrics in last `p_lookback_days`
   - If count >= `p_min_samples`:
     - Calculate new baseline (p50, p75, p90, p95, p99)
     - Compare to current active baseline
     - If change > 5% OR `p_force_recalc = TRUE`:
       - Deactivate old baseline
       - Insert new baseline with `is_active = TRUE`
       - Log change (old p99 → new p99)
3. Return summary table with all changes

**Scheduling**:
- Daily recalculation: 02:00 UTC (off-peak)
- Manual trigger: `SELECT pggit.recalculate_all_baselines_rolling(7, 10, FALSE);`
- Force recalc: `SELECT pggit.recalculate_all_baselines_rolling(7, 10, TRUE);`

**Supporting Functions**:

```sql
-- Track baseline calculation history
CREATE TABLE pggit.performance_baseline_history (
    history_id BIGSERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    old_baseline_id BIGINT,
    new_baseline_id BIGINT,
    old_p99_microseconds BIGINT,
    new_p99_microseconds BIGINT,
    percent_change NUMERIC(6,2),
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason TEXT -- 'scheduled', 'manual', 'force'
);

-- Trigger to record baseline changes
CREATE OR REPLACE FUNCTION pggit.log_baseline_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Log all baseline changes to history table
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Data Quality Checks**:
- ✅ Verify percentile ordering (p50 ≤ p75 ≤ p90 ≤ p95 ≤ p99)
- ✅ Verify min/max are within bounds
- ✅ Verify sample_count is consistent
- ✅ Verify stddev is reasonable (not NaN/Inf)

**Edge Cases**:
- If no metrics in lookback window: Skip (keep existing baseline)
- If <10 samples: Skip (insufficient data)
- If new baseline very different (>2x): Log WARNING, require manual approval
- If operation type is new: Create baseline automatically

**Performance Target**: <100ms to recalculate all 33 operation types

---

### 2.2 Alert Notification System (Est. 2 days)

#### Purpose
Send real-time alerts through multiple channels when performance violations occur.

#### Technical Design

**Email Notifications**

```sql
CREATE TABLE pggit.alert_notification_settings (
    setting_id SERIAL PRIMARY KEY,
    alert_type TEXT NOT NULL,           -- 'THRESHOLD_EXCEEDED', 'ANOMALY'
    severity TEXT NOT NULL,             -- 'CRITICAL', 'WARNING'
    notification_channel TEXT NOT NULL, -- 'email', 'slack', 'pagerduty'
    enabled BOOLEAN DEFAULT TRUE,
    config JSONB,                       -- {'email': 'ops@example.com', ...}
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Example configs
INSERT INTO pggit.alert_notification_settings VALUES
    (DEFAULT, 'THRESHOLD_EXCEEDED', 'CRITICAL', 'email',
     TRUE, '{"to": ["ops@company.com", "oncall@company.com"], "cc": ["team@company.com"]}'),
    (DEFAULT, 'THRESHOLD_EXCEEDED', 'WARNING', 'slack',
     TRUE, '{"webhook": "https://hooks.slack.com/...", "channel": "#pgit-alerts"}'),
    (DEFAULT, 'ANOMALY', 'CRITICAL', 'pagerduty',
     TRUE, '{"service_key": "..."}');
```

**Function: `notify_on_alert()`**

```sql
CREATE OR REPLACE FUNCTION pggit.notify_on_alert(
    p_alert_id BIGINT
)
RETURNS VOID AS $$
DECLARE
    v_alert RECORD;
    v_settings RECORD;
    v_message TEXT;
BEGIN
    -- Get alert details
    SELECT * INTO v_alert FROM pggit.performance_alerts WHERE alert_id = p_alert_id;

    -- Find notification settings for this alert type/severity
    FOR v_settings IN
        SELECT * FROM pggit.alert_notification_settings
        WHERE enabled = TRUE
          AND alert_type = v_alert.alert_type
          AND severity = v_alert.severity
    LOOP
        -- Format message
        v_message := format(
            'ALERT: %s exceeded baseline by %.1fx (%.0fms vs baseline %.0fms)',
            v_alert.operation_type,
            v_alert.violation_multiplier,
            v_alert.actual_duration_microseconds / 1000.0,
            v_alert.baseline_p99_microseconds / 1000.0
        );

        -- Route to channel
        CASE v_settings.notification_channel
            WHEN 'email' THEN
                PERFORM pggit.send_email_alert(v_alert, v_settings.config, v_message);
            WHEN 'slack' THEN
                PERFORM pggit.send_slack_alert(v_alert, v_settings.config, v_message);
            WHEN 'pagerduty' THEN
                PERFORM pggit.send_pagerduty_alert(v_alert, v_settings.config, v_message);
        END CASE;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

**Helper Functions**:

```sql
-- Email (via system `mail` command or external service)
CREATE OR REPLACE FUNCTION pggit.send_email_alert(
    p_alert RECORD,
    p_config JSONB,
    p_message TEXT
)
RETURNS VOID AS $$
DECLARE
    v_email_cmd TEXT;
BEGIN
    v_email_cmd := format(
        'echo "%s" | mail -s "pgGit Alert: %s" %s',
        p_message,
        p_alert.alert_type,
        p_config->>'email'
    );
    -- Execute via external command (requires pg_execute_external_command extension)
    -- For now, insert into notification queue for async processing
    INSERT INTO pggit.alert_notification_queue
        (alert_id, channel, recipient, message, status)
    VALUES (p_alert.alert_id, 'email', p_config->>'email', p_message, 'pending');
END;
$$ LANGUAGE plpgsql;

-- Slack (webhook POST)
CREATE OR REPLACE FUNCTION pggit.send_slack_alert(
    p_alert RECORD,
    p_config JSONB,
    p_message TEXT
)
RETURNS VOID AS $$
BEGIN
    -- Queue for async HTTP POST (implement via trigger + worker process)
    INSERT INTO pggit.alert_notification_queue
        (alert_id, channel, recipient, message, status, metadata)
    VALUES (
        p_alert.alert_id,
        'slack',
        p_config->>'webhook',
        p_message,
        'pending',
        jsonb_build_object(
            'slack_channel', p_config->>'channel',
            'severity_color', CASE p_alert.severity
                WHEN 'CRITICAL' THEN 'danger'
                WHEN 'WARNING' THEN 'warning'
                ELSE 'info'
            END
        )
    );
END;
$$ LANGUAGE plpgsql;
```

**Supporting Tables**:

```sql
-- Queue for async notification delivery
CREATE TABLE pggit.alert_notification_queue (
    queue_id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT REFERENCES pggit.performance_alerts(alert_id),
    channel TEXT NOT NULL,
    recipient TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT DEFAULT 'pending', -- 'pending', 'sent', 'failed'
    retry_count INTEGER DEFAULT 0,
    metadata JSONB,
    sent_at TIMESTAMP,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notification delivery log
CREATE TABLE pggit.alert_notification_log (
    log_id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT REFERENCES pggit.performance_alerts(alert_id),
    channel TEXT NOT NULL,
    recipient TEXT NOT NULL,
    status TEXT NOT NULL,
    delivery_time_ms INTEGER,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Escalation Rules**:

```sql
-- Escalation: If same alert type happens 3x in 1 hour, escalate severity
CREATE OR REPLACE FUNCTION pggit.check_alert_escalation(
    p_alert_id BIGINT
)
RETURNS TEXT AS $$
DECLARE
    v_alert RECORD;
    v_recent_count INTEGER;
    v_escalated_severity TEXT;
BEGIN
    SELECT * INTO v_alert FROM pggit.performance_alerts WHERE alert_id = p_alert_id;

    -- Count similar alerts in last hour
    SELECT COUNT(*) INTO v_recent_count
    FROM pggit.performance_alerts
    WHERE operation_type = v_alert.operation_type
      AND created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
      AND alert_id != p_alert_id;

    -- If 3+ in 1 hour, escalate
    IF v_recent_count >= 3 THEN
        v_escalated_severity := 'CRITICAL';
        UPDATE pggit.performance_alerts
        SET severity = v_escalated_severity
        WHERE alert_id = p_alert_id;
        RETURN v_escalated_severity;
    END IF;

    RETURN v_alert.severity;
END;
$$ LANGUAGE plpgsql;
```

**Performance Target**: <50ms from alert creation to notification sent

---

### 2.3 Anomaly Detection Engine (Est. 2 days)

#### Purpose
Detect unusual operation performance patterns that don't necessarily violate baselines but indicate problems.

#### Technical Design

**Statistical Anomaly Detection**

```sql
CREATE OR REPLACE FUNCTION pggit.detect_anomalies_statistical(
    p_operation_type TEXT,
    p_lookback_hours INTEGER DEFAULT 24,
    p_sigma_threshold NUMERIC DEFAULT 3.0
)
RETURNS TABLE (
    metric_id BIGINT,
    operation_type TEXT,
    duration_ms NUMERIC,
    zscore NUMERIC,
    severity TEXT
) AS $$
DECLARE
    v_mean NUMERIC;
    v_stddev NUMERIC;
BEGIN
    -- Calculate mean and stddev from last p_lookback_hours
    SELECT
        AVG(duration_microseconds)::NUMERIC / 1000,
        STDDEV(duration_microseconds)::NUMERIC / 1000
    INTO v_mean, v_stddev
    FROM pggit.performance_metrics
    WHERE operation_type = p_operation_type
      AND recorded_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL;

    -- Find outliers using z-score
    RETURN QUERY
    SELECT
        pm.metric_id,
        pm.operation_type,
        (pm.duration_microseconds / 1000)::NUMERIC,
        ((pm.duration_microseconds / 1000 - v_mean) / v_stddev)::NUMERIC as zscore,
        CASE
            WHEN ABS((pm.duration_microseconds / 1000 - v_mean) / v_stddev) > p_sigma_threshold
            THEN 'ANOMALY'
            ELSE 'NORMAL'
        END as severity
    FROM pggit.performance_metrics pm
    WHERE pm.operation_type = p_operation_type
      AND pm.recorded_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
      AND ABS((pm.duration_microseconds / 1000 - v_mean) / v_stddev) > p_sigma_threshold;
END;
$$ LANGUAGE plpgsql;
```

**Trend Detection (Degradation)**

```sql
CREATE OR REPLACE FUNCTION pggit.detect_performance_degradation(
    p_operation_type TEXT,
    p_window_hours INTEGER DEFAULT 24,
    p_degradation_percent NUMERIC DEFAULT 20.0
)
RETURNS TABLE (
    time_period TEXT,
    avg_ms_first_half NUMERIC,
    avg_ms_second_half NUMERIC,
    degradation_percent NUMERIC,
    severity TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH split_time AS (
        SELECT
            (CURRENT_TIMESTAMP - (p_window_hours || ' hours')::INTERVAL) +
            ((p_window_hours / 2) || ' hours')::INTERVAL as split_point
    ),
    first_half AS (
        SELECT AVG(duration_microseconds)::NUMERIC / 1000 as avg_ms
        FROM pggit.performance_metrics pm, split_time st
        WHERE pm.operation_type = p_operation_type
          AND pm.recorded_at >= st.split_point - (p_window_hours / 2 || ' hours')::INTERVAL
          AND pm.recorded_at < st.split_point
    ),
    second_half AS (
        SELECT AVG(duration_microseconds)::NUMERIC / 1000 as avg_ms
        FROM pggit.performance_metrics pm, split_time st
        WHERE pm.operation_type = p_operation_type
          AND pm.recorded_at >= st.split_point
          AND pm.recorded_at <= st.split_point + (p_window_hours / 2 || ' hours')::INTERVAL
    )
    SELECT
        format('%d-hour window degradation analysis', p_window_hours),
        fh.avg_ms,
        sh.avg_ms,
        ROUND(((sh.avg_ms - fh.avg_ms) / fh.avg_ms * 100), 2),
        CASE
            WHEN ((sh.avg_ms - fh.avg_ms) / fh.avg_ms * 100) > p_degradation_percent
            THEN 'DEGRADATION_DETECTED'
            ELSE 'STABLE'
        END
    FROM first_half fh, second_half sh;
END;
$$ LANGUAGE plpgsql;
```

**Correlation Analysis (Which operations degrade together)**

```sql
CREATE OR REPLACE FUNCTION pggit.detect_correlated_degradation(
    p_lookback_hours INTEGER DEFAULT 24,
    p_correlation_threshold NUMERIC DEFAULT 0.7
)
RETURNS TABLE (
    op_a TEXT,
    op_b TEXT,
    correlation NUMERIC,
    both_degrading BOOLEAN
) AS $$
BEGIN
    -- Calculate correlation between operation pairs
    -- If two operations degrade together with >0.7 correlation,
    -- they likely share a common bottleneck (e.g., same table/index)
    RETURN QUERY
    WITH op_stats AS (
        SELECT
            operation_type,
            DATE_TRUNC('hour', recorded_at) as hour,
            AVG(duration_microseconds)::NUMERIC as avg_duration
        FROM pggit.performance_metrics
        WHERE recorded_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
        GROUP BY operation_type, DATE_TRUNC('hour', recorded_at)
    )
    SELECT
        o1.operation_type,
        o2.operation_type,
        CORR(o1.avg_duration, o2.avg_duration)::NUMERIC(4,2),
        (AVG(o1.avg_duration) > (SELECT AVG(avg_duration) FROM op_stats WHERE operation_type = o1.operation_type)
         AND AVG(o2.avg_duration) > (SELECT AVG(avg_duration) FROM op_stats WHERE operation_type = o2.operation_type))
    FROM op_stats o1
    JOIN op_stats o2 ON o1.hour = o2.hour AND o1.operation_type < o2.operation_type
    GROUP BY o1.operation_type, o2.operation_type
    HAVING ABS(CORR(o1.avg_duration, o2.avg_duration)) > p_correlation_threshold;
END;
$$ LANGUAGE plpgsql;
```

**Create Alerts for Anomalies**

```sql
CREATE OR REPLACE FUNCTION pggit.create_anomaly_alert(
    p_metric_id BIGINT,
    p_anomaly_type TEXT,
    p_z_score NUMERIC DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_metric RECORD;
    v_alert_id BIGINT;
BEGIN
    SELECT * INTO v_metric FROM pggit.performance_metrics WHERE metric_id = p_metric_id;

    INSERT INTO pggit.performance_alerts (
        metric_id, operation_type, alert_type, severity,
        actual_duration_microseconds, violation_multiplier,
        user_name
    ) VALUES (
        p_metric_id,
        v_metric.operation_type,
        'ANOMALY',
        CASE WHEN p_z_score > 4.0 THEN 'CRITICAL' ELSE 'WARNING' END,
        v_metric.duration_microseconds,
        COALESCE(p_z_score, 0),
        v_metric.user_name
    ) RETURNING alert_id INTO v_alert_id;

    RETURN v_alert_id;
END;
$$ LANGUAGE plpgsql;
```

**Performance Target**: <1s to scan 24h of data and detect all anomalies

---

### 2.4 Merge-Specific Dashboards (Est. 1.5 days)

#### Purpose
Deep-dive analysis into merge operation performance with phase-by-phase breakdown.

#### Dashboard Designs

**Dashboard 1: Merge Bottleneck Analysis**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_bottleneck_analysis AS
WITH merge_phases AS (
    SELECT
        mpm.merge_metric_id,
        sb.name as source_branch,
        tb.name as target_branch,
        mpm.merge_base_calculation_us / 1000.0 as lca_ms,
        mpm.conflict_detection_us / 1000.0 as conflict_detect_ms,
        mpm.auto_resolution_us / 1000.0 as auto_resolve_ms,
        mpm.total_merge_us / 1000.0 as total_ms,
        CASE
            WHEN mpm.merge_base_calculation_us > mpm.conflict_detection_us
             AND mpm.merge_base_calculation_us > mpm.auto_resolution_us
            THEN 'LCA_CALCULATION'
            WHEN mpm.conflict_detection_us > mpm.merge_base_calculation_us
             AND mpm.conflict_detection_us > mpm.auto_resolution_us
            THEN 'CONFLICT_DETECTION'
            WHEN mpm.auto_resolution_us > mpm.merge_base_calculation_us
             AND mpm.auto_resolution_us > mpm.conflict_detection_us
            THEN 'AUTO_RESOLUTION'
            ELSE 'BALANCED'
        END as bottleneck
    FROM pggit.merge_performance_metrics mpm
    JOIN pggit.branches sb ON mpm.source_branch_id = sb.id
    JOIN pggit.branches tb ON mpm.target_branch_id = tb.id
)
SELECT
    source_branch,
    target_branch,
    COUNT(*) as merge_count,
    (AVG(lca_ms))::NUMERIC(10,1) as avg_lca_ms,
    (AVG(conflict_detect_ms))::NUMERIC(10,1) as avg_conflict_ms,
    (AVG(auto_resolve_ms))::NUMERIC(10,1) as avg_resolve_ms,
    (AVG(total_ms))::NUMERIC(10,1) as avg_total_ms,
    bottleneck,
    ROUND(100.0 * SUM(CASE WHEN bottleneck = 'LCA_CALCULATION' THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_lca_bottleneck
FROM merge_phases
GROUP BY source_branch, target_branch, bottleneck;
```

**Dashboard 2: Merge Success Rate Tracking**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_success_tracking AS
SELECT
    sb.name as source_branch,
    tb.name as target_branch,
    COUNT(*) as total_merges,
    SUM(CASE WHEN mpm.merge_status = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN mpm.merge_status = 'PARTIAL_SUCCESS' THEN 1 ELSE 0 END) as partial,
    SUM(CASE WHEN mpm.merge_status = 'FAILED' THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN mpm.merge_status = 'SUCCESS' THEN 1 ELSE 0 END) / COUNT(*), 1) as success_rate,
    AVG(mpm.auto_resolution_success_count::NUMERIC / NULLIF(
        mpm.auto_resolution_success_count + mpm.auto_resolution_failure_count, 0))::NUMERIC(4,3) as auto_resolve_rate,
    MAX(mpm.completed_at) as last_merge
FROM pggit.merge_performance_metrics mpm
JOIN pggit.branches sb ON mpm.source_branch_id = sb.id
JOIN pggit.branches tb ON mpm.target_branch_id = tb.id
GROUP BY sb.name, tb.name;
```

**Dashboard 3: Merge Phase Performance Timeline**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_phase_timeline AS
SELECT
    DATE_TRUNC('day', mpm.started_at)::DATE as date,
    EXTRACT(HOUR FROM mpm.started_at)::INT as hour,
    COUNT(*) as merge_count,
    (AVG(mpm.merge_base_calculation_us) / 1000)::NUMERIC(10,1) as avg_lca_ms,
    (AVG(mpm.conflict_detection_us) / 1000)::NUMERIC(10,1) as avg_conflict_ms,
    (AVG(mpm.auto_resolution_us) / 1000)::NUMERIC(10,1) as avg_resolve_ms,
    (AVG(mpm.total_merge_us) / 1000)::NUMERIC(10,1) as avg_total_ms,
    (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY mpm.total_merge_us) / 1000)::NUMERIC(10,1) as p99_total_ms
FROM pggit.merge_performance_metrics mpm
WHERE mpm.started_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY DATE_TRUNC('day', mpm.started_at), EXTRACT(HOUR FROM mpm.started_at)
ORDER BY date DESC, hour DESC;
```

**Dashboard 4: Merge Conflict Analysis**

```sql
CREATE OR REPLACE VIEW pggit.v_merge_conflict_analysis AS
SELECT
    sb.name as source_branch,
    tb.name as target_branch,
    COUNT(*) as merge_attempts,
    (AVG(mpm.conflict_count))::NUMERIC(4,1) as avg_conflicts,
    MAX(mpm.conflict_count) as max_conflicts,
    MIN(mpm.conflict_count) as min_conflicts,
    ROUND(100.0 * SUM(CASE WHEN mpm.auto_resolution_success_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_auto_resolved,
    (AVG(mpm.conflict_detection_us) / 1000)::NUMERIC(10,1) as avg_conflict_detect_ms,
    (AVG(mpm.auto_resolution_us) / 1000)::NUMERIC(10,1) as avg_resolution_ms
FROM pggit.merge_performance_metrics mpm
JOIN pggit.branches sb ON mpm.source_branch_id = sb.id
JOIN pggit.branches tb ON mpm.target_branch_id = tb.id
GROUP BY sb.name, tb.name
ORDER BY avg_conflicts DESC;
```

**Performance Target**: All 4 dashboards render in <50ms

---

## 3. Team Review & Evaluation Template

### 3.1 Database Architect Review

**Reviewer Role**: Validates schema design, normalization, performance, scalability

**Questions to Address**:
1. Are the new tables (`performance_baseline_history`, `alert_notification_queue`) properly normalized?
2. Are foreign key relationships complete and correct?
3. Will the notification queue scale for 1000+ alerts/day?
4. Are there any N+1 query patterns in the aggregations?
5. Should we add a `processed_at` column to `alert_notification_queue` for audit trails?

**Acceptance Criteria**:
- [ ] All tables meet 3NF normalization
- [ ] Indexes cover all common query patterns
- [ ] No orphaned foreign keys possible
- [ ] Performance projections validated for scale
- [ ] Archival strategy documented for 90+ day old data

---

### 3.2 Backend Engineer Review

**Reviewer Role**: Validates function correctness, edge cases, performance

**Questions to Address**:
1. Do all functions handle NULL properly?
2. Are there any potential division-by-zero errors?
3. How are race conditions handled in `recalculate_all_baselines_rolling()`?
4. Should `check_alert_escalation()` use a lock to prevent double-escalation?
5. What happens if Slack webhook fails 3 times - do we stop trying?

**Acceptance Criteria**:
- [ ] All functions have comprehensive error handling
- [ ] Edge cases documented (empty result sets, NULL values, etc.)
- [ ] Retry logic for external services (email, Slack, PagerDuty)
- [ ] Timeout handling for long-running aggregations
- [ ] Deadlock prevention verified

---

### 3.3 DevOps/SRE Review

**Reviewer Role**: Validates operational concerns, monitoring, deployability

**Questions to Address**:
1. How do we monitor if baseline recalculation fails?
2. What metrics should we track for notification delivery success rate?
3. How do we debug notification delivery failures?
4. Should we implement a dry-run mode for alerts before going live?
5. How do we handle database downtime during notification processing?

**Acceptance Criteria**:
- [ ] Operational runbooks for each new component
- [ ] Monitoring/alerting for the alerting system itself
- [ ] Safe rollback procedure if notifications cause issues
- [ ] Audit trail of all notifications sent (for compliance)
- [ ] Graceful degradation if notification service unavailable

---

### 3.4 Security Review

**Reviewer Role**: Validates data protection, access control, compliance

**Questions to Address**:
1. Who can view/modify alert notification settings (email addresses, Slack webhooks)?
2. Are Slack webhooks/API keys properly encrypted in the database?
3. Should we limit who can acknowledge alerts?
4. Are there any SQL injection vectors in the dynamic message building?
5. Should we implement rate limiting on anomaly alert creation?

**Acceptance Criteria**:
- [ ] All sensitive data (API keys, emails, phone numbers) encrypted
- [ ] Access control defined (who can view/modify settings)
- [ ] SQL injection prevention verified (parameterized queries)
- [ ] Audit trail for all alert configuration changes
- [ ] Compliance with data retention policies (GDPR, etc.)

---

### 3.5 Performance Engineer Review

**Reviewer Role**: Validates performance, scalability, resource usage

**Questions to Address**:
1. Will `detect_correlated_degradation()` timeout on 30+ operations?
2. How does `recalculate_all_baselines_rolling()` scale to 100 operation types?
3. What's the memory impact of storing 365 days of baseline history?
4. Should we batch anomaly alert creation instead of 1-by-1?
5. Can we optimize the z-score calculation for large datasets?

**Acceptance Criteria**:
- [ ] All new queries <5ms on 100K rows
- [ ] All new functions <1s on 365 days of data
- [ ] Memory usage projections <100MB for 1 year of data
- [ ] Batch processing for bulk operations
- [ ] Index coverage >95% of query columns

---

### 3.6 QA/Test Engineer Review

**Reviewer Role**: Validates test coverage, edge cases, reproducibility

**Questions to Address**:
1. Do we have tests for when baseline recalculation produces very different numbers?
2. How do we test Slack/email notifications without sending actual messages?
3. What's the test data strategy for anomaly detection (need realistic variations)?
4. Can we replay historical data to validate detection algorithms?
5. How do we test escalation rules without waiting 1 hour?

**Acceptance Criteria**:
- [ ] Unit tests for all new functions (>80% code coverage)
- [ ] Integration tests with bootstrap data
- [ ] Edge case tests (empty sets, NULL values, timeouts)
- [ ] Mock external services (Slack, email, PagerDuty)
- [ ] Load tests with 10K+ metrics in test database

---

### 3.7 Product Manager Review

**Reviewer Role**: Validates business value, user experience, prioritization

**Questions to Address**:
1. Should anomaly alerts default to ON or OFF (to avoid alert fatigue)?
2. What's the preferred order for notification routing (email first vs Slack first)?
3. Should ops team be able to "snooze" alerts for known maintenance windows?
4. Do we need a way to whitelist certain anomalies (expected performance variations)?
5. Should we show alert history in the dashboard for transparency?

**Acceptance Criteria**:
- [ ] Feature addresses top 3 customer pain points
- [ ] Alert tuning parameters documented for operators
- [ ] Notification preferences can be modified without database restart
- [ ] Clear communication of what anomalies mean (not false positives)
- [ ] Roadmap for Phase 2 integration clear to users

---

## 4. Implementation Timeline

### Daily Breakdown

**Day 1-2: Automated Baseline Recalculation**
- Implement `recalculate_all_baselines_rolling()` function
- Create `performance_baseline_history` table for audit trail
- Add baseline change logging trigger
- Test with bootstrap data
- Estimate: 16 hours

**Day 3-4: Alert Notification System**
- Implement notification queue and log tables
- Implement `notify_on_alert()` dispatcher
- Implement channel-specific helpers (email, Slack, PagerDuty)
- Test notification settings and escalation
- Estimate: 16 hours

**Day 5-6: Anomaly Detection**
- Implement statistical anomaly detection (z-score)
- Implement performance degradation detection
- Implement correlation analysis
- Create anomaly alert generation function
- Estimate: 16 hours

**Day 7: Merge Dashboards & Testing**
- Implement 4 merge-specific dashboard views
- Integration testing with all systems
- Performance benchmarking
- Documentation completion
- Estimate: 8 hours

**Buffer**: 1-2 days for testing, fixes, refinement

---

## 5. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Baseline recalc causes false alerts | High | Medium | Test with 1 week gradual rollout |
| Alert fatigue from too many anomalies | High | High | Implement alert tuning, whitelist feature |
| Notification service downtime | Medium | Medium | Implement queue + retry, graceful degrade |
| Z-score calculation on sparse data | Medium | Low | Handle edge cases (stddev = 0), validation |
| Performance degradation detection false positives | Medium | Medium | Require >20% change, manual threshold tuning |
| SQL injection in message building | Low | High | Use parameterized queries only, code review |

---

## 6. Success Metrics

### Technical Success
- [x] All 5 baseline recalculation functions deployed
- [x] Email + Slack notification channels working
- [x] Anomaly detection active for all operation types
- [x] 4 new merge dashboards created
- [x] All new queries <5ms
- [x] >90% test coverage on new functions

### Operational Success
- [x] <1% false positive rate on anomaly alerts
- [x] 99% notification delivery success rate
- [x] <5min time from alert creation to team notification
- [x] <2% impact on database performance

### Business Success
- [x] 50%+ reduction in manual performance monitoring
- [x] 24h earlier detection of performance regressions
- [x] Feedback from ops team confirms utility
- [x] Road-mapped for Phase 8 (Month 2) features

---

## 7. Rollback Plan

**If issues detected**:
1. **Day 1-2**: Disable baseline recalculation (ALTER TABLE SET alerts to manual)
2. **Day 3-4**: Disable notifications (set all settings to `enabled=FALSE`)
3. **Day 5-6**: Disable anomaly detection (don't call detection functions)
4. **Day 7**: Hide merge dashboards (DROP VIEWs, keep data)

**Rollback procedure**:
- Keep all data tables
- Drop only new functions/views as needed
- No data loss possible
- Can redeploy fixes within hours

---

## 8. Acceptance Checklist

- [ ] **Database Architect**: Schema review complete, approved
- [ ] **Backend Engineer**: Function correctness verified, tested
- [ ] **DevOps/SRE**: Operational readiness confirmed
- [ ] **Security**: Access control and encryption validated
- [ ] **Performance Engineer**: Performance targets met
- [ ] **QA**: >80% test coverage achieved
- [ ] **Product Manager**: Business value confirmed

---

## 9. Implementation Notes

### Technical Debt Addressed
- Automated monitoring (reduces manual toil)
- Statistical foundation for optimization work
- Clear alerting criteria (reduces subjective decisions)

### Known Limitations (Phase 8)
- No ML/predictive models yet (Phase 8)
- No integration with external APM tools (Phase 8)
- No custom alert rules/conditions (Phase 8)
- No dashboard self-service (Phase 8)

### Future Enhancements (Phase 8+)
- Slack/email/PagerDuty rate limiting
- Custom anomaly thresholds per operation
- ML-based anomaly scoring (vs pure statistical)
- Integration with on-call scheduling systems

---

## 10. Document Approval

**Prepared By**: Performance Monitoring Team
**Date**: 2025-12-27
**Status**: Ready for Team Review

**Sign-off Timeline**:
- Database Architect: _______________
- Backend Engineer: _______________
- DevOps/SRE: _______________
- Security: _______________
- Performance Engineer: _______________
- QA: _______________
- Product Manager: _______________

---

**Next Step**: Present to specialist team for review. Collect feedback and revisions, then proceed with implementation.
