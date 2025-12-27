# Phase 8: Week 2 - Real HTTP Delivery System

**Period**: After Phase 8 Week 1 completion
**Status**: Planning phase
**Objective**: Replace simulated HTTP delivery with real webhook HTTP calls
**Architecture**: Production-grade HTTP delivery with health monitoring

---

## Executive Summary

Phase 8 Week 2 transforms the simulated delivery system from Week 1 into a **production-ready HTTP webhook delivery system**:

- Real HTTP calls to external webhooks (replacing `v_http_status := 200` simulation)
- Webhook endpoint discovery and health monitoring
- Exponential backoff with intelligent retry strategies
- Connection pooling and rate limiting for webhook delivery
- Comprehensive audit trail for all HTTP interactions
- Production deployment guide with troubleshooting

**Why Real HTTP**:
- Week 1 simulated delivery for rapid prototyping
- Week 2 moves to production with actual HTTP delivery
- Full observability: response times, error codes, health metrics

**This Week's Focus**: 3 tasks (3-5 hours), production-ready HTTP delivery

---

## Architecture: Real HTTP Delivery

### Week 1 vs Week 2 Comparison

**Week 1 (Simulated)**:
```sql
-- Week 1: Simulation
v_http_status := 200;  -- Always succeeds
```

**Week 2 (Real HTTP)**:
```sql
-- Week 2: Real HTTP call via pgnet or external service
v_response := pggit.http_post_webhook(v_webhook_url, v_message_body);
v_http_status := v_response.http_status;
v_response_time_ms := v_response.response_time_ms;
```

### HTTP Delivery Flow

```
Alert in queue
├─ Get webhook endpoint & credentials
├─ Build HTTP request (POST JSON)
├─ Call webhook endpoint
│  ├─ Success (2xx): Mark delivered, log response time
│  ├─ Retriable (5xx, timeout): Schedule retry
│  └─ Permanent failure (4xx): Mark failed, escalate
├─ Log HTTP details (status, response, time)
└─ Update delivery status
```

### Health Monitoring

```
Webhook Health Tracking
├─ Success rate (% of successful deliveries)
├─ Average response time
├─ Last delivery attempt time
├─ Consecutive failure count
├─ Health status (healthy, degraded, unavailable)
└─ Auto-recovery (mark healthy after recovery)
```

---

## Task Breakdown

### Task 1: HTTP Transport Layer (pgnet or Alternative)
**Priority**: CRITICAL
**Effort**: 1-2 hours

#### Objective
Implement HTTP POST functionality for webhook delivery. Choose between:
1. **pgnet** (native PostgreSQL HTTP extension)
2. **pl/python** (if pgnet unavailable)
3. **External HTTP service** (as fallback)

#### Deliverables

**Option A: pgnet Extension**
```sql
-- Install pgnet extension (if available)
CREATE EXTENSION IF NOT EXISTS pgnet;

-- Create HTTP helper function
CREATE OR REPLACE FUNCTION pggit.http_post_webhook(
    p_webhook_url TEXT,
    p_message_body JSONB,
    p_timeout_ms INT DEFAULT 5000
)
RETURNS TABLE (
    http_status INT,
    response_body TEXT,
    response_time_ms INT,
    error_message TEXT
) AS $$
DECLARE
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_response RECORD;
    v_response_time_ms INT;
    v_error_message TEXT := NULL;
BEGIN
    BEGIN
        -- Use pgnet to make HTTP POST request
        SELECT * INTO v_response FROM pgnet.http_post(
            url => p_webhook_url,
            headers => jsonb_build_object(
                'Content-Type', 'application/json',
                'User-Agent', 'pggit-alert-delivery/1.0'
            ),
            body => p_message_body::TEXT,
            timeout => (p_timeout_ms || ' ms')::INTERVAL
        );

        v_response_time_ms := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time))::INT * 1000;

        RETURN QUERY SELECT
            v_response.status,
            v_response.body,
            v_response_time_ms,
            NULL::TEXT;

    EXCEPTION WHEN OTHERS THEN
        v_response_time_ms := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time))::INT * 1000;
        v_error_message := SQLERRM;

        RETURN QUERY SELECT
            0::INT,
            NULL::TEXT,
            v_response_time_ms,
            v_error_message;
    END;
END;
$$ LANGUAGE plpgsql;
```

**Option B: pl/python (if pgnet unavailable)**
```sql
-- Install pl/python extension
CREATE EXTENSION IF NOT EXISTS plpython3u;

-- Create HTTP helper using Python
CREATE OR REPLACE FUNCTION pggit.http_post_webhook(
    p_webhook_url TEXT,
    p_message_body JSONB,
    p_timeout_ms INT DEFAULT 5000
)
RETURNS TABLE (
    http_status INT,
    response_body TEXT,
    response_time_ms INT,
    error_message TEXT
) AS $$
import requests
import time
import json

start_time = time.time()
error_msg = None

try:
    response = requests.post(
        p_webhook_url,
        json=json.loads(p_message_body),
        headers={
            'Content-Type': 'application/json',
            'User-Agent': 'pggit-alert-delivery/1.0'
        },
        timeout=p_timeout_ms / 1000.0
    )

    response_time_ms = int((time.time() - start_time) * 1000)

    return [(
        response.status_code,
        response.text,
        response_time_ms,
        None
    )]

except Exception as e:
    response_time_ms = int((time.time() - start_time) * 1000)
    return [(0, None, response_time_ms, str(e))]
$$ LANGUAGE plpython3u;
```

#### Files to Create
- `phase8_week2_http_transport.sql` (~100 lines)
  - HTTP POST helper function
  - URL validation helper
  - Connection pooling configuration (if needed)

#### Acceptance Criteria
- ✅ `http_post_webhook()` function created and testable
- ✅ Handles success responses (2xx status codes)
- ✅ Handles failure responses (4xx, 5xx)
- ✅ Handles timeouts and connection errors
- ✅ Measures response time accurately

---

### Task 2: Webhook Health Monitoring System
**Priority**: HIGH
**Effort**: 1-2 hours

#### Objective
Track webhook endpoint health and availability

#### Deliverables

**1. Webhook Health Table**
```sql
CREATE TABLE IF NOT EXISTS pggit.webhook_health_metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.alert_notification_webhooks(webhook_id),

    -- Health metrics
    total_deliveries BIGINT DEFAULT 0,
    successful_deliveries BIGINT DEFAULT 0,
    failed_deliveries BIGINT DEFAULT 0,
    avg_response_time_ms NUMERIC(10,2),
    consecutive_failures INT DEFAULT 0,

    -- Health status
    health_status TEXT DEFAULT 'unknown',  -- healthy, degraded, unavailable
    last_success_at TIMESTAMP,
    last_failure_at TIMESTAMP,
    last_check_at TIMESTAMP,

    -- Recovery tracking
    auto_recovery_enabled BOOLEAN DEFAULT TRUE,
    recovery_attempt_count INT DEFAULT 0,
    recovery_next_check_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT health_status_check CHECK (
        health_status IN ('healthy', 'degraded', 'unavailable', 'unknown')
    )
);

CREATE INDEX idx_webhook_health_status
    ON pggit.webhook_health_metrics(health_status, webhook_id);
CREATE INDEX idx_webhook_health_last_check
    ON pggit.webhook_health_metrics(last_check_at DESC);
```

**2. Health Update Function**
```sql
CREATE OR REPLACE FUNCTION pggit.update_webhook_health(
    p_webhook_id BIGINT,
    p_http_status INT,
    p_response_time_ms INT,
    p_error_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_success BOOLEAN;
    v_current_health TEXT;
    v_new_health TEXT;
BEGIN
    -- Determine if this attempt was successful
    v_is_success := (p_http_status >= 200 AND p_http_status < 300);

    -- Get current health status
    SELECT health_status INTO v_current_health
    FROM pggit.webhook_health_metrics
    WHERE webhook_id = p_webhook_id;

    -- Calculate new health status
    IF v_is_success THEN
        v_new_health := 'healthy';
    ELSIF p_http_status >= 500 OR p_http_status = 0 THEN
        -- Server error or timeout - degraded or unavailable
        v_new_health := CASE
            WHEN v_current_health = 'healthy' THEN 'degraded'
            WHEN v_current_health = 'degraded' THEN 'unavailable'
            ELSE 'unavailable'
        END;
    ELSE
        -- Client error - likely permanent failure
        v_new_health := 'unavailable';
    END IF;

    -- Upsert health metrics
    INSERT INTO pggit.webhook_health_metrics (
        webhook_id,
        health_status,
        last_check_at,
        total_deliveries,
        successful_deliveries,
        failed_deliveries,
        last_success_at,
        last_failure_at,
        consecutive_failures
    ) VALUES (
        p_webhook_id,
        v_new_health,
        CURRENT_TIMESTAMP,
        1,
        CASE WHEN v_is_success THEN 1 ELSE 0 END,
        CASE WHEN v_is_success THEN 0 ELSE 1 END,
        CASE WHEN v_is_success THEN CURRENT_TIMESTAMP ELSE NULL END,
        CASE WHEN v_is_success THEN NULL ELSE CURRENT_TIMESTAMP END,
        CASE WHEN v_is_success THEN 0 ELSE 1 END
    )
    ON CONFLICT (webhook_id) DO UPDATE SET
        health_status = v_new_health,
        total_deliveries = webhook_health_metrics.total_deliveries + 1,
        successful_deliveries = webhook_health_metrics.successful_deliveries +
            CASE WHEN v_is_success THEN 1 ELSE 0 END,
        failed_deliveries = webhook_health_metrics.failed_deliveries +
            CASE WHEN v_is_success THEN 0 ELSE 1 END,
        avg_response_time_ms = CASE
            WHEN p_response_time_ms IS NOT NULL THEN
                (webhook_health_metrics.avg_response_time_ms * webhook_health_metrics.total_deliveries + p_response_time_ms) /
                (webhook_health_metrics.total_deliveries + 1)
            ELSE webhook_health_metrics.avg_response_time_ms
        END,
        consecutive_failures = CASE
            WHEN v_is_success THEN 0
            ELSE webhook_health_metrics.consecutive_failures + 1
        END,
        last_success_at = CASE WHEN v_is_success THEN CURRENT_TIMESTAMP
            ELSE webhook_health_metrics.last_success_at END,
        last_failure_at = CASE WHEN v_is_success THEN webhook_health_metrics.last_failure_at
            ELSE CURRENT_TIMESTAMP END,
        last_check_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP;

    RETURN v_is_success;
END;
$$ LANGUAGE plpgsql;
```

**3. Health Monitoring View**
```sql
CREATE OR REPLACE VIEW pggit.v_webhook_health_dashboard AS
SELECT
    anw.webhook_id,
    anw.webhook_url,
    anw.webhook_type,
    whm.health_status,
    ROUND(whm.avg_response_time_ms::NUMERIC, 2) as avg_response_time_ms,
    COALESCE(whm.consecutive_failures, 0) as consecutive_failures,
    whm.last_success_at,
    whm.last_failure_at,
    ROUND(
        100.0 * whm.successful_deliveries::NUMERIC /
        NULLIF(whm.total_deliveries, 0),
        1
    ) as success_rate_percent,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - whm.last_check_at)) / 3600, 1) as hours_since_check,
    CASE
        WHEN whm.health_status = 'healthy' AND whm.consecutive_failures = 0 THEN 'OK'
        WHEN whm.health_status = 'healthy' AND COALESCE(whm.avg_response_time_ms, 0) > 3000 THEN 'SLOW'
        WHEN whm.health_status = 'degraded' THEN 'DEGRADED'
        WHEN whm.health_status = 'unavailable' THEN 'CRITICAL'
        ELSE 'UNKNOWN'
    END as status_summary
FROM pggit.alert_notification_webhooks anw
LEFT JOIN pggit.webhook_health_metrics whm ON anw.webhook_id = whm.webhook_id
WHERE anw.enabled = TRUE
ORDER BY whm.health_status DESC, whm.consecutive_failures DESC;
```

#### Files to Create
- `phase8_week2_webhook_health.sql` (~150 lines)
  - `webhook_health_metrics` table
  - `update_webhook_health()` function
  - Health monitoring views

#### Acceptance Criteria
- ✅ `webhook_health_metrics` table created
- ✅ `update_webhook_health()` function tracks all metrics
- ✅ Health status transitions (healthy → degraded → unavailable)
- ✅ Success rate and response time tracking
- ✅ Dashboard view shows all webhooks with health

---

### Task 3: Integrate Real HTTP into Delivery Observer
**Priority**: CRITICAL
**Effort**: 1.5-2 hours

#### Objective
Replace Week 1 simulated delivery with real HTTP calls

#### Deliverables

**Modified `observer_deliver_alert()` Function**
```sql
CREATE OR REPLACE FUNCTION pggit.observer_deliver_alert(
    p_delivery_id BIGINT
)
RETURNS TABLE (
    delivery_id BIGINT,
    status TEXT,
    http_status INT,
    error_message TEXT
) AS $$
DECLARE
    v_webhook_id BIGINT;
    v_webhook_url TEXT;
    v_message_body JSONB;
    v_http_status INT;
    v_error TEXT := NULL;
    v_response_time_ms INT;
    v_response_body TEXT;
    v_current_status TEXT;
    v_http_response RECORD;
BEGIN
    -- Get delivery details
    SELECT adq.webhook_id, adq.message_body, adq.delivery_status
    INTO v_webhook_id, v_message_body, v_current_status
    FROM pggit.alert_delivery_queue adq
    WHERE adq.delivery_id = p_delivery_id;

    -- If not found, return error
    IF v_webhook_id IS NULL THEN
        RETURN QUERY SELECT
            p_delivery_id,
            'failed'::TEXT,
            0::INT,
            'Delivery record not found'::TEXT;
        RETURN;
    END IF;

    -- Get webhook URL (may be encrypted)
    SELECT COALESCE(webhook_url, pggit.get_webhook_decrypted(v_webhook_id))
    INTO v_webhook_url
    FROM pggit.alert_notification_webhooks anw
    WHERE anw.webhook_id = v_webhook_id;

    BEGIN
        -- Log delivery attempt
        INSERT INTO pggit.alert_delivery_log (
            delivery_id,
            webhook_id,
            event_type,
            created_at
        ) VALUES (
            p_delivery_id,
            v_webhook_id,
            'attempt',
            CURRENT_TIMESTAMP
        );

        -- Week 2: Real HTTP call (replaces simulation)
        SELECT * INTO v_http_response FROM pggit.http_post_webhook(
            v_webhook_url,
            v_message_body,
            5000  -- 5 second timeout
        );

        v_http_status := v_http_response.http_status;
        v_response_body := v_http_response.response_body;
        v_response_time_ms := v_http_response.response_time_ms;
        v_error := v_http_response.error_message;

        -- Determine delivery status based on HTTP response
        IF v_http_status >= 200 AND v_http_status < 300 THEN
            -- Success: 2xx response
            UPDATE pggit.alert_delivery_queue
            SET delivery_status = 'delivered',
                delivered_at = CURRENT_TIMESTAMP,
                attempted_at = CURRENT_TIMESTAMP
            WHERE delivery_id = p_delivery_id;

            -- Update webhook health
            PERFORM pggit.update_webhook_health(v_webhook_id, v_http_status, v_response_time_ms);

            -- Log successful delivery
            INSERT INTO pggit.alert_delivery_log (
                delivery_id,
                webhook_id,
                event_type,
                event_details,
                created_at
            ) VALUES (
                p_delivery_id,
                v_webhook_id,
                'delivered',
                jsonb_build_object(
                    'http_status', v_http_status,
                    'response_time_ms', v_response_time_ms
                ),
                CURRENT_TIMESTAMP
            );

            RETURN QUERY SELECT p_delivery_id, 'delivered'::TEXT, v_http_status, NULL::TEXT;

        ELSIF v_http_status >= 500 OR v_http_status = 0 THEN
            -- Server error or timeout: Schedule retry
            UPDATE pggit.alert_delivery_queue adq2
            SET delivery_status = 'retrying',
                retry_count = retry_count + 1,
                next_retry_at = CURRENT_TIMESTAMP + (INTERVAL '5 minutes' * (retry_count + 1)),
                attempted_at = CURRENT_TIMESTAMP
            WHERE adq2.delivery_id = p_delivery_id
              AND retry_count < max_retries;

            -- Update webhook health
            PERFORM pggit.update_webhook_health(v_webhook_id, v_http_status, v_response_time_ms, v_error);

            -- Log retry scheduled
            INSERT INTO pggit.alert_delivery_log (
                delivery_id,
                webhook_id,
                event_type,
                event_details,
                created_at
            ) VALUES (
                p_delivery_id,
                v_webhook_id,
                'retrying',
                jsonb_build_object(
                    'http_status', v_http_status,
                    'response_time_ms', v_response_time_ms,
                    'error', v_error,
                    'retry_count', (SELECT retry_count FROM pggit.alert_delivery_queue WHERE delivery_id = p_delivery_id)
                ),
                CURRENT_TIMESTAMP
            );

            RETURN QUERY SELECT p_delivery_id, 'retrying'::TEXT, v_http_status, v_error;

        ELSE
            -- Client error (4xx): Permanent failure, don't retry
            UPDATE pggit.alert_delivery_queue
            SET delivery_status = 'failed',
                attempted_at = CURRENT_TIMESTAMP
            WHERE delivery_id = p_delivery_id;

            -- Update webhook health
            PERFORM pggit.update_webhook_health(v_webhook_id, v_http_status, v_response_time_ms, v_error);

            -- Log permanent failure
            INSERT INTO pggit.alert_delivery_log (
                delivery_id,
                webhook_id,
                event_type,
                event_details,
                created_at
            ) VALUES (
                p_delivery_id,
                v_webhook_id,
                'failed',
                jsonb_build_object(
                    'http_status', v_http_status,
                    'response_time_ms', v_response_time_ms,
                    'error', v_error,
                    'reason', 'permanent_client_error'
                ),
                CURRENT_TIMESTAMP
            );

            RETURN QUERY SELECT p_delivery_id, 'failed'::TEXT, v_http_status, v_error;
        END IF;

    EXCEPTION WHEN OTHERS THEN
        v_error := SQLERRM;
        v_http_status := 0;

        -- Determine retry strategy
        IF (SELECT retry_count FROM pggit.alert_delivery_queue adq WHERE adq.delivery_id = p_delivery_id) < 3 THEN
            -- Schedule retry
            UPDATE pggit.alert_delivery_queue adq2
            SET delivery_status = 'retrying',
                retry_count = retry_count + 1,
                next_retry_at = CURRENT_TIMESTAMP + (INTERVAL '5 minutes' * (retry_count + 1)),
                attempted_at = CURRENT_TIMESTAMP
            WHERE adq2.delivery_id = p_delivery_id;
        ELSE
            -- Max retries exceeded
            UPDATE pggit.alert_delivery_queue
            SET delivery_status = 'failed',
                attempted_at = CURRENT_TIMESTAMP
            WHERE delivery_id = p_delivery_id;
        END IF;

        -- Update webhook health for error
        PERFORM pggit.update_webhook_health(v_webhook_id, 0, 0, v_error);

        -- Log failure
        INSERT INTO pggit.alert_delivery_log (
            delivery_id,
            webhook_id,
            event_type,
            event_details,
            created_at
        ) VALUES (
            p_delivery_id,
            v_webhook_id,
            'failed',
            jsonb_build_object('error', v_error, 'http_status', v_http_status),
            CURRENT_TIMESTAMP
        );

        RETURN QUERY SELECT p_delivery_id, 'failed'::TEXT, v_http_status, v_error;
    END;
END;
$$ LANGUAGE plpgsql;
```

**Intelligent Retry Strategy**
- **2xx**: Delivered - success
- **5xx, timeout (0)**: Retry with exponential backoff (5min, 10min, 15min)
- **4xx**: Permanent failure - don't retry
- **Other exceptions**: Retry up to max_retries

#### Files to Modify
- `phase8_week1_alert_delivery_observers.sql` - Update `observer_deliver_alert()` function

#### Acceptance Criteria
- ✅ Real HTTP calls via `http_post_webhook()` function
- ✅ 2xx responses mark as delivered
- ✅ 5xx/timeout responses schedule retry
- ✅ 4xx responses mark as permanent failures
- ✅ Webhook health metrics updated for each attempt
- ✅ Full audit trail logged (http_status, response_time, errors)
- ✅ Week 1 simulated delivery replaced completely

---

## Implementation Order

**Week 2 Timeline:**

| Task | Effort | Focus | Dependencies |
|------|--------|-------|--------------|
| Task 1: HTTP Transport Layer | 1-2 hours | pgnet/pl/python HTTP calls | Week 1 schema |
| Task 2: Webhook Health Monitoring | 1-2 hours | Health tracking & dashboard | Task 1 |
| Task 3: Integrate Real HTTP Delivery | 1.5-2 hours | Replace simulation with real calls | Tasks 1 & 2 |

**Total**: ~3-5 hours

**Deferred to Phase 8 Week 3+**:
- Rate limiting per webhook
- Circuit breaker pattern for failing webhooks
- Webhook encryption key management
- Advanced retry strategies (exponential backoff tuning)
- Webhook signature/HMAC validation

---

## Deliverables

### SQL Files (~250 lines total)

1. **`phase8_week2_http_transport.sql`** (~100 lines)
   - `http_post_webhook()` function (pgnet or pl/python)
   - URL validation helper
   - Connection handling

2. **`phase8_week2_webhook_health.sql`** (~150 lines)
   - `webhook_health_metrics` table
   - `update_webhook_health()` function
   - Health monitoring views
   - Dashboard views

3. **Modified `phase8_week1_alert_delivery_observers.sql`**
   - Updated `observer_deliver_alert()` with real HTTP
   - Intelligent retry strategy based on HTTP status
   - Health metric updates

### Database Objects Created
- 1 new table: `webhook_health_metrics`
- 2 new functions: `http_post_webhook()`, `update_webhook_health()`
- 2 new views: `v_webhook_health_dashboard`, health summary views
- 1 modified function: `observer_deliver_alert()`
- 0 modified tables: Zero changes to existing schema

---

## Success Criteria

**Phase 8 Week 2 Completion**:

- [ ] Task 1: HTTP Transport Layer
  - [ ] `http_post_webhook()` function created (pgnet or pl/python)
  - [ ] Handles success responses (2xx)
  - [ ] Handles failures (4xx, 5xx, timeouts)
  - [ ] Measures response time accurately
  - [ ] Properly escapes/validates webhook URLs

- [ ] Task 2: Webhook Health Monitoring
  - [ ] `webhook_health_metrics` table created
  - [ ] `update_webhook_health()` function tracks success/failure metrics
  - [ ] Health status transitions: healthy → degraded → unavailable
  - [ ] Success rate and average response time tracking
  - [ ] Dashboard view shows all webhooks with current health

- [ ] Task 3: Integrate Real HTTP Delivery
  - [ ] `observer_deliver_alert()` replaced with real HTTP calls
  - [ ] 2xx responses mark as delivered
  - [ ] 5xx/timeout responses schedule retry with exponential backoff
  - [ ] 4xx responses marked as permanent failures (no retry)
  - [ ] Webhook health metrics updated for each attempt
  - [ ] Full audit trail logged (http_status, response_time, error)
  - [ ] Week 1 simulated delivery completely replaced

**Overall Phase 8 Week 2**:
- [ ] Real HTTP webhook delivery operational
- [ ] Webhook health monitoring dashboard functional
- [ ] Intelligent retry strategy working (2xx: done, 5xx: retry, 4xx: fail)
- [ ] Production-ready HTTP delivery system
- [ ] Ready for Phase 8 Week 3 (rate limiting, encryption, etc.)

---

## Technical Decisions

### HTTP Library Choice

**Option 1: pgnet Extension** (Preferred)
- ✅ Pure PostgreSQL, no language dependencies
- ✅ Built-in connection pooling
- ✅ Integrated with PostgreSQL transaction model
- ❌ May require extension installation/permissions

**Option 2: pl/python** (Fallback)
- ✅ Python requests library widely available
- ✅ More flexible error handling
- ✅ Easier to extend with complex logic
- ❌ Requires pl/python extension (language support)
- ❌ Slight performance overhead vs pgnet

**Recommendation**: Try pgnet first, fall back to pl/python if unavailable

### Retry Strategy

```
HTTP Status → Action
2xx (200-299) → Mark delivered, success
5xx (500-599) → Schedule retry (5min, 10min, 15min exponential backoff)
4xx (400-499) → Mark failed, don't retry (permanent client error)
0 (timeout)  → Schedule retry (treat as server error)
Other        → Schedule retry (treat as server error)
```

### Health Status Transitions

```
Unknown
  ↓
Healthy (first success)
  ├─ Stay healthy (success continues)
  └─ → Degraded (consecutive failure)
       ├─ Recover → Healthy
       └─ → Unavailable (persistent failures)
            └─ Recover → Degraded → Healthy
```

---

## Performance Targets

- **HTTP POST call**: <5 seconds (configurable timeout)
- **Webhook health update**: <10ms (lightweight metrics)
- **Retry processor**: <500ms for 50-item batch
- **Health dashboard query**: <5ms
- **Success rate calculation**: <1ms

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Webhook timeout | Medium | 5-second timeout, exponential backoff prevents hammer effect |
| HTTP library unavailable | Medium | Fall back from pgnet to pl/python to external service |
| Malformed webhook URL | Low | Validate URLs before attempting HTTP POST |
| High failure rate | Medium | Health monitoring identifies unavailable webhooks automatically |
| Response time spike | Low | Track avg_response_time_ms, alert on degradation |
| Connection exhaustion | Low | Use connection pooling (pgnet) or limit concurrent requests |
| Week 1→2 compatibility | None | Modified `observer_deliver_alert()` backward compatible |

---

## Testing Strategy

**Unit Tests**:
1. `http_post_webhook()` with mock webhooks (success, failure, timeout)
2. `update_webhook_health()` with various scenarios
3. Health status transitions

**Integration Tests**:
1. End-to-end delivery flow with real webhooks
2. Retry logic with simulated failures
3. Health monitoring accuracy

**Performance Tests**:
1. Batch delivery (50+ concurrent deliveries)
2. High-volume health updates
3. Dashboard query performance

---

## Deployment & Troubleshooting

### Pre-Deployment Checklist
- [ ] pgnet extension available OR pl/python enabled
- [ ] Test HTTP connectivity to all webhook endpoints
- [ ] Webhook URLs validated (HTTPS recommended)
- [ ] Health monitoring tables created and indexed
- [ ] Monitoring dashboard accessible

### Troubleshooting Guide

**"pgnet extension not found"**
- Install pgnet: `CREATE EXTENSION pgnet;`
- Fallback to pl/python: Ensure `CREATE EXTENSION plpython3u;` succeeds

**"Webhooks not receiving deliveries"**
- Check `v_webhook_health_dashboard` for health status
- Verify webhook URLs in `alert_notification_webhooks`
- Check `alert_delivery_log` for error details
- Test connectivity: `SELECT pggit.http_post_webhook(url, '{}', 5000);`

**"High failure rate"**
- Check webhook health: `SELECT * FROM pggit.v_webhook_health_dashboard WHERE health_status != 'healthy';`
- Review error logs: `SELECT * FROM pggit.alert_delivery_log WHERE event_type = 'failed' ORDER BY created_at DESC LIMIT 20;`
- Consider increasing timeout if response times high

---

## Notes

**Week 2 Approach: Real HTTP with Health Monitoring**
- Replace Week 1 simulation with actual HTTP calls
- Comprehensive health tracking for all webhooks
- Intelligent retry strategy (2xx, 5xx, 4xx handling)
- Production observability and troubleshooting support
- Zero breaking changes to Week 1 schema/functions

**Design Decisions**:
- **HTTP Library**: pgnet preferred (pure SQL), pl/python fallback
- **Retry Strategy**: Exponential backoff (5min, 10min, 15min), max 3 retries
- **Health Monitoring**: Separate metrics table for independent tracking
- **Error Handling**: Different handling for 4xx (permanent) vs 5xx (retriable)

**Why Week 2**:
- Week 1 provides fast prototyping with simulation
- Week 2 adds production-grade HTTP delivery
- Smooth transition: Same queue/observer architecture, only delivery transport changes
- No breaking changes to existing code

---

## Sign-off

**Phase 8 Week 2 Objectives**:

✅ **Real HTTP Delivery**: Replace simulation with actual webhook HTTP calls
✅ **Health Monitoring**: Track webhook health, success rates, response times
✅ **Intelligent Retries**: Different strategies for 2xx, 4xx, 5xx responses
✅ **Observability**: Full audit trail of all HTTP interactions
✅ **Production-Ready**: Dashboard and monitoring for operational visibility
✅ **Backward Compatible**: No changes to Week 1 schema or trigger architecture

**NOT in Phase 8 Week 2** (deferred to Week 3+):
- Rate limiting per webhook
- Circuit breaker pattern
- Webhook signature/HMAC validation
- Encryption key management
- Advanced retry tuning (backoff curve optimization)

---

## Next Steps: Phase 8 Week 3+

Once Phase 8 Week 2 complete:

1. **Rate Limiting**: Per-webhook rate limits to prevent overwhelming endpoints
2. **Circuit Breaker**: Auto-disable failing webhooks temporarily
3. **Signature Validation**: HMAC-SHA256 webhook signing for security
4. **Encryption**: Encrypt sensitive webhook URLs in database
5. **Advanced Monitoring**: Correlate delivery failures with webhook health trends

---

## Related Documentation

- Phase 8 Week 1 Plan: `/home/lionel/code/pggit/PHASE8_WEEK1_PLAN.md`
- Phase 7 Week 4: Alert routing and detection
- Phase 7 Week 3: Anomaly detection and correlation analysis

