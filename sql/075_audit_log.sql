-- pgGit Operation Audit Logging
-- Phase 3: Reliability - Operation Audit Logging
-- =====================================================

-- Create audit table for operation tracking
CREATE TABLE pggit.operation_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    operation_name TEXT NOT NULL,
    operation_type TEXT NOT NULL CHECK (operation_type IN ('read', 'write', 'delete')),
    user_name TEXT NOT NULL DEFAULT CURRENT_USER,
    session_id TEXT NOT NULL DEFAULT pg_backend_pid()::TEXT,

    -- Context
    parameters JSONB,
    affected_resources JSONB,

    -- Timing
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    duration_ms BIGINT,

    -- Result
    success BOOLEAN,
    error_code TEXT,
    error_message TEXT,
    rows_affected INTEGER,

    -- Metadata
    client_addr INET DEFAULT inet_client_addr(),
    application_name TEXT DEFAULT current_setting('application_name', true)
);

-- Add indexes for efficient querying
CREATE INDEX idx_operation_audit_operation ON pggit.operation_audit(operation_name);
CREATE INDEX idx_operation_audit_started ON pggit.operation_audit(started_at DESC);
CREATE INDEX idx_operation_audit_user ON pggit.operation_audit(user_name);
CREATE INDEX idx_operation_audit_success ON pggit.operation_audit(success);
CREATE INDEX idx_operation_audit_session ON pggit.operation_audit(session_id);

-- Add trigger for auto-updating duration
CREATE OR REPLACE FUNCTION pggit.update_audit_duration()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND OLD.completed_at IS NULL THEN
        NEW.duration_ms := EXTRACT(EPOCH FROM (NEW.completed_at - NEW.started_at)) * 1000;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_operation_audit_duration
    BEFORE UPDATE ON pggit.operation_audit
    FOR EACH ROW
    EXECUTE FUNCTION pggit.update_audit_duration();

-- Helper function for audit logging
CREATE OR REPLACE FUNCTION pggit.audit_operation(
    p_operation_name TEXT,
    p_operation_type TEXT,
    p_parameters JSONB DEFAULT NULL,
    p_affected_resources JSONB DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_audit_id BIGINT;
BEGIN
    INSERT INTO pggit.operation_audit (
        operation_name,
        operation_type,
        parameters,
        affected_resources
    ) VALUES (
        p_operation_name,
        p_operation_type,
        p_parameters,
        p_affected_resources
    ) RETURNING audit_id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function to complete audit logging
CREATE OR REPLACE FUNCTION pggit.complete_audit(
    p_audit_id BIGINT,
    p_success BOOLEAN,
    p_error_code TEXT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_rows_affected INTEGER DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE pggit.operation_audit
    SET completed_at = clock_timestamp(),
        success = p_success,
        error_code = p_error_code,
        error_message = p_error_message,
        rows_affected = p_rows_affected
    WHERE audit_id = p_audit_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function for audited operations with error handling
CREATE OR REPLACE FUNCTION pggit.audited_operation(
    p_operation_name TEXT,
    p_operation_type TEXT,
    p_parameters JSONB DEFAULT NULL,
    p_operation_sql TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_audit_id BIGINT;
    v_result JSONB;
    v_rows_affected INTEGER := 0;
BEGIN
    -- Start audit
    v_audit_id := pggit.audit_operation(p_operation_name, p_operation_type, p_parameters);

    BEGIN
        -- Execute operation
        EXECUTE p_operation_sql INTO v_result;

        -- Get affected rows if applicable
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

        -- Complete audit successfully
        PERFORM pggit.complete_audit(v_audit_id, true, NULL, NULL, v_rows_affected);

        RETURN jsonb_build_object(
            'success', true,
            'audit_id', v_audit_id,
            'result', v_result,
            'rows_affected', v_rows_affected
        );

    EXCEPTION WHEN OTHERS THEN
        -- Complete audit with failure
        PERFORM pggit.complete_audit(v_audit_id, false, SQLSTATE, SQLERRM, NULL);

        -- Re-raise the exception
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE pggit.operation_audit IS
'Comprehensive audit log for all pgGit operations with timing, success/failure tracking';

COMMENT ON FUNCTION pggit.audit_operation IS
'Start audit logging for an operation and return audit ID';

COMMENT ON FUNCTION pggit.complete_audit IS
'Complete audit logging with success/failure information';

COMMENT ON FUNCTION pggit.audited_operation IS
'Execute an operation with full audit logging and error handling';