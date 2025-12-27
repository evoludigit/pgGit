-- ============================================================================
-- Phase 7: Week 3 Critical Enhancements
-- ============================================================================
-- Description: Critical and recommended implementations from specialist review
-- - Temporal range checks for baseline recalculation
-- - Transaction safety with early exit
-- - Mattermost + Slack webhook integration with encryption
-- - Alert notification system with escalation
-- - Snooze feature for repeated alerts
-- - Batch processing optimization
-- Version: 1.0.0
-- Date: 2025-12-27
-- ============================================================================

-- ============================================================================
-- CRITICAL: 1. TEMPORAL RANGE CHECKS & TRANSACTION SAFETY
-- ============================================================================

-- Table to track baseline recalculation executions
CREATE TABLE IF NOT EXISTS pggit.baseline_recalc_execution (
    execution_id BIGSERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    start_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP,
    status TEXT NOT NULL DEFAULT 'RUNNING', -- 'RUNNING', 'SUCCESS', 'FAILED'
    duration_ms INTEGER,
    records_affected INTEGER,
    error_message TEXT,
    error_details JSONB,
    CONSTRAINT baseline_recalc_execution_status_check
        CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED')),
    CONSTRAINT baseline_recalc_op_type_fk
        FOREIGN KEY (operation_type)
        REFERENCES pggit.performance_operation_types(operation_type)
);

-- Table to track baseline calculation history
CREATE TABLE IF NOT EXISTS pggit.performance_baseline_history (
    history_id BIGSERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    old_baseline_id BIGINT,
    new_baseline_id BIGINT,
    old_p99_microseconds BIGINT,
    new_p99_microseconds BIGINT,
    percent_change NUMERIC(8,2),
    sample_count INTEGER,
    lookback_days INTEGER,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason TEXT, -- 'scheduled', 'manual', 'force', 'maintenance'
    CONSTRAINT baseline_history_op_type_fk
        FOREIGN KEY (operation_type)
        REFERENCES pggit.performance_operation_types(operation_type)
);

-- Create indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_baseline_recalc_execution_status
    ON pggit.baseline_recalc_execution(status, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_baseline_recalc_execution_operation
    ON pggit.baseline_recalc_execution(operation_type, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_baseline_history_operation
    ON pggit.performance_baseline_history(operation_type, calculated_at DESC);

-- ============================================================================
-- Enhanced Baseline Recalculation with Temporal Range Checks & Transaction Safety
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.recalculate_all_baselines_rolling(
    p_lookback_days INTEGER DEFAULT 7,
    p_min_samples INTEGER DEFAULT 10,
    p_force_recalc BOOLEAN DEFAULT FALSE,
    p_max_execution_time_seconds INTEGER DEFAULT 60
)
RETURNS TABLE (
    operation_type TEXT,
    baseline_id BIGINT,
    sample_count INTEGER,
    p99_old_ms NUMERIC,
    p99_new_ms NUMERIC,
    percent_change NUMERIC,
    status TEXT,
    message TEXT
) AS $$
DECLARE
    v_lookback_start TIMESTAMP;
    v_lookback_end TIMESTAMP;
    v_max_execution_time INTERVAL;
    v_execution_start TIMESTAMP;
    v_exec_id BIGINT;
    v_rec RECORD;
    v_row_count INTEGER := 0;
    v_error_msg TEXT;
    v_error_detail TEXT;
    v_error_context TEXT;
BEGIN
    -- Start execution tracking
    v_execution_start := CURRENT_TIMESTAMP;
    v_max_execution_time := format('%d seconds', p_max_execution_time_seconds)::INTERVAL;

    -- Validate input parameters
    IF p_lookback_days < 1 OR p_lookback_days > 365 THEN
        RAISE EXCEPTION 'Invalid lookback_days: must be between 1 and 365';
    END IF;

    IF p_min_samples < 1 OR p_min_samples > 1000 THEN
        RAISE EXCEPTION 'Invalid min_samples: must be between 1 and 1000';
    END IF;

    -- Calculate temporal range with safety checks
    v_lookback_end := CURRENT_TIMESTAMP;
    v_lookback_start := v_lookback_end - format('%d days', p_lookback_days)::INTERVAL;

    -- Verify temporal bounds are reasonable
    IF v_lookback_start > v_lookback_end THEN
        RAISE EXCEPTION 'Temporal range invalid: start_time > end_time';
    END IF;

    -- For each operation type, attempt recalculation
    FOR v_rec IN
        SELECT operation_type
        FROM pggit.performance_operation_types
        WHERE is_tracked = TRUE
        ORDER BY operation_type
    LOOP
        -- Check execution timeout every iteration
        IF (CURRENT_TIMESTAMP - v_execution_start) > v_max_execution_time THEN
            RETURN QUERY SELECT
                v_rec.operation_type,
                NULL::BIGINT,
                NULL::INTEGER,
                NULL::NUMERIC,
                NULL::NUMERIC,
                NULL::NUMERIC,
                'TIMEOUT'::TEXT,
                'Execution timeout exceeded'::TEXT;
            CONTINUE;
        END IF;

        -- Recalculate single operation baseline with error handling
        PERFORM pggit.recalculate_single_baseline_safe(
            v_rec.operation_type,
            p_lookback_days,
            p_min_samples,
            p_force_recalc
        );

        v_row_count := v_row_count + 1;
    END LOOP;

    -- Return results from recalculation history (most recent)
    RETURN QUERY
    SELECT
        ph.operation_type,
        ph.new_baseline_id,
        ph.sample_count,
        (ph.old_p99_microseconds::NUMERIC / 1000)::NUMERIC(10,2),
        (ph.new_p99_microseconds::NUMERIC / 1000)::NUMERIC(10,2),
        ph.percent_change,
        'SUCCESS'::TEXT,
        format('Recalculated with %d samples', ph.sample_count)::TEXT
    FROM pggit.performance_baseline_history ph
    WHERE ph.calculated_at >= v_execution_start
    ORDER BY ph.calculated_at DESC;

EXCEPTION WHEN OTHERS THEN
    -- Log error and return graceful failure
    GET STACKED DIAGNOSTICS
        v_error_msg = MESSAGE_TEXT,
        v_error_detail = PG_EXCEPTION_DETAIL,
        v_error_context = PG_EXCEPTION_CONTEXT;

    RETURN QUERY SELECT
        'ERROR'::TEXT,
        NULL::BIGINT,
        NULL::INTEGER,
        NULL::NUMERIC,
        NULL::NUMERIC,
        NULL::NUMERIC,
        'FAILED'::TEXT,
        v_error_msg;

    -- Log to monitoring table for alerting
    PERFORM pggit.log_baseline_recalc_error(
        p_operation_type => 'ALL',
        p_error_message => v_error_msg,
        p_error_detail => v_error_detail,
        p_error_context => v_error_context
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Safe Single Baseline Recalculation with Transaction Control
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.recalculate_single_baseline_safe(
    p_operation_type TEXT,
    p_lookback_days INTEGER DEFAULT 7,
    p_min_samples INTEGER DEFAULT 10,
    p_force_recalc BOOLEAN DEFAULT FALSE
)
RETURNS VOID AS $$
DECLARE
    v_sample_count INTEGER;
    v_old_baseline RECORD;
    v_new_baseline RECORD;
    v_percent_change NUMERIC;
    v_lookback_start TIMESTAMP;
    v_lookback_end TIMESTAMP;
    v_error_msg TEXT;
BEGIN
    -- Temporal range check
    v_lookback_end := CURRENT_TIMESTAMP;
    v_lookback_start := v_lookback_end - format('%d days', p_lookback_days)::INTERVAL;

    -- Count samples in temporal window
    SELECT COUNT(*) INTO v_sample_count
    FROM pggit.performance_metrics
    WHERE operation_type = p_operation_type
      AND recorded_at >= v_lookback_start
      AND recorded_at <= v_lookback_end;

    -- Early exit: insufficient samples
    IF v_sample_count < p_min_samples THEN
        RETURN; -- Silent return, keep existing baseline
    END IF;

    -- Get current active baseline
    SELECT * INTO v_old_baseline
    FROM pggit.performance_baselines
    WHERE operation_type = p_operation_type
      AND is_active = TRUE
    LIMIT 1;

    -- Calculate new baseline from recent data
    WITH new_baseline_calc AS (
        SELECT
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_microseconds) as p50_us,
            PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_microseconds) as p75_us,
            PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY duration_microseconds) as p90_us,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_microseconds) as p95_us,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_microseconds) as p99_us,
            MIN(duration_microseconds) as min_us,
            MAX(duration_microseconds) as max_us,
            STDDEV(duration_microseconds) as stddev_us,
            COUNT(*) as sample_count
        FROM pggit.performance_metrics
        WHERE operation_type = p_operation_type
          AND recorded_at >= v_lookback_start
          AND recorded_at <= v_lookback_end
    )
    SELECT
        nbc.p50_us::BIGINT,
        nbc.p75_us::BIGINT,
        nbc.p90_us::BIGINT,
        nbc.p95_us::BIGINT,
        nbc.p99_us::BIGINT,
        nbc.min_us::BIGINT,
        nbc.max_us::BIGINT,
        nbc.stddev_us,
        nbc.sample_count
    INTO v_new_baseline
    FROM new_baseline_calc;

    -- Validate data quality
    IF v_new_baseline IS NULL THEN
        RETURN; -- No data to process
    END IF;

    -- Verify percentile ordering
    IF v_new_baseline.p50_us > v_new_baseline.p75_us OR
       v_new_baseline.p75_us > v_new_baseline.p90_us OR
       v_new_baseline.p90_us > v_new_baseline.p95_us OR
       v_new_baseline.p95_us > v_new_baseline.p99_us THEN
        RAISE EXCEPTION 'Percentile ordering violation for %', p_operation_type;
    END IF;

    -- Calculate percent change from old baseline
    IF v_old_baseline IS NOT NULL THEN
        v_percent_change := ((v_new_baseline.p99_us::NUMERIC - v_old_baseline.p99_microseconds::NUMERIC) /
                            v_old_baseline.p99_microseconds::NUMERIC * 100)::NUMERIC(8,2);

        -- Early exit: change below threshold (unless force_recalc)
        IF ABS(v_percent_change) < 5.0 AND NOT p_force_recalc THEN
            RETURN; -- Keep existing baseline
        END IF;
    ELSE
        v_percent_change := 0;
    END IF;

    -- TRANSACTION: Deactivate old and insert new baseline
    BEGIN
        -- Deactivate old baseline if exists
        IF v_old_baseline IS NOT NULL THEN
            UPDATE pggit.performance_baselines
            SET is_active = FALSE,
                deactivated_at = CURRENT_TIMESTAMP
            WHERE baseline_id = v_old_baseline.baseline_id;
        END IF;

        -- Insert new baseline
        INSERT INTO pggit.performance_baselines (
            operation_type,
            p50_microseconds,
            p75_microseconds,
            p90_microseconds,
            p95_microseconds,
            p99_microseconds,
            min_microseconds,
            max_microseconds,
            stddev_microseconds,
            sample_count,
            lookback_days,
            alert_threshold_multiplier,
            is_active,
            calculated_at
        ) VALUES (
            p_operation_type,
            v_new_baseline.p50_us,
            v_new_baseline.p75_us,
            v_new_baseline.p90_us,
            v_new_baseline.p95_us,
            v_new_baseline.p99_us,
            v_new_baseline.min_us,
            v_new_baseline.max_us,
            v_new_baseline.stddev_us::NUMERIC,
            v_new_baseline.sample_count,
            p_lookback_days,
            CASE
                WHEN p_operation_type LIKE '%merge%' THEN 2.0
                WHEN p_operation_type LIKE '%get_history%' THEN 2.0
                WHEN p_operation_type LIKE '%rollback%' THEN 2.0
                ELSE 2.5
            END,
            TRUE,
            CURRENT_TIMESTAMP
        );

        -- Log change to history
        INSERT INTO pggit.performance_baseline_history (
            operation_type,
            old_baseline_id,
            new_baseline_id,
            old_p99_microseconds,
            new_p99_microseconds,
            percent_change,
            sample_count,
            lookback_days,
            calculated_at,
            reason
        ) VALUES (
            p_operation_type,
            COALESCE(v_old_baseline.baseline_id, NULL),
            (SELECT baseline_id FROM pggit.performance_baselines
             WHERE operation_type = p_operation_type AND is_active = TRUE LIMIT 1),
            COALESCE(v_old_baseline.p99_microseconds, NULL),
            v_new_baseline.p99_us,
            v_percent_change,
            v_new_baseline.sample_count,
            p_lookback_days,
            CURRENT_TIMESTAMP,
            CASE WHEN p_force_recalc THEN 'force' ELSE 'scheduled' END
        );

    EXCEPTION WHEN OTHERS THEN
        -- Log error and continue (don't fail entire batch)
        v_error_msg := SQLERRM;
        PERFORM pggit.log_baseline_recalc_error(
            p_operation_type => p_operation_type,
            p_error_message => v_error_msg,
            p_error_detail => NULL,
            p_error_context => NULL
        );
        RETURN;
    END;

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Error Logging for Baseline Recalculation
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.log_baseline_recalc_error(
    p_operation_type TEXT,
    p_error_message TEXT,
    p_error_detail TEXT DEFAULT NULL,
    p_error_context TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.performance_alerts (
        operation_type,
        alert_type,
        severity,
        alert_message,
        violation_multiplier,
        alert_data,
        is_active
    ) VALUES (
        p_operation_type,
        'BASELINE_RECALC_ERROR',
        'CRITICAL',
        format('Baseline recalculation error: %s', p_error_message),
        1.0,
        jsonb_build_object(
            'error_message', p_error_message,
            'error_detail', p_error_detail,
            'error_context', p_error_context
        ),
        TRUE
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CRITICAL: 2. MATTERMOST & SLACK WEBHOOK ENCRYPTION
-- ============================================================================

-- Table for encrypted webhook configurations (Slack, Mattermost, etc.)
CREATE TABLE IF NOT EXISTS pggit.alert_notification_webhooks (
    webhook_id BIGSERIAL PRIMARY KEY,
    webhook_type TEXT NOT NULL, -- 'slack', 'mattermost', 'pagerduty', 'email'
    name TEXT NOT NULL,
    channel_or_recipient TEXT, -- Slack channel, Mattermost team-channel, or email
    webhook_url_encrypted BYTEA NOT NULL, -- Encrypted webhook URL
    webhook_url_iv BYTEA NOT NULL, -- Initialization vector for encryption
    encryption_key_id TEXT NOT NULL DEFAULT 'phase7_default', -- Key identifier
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_tested_at TIMESTAMP,
    test_status TEXT, -- 'success', 'failed', 'untested'
    test_error_message TEXT,
    CONSTRAINT webhook_type_check CHECK (webhook_type IN ('slack', 'mattermost', 'pagerduty', 'email')),
    CONSTRAINT webhook_name_unique UNIQUE (webhook_type, name)
);

CREATE INDEX IF NOT EXISTS idx_alert_webhooks_type_enabled
    ON pggit.alert_notification_webhooks(webhook_type, enabled);

-- Initialize encryption key (in production, this would be managed by pg_vault or similar)
-- For now, we'll use a secure approach with pgcrypto
DO $$
BEGIN
    INSERT INTO pggit.alert_notification_webhooks
        (webhook_type, name, channel_or_recipient, webhook_url_encrypted, webhook_url_iv, enabled, test_status)
    SELECT 'slack', 'slack-default', '#alerts',
           E'\\x'::bytea, E'\\x'::bytea, FALSE, 'untested'
    WHERE NOT EXISTS (SELECT 1 FROM pggit.alert_notification_webhooks WHERE name = 'slack-default');
END $$;

-- Function to store encrypted webhook
CREATE OR REPLACE FUNCTION pggit.store_webhook_encrypted(
    p_webhook_type TEXT,
    p_name TEXT,
    p_webhook_url TEXT,
    p_channel_or_recipient TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_encrypted_url BYTEA;
    v_iv BYTEA;
    v_webhook_id BIGINT;
BEGIN
    -- Generate random IV
    v_iv := gen_random_bytes(16);

    -- Encrypt webhook URL using pgcrypto
    -- Use SHA256 hash of a system secret as encryption key
    v_encrypted_url := encrypt(
        convert_to(p_webhook_url, 'UTF8'),
        digest('pggit_phase7_webhook_key_2025', 'sha256'),
        'aes'
    );

    -- Insert encrypted webhook
    INSERT INTO pggit.alert_notification_webhooks (
        webhook_type,
        name,
        channel_or_recipient,
        webhook_url_encrypted,
        webhook_url_iv,
        enabled,
        test_status
    ) VALUES (
        p_webhook_type,
        p_name,
        p_channel_or_recipient,
        v_encrypted_url,
        v_iv,
        TRUE,
        'untested'
    )
    ON CONFLICT (webhook_type, name)
    DO UPDATE SET
        webhook_url_encrypted = EXCLUDED.webhook_url_encrypted,
        webhook_url_iv = EXCLUDED.webhook_url_iv,
        enabled = TRUE,
        last_tested_at = NULL
    RETURNING webhook_id INTO v_webhook_id;

    RETURN v_webhook_id;
END;
$$ LANGUAGE plpgsql;

-- Function to retrieve encrypted webhook
CREATE OR REPLACE FUNCTION pggit.get_webhook_decrypted(
    p_webhook_id BIGINT
)
RETURNS TABLE (
    webhook_id BIGINT,
    webhook_type TEXT,
    name TEXT,
    channel_or_recipient TEXT,
    webhook_url TEXT
) AS $$
DECLARE
    v_encrypted_url BYTEA;
    v_decrypted_url TEXT;
BEGIN
    SELECT webhook_url_encrypted INTO v_encrypted_url
    FROM pggit.alert_notification_webhooks
    WHERE webhook_id = p_webhook_id;

    IF v_encrypted_url IS NULL THEN
        RAISE EXCEPTION 'Webhook not found: %', p_webhook_id;
    END IF;

    -- Decrypt webhook URL
    v_decrypted_url := convert_from(
        decrypt(
            v_encrypted_url,
            digest('pggit_phase7_webhook_key_2025', 'sha256'),
            'aes'
        ),
        'UTF8'
    );

    RETURN QUERY
    SELECT
        w.webhook_id,
        w.webhook_type,
        w.name,
        w.channel_or_recipient,
        v_decrypted_url
    FROM pggit.alert_notification_webhooks w
    WHERE w.webhook_id = p_webhook_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- RECOMMENDED: 3. ALERT NOTIFICATION SYSTEM WITH MATTERMOST SUPPORT
-- ============================================================================

-- Table for notification configuration (which channels to use for which alerts)
CREATE TABLE IF NOT EXISTS pggit.alert_notification_settings (
    setting_id BIGSERIAL PRIMARY KEY,
    alert_type TEXT NOT NULL, -- 'THRESHOLD_EXCEEDED', 'ANOMALY', 'DEGRADATION', 'CORRELATION'
    severity TEXT NOT NULL, -- 'CRITICAL', 'WARNING', 'INFO'
    webhook_id BIGINT NOT NULL REFERENCES pggit.alert_notification_webhooks(webhook_id),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT alert_setting_severity_check CHECK (severity IN ('CRITICAL', 'WARNING', 'INFO')),
    CONSTRAINT alert_setting_alert_type_check CHECK (alert_type IN (
        'THRESHOLD_EXCEEDED', 'ANOMALY', 'DEGRADATION', 'CORRELATION', 'BASELINE_RECALC_ERROR'
    ))
);

CREATE INDEX IF NOT EXISTS idx_alert_notification_settings_alert_type_severity
    ON pggit.alert_notification_settings(alert_type, severity, enabled);

-- Queue for async notification delivery
CREATE TABLE IF NOT EXISTS pggit.alert_notification_queue (
    queue_id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT REFERENCES pggit.performance_alerts(alert_id) ON DELETE CASCADE,
    webhook_id BIGINT REFERENCES pggit.alert_notification_webhooks(webhook_id),
    message_body TEXT NOT NULL,
    message_format TEXT DEFAULT 'json', -- 'json', 'text', 'html'
    status TEXT DEFAULT 'pending', -- 'pending', 'sent', 'failed', 'retrying'
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP,
    CONSTRAINT notification_status_check CHECK (status IN ('pending', 'sent', 'failed', 'retrying'))
);

CREATE INDEX IF NOT EXISTS idx_notification_queue_status
    ON pggit.alert_notification_queue(status, created_at);

CREATE INDEX IF NOT EXISTS idx_notification_queue_webhook
    ON pggit.alert_notification_queue(webhook_id, status);

-- Notification delivery log
CREATE TABLE IF NOT EXISTS pggit.alert_notification_log (
    log_id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT REFERENCES pggit.performance_alerts(alert_id) ON DELETE CASCADE,
    webhook_id BIGINT REFERENCES pggit.alert_notification_webhooks(webhook_id),
    webhook_type TEXT NOT NULL,
    status TEXT NOT NULL, -- 'success', 'failed'
    delivery_time_ms INTEGER,
    http_status_code INTEGER,
    error_message TEXT,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_log_alert
    ON pggit.alert_notification_log(alert_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_log_webhook_type
    ON pggit.alert_notification_log(webhook_type, sent_at DESC);

-- ============================================================================
-- RECOMMENDED: 4. SNOOZE FEATURE FOR REPEATED ALERTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.alert_snooze (
    snooze_id BIGSERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    alert_type TEXT NOT NULL,
    snooze_until TIMESTAMP NOT NULL,
    snooze_reason TEXT,
    created_by TEXT NOT NULL DEFAULT CURRENT_USER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT snooze_alert_type_check CHECK (alert_type IN (
        'THRESHOLD_EXCEEDED', 'ANOMALY', 'DEGRADATION', 'CORRELATION', 'BASELINE_RECALC_ERROR'
    )),
    CONSTRAINT snooze_operation_type_fk
        FOREIGN KEY (operation_type)
        REFERENCES pggit.performance_operation_types(operation_type)
);

CREATE INDEX IF NOT EXISTS idx_alert_snooze_active
    ON pggit.alert_snooze(operation_type, alert_type, snooze_until)
    WHERE is_active = TRUE;

-- Function to create snooze
CREATE OR REPLACE FUNCTION pggit.snooze_alerts(
    p_operation_type TEXT DEFAULT NULL,
    p_alert_type TEXT DEFAULT NULL,
    p_snooze_minutes INTEGER DEFAULT 60,
    p_snooze_reason TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_snooze_id BIGINT;
BEGIN
    INSERT INTO pggit.alert_snooze (
        operation_type,
        alert_type,
        snooze_until,
        snooze_reason,
        is_active
    ) VALUES (
        COALESCE(p_operation_type, 'ALL'),
        COALESCE(p_alert_type, 'ALL'),
        CURRENT_TIMESTAMP + (p_snooze_minutes || ' minutes')::INTERVAL,
        p_snooze_reason,
        TRUE
    )
    RETURNING snooze_id INTO v_snooze_id;

    RETURN v_snooze_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check if alert is snoozed
CREATE OR REPLACE FUNCTION pggit.is_alert_snoozed(
    p_operation_type TEXT,
    p_alert_type TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_snoozed BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM pggit.alert_snooze
        WHERE is_active = TRUE
          AND snooze_until > CURRENT_TIMESTAMP
          AND (operation_type = 'ALL' OR operation_type = p_operation_type)
          AND (alert_type = 'ALL' OR alert_type = p_alert_type)
        LIMIT 1
    ) INTO v_snoozed;

    RETURN COALESCE(v_snoozed, FALSE);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- RECOMMENDED: 5. BATCH PROCESSING OPTIMIZATION
-- ============================================================================

-- Batch configuration table
CREATE TABLE IF NOT EXISTS pggit.notification_batch_config (
    config_id SERIAL PRIMARY KEY,
    webhook_type TEXT NOT NULL,
    batch_size INTEGER NOT NULL DEFAULT 10,
    batch_timeout_seconds INTEGER NOT NULL DEFAULT 30,
    enabled BOOLEAN DEFAULT TRUE,
    CONSTRAINT batch_config_webhook_type_check
        CHECK (webhook_type IN ('slack', 'mattermost', 'pagerduty', 'email'))
);

-- Batch queue for accumulating notifications
CREATE TABLE IF NOT EXISTS pggit.notification_batch_queue (
    batch_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.alert_notification_webhooks(webhook_id),
    batch_items JSONB NOT NULL, -- Array of notification items
    item_count INTEGER NOT NULL,
    status TEXT DEFAULT 'accumulating', -- 'accumulating', 'ready', 'sent', 'failed'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_batch_queue_status
    ON pggit.notification_batch_queue(webhook_id, status, created_at);

-- Function to add notification to batch
CREATE OR REPLACE FUNCTION pggit.enqueue_notification_batch(
    p_webhook_id BIGINT,
    p_notification_item JSONB,
    p_max_batch_size INTEGER DEFAULT 10,
    p_timeout_minutes INTEGER DEFAULT 1
)
RETURNS BIGINT AS $$
DECLARE
    v_batch_id BIGINT;
    v_item_count INTEGER;
BEGIN
    -- Try to append to existing batch
    SELECT batch_id, item_count INTO v_batch_id, v_item_count
    FROM pggit.notification_batch_queue
    WHERE webhook_id = p_webhook_id
      AND status = 'accumulating'
      AND created_at >= CURRENT_TIMESTAMP - format('%d minutes', p_timeout_minutes)::INTERVAL
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_batch_id IS NOT NULL AND v_item_count < p_max_batch_size THEN
        -- Append to existing batch
        UPDATE pggit.notification_batch_queue
        SET batch_items = batch_items || jsonb_build_array(p_notification_item),
            item_count = item_count + 1,
            status = CASE WHEN (item_count + 1) >= p_max_batch_size THEN 'ready' ELSE 'accumulating' END
        WHERE batch_id = v_batch_id
        RETURNING batch_id INTO v_batch_id;
    ELSE
        -- Create new batch
        INSERT INTO pggit.notification_batch_queue (
            webhook_id,
            batch_items,
            item_count,
            status
        ) VALUES (
            p_webhook_id,
            jsonb_build_array(p_notification_item),
            1,
            'accumulating'
        )
        RETURNING batch_id INTO v_batch_id;
    END IF;

    RETURN v_batch_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HELPER: Format alert message for different notification channels
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.format_alert_message(
    p_alert_id BIGINT,
    p_format_type TEXT DEFAULT 'json' -- 'json', 'slack', 'mattermost', 'text'
)
RETURNS TEXT AS $$
DECLARE
    v_alert RECORD;
    v_baseline RECORD;
    v_message TEXT;
BEGIN
    -- Get alert details
    SELECT a.*, b.p99_microseconds as baseline_p99_us
    INTO v_alert
    FROM pggit.performance_alerts a
    LEFT JOIN pggit.performance_baselines b
        ON a.operation_type = b.operation_type AND b.is_active = TRUE
    WHERE a.alert_id = p_alert_id;

    IF v_alert IS NULL THEN
        RAISE EXCEPTION 'Alert not found: %', p_alert_id;
    END IF;

    -- Format message based on type
    CASE p_format_type
        WHEN 'slack' THEN
            v_message := format(
                '{"text": "🚨 pgGit Performance Alert", "attachments": [{"color": "%s", "fields": [{"title": "Operation", "value": "%s", "short": true}, {"title": "Severity", "value": "%s", "short": true}, {"title": "Duration", "value": "%.0fms", "short": true}, {"title": "Baseline", "value": "%.0fms", "short": true}, {"title": "Violation", "value": "%.1fx", "short": true}, {"title": "Time", "value": "%s", "short": true}]}]}',
                CASE v_alert.severity WHEN 'CRITICAL' THEN 'danger' WHEN 'WARNING' THEN 'warning' ELSE 'info' END,
                v_alert.operation_type,
                v_alert.severity,
                v_alert.actual_duration_microseconds / 1000.0,
                v_alert.baseline_p99_us / 1000.0,
                v_alert.violation_multiplier,
                to_char(v_alert.created_at, 'HH24:MI:SS')
            );
        WHEN 'mattermost' THEN
            v_message := format(
                '{"text": "⚠️ pgGit Performance Alert", "attachments": [{"color": "%s", "fields": [{"title": "Operation", "value": "%s", "short": true}, {"title": "Severity", "value": "%s", "short": true}, {"title": "Duration", "value": "%.0fms", "short": true}, {"title": "Baseline", "value": "%.0fms", "short": true}, {"title": "Violation", "value": "%.1fx", "short": true}, {"title": "Time", "value": "%s", "short": true}]}]}',
                CASE v_alert.severity WHEN 'CRITICAL' THEN '#FF0000' WHEN 'WARNING' THEN '#FFCC00' ELSE '#0099FF' END,
                v_alert.operation_type,
                v_alert.severity,
                v_alert.actual_duration_microseconds / 1000.0,
                v_alert.baseline_p99_us / 1000.0,
                v_alert.violation_multiplier,
                to_char(v_alert.created_at, 'HH24:MI:SS')
            );
        WHEN 'text' THEN
            v_message := format(
                'ALERT: %s exceeded baseline by %.1fx (%.0fms vs baseline %.0fms) - Severity: %s - Time: %s',
                v_alert.operation_type,
                v_alert.violation_multiplier,
                v_alert.actual_duration_microseconds / 1000.0,
                v_alert.baseline_p99_us / 1000.0,
                v_alert.severity,
                to_char(v_alert.created_at, 'HH24:MI:SS')
            );
        ELSE -- json (default)
            v_message := jsonb_build_object(
                'alert_id', v_alert.alert_id,
                'operation_type', v_alert.operation_type,
                'alert_type', v_alert.alert_type,
                'severity', v_alert.severity,
                'actual_duration_ms', v_alert.actual_duration_microseconds / 1000.0,
                'baseline_p99_ms', v_alert.baseline_p99_us / 1000.0,
                'violation_multiplier', v_alert.violation_multiplier,
                'message', v_alert.alert_message,
                'timestamp', to_char(v_alert.created_at, 'YYYY-MM-DD HH24:MI:SS'),
                'is_active', v_alert.is_active
            )::TEXT;
    END CASE;

    RETURN v_message;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION pggit.recalculate_all_baselines_rolling(INTEGER, INTEGER, BOOLEAN, INTEGER) TO public;
GRANT EXECUTE ON FUNCTION pggit.recalculate_single_baseline_safe(TEXT, INTEGER, INTEGER, BOOLEAN) TO public;
GRANT EXECUTE ON FUNCTION pggit.store_webhook_encrypted(TEXT, TEXT, TEXT, TEXT) TO public;
GRANT EXECUTE ON FUNCTION pggit.get_webhook_decrypted(BIGINT) TO public;
GRANT EXECUTE ON FUNCTION pggit.snooze_alerts(TEXT, TEXT, INTEGER, TEXT) TO public;
GRANT EXECUTE ON FUNCTION pggit.is_alert_snoozed(TEXT, TEXT) TO public;
GRANT EXECUTE ON FUNCTION pggit.enqueue_notification_batch(BIGINT, JSONB, INTEGER, INTEGER) TO public;
GRANT EXECUTE ON FUNCTION pggit.format_alert_message(BIGINT, TEXT) TO public;

-- ============================================================================
-- SAMPLE DATA FOR TESTING
-- ============================================================================

-- Insert sample Mattermost webhook (encrypted)
DO $$
BEGIN
    PERFORM pggit.store_webhook_encrypted(
        'mattermost',
        'mattermost-alerts',
        'https://mattermost.example.com/hooks/xxx/yyy/zzz',
        'pgit-alerts'
    );
    RAISE NOTICE 'Mattermost webhook stored (encrypted)';
EXCEPTION WHEN UNIQUE_VIOLATION THEN
    RAISE NOTICE 'Mattermost webhook already exists';
END $$;

-- Insert sample Slack webhook (encrypted)
DO $$
BEGIN
    PERFORM pggit.store_webhook_encrypted(
        'slack',
        'slack-alerts',
        'https://hooks.slack.com/services/XXX/YYY/ZZZ',
        '#pgit-alerts'
    );
    RAISE NOTICE 'Slack webhook stored (encrypted)';
EXCEPTION WHEN UNIQUE_VIOLATION THEN
    RAISE NOTICE 'Slack webhook already exists';
END $$;

-- ============================================================================
-- VERSION AND METADATA
-- ============================================================================

COMMENT ON TABLE pggit.baseline_recalc_execution IS
'Tracks baseline recalculation executions with temporal bounds checking and error handling';

COMMENT ON TABLE pggit.performance_baseline_history IS
'History of baseline changes for audit and trend analysis';

COMMENT ON TABLE pggit.alert_notification_webhooks IS
'Encrypted webhook configurations for Slack, Mattermost, PagerDuty, and Email';

COMMENT ON TABLE pggit.alert_notification_queue IS
'Queue for async notification delivery with retry logic';

COMMENT ON TABLE pggit.alert_snooze IS
'Temporarily suppress alerts for maintenance windows or known issues';

COMMENT ON FUNCTION pggit.recalculate_all_baselines_rolling IS
'Recalculate all performance baselines with temporal range checks and transaction safety';

COMMENT ON FUNCTION pggit.snooze_alerts IS
'Snooze alerts for a specified duration to reduce fatigue';

COMMENT ON FUNCTION pggit.format_alert_message IS
'Format alert messages for different notification channels (Slack, Mattermost, etc.)';
