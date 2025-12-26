-- ============================================================================
-- PHASE 6: Rollback & Undo API
-- ============================================================================
-- Provides comprehensive rollback, undo, and time-travel capabilities
-- Created: 2025-12-26
-- Status: Implementation Phase (Phase 6.1 Foundation)
-- ============================================================================

-- ============================================================================
-- TABLE 1: pggit.rollback_operations
-- Purpose: Complete audit trail of all rollback operations
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.rollback_operations (
    rollback_id BIGSERIAL PRIMARY KEY,
    source_commit_hash CHAR(64) NOT NULL,
    target_commit_hash CHAR(64),
    rollback_type TEXT NOT NULL CHECK (rollback_type IN ('SINGLE_COMMIT', 'RANGE', 'TO_TIMESTAMP', 'UNDO')),
    rollback_mode TEXT NOT NULL CHECK (rollback_mode IN ('DRY_RUN', 'VALIDATED', 'EXECUTED')),
    branch_id INTEGER NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    executed_at TIMESTAMP,
    status TEXT NOT NULL CHECK (status IN ('PENDING', 'IN_PROGRESS', 'SUCCESS', 'PARTIAL_SUCCESS', 'FAILED')),
    error_message TEXT,
    objects_affected INTEGER,
    dependencies_validated BOOLEAN DEFAULT FALSE,
    breaking_changes_count INTEGER DEFAULT 0,
    rollback_commit_hash CHAR(64),

    -- Foreign key constraints
    CONSTRAINT fk_rollback_operations_branch
        FOREIGN KEY (branch_id) REFERENCES pggit.branches(branch_id)
);

CREATE INDEX IF NOT EXISTS idx_rollback_operations_status
    ON pggit.rollback_operations(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rollback_operations_branch
    ON pggit.rollback_operations(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rollback_operations_source_commit
    ON pggit.rollback_operations(source_commit_hash);

-- ============================================================================
-- TABLE 2: pggit.rollback_validations
-- Purpose: Pre-flight validation check results for rollback operations
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.rollback_validations (
    validation_id BIGSERIAL PRIMARY KEY,
    rollback_id BIGINT NOT NULL,
    validation_type TEXT NOT NULL CHECK (validation_type IN (
        'COMMIT_EXISTENCE', 'DEPENDENCY_ANALYSIS', 'MERGE_CONFLICT',
        'ORDERING_CONSTRAINTS', 'REFERENTIAL_INTEGRITY', 'DATA_LOSS_PREVENTION'
    )),
    status TEXT NOT NULL CHECK (status IN ('PASS', 'WARN', 'FAIL')),
    severity TEXT NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    message TEXT NOT NULL,
    affected_objects TEXT[],
    recommendation TEXT,
    created_at TIMESTAMP DEFAULT NOW(),

    -- Foreign key constraints
    CONSTRAINT fk_rollback_validations_rollback
        FOREIGN KEY (rollback_id) REFERENCES pggit.rollback_operations(rollback_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rollback_validations_rollback
    ON pggit.rollback_validations(rollback_id, validation_type);
CREATE INDEX IF NOT EXISTS idx_rollback_validations_severity
    ON pggit.rollback_validations(severity);

-- ============================================================================
-- NOTE: pggit.object_dependencies table already exists from Phase 1
-- It has columns: dependency_id, dependent_object_id, depends_on_object_id,
-- dependency_type, branch_id, discovered_at_commit, metadata
--
-- For Phase 6, we use this existing table for rollback dependency analysis.
-- Mapping: dependent_object_id = source (object with dependency)
--          depends_on_object_id = target (object being depended on)
-- ============================================================================

-- ============================================================================
-- Function 1: pggit.validate_rollback()
-- Purpose: Pre-flight validation before any rollback operation (read-only)
-- Returns: Set of validation results with severity levels
-- Note: This is a pure read-only function for analysis purposes
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.validate_rollback(
    p_branch_name TEXT,
    p_source_commit_hash CHAR(64),
    p_target_commit_hash CHAR(64) DEFAULT NULL,
    p_rollback_type TEXT DEFAULT 'SINGLE_COMMIT'
) RETURNS TABLE (
    validation_type TEXT,
    status TEXT,
    severity TEXT,
    message TEXT,
    affected_objects TEXT[],
    recommendation TEXT
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_branch_id BIGINT;
    v_source_commit_id BIGINT;
    v_target_commit_id BIGINT;
    v_source_time TIMESTAMP;
    v_target_time TIMESTAMP;
    v_already_rolled_back BOOLEAN;
    v_is_merge_commit BOOLEAN;
    v_dependent_objects TEXT[];
    v_table_count INTEGER;
BEGIN
    -- Parameter validation
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
               'Branch name cannot be null or empty'::TEXT,
               ARRAY[]::TEXT[], 'Provide a valid branch name'::TEXT;
        RETURN;
    END IF;

    IF p_source_commit_hash IS NULL OR LENGTH(p_source_commit_hash) != 64 THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
               'Source commit hash must be 64 character hex string'::TEXT,
               ARRAY[]::TEXT[], 'Provide valid commit hash'::TEXT;
        RETURN;
    END IF;

    IF p_rollback_type NOT IN ('SINGLE_COMMIT', 'RANGE', 'TO_TIMESTAMP') THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
               'Invalid rollback_type: ' || p_rollback_type::TEXT,
               ARRAY[]::TEXT[], 'Use SINGLE_COMMIT, RANGE, or TO_TIMESTAMP'::TEXT;
        RETURN;
    END IF;

    -- VALIDATION 1: Verify branch exists
    SELECT b.branch_id INTO v_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = p_branch_name;

    IF v_branch_id IS NULL THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
               'Branch "' || p_branch_name || '" does not exist'::TEXT,
               ARRAY[]::TEXT[],
               'Use pggit.list_branches() to see available branches'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT 'COMMIT_EXISTENCE'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
           'Branch "' || p_branch_name || '" exists'::TEXT,
           ARRAY[]::TEXT[], NULL::TEXT;

    -- VALIDATION 2: Verify source commit exists on branch
    SELECT c.commit_id, c.author_time INTO v_source_commit_id, v_source_time
    FROM pggit.commits c
    WHERE c.branch_id = v_branch_id
      AND c.commit_hash = p_source_commit_hash;

    IF v_source_commit_id IS NULL THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
               'Commit ' || SUBSTRING(p_source_commit_hash, 1, 8) || '... does not exist on branch "' || p_branch_name || '"'::TEXT,
               ARRAY[]::TEXT[],
               'Use pggit.get_commit_history() to find valid commit hashes'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT 'COMMIT_EXISTENCE'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
           'Source commit ' || SUBSTRING(p_source_commit_hash, 1, 8) || '... found'::TEXT,
           ARRAY[]::TEXT[], NULL::TEXT;

    -- VALIDATION 3: Verify target commit (for range rollback)
    IF p_rollback_type = 'RANGE' THEN
        IF p_target_commit_hash IS NULL OR LENGTH(p_target_commit_hash) != 64 THEN
            RETURN QUERY
            SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
                   'Target commit hash required for RANGE rollback'::TEXT,
                   ARRAY[]::TEXT[],
                   'Provide p_target_commit_hash parameter'::TEXT;
            RETURN;
        END IF;

        SELECT c.commit_id, c.author_time INTO v_target_commit_id, v_target_time
        FROM pggit.commits c
        WHERE c.branch_id = v_branch_id
          AND c.commit_hash = p_target_commit_hash;

        IF v_target_commit_id IS NULL THEN
            RETURN QUERY
            SELECT 'COMMIT_EXISTENCE'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
                   'Target commit ' || SUBSTRING(p_target_commit_hash, 1, 8) || '... does not exist'::TEXT,
                   ARRAY[]::TEXT[],
                   'Use pggit.get_commit_history() to find valid hashes'::TEXT;
            RETURN;
        END IF;

        IF v_target_time <= v_source_time THEN
            RETURN QUERY
            SELECT 'ORDERING_CONSTRAINTS'::TEXT, 'FAIL'::TEXT, 'ERROR'::TEXT,
                   'Target commit must be after source commit in time'::TEXT,
                   ARRAY[]::TEXT[],
                   'Target: ' || v_target_time::TEXT || ', Source: ' || v_source_time::TEXT;
            RETURN;
        END IF;

        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
               'Target commit ' || SUBSTRING(p_target_commit_hash, 1, 8) || '... is valid'::TEXT,
               ARRAY[]::TEXT[], NULL::TEXT;
    END IF;

    -- VALIDATION 4: Check if commit was already rolled back
    SELECT EXISTS(
        SELECT 1 FROM pggit.rollback_operations
        WHERE source_commit_hash = p_source_commit_hash
          AND status = 'SUCCESS'
          AND branch_id = v_branch_id
    ) INTO v_already_rolled_back;

    IF v_already_rolled_back THEN
        RETURN QUERY
        SELECT 'COMMIT_EXISTENCE'::TEXT, 'WARN'::TEXT, 'WARNING'::TEXT,
               'Commit has already been rolled back once'::TEXT,
               ARRAY[]::TEXT[],
               'Consider undoing previous rollback instead'::TEXT;
    END IF;

    -- VALIDATION 5: Check for dependency issues
    WITH changed_objects AS (
        SELECT DISTINCT oh.object_id
        FROM pggit.object_history oh
        WHERE oh.commit_hash = p_source_commit_hash
          AND oh.branch_id = v_branch_id
    ),
    dependent_objects AS (
        SELECT DISTINCT od.dependent_object_id, so.object_name, so.schema_name
        FROM pggit.object_dependencies od
        JOIN changed_objects co ON od.depends_on_object_id = co.object_id
        JOIN pggit.schema_objects so ON od.dependent_object_id = so.object_id
        WHERE od.dependency_type IN ('FOREIGN_KEY', 'TRIGGERS_ON', 'INDEXES')
    )
    SELECT ARRAY_AGG(schema_name || '.' || object_name)
    INTO v_dependent_objects
    FROM dependent_objects;

    IF v_dependent_objects IS NOT NULL AND ARRAY_LENGTH(v_dependent_objects, 1) > 0 THEN
        RETURN QUERY
        SELECT 'DEPENDENCY_ANALYSIS'::TEXT, 'WARN'::TEXT, 'WARNING'::TEXT,
               'Found ' || ARRAY_LENGTH(v_dependent_objects, 1) || ' object(s) with dependencies on rolled-back objects'::TEXT,
               v_dependent_objects,
               'These objects would be affected: ' || ARRAY_TO_STRING(v_dependent_objects, ', ')::TEXT;
    ELSE
        RETURN QUERY
        SELECT 'DEPENDENCY_ANALYSIS'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
               'No significant dependencies on rolled-back objects'::TEXT,
               ARRAY[]::TEXT[], NULL::TEXT;
    END IF;

    -- VALIDATION 6: Check if commit is a merge commit
    SELECT EXISTS(
        SELECT 1 FROM pggit.merge_operations mo
        WHERE mo.target_commit_hash = p_source_commit_hash
    ) INTO v_is_merge_commit;

    IF v_is_merge_commit THEN
        RETURN QUERY
        SELECT 'MERGE_CONFLICT'::TEXT, 'WARN'::TEXT, 'WARNING'::TEXT,
               'Commit is a merge commit - rolling back may affect multiple branches'::TEXT,
               ARRAY[]::TEXT[],
               'Consider rolling back individual branch commits instead'::TEXT;
    ELSE
        RETURN QUERY
        SELECT 'MERGE_CONFLICT'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
               'Commit is not a merge - safe to rollback'::TEXT,
               ARRAY[]::TEXT[], NULL::TEXT;
    END IF;

    -- VALIDATION 7: Data loss prevention check
    WITH created_tables AS (
        SELECT COUNT(*) as cnt
        FROM pggit.object_history oh
        JOIN pggit.schema_objects so ON oh.object_id = so.object_id
        WHERE oh.commit_hash = p_source_commit_hash
          AND oh.branch_id = v_branch_id
          AND oh.change_type = 'CREATE'
          AND so.object_type = 'TABLE'
    )
    SELECT cnt INTO v_table_count FROM created_tables;

    IF v_table_count > 0 THEN
        RETURN QUERY
        SELECT 'DATA_LOSS_PREVENTION'::TEXT, 'WARN'::TEXT, 'WARNING'::TEXT,
               'Rollback would drop ' || v_table_count || ' table(s) - potential data loss'::TEXT,
               ARRAY[]::TEXT[],
               'Verify no important data in these tables before proceeding'::TEXT;
    ELSE
        RETURN QUERY
        SELECT 'DATA_LOSS_PREVENTION'::TEXT, 'PASS'::TEXT, 'INFO'::TEXT,
               'No data loss risk detected'::TEXT,
               ARRAY[]::TEXT[], NULL::TEXT;
    END IF;

END;
$$;

-- ============================================================================
-- COMMENT: validate_rollback() completion
-- ============================================================================
-- Function validates 7 key aspects:
-- 1. Branch exists
-- 2. Source commit exists on branch
-- 3. Target commit exists (for RANGE rollback)
-- 4. Commit not already rolled back
-- 5. No hard dependencies would break
-- 6. Handles merge commits explicitly
-- 7. Data loss prevention checks
--
-- This is a pure read-only function that returns validation result set.
-- Status: PASS = OK, WARN = proceed with caution, FAIL = cannot proceed
-- Severity: INFO < WARNING < ERROR < CRITICAL
-- ============================================================================

