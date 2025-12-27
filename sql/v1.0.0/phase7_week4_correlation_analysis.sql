-- ============================================================================
-- Phase 7: Week 4 - Correlation Analysis for Shared Bottlenecks
-- ============================================================================
-- Purpose: Detect when multiple operations degrade together, indicating shared bottlenecks
-- Date: 2025-12-27
-- Status: Production-ready implementation
-- ============================================================================

-- ============================================================================
-- TABLE DEFINITIONS: Supporting tables for correlation analysis
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_correlations (
    correlation_id BIGSERIAL PRIMARY KEY,
    operation_type_1 TEXT NOT NULL,
    operation_type_2 TEXT NOT NULL,

    -- Correlation metrics
    correlation_coefficient NUMERIC(5,2) NOT NULL,
    confidence NUMERIC(5,2),           -- 0-1 scale
    shared_bottleneck TEXT,

    -- Analysis context
    lookback_hours INTEGER DEFAULT 24,
    sample_pairs INTEGER,              -- Number of time-windowed pairs analyzed

    -- Bottleneck details
    recommendation TEXT,
    severity TEXT DEFAULT 'INFO',      -- INFO, WARNING, CRITICAL

    -- Metadata
    analyzed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT operation_pair_unique UNIQUE (operation_type_1, operation_type_2),
    CONSTRAINT correlation_range CHECK (correlation_coefficient >= -1 AND correlation_coefficient <= 1),
    CONSTRAINT confidence_range CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
);

CREATE INDEX idx_performance_correlations_bottleneck
    ON pggit.performance_correlations(shared_bottleneck, correlation_coefficient DESC);
CREATE INDEX idx_performance_correlations_severity
    ON pggit.performance_correlations(severity, analyzed_at DESC);
CREATE INDEX idx_performance_correlations_active
    ON pggit.performance_correlations(is_active, correlation_coefficient DESC);

-- ============================================================================
-- FUNCTION: detect_correlated_degradation
-- ============================================================================
-- Purpose: Find pairs of operations with correlated performance degradation
-- Input: lookback_hours, correlation_threshold
-- Output: Table of correlated operation pairs with bottleneck identification
-- Algorithm:
--   1. Build time-windowed (1-minute windows) performance series for each operation
--   2. For each operation pair, calculate Pearson correlation coefficient
--   3. Identify shared bottleneck based on operation types affected
--   4. Return pairs with correlation > threshold
-- ============================================================================

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
    sample_pairs INTEGER,
    detected_at TIMESTAMP
) AS $$
DECLARE
    v_lookback_start TIMESTAMP;
    v_lookback_end TIMESTAMP;
    v_op_type_1 TEXT;
    v_op_type_2 TEXT;
    v_correlation NUMERIC;
    v_confidence NUMERIC;
    v_bottleneck TEXT;
    v_recommendation TEXT;
    v_sample_count INTEGER;
    v_min_samples INTEGER := 10;  -- Minimum pairs for statistical significance
BEGIN
    -- Validate inputs
    IF p_lookback_hours < 1 THEN
        RAISE EXCEPTION 'lookback_hours must be >= 1';
    END IF;

    IF p_correlation_threshold < 0 OR p_correlation_threshold > 1 THEN
        RAISE EXCEPTION 'correlation_threshold must be between 0 and 1';
    END IF;

    -- Calculate time window
    v_lookback_end := CURRENT_TIMESTAMP;
    v_lookback_start := v_lookback_end - (p_lookback_hours || ' hours')::INTERVAL;

    -- Get all unique operation types
    -- Analyze correlation for each pair
    FOR v_op_type_1, v_op_type_2 IN
        SELECT DISTINCT
            o1.operation_type,
            o2.operation_type
        FROM pggit.performance_operation_types o1
        CROSS JOIN pggit.performance_operation_types o2
        WHERE o1.operation_type < o2.operation_type  -- Avoid duplicate pairs
          AND o1.is_tracked = TRUE
          AND o2.is_tracked = TRUE
    LOOP
        -- Calculate correlation for this pair
        WITH time_series AS (
            -- Build 1-minute windowed performance series
            SELECT
                DATE_TRUNC('minute', pm1.recorded_at) as minute_window,
                AVG(CASE WHEN pm1.operation_type = v_op_type_1 THEN pm1.duration_ms END) as avg_duration_op1,
                AVG(CASE WHEN pm2.operation_type = v_op_type_2 THEN pm2.duration_ms END) as avg_duration_op2,
                COUNT(DISTINCT pm1.metric_id) as count_op1,
                COUNT(DISTINCT pm2.metric_id) as count_op2
            FROM pggit.performance_metrics pm1
            LEFT JOIN pggit.performance_metrics pm2
                ON DATE_TRUNC('minute', pm1.recorded_at) = DATE_TRUNC('minute', pm2.recorded_at)
                AND pm2.operation_type = v_op_type_2
            WHERE pm1.operation_type = v_op_type_1
              AND pm1.recorded_at >= v_lookback_start
              AND pm1.recorded_at <= v_lookback_end
              AND pm2.recorded_at >= v_lookback_start
              AND pm2.recorded_at <= v_lookback_end
            GROUP BY DATE_TRUNC('minute', pm1.recorded_at)
        ),
        valid_pairs AS (
            -- Only use pairs with data from both operations
            SELECT
                minute_window,
                avg_duration_op1,
                avg_duration_op2
            FROM time_series
            WHERE avg_duration_op1 IS NOT NULL
              AND avg_duration_op2 IS NOT NULL
              AND count_op1 > 0
              AND count_op2 > 0
        ),
        stats AS (
            SELECT
                COUNT(*) as pair_count,
                AVG(avg_duration_op1) as mean_1,
                AVG(avg_duration_op2) as mean_2,
                STDDEV_POP(avg_duration_op1) as stddev_1,
                STDDEV_POP(avg_duration_op2) as stddev_2
            FROM valid_pairs
        ),
        correlation_calc AS (
            SELECT
                stats.pair_count,
                SUM((vp.avg_duration_op1 - stats.mean_1) * (vp.avg_duration_op2 - stats.mean_2)) /
                NULLIF(stats.pair_count * stats.stddev_1 * stats.stddev_2, 0) as correlation
            FROM valid_pairs vp, stats
            GROUP BY stats.pair_count
        )
        SELECT
            pair_count,
            correlation
        INTO
            v_sample_count,
            v_correlation
        FROM correlation_calc;

        -- If insufficient data, skip this pair
        IF COALESCE(v_sample_count, 0) < v_min_samples THEN
            CONTINUE;
        END IF;

        -- Skip if correlation doesn't meet threshold
        IF COALESCE(v_correlation, 0) < p_correlation_threshold THEN
            CONTINUE;
        END IF;

        -- Calculate confidence based on sample count (more samples = higher confidence)
        v_confidence := LEAST(1.0, v_sample_count::NUMERIC / 100.0);

        -- Identify shared bottleneck based on operation types
        v_bottleneck := identify_bottleneck(v_op_type_1, v_op_type_2);

        -- Generate recommendation based on bottleneck type
        v_recommendation := get_bottleneck_recommendation(v_bottleneck);

        -- Return correlated pair
        RETURN QUERY SELECT
            v_op_type_1,
            v_op_type_2,
            v_correlation,
            v_bottleneck,
            v_confidence,
            v_recommendation,
            v_sample_count,
            CURRENT_TIMESTAMP;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- HELPER FUNCTION: identify_bottleneck
-- ============================================================================
-- Purpose: Classify likely shared bottleneck based on operation types involved
-- ============================================================================

CREATE OR REPLACE FUNCTION identify_bottleneck(
    p_op_type_1 TEXT,
    p_op_type_2 TEXT
)
RETURNS TEXT AS $$
BEGIN
    -- Merge-related operations together = pipeline saturation
    IF (p_op_type_1 LIKE 'merge_%' AND p_op_type_2 LIKE 'merge_%') THEN
        RETURN 'MERGE_PIPELINE_SATURATION';
    END IF;

    -- Write operations together = object storage I/O
    IF ((p_op_type_1 IN ('commit', 'branch_create') AND p_op_type_2 IN ('commit', 'branch_create'))
        OR (p_op_type_1 = 'commit' AND p_op_type_2 = 'branch_create')) THEN
        RETURN 'OBJECT_STORAGE_IO';
    END IF;

    -- Read operations together = query cache pressure
    IF ((p_op_type_1 IN ('get_history', 'get_object_timeline') AND p_op_type_2 IN ('get_history', 'get_object_timeline'))
        OR (p_op_type_1 = 'get_history' AND p_op_type_2 = 'get_object_timeline')) THEN
        RETURN 'QUERY_CACHE_PRESSURE';
    END IF;

    -- Rollback operations = transaction log saturation
    IF ((p_op_type_1 LIKE 'rollback_%' AND p_op_type_2 LIKE 'rollback_%')
        OR (p_op_type_1 LIKE 'rollback_%' AND p_op_type_2 != 'rollback_%')) THEN
        RETURN 'TRANSACTION_LOG_SATURATION';
    END IF;

    -- Mixed operations = lock contention or generic resource contention
    RETURN 'SHARED_RESOURCE_CONTENTION';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- HELPER FUNCTION: get_bottleneck_recommendation
-- ============================================================================
-- Purpose: Provide actionable recommendation for identified bottleneck
-- ============================================================================

CREATE OR REPLACE FUNCTION get_bottleneck_recommendation(
    p_bottleneck TEXT
)
RETURNS TEXT AS $$
BEGIN
    CASE p_bottleneck
        WHEN 'MERGE_PIPELINE_SATURATION' THEN
            RETURN 'Increase merge worker threads, optimize conflict detection algorithm, or implement merge result caching';
        WHEN 'OBJECT_STORAGE_IO' THEN
            RETURN 'Check disk I/O capacity, consider SSD upgrade or add caching layer. Review buffer pool tuning (shared_buffers).';
        WHEN 'QUERY_CACHE_PRESSURE' THEN
            RETURN 'Increase shared_buffers PostgreSQL setting or implement query result caching layer (Redis/Memcached)';
        WHEN 'TRANSACTION_LOG_SATURATION' THEN
            RETURN 'Optimize transaction log flushing, enable asynchronous commit for non-critical operations, or increase wal_buffers';
        WHEN 'SHARED_RESOURCE_CONTENTION' THEN
            RETURN 'Investigate pg_locks for lock contention, profile CPU usage, check memory pressure, or review connection pooling';
        ELSE
            RETURN 'Investigate using pg_stat_statements, pg_stat_database, and system-level monitoring (CPU, disk I/O, memory)';
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: store_correlation_analysis
-- ============================================================================
-- Purpose: Store correlation analysis results for historical tracking
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.store_correlation_analysis(
    p_operation_type_1 TEXT,
    p_operation_type_2 TEXT,
    p_correlation_coefficient NUMERIC,
    p_confidence NUMERIC,
    p_shared_bottleneck TEXT,
    p_recommendation TEXT,
    p_sample_pairs INTEGER,
    p_lookback_hours INTEGER DEFAULT 24
)
RETURNS BIGINT AS $$
DECLARE
    v_severity TEXT;
    v_correlation_id BIGINT;
BEGIN
    -- Determine severity based on correlation strength
    IF p_correlation_coefficient >= 0.9 THEN
        v_severity := 'CRITICAL';
    ELSIF p_correlation_coefficient >= 0.75 THEN
        v_severity := 'WARNING';
    ELSE
        v_severity := 'INFO';
    END IF;

    -- Insert or update correlation record
    INSERT INTO pggit.performance_correlations (
        operation_type_1,
        operation_type_2,
        correlation_coefficient,
        confidence,
        shared_bottleneck,
        recommendation,
        sample_pairs,
        lookback_hours,
        severity,
        analyzed_at
    ) VALUES (
        LEAST(p_operation_type_1, p_operation_type_2),
        GREATEST(p_operation_type_1, p_operation_type_2),
        p_correlation_coefficient,
        p_confidence,
        p_shared_bottleneck,
        p_recommendation,
        p_sample_pairs,
        p_lookback_hours,
        v_severity,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (operation_type_1, operation_type_2) DO UPDATE SET
        correlation_coefficient = EXCLUDED.correlation_coefficient,
        confidence = EXCLUDED.confidence,
        shared_bottleneck = EXCLUDED.shared_bottleneck,
        recommendation = EXCLUDED.recommendation,
        sample_pairs = EXCLUDED.sample_pairs,
        severity = EXCLUDED.severity,
        analyzed_at = CURRENT_TIMESTAMP
    RETURNING correlation_id INTO v_correlation_id;

    RETURN v_correlation_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: v_active_correlations
-- ============================================================================
-- Purpose: Display currently active correlations for operational monitoring
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_active_correlations AS
SELECT
    correlation_id,
    operation_type_1,
    operation_type_2,
    correlation_coefficient,
    confidence,
    shared_bottleneck,
    severity,
    recommendation,
    sample_pairs,
    analyzed_at,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - analyzed_at)) / 3600, 1) as hours_since_analysis
FROM pggit.performance_correlations
WHERE is_active = TRUE
  AND correlation_coefficient >= 0.75
ORDER BY correlation_coefficient DESC, severity DESC;

-- ============================================================================
-- VIEW: v_bottleneck_summary
-- ============================================================================
-- Purpose: Aggregate view of bottlenecks and affected operations
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_bottleneck_summary AS
SELECT
    shared_bottleneck,
    severity,
    COUNT(*) as affected_operation_pairs,
    ROUND(AVG(correlation_coefficient)::NUMERIC, 2) as avg_correlation,
    ROUND(MAX(correlation_coefficient)::NUMERIC, 2) as max_correlation,
    ROUND(AVG(confidence)::NUMERIC, 2) as avg_confidence,
    STRING_AGG(DISTINCT operation_type_1, ', ' ORDER BY operation_type_1) as operations_involved,
    MAX(analyzed_at) as last_detected
FROM pggit.performance_correlations
WHERE is_active = TRUE
GROUP BY shared_bottleneck, severity
ORDER BY MAX(correlation_coefficient) DESC, severity DESC;

-- ============================================================================
-- VIEW: v_correlated_operation_graph
-- ============================================================================
-- Purpose: Network view of operation correlations (for visualization/analysis)
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_correlated_operation_graph AS
SELECT
    operation_type_1 as source_operation,
    operation_type_2 as target_operation,
    correlation_coefficient as edge_weight,
    confidence,
    shared_bottleneck as edge_label,
    severity as edge_color,
    recommendation
FROM pggit.performance_correlations
WHERE is_active = TRUE
  AND correlation_coefficient >= 0.75
ORDER BY correlation_coefficient DESC;

-- ============================================================================
-- FUNCTION: analyze_all_correlations
-- ============================================================================
-- Purpose: Run complete correlation analysis and store results
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.analyze_all_correlations(
    p_lookback_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    correlation_count BIGINT,
    critical_bottlenecks BIGINT,
    warning_bottlenecks BIGINT,
    max_correlation NUMERIC,
    analysis_timestamp TIMESTAMP
) AS $$
DECLARE
    v_rec RECORD;
    v_stored_count BIGINT := 0;
BEGIN
    -- Clear old analysis results (keep last 7 days)
    DELETE FROM pggit.performance_correlations
    WHERE analyzed_at < CURRENT_TIMESTAMP - INTERVAL '7 days';

    -- Run correlation analysis
    FOR v_rec IN
        SELECT * FROM pggit.detect_correlated_degradation(
            p_lookback_hours,
            0.75  -- Threshold: 75% correlation
        )
    LOOP
        -- Store each correlation result
        PERFORM pggit.store_correlation_analysis(
            v_rec.operation_type_1,
            v_rec.operation_type_2,
            v_rec.correlation_coefficient,
            v_rec.confidence,
            v_rec.shared_bottleneck,
            v_rec.recommendation,
            v_rec.sample_pairs,
            p_lookback_hours
        );
        v_stored_count := v_stored_count + 1;
    END LOOP;

    -- Return analysis summary
    RETURN QUERY SELECT
        v_stored_count,
        COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END),
        COUNT(CASE WHEN severity = 'WARNING' THEN 1 END),
        MAX(correlation_coefficient),
        CURRENT_TIMESTAMP
    FROM pggit.performance_correlations
    WHERE analyzed_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Created functions:
--   1. detect_correlated_degradation() - Main correlation detection
--   2. identify_bottleneck() - Helper for bottleneck classification
--   3. get_bottleneck_recommendation() - Helper for recommendations
--   4. store_correlation_analysis() - Results persistence
--   5. analyze_all_correlations() - Batch analysis coordinator
--
-- Created tables:
--   1. performance_correlations - Correlation history and metadata
--
-- Created views:
--   1. v_active_correlations - Current correlations filtered by threshold
--   2. v_bottleneck_summary - Aggregate bottleneck statistics
--   3. v_correlated_operation_graph - Network graph for visualization
--
-- Performance targets:
--   - Correlation detection: <100ms for all operation pairs (33×32/2 = 528 pairs)
--   - Views: <5ms per query
--   - Batch analysis: <500ms for all correlations
-- ============================================================================
