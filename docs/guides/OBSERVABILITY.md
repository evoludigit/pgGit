# pgGit Observability Guide

**Structured logging and distributed tracing for production deployments**

## Overview

The pgGit observability extension provides:

- **Distributed Tracing**: OpenTelemetry-compatible trace spans
- **Structured Logging**: Machine-parseable logs with context
- **Performance Monitoring**: Track slow operations
- **Debug Support**: Correlate logs with traces

## Installation

```sql
\i sql/pggit_observability.sql
```

## Quick Start

### Basic Tracing

```sql
-- Start a trace span
SELECT pggit.start_span('my_operation') AS span_id \gset

-- Do work...
SELECT pggit.create_table('users', '...');

-- End the span
SELECT pggit.end_span(:'span_id', 'ok');
```

### Nested Spans (Parent-Child)

```sql
-- Parent span
SELECT pggit.start_span('process_data') AS parent_id \gset

-- Child span 1
SELECT pggit.start_span(
    'validate_data',
    trace_id := NULL,  -- Will inherit from parent
    parent_span_id := :'parent_id'
) AS child1_id \gset

SELECT pggit.end_span(:'child1_id', 'ok');

-- Child span 2
SELECT pggit.start_span(
    'save_data',
    parent_span_id := :'parent_id'
) AS child2_id \gset

SELECT pggit.end_span(:'child2_id', 'ok');

-- End parent
SELECT pggit.end_span(:'parent_id', 'ok');
```

### Adding Events to Spans

```sql
SELECT pggit.start_span('long_operation') AS span_id \gset

-- Add milestone events
SELECT pggit.add_span_event(
    :'span_id',
    'validation_complete',
    '{"rows_validated": 1000}'::jsonb
);

SELECT pggit.add_span_event(
    :'span_id',
    'processing_complete',
    '{"rows_processed": 1000}'::jsonb
);

SELECT pggit.end_span(:'span_id', 'ok');
```

### Structured Logging

```sql
-- Basic logging
SELECT pggit.log_info('User created', '{"user_id": 123}'::jsonb);

-- With trace context
SELECT pggit.start_span('create_user') AS span_id \gset
SELECT pggit.log_info(
    'Creating user',
    '{"username": "alice"}'::jsonb,
    trace_id := (SELECT trace_id FROM pggit.trace_spans WHERE span_id = :'span_id'),
    span_id := :'span_id'
);
```

## API Reference

### Tracing Functions

#### `pggit.start_span(operation, trace_id, parent_span_id, attributes)`

Start a new trace span.

**Parameters**:
- `operation` (TEXT): Operation name (e.g., 'create_branch')
- `trace_id` (UUID, optional): Trace ID (generates new if NULL)
- `parent_span_id` (UUID, optional): Parent span for nesting
- `attributes` (JSONB, optional): Span attributes

**Returns**: UUID span_id

**Example**:
```sql
SELECT pggit.start_span(
    'create_branch',
    p_attributes := '{"branch": "feature-x"}'::jsonb
);
```

#### `pggit.end_span(span_id, status, status_message)`

End a trace span.

**Parameters**:
- `span_id` (UUID): Span ID from start_span
- `status` (TEXT, optional): 'ok' or 'error' (default: 'ok')
- `status_message` (TEXT, optional): Status description

**Returns**: VOID

**Example**:
```sql
SELECT pggit.end_span(:'span_id', 'error', 'Validation failed');
```

#### `pggit.add_span_event(span_id, event_name, attributes)`

Add an event to a span.

**Parameters**:
- `span_id` (UUID): Span ID
- `event_name` (TEXT): Event name
- `attributes` (JSONB, optional): Event attributes

**Returns**: VOID

### Logging Functions

#### `pggit.log(severity, message, attributes, trace_id, span_id)`

Write a structured log entry.

**Parameters**:
- `severity` (TEXT): DEBUG, INFO, WARN, ERROR, FATAL
- `message` (TEXT): Log message
- `attributes` (JSONB, optional): Structured attributes
- `trace_id` (UUID, optional): Associated trace
- `span_id` (UUID, optional): Associated span

**Returns**: VOID

#### Convenience Functions

```sql
-- Severity shortcuts
pggit.log_debug(message, attributes)
pggit.log_info(message, attributes)
pggit.log_warn(message, attributes)
pggit.log_error(message, attributes)
```

### Query Functions

#### `pggit.get_trace(trace_id)`

Get all spans for a trace.

**Example**:
```sql
SELECT * FROM pggit.get_trace('abc123...');
```

#### `pggit.get_slow_operations(threshold_ms, limit)`

Find operations slower than threshold.

**Example**:
```sql
-- Get top 10 slowest operations
SELECT * FROM pggit.get_slow_operations(1000, 10);
```

### Maintenance Functions

#### `pggit.cleanup_old_traces(retention_days)`

Clean up old observability data.

**Example**:
```sql
-- Delete traces older than 30 days
SELECT pggit.cleanup_old_traces(30);
```

## Usage Patterns

### Instrumenting Functions

```sql
CREATE OR REPLACE FUNCTION my_business_logic(p_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_span_id UUID;
    v_result TEXT;
BEGIN
    -- Start span
    v_span_id := pggit.start_span(
        'my_business_logic',
        p_attributes := jsonb_build_object('input', p_input)
    );

    BEGIN
        -- Your business logic
        v_result := upper(p_input);

        -- Add event
        PERFORM pggit.add_span_event(
            v_span_id,
            'processing_complete',
            jsonb_build_object('result', v_result)
        );

        -- End span
        PERFORM pggit.end_span(v_span_id, 'ok');

        RETURN v_result;

    EXCEPTION
        WHEN OTHERS THEN
            -- Log error
            PERFORM pggit.log_error(
                'Business logic failed: ' || SQLERRM,
                jsonb_build_object('input', p_input)
            );

            -- End span with error
            PERFORM pggit.end_span(v_span_id, 'error', SQLERRM);

            RAISE;
    END;
END;
$$;
```

### Distributed Tracing Across Services

```sql
-- Service A: Create trace
SELECT pggit.start_span('api_request') AS span_id \gset
SELECT trace_id FROM pggit.trace_spans WHERE span_id = :'span_id' \gset

-- Pass trace_id to Service B (e.g., via HTTP header)
-- X-Trace-ID: {trace_id}

-- Service B: Continue trace
SELECT pggit.start_span(
    'database_query',
    trace_id := :'trace_id'
) AS db_span_id \gset

-- ... do work ...

SELECT pggit.end_span(:'db_span_id', 'ok');

-- Service A: End trace
SELECT pggit.end_span(:'span_id', 'ok');

-- View complete trace
SELECT * FROM pggit.get_trace(:'trace_id');
```

### Performance Monitoring

```sql
-- Find slow operations daily
SELECT
    operation_name,
    COUNT(*) as occurrences,
    AVG(duration_ms) as avg_ms,
    MAX(duration_ms) as max_ms
FROM pggit.trace_spans
WHERE start_time > now() - INTERVAL '1 day'
  AND end_time IS NOT NULL
GROUP BY operation_name
HAVING AVG(duration_ms) > 100
ORDER BY avg_ms DESC;
```

### Error Tracking

```sql
-- Find errors by operation
SELECT
    operation_name,
    COUNT(*) as error_count,
    array_agg(DISTINCT status_message) as error_messages
FROM pggit.trace_spans
WHERE status = 'error'
  AND start_time > now() - INTERVAL '1 day'
GROUP BY operation_name
ORDER BY error_count DESC;
```

## Integration with Observability Platforms

### Jaeger / Zipkin

Export spans to Jaeger/Zipkin using a foreign data wrapper:

```sql
-- Install postgres_fdw
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Create foreign server (Jaeger backend)
CREATE SERVER jaeger_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'jaeger-collector', port '5432', dbname 'jaeger');

-- Export traces periodically
INSERT INTO jaeger.spans
SELECT
    span_id,
    trace_id,
    parent_span_id,
    operation_name,
    start_time,
    duration_ms,
    attributes
FROM pggit.trace_spans
WHERE exported IS FALSE;
```

### Prometheus / Grafana

Create views for Prometheus postgres_exporter:

```sql
-- Metrics view for Prometheus
CREATE VIEW pggit.metrics AS
SELECT
    operation_name,
    COUNT(*) as requests_total,
    AVG(duration_ms) as duration_avg_ms,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) as duration_p95_ms,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_ms) as duration_p99_ms
FROM pggit.trace_spans
WHERE start_time > now() - INTERVAL '5 minutes'
  AND end_time IS NOT NULL
GROUP BY operation_name;
```

### CloudWatch / Datadog

Export logs using CloudWatch RDS integration or Datadog agent:

```sql
-- Query for CloudWatch export
SELECT
    timestamp,
    severity,
    message,
    attributes,
    trace_id
FROM pggit.structured_logs
WHERE timestamp > now() - INTERVAL '1 minute'
ORDER BY timestamp;
```

## Best Practices

1. **Span Naming**: Use descriptive, hierarchical names (e.g., 'db.query.users.select')

2. **Attribute Keys**: Follow OpenTelemetry semantic conventions
   - `db.statement`, `db.operation`, `http.method`, etc.

3. **Error Handling**: Always end spans, even on error

4. **Sampling**: For high-volume systems, sample traces (e.g., 1 in 100)

5. **Retention**: Clean up old data regularly
   ```sql
   -- Run daily
   SELECT pggit.cleanup_old_traces(30);
   ```

6. **Performance**: Observability adds overhead (~1-5ms per span)
   - Use for critical paths only
   - Batch log writes if needed

## Troubleshooting

### High Overhead

```sql
-- Check span creation rate
SELECT
    COUNT(*) as spans_per_minute,
    AVG(duration_ms) as avg_duration
FROM pggit.trace_spans
WHERE start_time > now() - INTERVAL '1 minute';

-- If too high, implement sampling
```

### Storage Growth

```sql
-- Check table sizes
SELECT
    pg_size_pretty(pg_total_relation_size('pggit.trace_spans')) as spans_size,
    pg_size_pretty(pg_total_relation_size('pggit.structured_logs')) as logs_size;

-- Cleanup more aggressively
SELECT pggit.cleanup_old_traces(7);  -- 7 days instead of 30
```

## Related Documentation

- [Operations Runbook](../operations/RUNBOOK.md)
- [Monitoring Guide](../operations/MONITORING.md)
- [Performance Tuning](PERFORMANCE_TUNING.md)
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/)
