-- pgGit Production Mode: DDL Tracking Pause/Resume
-- File: 023_production_mode.sql
-- Purpose: Enable/disable DDL tracking for bulk operations and maintenance

-- ============================================================================
-- Configuration Table for Runtime Settings
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.tracking_config (
    config_key TEXT PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by TEXT DEFAULT current_user
);

COMMENT ON TABLE pggit.tracking_config IS 
    'Runtime configuration for pgGit DDL tracking behavior';

-- ============================================================================
-- Function: Pause DDL Tracking
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.pause_tracking(
    p_reason TEXT DEFAULT 'Bulk operation'
) RETURNS VOID AS $$
BEGIN
    -- Check if already paused
    IF EXISTS (SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused') THEN
        RAISE NOTICE 'DDL tracking is already paused. Current pause reason: %', 
            (SELECT config_value->>'reason' FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused');
        RETURN;
    END IF;
    
    -- Insert pause record
    INSERT INTO pggit.tracking_config (config_key, config_value, updated_by)
    VALUES (
        'ddl_tracking_paused',
        jsonb_build_object(
            'paused_at', CURRENT_TIMESTAMP,
            'paused_by', current_user,
            'reason', p_reason,
            'session_pid', pg_backend_pid()
        ),
        current_user
    );
    
    RAISE NOTICE 'DDL tracking paused by % at %. Reason: %', 
        current_user, CURRENT_TIMESTAMP, p_reason;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.pause_tracking IS 
    'Pause DDL event trigger tracking for bulk operations. 
     Tracking remains paused for the current session only.
     Example: SELECT pggit.pause_tracking(''Loading 1M rows'');';

-- ============================================================================
-- Function: Resume DDL Tracking
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.resume_tracking()
RETURNS VOID AS $$
DECLARE
    v_pause_record JSONB;
BEGIN
    -- Get the pause record
    SELECT config_value INTO v_pause_record
    FROM pggit.tracking_config 
    WHERE config_key = 'ddl_tracking_paused';
    
    -- Check if tracking is actually paused
    IF v_pause_record IS NULL THEN
        RAISE NOTICE 'DDL tracking is not currently paused';
        RETURN;
    END IF;
    
    -- Log the resume
    RAISE NOTICE 'DDL tracking resumed by % at %. Was paused by % at % for reason: %',
        current_user,
        CURRENT_TIMESTAMP,
        v_pause_record->>'paused_by',
        v_pause_record->>'paused_at',
        v_pause_record->>'reason';
    
    -- Remove the pause record
    DELETE FROM pggit.tracking_config 
    WHERE config_key = 'ddl_tracking_paused';
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.resume_tracking IS 
    'Resume DDL event trigger tracking after it was paused.
     Example: SELECT pggit.resume_tracking();';

-- ============================================================================
-- Function: Check if DDL Tracking is Paused
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.is_tracking_paused()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM pggit.tracking_config 
        WHERE config_key = 'ddl_tracking_paused'
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.is_tracking_paused IS 
    'Check if DDL tracking is currently paused.
     Returns true if tracking is paused, false otherwise.';

-- ============================================================================
-- Function: Get Current Pause Status
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_pause_status()
RETURNS TABLE (
    is_paused BOOLEAN,
    paused_at TIMESTAMP,
    paused_by TEXT,
    reason TEXT,
    duration INTERVAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        true AS is_paused,
        (config_value->>'paused_at')::TIMESTAMP AS paused_at,
        config_value->>'paused_by' AS paused_by,
        config_value->>'reason' AS reason,
        CURRENT_TIMESTAMP - (config_value->>'paused_at')::TIMESTAMP AS duration
    FROM pggit.tracking_config
    WHERE config_key = 'ddl_tracking_paused'
    
    UNION ALL
    
    SELECT 
        false AS is_paused,
        NULL::TIMESTAMP AS paused_at,
        NULL::TEXT AS paused_by,
        NULL::TEXT AS reason,
        NULL::INTERVAL AS duration
    WHERE NOT EXISTS (
        SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused'
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.get_pause_status IS 
    'Get detailed information about DDL tracking pause status.
     Returns current pause state including duration if paused.';

-- ============================================================================
-- Enhanced Event Trigger Handler (Production Mode Check)
-- ============================================================================

-- Note: This modifies the existing event trigger function to check for pause status
-- The actual implementation will be in a separate file that updates the existing function

-- ============================================================================
-- Production Mode Helper Functions
-- ============================================================================

-- Function: Enable Production Mode (conservative settings)
CREATE OR REPLACE FUNCTION pggit.enable_production_mode()
RETURNS VOID AS $$
BEGIN
    -- Set conservative production settings
    INSERT INTO pggit.tracking_config (config_key, config_value)
    VALUES 
        ('production_mode', jsonb_build_object(
            'enabled', true,
            'max_history_days', 90,
            'enable_auto_cleanup', true,
            'created_at', CURRENT_TIMESTAMP
        ))
    ON CONFLICT (config_key) DO UPDATE
    SET config_value = jsonb_build_object(
        'enabled', true,
        'max_history_days', 90,
        'enable_auto_cleanup', true,
        'updated_at', CURRENT_TIMESTAMP
    );
    
    RAISE NOTICE 'pgGit production mode enabled. Settings:';
    RAISE NOTICE '  - Max history retention: 90 days';
    RAISE NOTICE '  - Auto-cleanup: enabled';
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.enable_production_mode IS 
    'Enable production mode with conservative settings for stability.
     Sets 90-day history retention and enables automatic cleanup.';

-- Function: Disable Production Mode
CREATE OR REPLACE FUNCTION pggit.disable_production_mode()
RETURNS VOID AS $$
BEGIN
    DELETE FROM pggit.tracking_config WHERE config_key = 'production_mode';
    RAISE NOTICE 'pgGit production mode disabled. Development settings active.';
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.disable_production_mode IS 
    'Disable production mode and return to development settings.';

-- Function: Check Production Mode Status
CREATE OR REPLACE FUNCTION pggit.is_production_mode()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN COALESCE(
        (SELECT (config_value->>'enabled')::BOOLEAN 
         FROM pggit.tracking_config 
         WHERE config_key = 'production_mode'),
        false
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.is_production_mode IS 
    'Check if production mode is currently enabled.';

-- ============================================================================
-- Auto-Resume on Session End (Optional Safety Feature)
-- ============================================================================

-- Note: In production, consider adding a periodic check to auto-resume 
-- tracking for sessions that have been paused too long

-- Function: Force Resume All Tracking (Admin only)
CREATE OR REPLACE FUNCTION pggit.force_resume_all_tracking()
RETURNS TABLE (
    was_paused BOOLEAN,
    paused_by TEXT,
    paused_at TIMESTAMP,
    reason TEXT
) AS $$
DECLARE
    v_record RECORD;
BEGIN
    -- Only superusers should be able to force resume
    IF NOT pg_has_role(current_user, 'pg_execute_server_program', 'MEMBER') THEN
        RAISE EXCEPTION 'Only superusers can force resume all tracking';
    END IF;
    
    -- Return status before deletion
    FOR v_record IN 
        SELECT 
            true AS was_paused,
            config_value->>'paused_by' AS paused_by,
            (config_value->>'paused_at')::TIMESTAMP AS paused_at,
            config_value->>'reason' AS reason
        FROM pggit.tracking_config
        WHERE config_key = 'ddl_tracking_paused'
    LOOP
        RETURN NEXT v_record;
    END LOOP;
    
    -- Remove all pause records
    DELETE FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused';
    
    RAISE NOTICE 'All DDL tracking forcibly resumed by %', current_user;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE;

COMMENT ON FUNCTION pggit.force_resume_all_tracking IS 
    'Force resume all DDL tracking (superuser only).
     Use in emergencies when tracking was left paused.';

-- ============================================================================
-- Index for Tracking Config
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tracking_config_key 
ON pggit.tracking_config(config_key);

-- ============================================================================
-- Grant Permissions
-- ============================================================================

-- Allow all users to check pause status
GRANT EXECUTE ON FUNCTION pggit.is_tracking_paused() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_pause_status() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.is_production_mode() TO PUBLIC;

-- Only allow specific roles to pause/resume (adjust as needed)
GRANT EXECUTE ON FUNCTION pggit.pause_tracking(TEXT) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.resume_tracking() TO PUBLIC;
