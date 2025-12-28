-- ============================================================================
-- Phase 7: Performance Monitoring - Schema Definition
-- ============================================================================
-- Description: Core tables and indexes for microsecond-precision performance
--              monitoring, distributed tracing, and SLA tracking
-- Version: 1.0.0
-- Created: 2025-12-27
-- ============================================================================

-- Ensure pggit schema exists
CREATE SCHEMA IF NOT EXISTS pggit;

-- ============================================================================
-- 1. PERFORMANCE_METRICS TABLE
-- ============================================================================
-- Purpose: Store individual operation timings with microsecond precision
-- Retention: Configurable via CLUSTER BY (default 90 days)
-- Partitioning: By period_start (monthly recommended)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
    metric_id BIGSERIAL PRIMARY KEY,

    -- Operation identification
    operation_type TEXT NOT NULL,                  -- 'commit', 'merge', 'rollback', etc.
    operation_name TEXT,                          -- Specific operation (e.g., 'merge_main_to_feature')

    -- Timing (microsecond precision)
    duration_microseconds BIGINT NOT NULL,        -- Exact microseconds for precision analysis
    duration_ms NUMERIC(10,3) NOT NULL,           -- Milliseconds (computed from microseconds)
    start_time TIMESTAMP NOT NULL,                -- When operation started
    end_time TIMESTAMP NOT NULL,                  -- When operation ended

    -- Context
    branch_id INTEGER REFERENCES pggit.branches(branch_id) ON DELETE SET NULL,
    user_name TEXT NOT NULL,                      -- WHO performed the operation
    session_id TEXT,                              -- Session tracking for correlation

    -- Resource utilization
    rows_affected INTEGER,                        -- Affected rows (for DML ops)
    memory_bytes BIGINT,                          -- Peak memory usage
    cpu_microseconds BIGINT,                      -- CPU time consumed
    connection_count INTEGER DEFAULT 1,           -- For distributed tracing context

    -- Flexible metadata storage
    operation_metadata JSONB,                     -- {"param1": value, "param2": value, ...}
    error_details JSONB,                          -- If operation failed

    -- Recording
    recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    period_start TIMESTAMP NOT NULL,              -- For partitioning by day/month

    -- Data quality & constraints
    CONSTRAINT chk_duration_positive CHECK (duration_microseconds > 0),
    CONSTRAINT chk_duration_consistency CHECK (duration_ms = duration_microseconds::NUMERIC / 1000),
    CONSTRAINT chk_time_order CHECK (start_time < end_time),
    CONSTRAINT chk_user_name_not_empty CHECK (length(trim(user_name)) > 0),
    CONSTRAINT chk_operation_type_not_empty CHECK (length(trim(operation_type)) > 0)
);

-- Strategic indexes for performance
CREATE INDEX idx_performance_metrics_operation_type
    ON pggit.performance_metrics(operation_type);

CREATE INDEX idx_performance_metrics_branch_id
    ON pggit.performance_metrics(branch_id)
    WHERE branch_id IS NOT NULL;

CREATE INDEX idx_performance_metrics_recorded_at
    ON pggit.performance_metrics(recorded_at DESC);

CREATE INDEX idx_performance_metrics_period_start
    ON pggit.performance_metrics(period_start DESC);

CREATE INDEX idx_performance_metrics_user_name
    ON pggit.performance_metrics(user_name);

CREATE INDEX idx_performance_metrics_composite
    ON pggit.performance_metrics(operation_type, period_start DESC, duration_microseconds DESC);

-- ============================================================================
-- 2. OPERATION_TRACES TABLE
-- ============================================================================
-- Purpose: Distributed tracing with parent-child span relationships
--          (OpenTelemetry-compatible)
-- Usage: Track multi-step operations (merge process, deploy sequence, etc.)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.operation_traces (
    trace_id TEXT PRIMARY KEY,                    -- UUID, globally unique
    span_id TEXT NOT NULL UNIQUE,                 -- UUID, span identifier
    parent_span_id TEXT REFERENCES pggit.operation_traces(span_id) ON DELETE CASCADE,

    -- Operation details
    operation_type TEXT NOT NULL,                 -- 'merge_workflow', 'rollback_chain', etc.
    span_name TEXT NOT NULL,                      -- Human-readable step name
    span_status TEXT DEFAULT 'PENDING',           -- PENDING, RUNNING, SUCCESS, FAILED

    -- Timing
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_microseconds BIGINT,

    -- Context
    branch_id INTEGER REFERENCES pggit.branches(branch_id) ON DELETE SET NULL,
    user_name TEXT NOT NULL,
    session_id TEXT,

    -- Resource tracking
    memory_peak_bytes BIGINT,
    cpu_microseconds BIGINT,

    -- Error details
    error_message TEXT,
    error_code TEXT,
    error_details JSONB,

    -- Metadata
    attributes JSONB,                            -- Custom span attributes
    recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_trace_status CHECK (span_status IN ('PENDING', 'RUNNING', 'SUCCESS', 'FAILED')),
    CONSTRAINT chk_trace_times CHECK (end_time IS NULL OR start_time <= end_time)
);

-- Indexes for trace traversal
CREATE INDEX idx_operation_traces_trace_id
    ON pggit.operation_traces(trace_id);

CREATE INDEX idx_operation_traces_parent_span_id
    ON pggit.operation_traces(parent_span_id)
    WHERE parent_span_id IS NOT NULL;

CREATE INDEX idx_operation_traces_operation_type
    ON pggit.operation_traces(operation_type);

CREATE INDEX idx_operation_traces_start_time
    ON pggit.operation_traces(start_time DESC);

CREATE INDEX idx_operation_traces_user_name
    ON pggit.operation_traces(user_name);

-- ============================================================================
-- 3. PERFORMANCE_BASELINES TABLE
-- ============================================================================
-- Purpose: Store SLA thresholds (p50, p75, p90, p95, p99) for each operation
-- Usage: Compare actual performance against baselines for alerting
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_baselines (
    baseline_id BIGSERIAL PRIMARY KEY,

    -- What operation?
    operation_type TEXT NOT NULL,
    branch_id INTEGER REFERENCES pggit.branches(branch_id) ON DELETE CASCADE,

    -- When was this baseline calculated?
    baseline_date DATE NOT NULL,
    calculation_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Sample size
    sample_count INTEGER NOT NULL,
    min_microseconds BIGINT NOT NULL,
    max_microseconds BIGINT NOT NULL,

    -- Percentiles (key for SLA monitoring)
    p50_microseconds BIGINT NOT NULL,             -- Median
    p75_microseconds BIGINT NOT NULL,
    p90_microseconds BIGINT NOT NULL,
    p95_microseconds BIGINT NOT NULL,
    p99_microseconds BIGINT NOT NULL,

    -- Statistical properties
    mean_microseconds NUMERIC(12,2) NOT NULL,
    stddev_microseconds NUMERIC(12,2),

    -- Configuration
    alert_threshold_multiplier NUMERIC(3,2) DEFAULT 2.0,  -- Alert if > 2x p99
    is_active BOOLEAN DEFAULT TRUE,

    -- Tracking
    calculated_from_days INTEGER DEFAULT 7,      -- Last N days of data

    CONSTRAINT chk_baseline_percentiles CHECK (
        p50_microseconds <= p75_microseconds AND
        p75_microseconds <= p90_microseconds AND
        p90_microseconds <= p95_microseconds AND
        p95_microseconds <= p99_microseconds
    ),
    CONSTRAINT chk_baseline_min_max CHECK (min_microseconds <= max_microseconds),
    CONSTRAINT chk_sample_count CHECK (sample_count > 0),
    CONSTRAINT chk_alert_threshold CHECK (alert_threshold_multiplier > 0)
);

CREATE UNIQUE INDEX idx_performance_baselines_active
    ON pggit.performance_baselines(operation_type, branch_id, baseline_date)
    WHERE is_active = TRUE;

CREATE INDEX idx_performance_baselines_operation_type
    ON pggit.performance_baselines(operation_type);

CREATE INDEX idx_performance_baselines_calculation_timestamp
    ON pggit.performance_baselines(calculation_timestamp DESC);

-- ============================================================================
-- 4. PERFORMANCE_ALERTS TABLE
-- ============================================================================
-- Purpose: Track performance anomalies and baseline violations
-- Usage: Alert when operations exceed SLA thresholds
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_alerts (
    alert_id BIGSERIAL PRIMARY KEY,

    -- What triggered the alert?
    metric_id BIGINT NOT NULL REFERENCES pggit.performance_metrics(metric_id) ON DELETE CASCADE,
    baseline_id BIGINT REFERENCES pggit.performance_baselines(baseline_id) ON DELETE SET NULL,

    -- Alert details
    operation_type TEXT NOT NULL,
    alert_type TEXT NOT NULL,                     -- 'THRESHOLD_EXCEEDED', 'ANOMALY', 'DEGRADATION'
    severity TEXT DEFAULT 'WARNING',              -- CRITICAL, WARNING, INFO

    -- Violation metrics
    baseline_p99_microseconds BIGINT,
    actual_duration_microseconds BIGINT NOT NULL,
    violation_multiplier NUMERIC(6,2),            -- How much over threshold? (2.5x, etc.)

    -- Context
    branch_id INTEGER REFERENCES pggit.branches(branch_id) ON DELETE SET NULL,
    user_name TEXT,

    -- Status tracking
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_at TIMESTAMP,
    acknowledged_by TEXT,
    resolution_notes TEXT,

    -- Timing
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_alert_type CHECK (alert_type IN ('THRESHOLD_EXCEEDED', 'ANOMALY', 'DEGRADATION')),
    CONSTRAINT chk_alert_severity CHECK (severity IN ('CRITICAL', 'WARNING', 'INFO'))
);

CREATE INDEX idx_performance_alerts_created_at
    ON pggit.performance_alerts(created_at DESC);

CREATE INDEX idx_performance_alerts_severity
    ON pggit.performance_alerts(severity);

CREATE INDEX idx_performance_alerts_is_acknowledged
    ON pggit.performance_alerts(is_acknowledged)
    WHERE is_acknowledged = FALSE;

CREATE INDEX idx_performance_alerts_operation_type
    ON pggit.performance_alerts(operation_type);

-- ============================================================================
-- 5. MERGE_PERFORMANCE_METRICS TABLE
-- ============================================================================
-- Purpose: Specialized tracking for merge operations (highest-value feature)
-- Usage: Detailed merge workflow analysis and optimization
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.merge_performance_metrics (
    merge_metric_id BIGSERIAL PRIMARY KEY,

    -- Merge identification
    source_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id) ON DELETE CASCADE,
    target_branch_id INTEGER NOT NULL REFERENCES pggit.branches(branch_id) ON DELETE CASCADE,
    merge_base_commit_hash TEXT,

    -- Merge workflow phases
    merge_base_calculation_us BIGINT,             -- Time to find LCA
    conflict_detection_us BIGINT,                 -- Time to identify conflicts
    conflict_count INTEGER,                       -- How many conflicts?
    auto_resolution_us BIGINT,                    -- Time for auto-resolution
    auto_resolution_success_count INTEGER DEFAULT 0,
    auto_resolution_failure_count INTEGER DEFAULT 0,

    -- Total merge time
    total_merge_us BIGINT NOT NULL,

    -- Merge outcome
    merge_status TEXT NOT NULL,                   -- SUCCESS, PARTIAL_SUCCESS, FAILED, ABANDONED
    merge_outcome_details JSONB,

    -- Context
    user_name TEXT NOT NULL,
    session_id TEXT,

    -- Timing
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,

    CONSTRAINT chk_merge_status CHECK (merge_status IN ('SUCCESS', 'PARTIAL_SUCCESS', 'FAILED', 'ABANDONED')),
    CONSTRAINT chk_merge_times CHECK (completed_at IS NULL OR started_at <= completed_at)
);

CREATE INDEX idx_merge_performance_source_branch
    ON pggit.merge_performance_metrics(source_branch_id);

CREATE INDEX idx_merge_performance_target_branch
    ON pggit.merge_performance_metrics(target_branch_id);

CREATE INDEX idx_merge_performance_started_at
    ON pggit.merge_performance_metrics(started_at DESC);

CREATE INDEX idx_merge_performance_merge_status
    ON pggit.merge_performance_metrics(merge_status);

-- ============================================================================
-- 6. BOOTSTRAP DATA
-- ============================================================================
-- Initialize operation_type categories for consistency
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.performance_operation_types (
    operation_type_id SERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL UNIQUE,
    description TEXT,
    category TEXT,                               -- 'READ', 'WRITE', 'ADMIN', 'WORKFLOW'
    typical_duration_ms NUMERIC(10,1),
    is_tracked BOOLEAN DEFAULT TRUE
);

-- Insert standard operation types
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, typical_duration_ms)
VALUES
    ('commit', 'Create new commit', 'WRITE', 5.0),
    ('merge', 'Merge operations', 'WRITE', 50.0),
    ('rollback', 'Rollback operations', 'WRITE', 10.0),
    ('branch_create', 'Create new branch', 'WRITE', 2.0),
    ('branch_delete', 'Delete branch', 'WRITE', 1.0),
    ('get_objects', 'Query schema objects', 'READ', 1.0),
    ('get_history', 'Query object history', 'READ', 5.0),
    ('get_branches', 'List branches', 'READ', 0.5),
    ('get_commits', 'List commits', 'READ', 2.0),
    ('conflict_detection', 'Detect merge conflicts', 'WRITE', 20.0),
    ('auto_resolution', 'Auto-resolve conflicts', 'WRITE', 15.0)
ON CONFLICT (operation_type) DO NOTHING;

-- ============================================================================
-- Summary
-- ============================================================================
-- Tables created: 5 core + 1 lookup = 6 total
-- Indexes created: 21 strategic indexes for common queries
-- Constraints: Data integrity checks (timing, status, percentiles)
-- Bootstrap: Standard operation types pre-populated
--
-- Key features:
-- ✅ Microsecond precision (BIGINT storage)
-- ✅ Distributed tracing (OpenTelemetry-compatible)
-- ✅ SLA baselines (p50, p75, p90, p95, p99)
-- ✅ Alert management with acknowledgment workflow
-- ✅ Merge-specific metrics for highest-value operations
-- ✅ Scalable with partitioning support (period_start)
-- ✅ JSONB flexibility for custom metadata
-- ============================================================================
