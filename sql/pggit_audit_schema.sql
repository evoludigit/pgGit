-- ============================================
-- pgGit Audit Layer: Compliance and Change Tracking
-- ============================================
-- Immutable audit trail for schema changes
-- Extracts DDL history from pggit_v2 commits

-- Drop existing schema if it exists
DROP SCHEMA IF EXISTS pggit_audit CASCADE;
CREATE SCHEMA pggit_audit;

-- ============================================
-- CORE AUDIT TABLES
-- ============================================

-- Table: changes
-- Tracks all DDL changes detected from pggit_v2 commits
CREATE TABLE pggit_audit.changes (
    change_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    commit_sha TEXT NOT NULL,           -- Links to pggit_v2.objects.sha
    object_schema TEXT NOT NULL,
    object_name TEXT NOT NULL,
    object_type TEXT NOT NULL,          -- TABLE, FUNCTION, VIEW, etc.
    change_type TEXT NOT NULL,          -- CREATE, ALTER, DROP
    old_definition TEXT,                -- NULL for CREATE
    new_definition TEXT,                -- NULL for DROP
    author TEXT,
    committed_at TIMESTAMP,
    commit_message TEXT,
    backfilled_from_v1 BOOLEAN DEFAULT FALSE,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table: object_versions
-- Complete version history for each object
CREATE TABLE pggit_audit.object_versions (
    version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_schema TEXT NOT NULL,
    object_name TEXT NOT NULL,
    version_number BIGINT NOT NULL,     -- Incremental version per object
    definition TEXT NOT NULL,
    commit_sha TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    UNIQUE(object_schema, object_name, version_number)
);

-- Table: compliance_log (immutable)
-- Audit trail for compliance verification activities
CREATE TABLE pggit_audit.compliance_log (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_id UUID NOT NULL REFERENCES pggit_audit.changes(change_id),
    verified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_by TEXT NOT NULL,
    verification_status TEXT NOT NULL,  -- 'PASSED', 'FAILED', 'PENDING'
    verification_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- IMMUTABILITY ENFORCEMENT
-- ============================================

-- Prevent updates/deletes on compliance_log (immutable)
CREATE OR REPLACE FUNCTION pggit_audit.prevent_compliance_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION 'Compliance log is immutable - cannot % %', TG_OP, TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to compliance_log
CREATE TRIGGER compliance_immutability
    BEFORE UPDATE OR DELETE ON pggit_audit.compliance_log
    FOR EACH ROW EXECUTE FUNCTION pggit_audit.prevent_compliance_modification();

-- ============================================
-- PERFORMANCE INDICES
-- ============================================

-- Indices for changes table
CREATE INDEX idx_changes_commit_sha ON pggit_audit.changes(commit_sha);
CREATE INDEX idx_changes_object ON pggit_audit.changes(object_schema, object_name);
CREATE INDEX idx_changes_time ON pggit_audit.changes(committed_at DESC);
CREATE INDEX idx_changes_type ON pggit_audit.changes(change_type);
CREATE INDEX idx_changes_verified ON pggit_audit.changes(verified) WHERE verified = false;

-- Indices for object_versions table
CREATE INDEX idx_versions_object ON pggit_audit.object_versions(object_schema, object_name);
CREATE INDEX idx_versions_commit ON pggit_audit.object_versions(commit_sha);
CREATE INDEX idx_versions_time ON pggit_audit.object_versions(created_at DESC);

-- Indices for compliance_log table
CREATE INDEX idx_compliance_change ON pggit_audit.compliance_log(change_id);
CREATE INDEX idx_compliance_status ON pggit_audit.compliance_log(verification_status);
CREATE INDEX idx_compliance_time ON pggit_audit.compliance_log(verified_at DESC);

-- ============================================
-- QUERY VIEWS
-- ============================================

-- View: Recent changes (last 30 days)
CREATE VIEW pggit_audit.recent_changes AS
SELECT * FROM pggit_audit.changes
WHERE committed_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
ORDER BY committed_at DESC;

-- View: Unverified changes
CREATE VIEW pggit_audit.unverified_changes AS
SELECT * FROM pggit_audit.changes
WHERE verified = false
ORDER BY committed_at DESC;

-- View: Object history
CREATE VIEW pggit_audit.object_history AS
SELECT
    ov.*,
    c.change_type,
    c.author,
    c.commit_message
FROM pggit_audit.object_versions ov
LEFT JOIN pggit_audit.changes c ON c.commit_sha = ov.commit_sha
    AND c.object_schema = ov.object_schema
    AND c.object_name = ov.object_name
ORDER BY ov.object_schema, ov.object_name, ov.version_number;

-- View: Compliance summary
CREATE VIEW pggit_audit.compliance_summary AS
SELECT
    DATE_TRUNC('day', verified_at) as verification_date,
    verification_status,
    COUNT(*) as count,
    STRING_AGG(DISTINCT verified_by, ', ') as verifiers
FROM pggit_audit.compliance_log
GROUP BY DATE_TRUNC('day', verified_at), verification_status
ORDER BY verification_date DESC;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function: Mark change as verified
CREATE OR REPLACE FUNCTION pggit_audit.verify_change(
    p_change_id UUID,
    p_verified_by TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    -- Mark change as verified
    UPDATE pggit_audit.changes
    SET verified = true
    WHERE change_id = p_change_id;

    -- Log compliance verification
    INSERT INTO pggit_audit.compliance_log (
        change_id, verified_by, verification_status, verification_notes
    ) VALUES (
        p_change_id, p_verified_by, 'PASSED', p_notes
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: Get current version of an object
CREATE OR REPLACE FUNCTION pggit_audit.get_current_version(
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TABLE (
    version_number BIGINT,
    definition TEXT,
    commit_sha TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ov.version_number,
        ov.definition,
        ov.commit_sha,
        ov.created_at
    FROM pggit_audit.object_versions ov
    WHERE ov.object_schema = p_schema_name
      AND ov.object_name = p_object_name
    ORDER BY ov.version_number DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function: Get change history for an object
CREATE OR REPLACE FUNCTION pggit_audit.get_object_changes(
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TABLE (
    change_type TEXT,
    old_definition TEXT,
    new_definition TEXT,
    author TEXT,
    committed_at TIMESTAMP,
    commit_message TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.change_type,
        c.old_definition,
        c.new_definition,
        c.author,
        c.committed_at,
        c.commit_message
    FROM pggit_audit.changes c
    WHERE c.object_schema = p_schema_name
      AND c.object_name = p_object_name
    ORDER BY c.committed_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PERMISSIONS
-- ============================================

-- Grant read access to audit data
GRANT USAGE ON SCHEMA pggit_audit TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA pggit_audit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit_audit TO PUBLIC;

-- Grant write access for compliance operations (restrict as needed)
GRANT INSERT ON pggit_audit.compliance_log TO PUBLIC;
GRANT UPDATE ON pggit_audit.changes TO PUBLIC;

-- ============================================
-- METADATA
-- ============================================

COMMENT ON SCHEMA pggit_audit IS 'Immutable audit trail extracted from pggit_v2 commits';
COMMENT ON TABLE pggit_audit.changes IS 'All DDL changes detected from pggit_v2 commits';
COMMENT ON TABLE pggit_audit.object_versions IS 'Complete version history for each database object';
COMMENT ON TABLE pggit_audit.compliance_log IS 'Immutable log of compliance verification activities';
COMMENT ON FUNCTION pggit_audit.verify_change IS 'Mark a change as verified and log compliance activity';

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit Audit Layer initialized successfully';
    RAISE NOTICE 'Schema: pggit_audit created with compliance tables';
    RAISE NOTICE 'Immutability: compliance_log cannot be modified';
    RAISE NOTICE 'Ready to extract DDL history from pggit_v2';
END $$;