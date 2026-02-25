-- pgGit Observability Extension
-- Provides structured logging and distributed tracing capabilities
-- Compatible with OpenTelemetry conventions

-- Trace Spans Table
CREATE TABLE IF NOT EXISTS pggit.trace_spans (
    span_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trace_id UUID NOT NULL,
    parent_span_id UUID REFERENCES pggit.trace_spans(span_id),
    operation_name TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    end_time TIMESTAMPTZ,
    duration_ms NUMERIC GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (end_time - start_time)) * 1000
    ) STORED,
    status TEXT NOT NULL DEFAULT 'unset' CHECK (status IN ('unset', 'ok', 'error')),
    status_message TEXT,
    attributes JSONB DEFAULT '{}',
    events JSONB[] DEFAULT ARRAY[]::JSONB[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for trace lookup
CREATE INDEX IF NOT EXISTS idx_trace_spans_trace_id ON pggit.trace_spans(trace_id);
CREATE INDEX IF NOT EXISTS idx_trace_spans_parent ON pggit.trace_spans(parent_span_id);
CREATE INDEX IF NOT EXISTS idx_trace_spans_operation ON pggit.trace_spans(operation_name);
CREATE INDEX IF NOT EXISTS idx_trace_spans_start_time ON pggit.trace_spans(start_time DESC);

-- Structured Logs Table
CREATE TABLE IF NOT EXISTS pggit.structured_logs (
    log_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    trace_id UUID,
    span_id UUID REFERENCES pggit.trace_spans(span_id),
    severity TEXT NOT NULL CHECK (severity IN ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')),
    message TEXT NOT NULL,
    attributes JSONB DEFAULT '{}',
    source_function TEXT,
    source_line INTEGER
);

-- Index for log queries
CREATE INDEX IF NOT EXISTS idx_structured_logs_timestamp ON pggit.structured_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_structured_logs_trace_id ON pggit.structured_logs(trace_id);
CREATE INDEX IF NOT EXISTS idx_structured_logs_severity ON pggit.structured_logs(severity);

-- Start a new trace span
CREATE OR REPLACE FUNCTION pggit.start_span(
    p_operation TEXT,
    p_trace_id UUID DEFAULT NULL,
    p_parent_span_id UUID DEFAULT NULL,
    p_attributes JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trace_id UUID := COALESCE(p_trace_id, gen_random_uuid());
    v_span_id UUID;
BEGIN
    INSERT INTO pggit.trace_spans (trace_id, parent_span_id, operation_name, attributes)
    VALUES (v_trace_id, p_parent_span_id, p_operation, p_attributes)
    RETURNING span_id INTO v_span_id;

    RETURN v_span_id;
END;
$$;

COMMENT ON FUNCTION pggit.start_span IS 'Start a new trace span for distributed tracing';

-- End a trace span
CREATE OR REPLACE FUNCTION pggit.end_span(
    p_span_id UUID,
    p_status TEXT DEFAULT 'ok',
    p_status_message TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pggit.trace_spans
    SET end_time = clock_timestamp(),
        status = p_status,
        status_message = p_status_message
    WHERE span_id = p_span_id
      AND end_time IS NULL;  -- Only update if not already ended

    IF NOT FOUND THEN
        RAISE WARNING 'Span % not found or already ended', p_span_id;
    END IF;
END;
$$;

COMMENT ON FUNCTION pggit.end_span IS 'End a trace span and record its status';

-- Add event to span
CREATE OR REPLACE FUNCTION pggit.add_span_event(
    p_span_id UUID,
    p_event_name TEXT,
    p_attributes JSONB DEFAULT '{}'
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_event JSONB;
BEGIN
    v_event := jsonb_build_object(
        'timestamp', extract(epoch from clock_timestamp()),
        'name', p_event_name,
        'attributes', p_attributes
    );

    UPDATE pggit.trace_spans
    SET events = events || v_event
    WHERE span_id = p_span_id;
END;
$$;

COMMENT ON FUNCTION pggit.add_span_event IS 'Add an event to a trace span';

-- Log with structured data
CREATE OR REPLACE FUNCTION pggit.log(
    p_severity TEXT,
    p_message TEXT,
    p_attributes JSONB DEFAULT '{}',
    p_trace_id UUID DEFAULT NULL,
    p_span_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_context TEXT;
    v_source_function TEXT;
    v_source_line INTEGER;
BEGIN
    -- Extract caller context from PG call stack
    GET DIAGNOSTICS v_context = PG_CONTEXT;

    -- Parse context to extract function name (first function in stack)
    -- Format: "PL/pgSQL function <schema>.<function>(<args>) line <N> at <statement>"
    v_source_function := COALESCE(
        substring(v_context FROM 'function ([a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*)\('),
        current_setting('application_name', true),
        'unknown'
    );

    -- Extract line number from context
    v_source_line := COALESCE(
        substring(v_context FROM 'line ([0-9]+)')::INTEGER,
        0
    );

    INSERT INTO pggit.structured_logs (
        severity,
        message,
        attributes,
        trace_id,
        span_id,
        source_function,
        source_line
    ) VALUES (
        UPPER(p_severity),
        p_message,
        p_attributes,
        p_trace_id,
        p_span_id,
        v_source_function,
        v_source_line
    );
END;
$$;

COMMENT ON FUNCTION pggit.log IS 'Write structured log entry';

-- Convenience logging functions
CREATE OR REPLACE FUNCTION pggit.log_debug(p_message TEXT, p_attributes JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE SQL AS $$
    SELECT pggit.log('DEBUG', p_message, p_attributes);
$$;

CREATE OR REPLACE FUNCTION pggit.log_info(p_message TEXT, p_attributes JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE SQL AS $$
    SELECT pggit.log('INFO', p_message, p_attributes);
$$;

CREATE OR REPLACE FUNCTION pggit.log_warn(p_message TEXT, p_attributes JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE SQL AS $$
    SELECT pggit.log('WARN', p_message, p_attributes);
$$;

CREATE OR REPLACE FUNCTION pggit.log_error(p_message TEXT, p_attributes JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE SQL AS $$
    SELECT pggit.log('ERROR', p_message, p_attributes);
$$;

-- Get traces by ID
CREATE OR REPLACE FUNCTION pggit.get_trace(p_trace_id UUID)
RETURNS TABLE (
    span_id UUID,
    parent_span_id UUID,
    operation_name TEXT,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    duration_ms NUMERIC,
    status TEXT,
    attributes JSONB,
    events JSONB[]
)
LANGUAGE SQL STABLE
AS $$
    SELECT
        span_id,
        parent_span_id,
        operation_name,
        start_time,
        end_time,
        duration_ms,
        status,
        attributes,
        events
    FROM pggit.trace_spans
    WHERE trace_id = p_trace_id
    ORDER BY start_time;
$$;

COMMENT ON FUNCTION pggit.get_trace IS 'Get all spans for a trace ID';

-- Get slow operations
CREATE OR REPLACE FUNCTION pggit.get_slow_operations(
    p_threshold_ms NUMERIC DEFAULT 1000,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    trace_id UUID,
    operation_name TEXT,
    duration_ms NUMERIC,
    start_time TIMESTAMPTZ,
    attributes JSONB
)
LANGUAGE SQL STABLE
AS $$
    SELECT
        trace_id,
        operation_name,
        duration_ms,
        start_time,
        attributes
    FROM pggit.trace_spans
    WHERE duration_ms > p_threshold_ms
      AND end_time IS NOT NULL
    ORDER BY duration_ms DESC
    LIMIT p_limit;
$$;

COMMENT ON FUNCTION pggit.get_slow_operations IS 'Find operations slower than threshold';

-- Cleanup old traces
CREATE OR REPLACE FUNCTION pggit.cleanup_old_traces(p_retention_days INTEGER DEFAULT 30)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    -- Delete old trace spans
    DELETE FROM pggit.trace_spans
    WHERE created_at < now() - (p_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    -- Delete old logs
    DELETE FROM pggit.structured_logs
    WHERE timestamp < now() - (p_retention_days || ' days')::INTERVAL;

    PERFORM pggit.log_info(
        'Cleaned up old observability data',
        jsonb_build_object(
            'deleted_spans', v_deleted,
            'retention_days', p_retention_days
        )
    );

    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION pggit.cleanup_old_traces IS 'Clean up observability data older than retention period';

-- Example: Instrumented function
CREATE OR REPLACE FUNCTION pggit.create_branch_with_tracing(
    p_branch_name TEXT,
    p_parent_branch TEXT DEFAULT 'main'
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_span_id UUID;
    v_trace_id UUID;
    v_result UUID;
BEGIN
    -- Start trace
    v_span_id := pggit.start_span(
        'create_branch',
        p_attributes := jsonb_build_object(
            'branch_name', p_branch_name,
            'parent_branch', p_parent_branch
        )
    );

    BEGIN
        -- Actual branch creation logic would go here
        -- v_result := pggit.create_branch(p_branch_name, p_parent_branch);

        v_result := gen_random_uuid();  -- Placeholder

        -- Add success event
        PERFORM pggit.add_span_event(
            v_span_id,
            'branch_created',
            jsonb_build_object('branch_id', v_result)
        );

        -- End span with success
        PERFORM pggit.end_span(v_span_id, 'ok');

        RETURN v_result;

    EXCEPTION
        WHEN OTHERS THEN
            -- Log error
            PERFORM pggit.log_error(
                'Failed to create branch: ' || SQLERRM,
                jsonb_build_object(
                    'branch_name', p_branch_name,
                    'error_code', SQLSTATE
                )
            );

            -- End span with error
            PERFORM pggit.end_span(v_span_id, 'error', SQLERRM);

            RAISE;
    END;
END;
$$;

COMMENT ON FUNCTION pggit.create_branch_with_tracing IS
    'Example function demonstrating distributed tracing integration';

-- Grant permissions
GRANT SELECT, INSERT ON pggit.trace_spans TO PUBLIC;
GRANT SELECT, INSERT ON pggit.structured_logs TO PUBLIC;
GRANT USAGE ON SEQUENCE pggit.structured_logs_log_id_seq TO PUBLIC;
