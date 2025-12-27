-- ============================================================================
-- Phase 7: Week 4 - Anomaly Detection Engine
-- ============================================================================
-- Purpose: Statistical and trend-based anomaly detection for performance metrics
-- Date: 2025-12-27
-- Status: Production-ready implementation
-- ============================================================================

-- ============================================================================
-- TABLE DEFINITIONS: Supporting tables for anomaly detection history
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_anomalies (
    anomaly_id BIGSERIAL PRIMARY KEY,
    metric_id BIGINT NOT NULL REFERENCES pggit.performance_metrics(metric_id) ON DELETE CASCADE,
    operation_type TEXT NOT NULL,
    anomaly_type TEXT NOT NULL,  -- 'STATISTICAL_OUTLIER', 'PERFORMANCE_DEGRADATION', 'COMBINED'
    severity TEXT NOT NULL,       -- 'INFO', 'WARNING', 'CRITICAL'

    -- Statistical context
    duration_ms NUMERIC,
    baseline_p99_ms NUMERIC,
    z_score NUMERIC,
    deviation_percent NUMERIC,

    -- Degradation context
    degradation_percent NUMERIC,
    trend_slope NUMERIC,
    confidence NUMERIC,

    -- Metadata
    detected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    alert_generated BOOLEAN DEFAULT FALSE,
    investigation_notes TEXT,
    resolved_at TIMESTAMP,

    CONSTRAINT anomaly_type_check CHECK (
        anomaly_type IN ('STATISTICAL_OUTLIER', 'PERFORMANCE_DEGRADATION', 'COMBINED')
    ),
    CONSTRAINT severity_check CHECK (
        severity IN ('INFO', 'WARNING', 'CRITICAL')
    )
);

CREATE INDEX idx_performance_anomalies_operation_type
    ON pggit.performance_anomalies(operation_type, detected_at DESC);
CREATE INDEX idx_performance_anomalies_severity
    ON pggit.performance_anomalies(severity, detected_at DESC);
CREATE INDEX idx_performance_anomalies_metric
    ON pggit.performance_anomalies(metric_id);

-- ============================================================================
-- FUNCTION 1: detect_anomalies_statistical
-- ============================================================================
-- Purpose: Detect statistical outliers using z-score method
-- Input: operation_type, lookback_hours, z_score_threshold
-- Output: Table of detected anomalies with statistical context
-- ============================================================================

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
DECLARE
    v_mean_duration NUMERIC;
    v_stddev_duration NUMERIC;
    v_metric_count INTEGER;
    v_baseline_p99 NUMERIC;
    v_lookback_start TIMESTAMP;
    v_current_z_score NUMERIC;
    v_severity TEXT;
    v_rec RECORD;
BEGIN
    -- Validate inputs
    IF p_lookback_hours < 1 THEN
        RAISE EXCEPTION 'lookback_hours must be >= 1';
    END IF;

    IF p_z_score_threshold < 1.0 THEN
        RAISE EXCEPTION 'z_score_threshold must be >= 1.0 (1σ)';
    END IF;

    -- Calculate time window
    v_lookback_start := CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL;

    -- Get recent metrics statistics
    SELECT
        AVG(performance_metrics.duration_ms),
        STDDEV_POP(performance_metrics.duration_ms),
        COUNT(*)
    INTO
        v_mean_duration,
        v_stddev_duration,
        v_metric_count
    FROM pggit.performance_metrics
    WHERE performance_metrics.operation_type = p_operation_type
      AND performance_metrics.recorded_at >= v_lookback_start;

    -- If insufficient data, return no results
    IF v_metric_count < 5 THEN
        RETURN;
    END IF;

    -- Ensure stddev is non-zero
    IF COALESCE(v_stddev_duration, 0) = 0 THEN
        RETURN;
    END IF;

    -- Get baseline p99
    SELECT performance_baselines.p99_microseconds / 1000.0
    INTO v_baseline_p99
    FROM pggit.performance_baselines
    WHERE performance_baselines.operation_type = p_operation_type
      AND performance_baselines.is_active = TRUE
    LIMIT 1;

    -- Calculate anomalies for each recent metric
    FOR v_rec IN
        SELECT
            performance_metrics.metric_id,
            performance_metrics.duration_ms
        FROM pggit.performance_metrics
        WHERE performance_metrics.operation_type = p_operation_type
          AND performance_metrics.recorded_at >= v_lookback_start
        ORDER BY performance_metrics.recorded_at DESC
    LOOP
        -- Calculate z-score
        v_current_z_score := (v_rec.duration_ms - v_mean_duration) / v_stddev_duration;

        -- Check if anomaly threshold is exceeded
        IF ABS(v_current_z_score) >= p_z_score_threshold THEN
            -- Classify severity based on z-score magnitude
            IF ABS(v_current_z_score) >= 5.0 THEN
                v_severity := 'CRITICAL';
            ELSIF ABS(v_current_z_score) >= 4.0 THEN
                v_severity := 'CRITICAL';
            ELSIF ABS(v_current_z_score) >= 3.0 THEN
                v_severity := 'WARNING';
            ELSE
                v_severity := 'INFO';
            END IF;

            -- Return anomaly record
            RETURN QUERY SELECT
                v_rec.metric_id,
                p_operation_type,
                v_rec.duration_ms,
                v_baseline_p99,
                v_current_z_score,
                ROUND(100.0 * (v_rec.duration_ms - v_mean_duration) / NULLIF(v_mean_duration, 0), 1),
                v_severity,
                CURRENT_TIMESTAMP;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- FUNCTION 2: detect_performance_degradation
-- ============================================================================
-- Purpose: Detect sustained performance degradation using trend analysis
-- Input: operation_type, lookback_days, threshold_percent
-- Output: Table with before/after baselines and trend analysis
-- ============================================================================

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
DECLARE
    v_lookback_start TIMESTAMP;
    v_lookback_end TIMESTAMP;
    v_midpoint TIMESTAMP;
    v_before_p99 NUMERIC;
    v_after_p99 NUMERIC;
    v_degradation_percent NUMERIC;
    v_trend_slope NUMERIC;
    v_regression_count INTEGER;
    v_trend_text TEXT;
    v_severity TEXT;
    v_confidence NUMERIC;
BEGIN
    -- Validate inputs
    IF p_lookback_days < 1 THEN
        RAISE EXCEPTION 'lookback_days must be >= 1';
    END IF;

    IF p_threshold_percent < 1 THEN
        RAISE EXCEPTION 'threshold_percent must be >= 1';
    END IF;

    -- Calculate time windows
    v_lookback_end := CURRENT_TIMESTAMP;
    v_lookback_start := v_lookback_end - (p_lookback_days || ' days')::INTERVAL;
    v_midpoint := v_lookback_start + ((v_lookback_end - v_lookback_start) / 2);

    -- Calculate before baseline (first half of period)
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms)
    INTO v_before_p99
    FROM pggit.performance_metrics
    WHERE operation_type = p_operation_type
      AND recorded_at >= v_lookback_start
      AND recorded_at < v_midpoint;

    -- Calculate after baseline (second half of period)
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms)
    INTO v_after_p99
    FROM pggit.performance_metrics
    WHERE operation_type = p_operation_type
      AND recorded_at >= v_midpoint
      AND recorded_at <= v_lookback_end;

    -- If insufficient data in either period, return no results
    IF v_before_p99 IS NULL OR v_after_p99 IS NULL THEN
        RETURN;
    END IF;

    -- Calculate degradation percentage
    v_degradation_percent := 100.0 * (v_after_p99 - v_before_p99) / NULLIF(v_before_p99, 0);

    -- Only report if degradation exceeds threshold
    IF v_degradation_percent < p_threshold_percent THEN
        RETURN;
    END IF;

    -- Calculate trend slope using daily baselines
    WITH daily_baselines AS (
        SELECT
            DATE_TRUNC('day', recorded_at) as day,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99_ms,
            COUNT(*) as sample_count
        FROM pggit.performance_metrics
        WHERE operation_type = p_operation_type
          AND recorded_at >= v_lookback_start
          AND recorded_at <= v_lookback_end
        GROUP BY 1
    ),
    regression_data AS (
        SELECT
            COUNT(*) as n,
            SUM(EXTRACT(EPOCH FROM day)) as sum_x,
            SUM(p99_ms) as sum_y,
            SUM(EXTRACT(EPOCH FROM day) * p99_ms) as sum_xy,
            SUM(EXTRACT(EPOCH FROM day)^2) as sum_x2,
            AVG(sample_count) as avg_samples
        FROM daily_baselines
    )
    SELECT
        (n * sum_xy - sum_x * sum_y) / NULLIF(n * sum_x2 - sum_x^2, 0),
        n,
        avg_samples
    INTO
        v_trend_slope,
        v_regression_count,
        v_confidence
    FROM regression_data;

    -- Classify trend
    IF COALESCE(v_trend_slope, 0) > 0 THEN
        v_trend_text := 'DEGRADING';
    ELSIF COALESCE(v_trend_slope, 0) < 0 THEN
        v_trend_text := 'IMPROVING';
    ELSE
        v_trend_text := 'STABLE';
    END IF;

    -- Normalize confidence to 0-1 range (more days = higher confidence)
    v_confidence := LEAST(1.0, COALESCE(v_confidence, 0) / 50.0);

    -- Classify severity
    IF v_degradation_percent >= 50 THEN
        v_severity := 'CRITICAL';
    ELSIF v_degradation_percent >= 30 THEN
        v_severity := 'WARNING';
    ELSE
        v_severity := 'INFO';
    END IF;

    -- Return degradation record
    RETURN QUERY SELECT
        v_lookback_start::DATE,
        v_lookback_end::DATE,
        ROUND(v_before_p99::NUMERIC, 1),
        ROUND(v_after_p99::NUMERIC, 1),
        ROUND(v_degradation_percent::NUMERIC, 1),
        v_trend_text,
        ROUND(v_confidence::NUMERIC, 2),
        v_severity;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- FUNCTION 3: detect_combined_anomalies
-- ============================================================================
-- Purpose: Combine statistical and trend-based detection for robust anomaly detection
-- Input: operation_type, lookback_hours
-- Output: Union of all detected anomalies with classification
-- ============================================================================

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
DECLARE
    v_has_degradation BOOLEAN;
    v_degradation_severity TEXT;
    v_degradation_percent NUMERIC;
    v_lookback_days INTEGER;
    v_rec_stat RECORD;
    v_combined_severity TEXT;
BEGIN
    -- Convert hours to days for degradation detection
    v_lookback_days := GREATEST(1, p_lookback_hours / 24);

    -- Check for degradation anomalies first
    SELECT
        severity,
        degradation_percent
    INTO
        v_degradation_severity,
        v_degradation_percent
    FROM pggit.detect_performance_degradation(
        p_operation_type,
        v_lookback_days,
        20.0
    )
    LIMIT 1;

    v_has_degradation := v_degradation_severity IS NOT NULL;

    -- Get statistical anomalies
    FOR v_rec_stat IN
        SELECT
            metric_id,
            operation_type,
            severity,
            z_score,
            detected_at
        FROM pggit.detect_anomalies_statistical(
            p_operation_type,
            p_lookback_hours,
            3.0
        )
    LOOP
        -- Determine combined severity
        IF v_has_degradation THEN
            -- Both anomalies detected: escalate if either is CRITICAL
            IF v_rec_stat.severity = 'CRITICAL' OR v_degradation_severity = 'CRITICAL' THEN
                v_combined_severity := 'CRITICAL';
            ELSE
                v_combined_severity := 'WARNING';
            END IF;
        ELSE
            -- Only statistical anomaly
            v_combined_severity := v_rec_stat.severity;
        END IF;

        -- Return combined anomaly record
        RETURN QUERY SELECT
            v_rec_stat.metric_id,
            v_rec_stat.operation_type,
            CASE WHEN v_has_degradation THEN 'COMBINED'::TEXT ELSE 'STATISTICAL_OUTLIER'::TEXT END,
            v_combined_severity,
            v_rec_stat.z_score,
            CASE WHEN v_has_degradation THEN v_degradation_percent ELSE NULL END,
            v_rec_stat.detected_at,
            v_combined_severity IN ('CRITICAL', 'WARNING');
    END LOOP;

    -- Get degradation anomalies (that don't have statistical counterparts)
    IF v_has_degradation AND NOT EXISTS (
        SELECT 1 FROM pggit.detect_anomalies_statistical(
            p_operation_type,
            p_lookback_hours,
            3.0
        )
    ) THEN
        RETURN QUERY SELECT
            NULL::BIGINT,
            p_operation_type,
            'PERFORMANCE_DEGRADATION'::TEXT,
            v_degradation_severity,
            NULL::NUMERIC,
            v_degradation_percent,
            CURRENT_TIMESTAMP,
            v_degradation_severity IN ('CRITICAL', 'WARNING');
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- FUNCTION: log_detected_anomaly
-- ============================================================================
-- Purpose: Log detected anomalies to performance_anomalies table
-- Called by: detect_combined_anomalies and alert generation functions
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.log_detected_anomaly(
    p_metric_id BIGINT,
    p_operation_type TEXT,
    p_anomaly_type TEXT,
    p_severity TEXT,
    p_duration_ms NUMERIC,
    p_baseline_p99_ms NUMERIC,
    p_z_score NUMERIC,
    p_deviation_percent NUMERIC,
    p_degradation_percent NUMERIC DEFAULT NULL,
    p_trend_slope NUMERIC DEFAULT NULL,
    p_confidence NUMERIC DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_anomaly_id BIGINT;
BEGIN
    INSERT INTO pggit.performance_anomalies (
        metric_id,
        operation_type,
        anomaly_type,
        severity,
        duration_ms,
        baseline_p99_ms,
        z_score,
        deviation_percent,
        degradation_percent,
        trend_slope,
        confidence,
        detected_at
    ) VALUES (
        p_metric_id,
        p_operation_type,
        p_anomaly_type,
        p_severity,
        p_duration_ms,
        p_baseline_p99_ms,
        p_z_score,
        p_deviation_percent,
        p_degradation_percent,
        p_trend_slope,
        p_confidence,
        CURRENT_TIMESTAMP
    )
    RETURNING anomaly_id INTO v_anomaly_id;

    RETURN v_anomaly_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: v_recent_anomalies
-- ============================================================================
-- Purpose: Display recent anomalies for operational monitoring
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_recent_anomalies AS
SELECT
    anomaly_id,
    operation_type,
    anomaly_type,
    severity,
    duration_ms,
    baseline_p99_ms,
    z_score,
    deviation_percent,
    degradation_percent,
    confidence,
    detected_at,
    alert_generated,
    CASE
        WHEN resolved_at IS NOT NULL THEN 'RESOLVED'
        WHEN alert_generated = TRUE THEN 'ALERTED'
        ELSE 'PENDING'
    END as status,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - detected_at)) / 60, 1) as minutes_since_detection
FROM pggit.performance_anomalies
WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY detected_at DESC;

-- ============================================================================
-- VIEW: v_anomaly_summary_by_operation
-- ============================================================================
-- Purpose: Aggregate view of anomalies by operation type
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_anomaly_summary_by_operation AS
SELECT
    operation_type,
    anomaly_type,
    COUNT(*) as anomaly_count,
    SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical_count,
    SUM(CASE WHEN severity = 'WARNING' THEN 1 ELSE 0 END) as warning_count,
    SUM(CASE WHEN severity = 'INFO' THEN 1 ELSE 0 END) as info_count,
    AVG(z_score) as avg_z_score,
    MAX(z_score) as max_z_score,
    AVG(degradation_percent) as avg_degradation_percent,
    MAX(degradation_percent) as max_degradation_percent,
    COUNT(CASE WHEN alert_generated = TRUE THEN 1 END) as alerts_generated,
    MAX(detected_at) as last_detected
FROM pggit.performance_anomalies
WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY operation_type, anomaly_type
ORDER BY critical_count DESC, anomaly_count DESC;

-- ============================================================================
-- VIEW: v_anomaly_false_positive_analysis
-- ============================================================================
-- Purpose: Identify potential false positives for threshold tuning
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_anomaly_false_positive_analysis AS
WITH anomaly_stats AS (
    SELECT
        operation_type,
        anomaly_type,
        severity,
        COUNT(*) as anomaly_count,
        AVG(z_score) as avg_z_score,
        STDDEV_POP(z_score) as stddev_z_score
    FROM pggit.performance_anomalies
    WHERE detected_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY operation_type, anomaly_type, severity
)
SELECT
    operation_type,
    anomaly_type,
    severity,
    anomaly_count,
    CASE
        WHEN anomaly_count < 5 THEN 'RARE'
        WHEN anomaly_count < 20 THEN 'OCCASIONAL'
        WHEN anomaly_count < 50 THEN 'FREQUENT'
        ELSE 'VERY_FREQUENT'
    END as frequency_level,
    ROUND(avg_z_score::NUMERIC, 2) as avg_z_score,
    ROUND(stddev_z_score::NUMERIC, 2) as stddev_z_score
FROM anomaly_stats
ORDER BY operation_type, frequency_level DESC, anomaly_count DESC;

-- ============================================================================
-- HELPER FUNCTION: cleanup_old_anomalies
-- ============================================================================
-- Purpose: Remove anomalies older than retention period
-- Called by: pg_cron scheduler (optional)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.cleanup_old_anomalies(
    p_retention_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    deleted_count BIGINT,
    oldest_remaining_timestamp TIMESTAMP
) AS $$
DECLARE
    v_cutoff_date TIMESTAMP;
    v_deleted_count BIGINT;
BEGIN
    v_cutoff_date := CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL;

    -- Delete old anomalies
    DELETE FROM pggit.performance_anomalies
    WHERE detected_at < v_cutoff_date;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    -- Get oldest remaining timestamp
    RETURN QUERY SELECT
        v_deleted_count,
        MIN(detected_at)
    FROM pggit.performance_anomalies;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Created functions:
--   1. detect_anomalies_statistical() - Z-score based outlier detection
--   2. detect_performance_degradation() - Trend analysis detection
--   3. detect_combined_anomalies() - Composite detection
--   4. log_detected_anomaly() - Anomaly logging helper
--   5. cleanup_old_anomalies() - Data retention management
--
-- Created tables:
--   1. performance_anomalies - Anomaly history and records
--
-- Created views:
--   1. v_recent_anomalies - 24-hour anomaly summary
--   2. v_anomaly_summary_by_operation - Aggregated anomaly statistics
--   3. v_anomaly_false_positive_analysis - False positive detection
--
-- Performance targets:
--   - Anomaly detection: <50ms per 24-hour analysis
--   - Views: <5ms per query
--   - Cleanup: <100ms for 30-day retention
-- ============================================================================
