-- pgGit Structured Error Codes
-- Phase 3: Reliability - Structured Error Codes
-- =====================================================

-- Create schema for error codes
CREATE SCHEMA IF NOT EXISTS pggit_errors;

-- Structured error codes table
CREATE TABLE pggit_errors.error_codes (
    error_code TEXT PRIMARY KEY,
    sqlstate TEXT NOT NULL,  -- PostgreSQL SQLSTATE
    severity TEXT NOT NULL CHECK (severity IN ('ERROR', 'WARNING', 'NOTICE')),
    description TEXT NOT NULL,
    recovery_hint TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Add helpful indexes
CREATE INDEX idx_error_codes_sqlstate ON pggit_errors.error_codes(sqlstate);
CREATE INDEX idx_error_codes_severity ON pggit_errors.error_codes(severity);

-- Insert standardized error codes for pgGit operations
INSERT INTO pggit_errors.error_codes (error_code, sqlstate, severity, description, recovery_hint) VALUES
    ('PGGIT_NULL_PARAM', '22004', 'ERROR', 'Required parameter is NULL', 'Provide a non-NULL value for the required parameter'),
    ('PGGIT_RANGE_ERROR', '22003', 'ERROR', 'Parameter value is out of valid range', 'Check parameter bounds in the function documentation'),
    ('PGGIT_INVALID_FORMAT', '22023', 'ERROR', 'Parameter has invalid format or structure', 'Verify parameter format matches expected schema'),
    ('PGGIT_NOT_FOUND', '02000', 'ERROR', 'Requested resource not found', 'Verify the ID exists and is correct'),
    ('PGGIT_ALREADY_EXISTS', '23505', 'ERROR', 'Resource already exists', 'Use UPDATE instead of INSERT, or check for duplicates'),
    ('PGGIT_LOCKED', '55P03', 'ERROR', 'Resource is locked by another transaction', 'Retry the operation after a brief delay'),
    ('PGGIT_DEPENDENCY', '23503', 'ERROR', 'Operation blocked by resource dependency', 'Remove or update dependent resources first'),
    ('PGGIT_CONCURRENT', '40001', 'WARNING', 'Operation already in progress', 'Wait for current operation to complete'),
    ('PGGIT_TRANSACTION_REQUIRED', '25P01', 'ERROR', 'Destructive operation requires explicit transaction', 'Wrap the call in BEGIN...COMMIT block'),
    ('PGGIT_IDEMPOTENT_SKIP', '00000', 'NOTICE', 'Operation skipped due to idempotency check', 'Operation was already completed, no action needed'),
    ('PGGIT_RETRY_EXHAUSTED', '57014', 'ERROR', 'Operation failed after maximum retry attempts', 'Check system health and retry manually if appropriate'),
    ('PGGIT_AUDIT_FAILURE', 'XX000', 'WARNING', 'Audit logging failed but operation succeeded', 'Check audit table permissions and space');

-- Add trigger for updated_at
CREATE OR REPLACE FUNCTION pggit_errors.update_error_codes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_error_codes_updated_at
    BEFORE UPDATE ON pggit_errors.error_codes
    FOR EACH ROW
    EXECUTE FUNCTION pggit_errors.update_error_codes_updated_at();

-- Helper function to raise structured errors
CREATE OR REPLACE FUNCTION pggit_errors.raise_error(
    p_error_code TEXT,
    p_detail TEXT DEFAULT NULL,
    p_hint TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_error_record RECORD;
    v_message TEXT;
BEGIN
    -- Get error definition
    SELECT * INTO v_error_record
    FROM pggit_errors.error_codes
    WHERE error_code = p_error_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown error code: %', p_error_code;
    END IF;

    -- Build message
    v_message := v_error_record.description;
    IF p_detail IS NOT NULL THEN
        v_message := v_message || ': ' || p_detail;
    END IF;

    -- Raise with structured information
    RAISE EXCEPTION '%', v_message
        USING ERRCODE = v_error_record.sqlstate,
              HINT = COALESCE(p_hint, v_error_record.recovery_hint);
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE pggit_errors.error_codes IS
'Standardized error codes for pgGit operations with consistent SQLSTATE mapping';

COMMENT ON FUNCTION pggit_errors.raise_error IS
'Helper function to raise structured errors using standardized error codes';