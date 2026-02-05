-- =====================================================
-- pgGit Backup Integration - Phase 1: Metadata Tracking
-- =====================================================
--
-- This module provides Git-like tracking of database backups.
-- Phase 1 focuses on metadata tracking only - users manually
-- create backups using external tools, then register them here.
--
-- Features:
-- - Link backups to specific commits
-- - Track backup metadata (size, location, tool, status)
-- - Query backups by commit or branch
-- - Backup coverage analysis
-- - Backup dependency tracking (for incremental backups)
-- - Backup verification records
--
-- Phase 2 (future): Automated backup execution
-- Phase 3 (future): Recovery workflows
-- =====================================================

-- =====================================================
-- Schema: Backup Metadata Tables
-- =====================================================

-- Main backups table
-- NOTE: Backups are database-wide snapshots linked to commits, not branches
CREATE TABLE IF NOT EXISTS pggit.backups (
    backup_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    backup_name TEXT NOT NULL,
    backup_type TEXT NOT NULL CHECK (backup_type IN ('full', 'incremental', 'differential', 'snapshot')),
    backup_tool TEXT NOT NULL CHECK (backup_tool IN ('pgbackrest', 'barman', 'pg_dump', 'pg_basebackup', 'custom')),

    -- Git integration: Link to commit (primary) and optional snapshot
    commit_hash TEXT REFERENCES pggit.commits(hash),
    snapshot_id UUID REFERENCES pggit.temporal_snapshots(snapshot_id),

    -- Backup details
    backup_size BIGINT,  -- bytes
    compressed_size BIGINT,  -- bytes
    location TEXT NOT NULL,  -- URI: s3://bucket/path, file:///path, barman://server/backup

    -- Metadata
    metadata JSONB DEFAULT '{}',  -- Tool-specific metadata
    compression TEXT,  -- 'gzip', 'lz4', 'zstd', 'none'
    encryption BOOLEAN DEFAULT false,

    -- Status tracking
    status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed', 'expired', 'deleted')),
    error_message TEXT,

    -- Timestamps
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,  -- For backup retention policies

    -- Audit
    created_by TEXT DEFAULT CURRENT_USER,

    -- Constraints
    CONSTRAINT valid_completion CHECK (
        (status = 'completed' AND completed_at IS NOT NULL) OR
        (status != 'completed')
    ),
    CONSTRAINT valid_commit CHECK (
        commit_hash IS NOT NULL OR status = 'in_progress'
    )
);

COMMENT ON TABLE pggit.backups IS 'Tracks database backups linked to Git commits';
COMMENT ON COLUMN pggit.backups.commit_hash IS 'The commit hash representing the database state captured in this backup';
COMMENT ON COLUMN pggit.backups.snapshot_id IS 'Optional temporal snapshot for point-in-time queries';

-- Backup dependencies (for incremental/differential backups)
CREATE TABLE IF NOT EXISTS pggit.backup_dependencies (
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    depends_on_backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE RESTRICT,
    dependency_type TEXT NOT NULL CHECK (dependency_type IN ('base', 'incremental_chain', 'differential_base')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (backup_id, depends_on_backup_id)
);

COMMENT ON TABLE pggit.backup_dependencies IS 'Tracks dependencies between incremental and full backups';

-- Backup verification records
CREATE TABLE IF NOT EXISTS pggit.backup_verifications (
    verification_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    verification_type TEXT NOT NULL CHECK (verification_type IN ('checksum', 'restore_test', 'integrity_check')),
    status TEXT NOT NULL CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'queued')),
    details JSONB DEFAULT '{}',
    verified_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    verified_by TEXT DEFAULT CURRENT_USER
);

COMMENT ON TABLE pggit.backup_verifications IS 'Records of backup verification attempts';

-- Backup tags (for organization)
CREATE TABLE IF NOT EXISTS pggit.backup_tags (
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    tag_name TEXT NOT NULL,
    tag_value TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (backup_id, tag_name)
);

COMMENT ON TABLE pggit.backup_tags IS 'Custom tags for organizing backups';

-- =====================================================
-- Indexes
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_backups_commit ON pggit.backups(commit_hash, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_backups_status ON pggit.backups(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_backups_tool ON pggit.backups(backup_tool, backup_type);
CREATE INDEX IF NOT EXISTS idx_backups_location ON pggit.backups(location);
CREATE INDEX IF NOT EXISTS idx_backups_expires ON pggit.backups(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_backup_tags_name ON pggit.backup_tags(tag_name, tag_value);

-- =====================================================
-- Core Functions: Backup Registration
-- =====================================================

-- Register a backup that was created externally
-- Phase 1: Users run backup tools manually, then register the backup metadata
CREATE OR REPLACE FUNCTION pggit.register_backup(
    p_backup_name TEXT,
    p_backup_type TEXT,
    p_backup_tool TEXT,
    p_location TEXT,
    p_commit_hash TEXT DEFAULT NULL,  -- Explicit commit hash, or detect from current branch
    p_branch_name TEXT DEFAULT NULL,  -- Used to detect commit if p_commit_hash is NULL
    p_create_snapshot BOOLEAN DEFAULT FALSE,  -- Optional: create temporal snapshot
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID := gen_random_uuid();
    v_commit_hash TEXT;
    v_snapshot_id UUID := NULL;
    v_branch_id INTEGER;
BEGIN
    -- Determine commit hash
    IF p_commit_hash IS NOT NULL THEN
        -- Explicit commit provided
        v_commit_hash := p_commit_hash;

        -- Validate commit exists
        IF NOT EXISTS (SELECT 1 FROM pggit.commits WHERE hash = v_commit_hash) THEN
            RAISE EXCEPTION 'Commit % not found', v_commit_hash;
        END IF;
    ELSIF p_branch_name IS NOT NULL THEN
        -- Get HEAD commit from branch
        SELECT head_commit_hash INTO v_commit_hash
        FROM pggit.branches
        WHERE name = p_branch_name;

        IF v_commit_hash IS NULL THEN
            RAISE EXCEPTION 'Branch % not found or has no commits', p_branch_name;
        END IF;
    ELSE
        -- Use current branch's HEAD (try current_setting first)
        BEGIN
            SELECT head_commit_hash INTO v_commit_hash
            FROM pggit.branches
            WHERE name = current_setting('pggit.current_branch', TRUE);
        EXCEPTION
            WHEN OTHERS THEN
                v_commit_hash := NULL;
        END;

        IF v_commit_hash IS NULL THEN
            -- Fallback to main branch
            SELECT head_commit_hash INTO v_commit_hash
            FROM pggit.branches
            WHERE name = 'main';

            IF v_commit_hash IS NULL THEN
                RAISE EXCEPTION 'Cannot determine commit hash: no branch specified and main branch not found';
            END IF;
        END IF;
    END IF;

    -- Create temporal snapshot if requested (optional, has performance cost)
    IF p_create_snapshot THEN
        -- Get branch_id for snapshot creation
        SELECT id INTO v_branch_id
        FROM pggit.branches
        WHERE head_commit_hash = v_commit_hash
        LIMIT 1;

        IF v_branch_id IS NOT NULL THEN
            SELECT snapshot_id INTO v_snapshot_id
            FROM pggit.create_temporal_snapshot(
                p_backup_name || '_snapshot',
                v_branch_id,
                'Snapshot created for backup ' || p_backup_name
            );
        END IF;
    END IF;

    -- Register backup metadata
    INSERT INTO pggit.backups (
        backup_id,
        backup_name,
        backup_type,
        backup_tool,
        commit_hash,
        snapshot_id,
        location,
        metadata
    ) VALUES (
        v_backup_id,
        p_backup_name,
        p_backup_type,
        p_backup_tool,
        v_commit_hash,
        v_snapshot_id,
        p_location,
        p_metadata
    );

    RAISE NOTICE 'Registered backup % for commit %', p_backup_name, v_commit_hash;

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.register_backup IS 'Register a manually-created backup with pgGit metadata tracking';

-- Mark backup as completed
CREATE OR REPLACE FUNCTION pggit.complete_backup(
    p_backup_id UUID,
    p_backup_size BIGINT DEFAULT NULL,
    p_compressed_size BIGINT DEFAULT NULL,
    p_compression TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backups
    SET status = 'completed',
        completed_at = CURRENT_TIMESTAMP,
        backup_size = COALESCE(p_backup_size, backup_size),
        compressed_size = COALESCE(p_compressed_size, compressed_size),
        compression = COALESCE(p_compression, compression)
    WHERE backup_id = p_backup_id
      AND status = 'in_progress';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup % not found or not in progress', p_backup_id;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.complete_backup IS 'Mark a backup as successfully completed';

-- Mark backup as failed
CREATE OR REPLACE FUNCTION pggit.fail_backup(
    p_backup_id UUID,
    p_error_message TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backups
    SET status = 'failed',
        error_message = p_error_message,
        completed_at = CURRENT_TIMESTAMP
    WHERE backup_id = p_backup_id
      AND status = 'in_progress';

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.fail_backup IS 'Mark a backup as failed with an error message';

-- =====================================================
-- Core Functions: Backup Queries
-- =====================================================

-- List backups, optionally filtered by branch or commit
CREATE OR REPLACE FUNCTION pggit.list_backups(
    p_branch_name TEXT DEFAULT NULL,
    p_commit_hash TEXT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
    backup_id UUID,
    backup_name TEXT,
    backup_type TEXT,
    backup_tool TEXT,
    commit_hash TEXT,
    status TEXT,
    backup_size BIGINT,
    location TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
) AS $$
DECLARE
    v_commit_hash TEXT;
BEGIN
    -- If branch name provided, get its HEAD commit
    IF p_branch_name IS NOT NULL THEN
        SELECT head_commit_hash INTO v_commit_hash
        FROM pggit.branches
        WHERE name = p_branch_name;
    ELSE
        v_commit_hash := p_commit_hash;
    END IF;

    RETURN QUERY
    SELECT
        b.backup_id,
        b.backup_name,
        b.backup_type,
        b.backup_tool,
        b.commit_hash,
        b.status,
        b.backup_size,
        b.location,
        b.started_at,
        b.completed_at
    FROM pggit.backups b
    WHERE (v_commit_hash IS NULL OR b.commit_hash = v_commit_hash)
      AND (p_status IS NULL OR b.status = p_status)
    ORDER BY b.started_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.list_backups IS 'List backups filtered by branch, commit, or status';

-- Get backup details with related commits/branches
CREATE OR REPLACE FUNCTION pggit.get_backup_info(
    p_backup_id UUID
) RETURNS TABLE (
    backup_id UUID,
    backup_name TEXT,
    backup_type TEXT,
    backup_tool TEXT,
    commit_hash TEXT,
    commit_message TEXT,
    branches_at_commit TEXT[],
    status TEXT,
    backup_size BIGINT,
    compressed_size BIGINT,
    compression TEXT,
    location TEXT,
    metadata JSONB,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.backup_id,
        b.backup_name,
        b.backup_type,
        b.backup_tool,
        b.commit_hash,
        c.message AS commit_message,
        ARRAY(
            SELECT br.name
            FROM pggit.branches br
            WHERE br.head_commit_hash = b.commit_hash
        ) AS branches_at_commit,
        b.status,
        b.backup_size,
        b.compressed_size,
        b.compression,
        b.location,
        b.metadata,
        b.started_at,
        b.completed_at,
        b.expires_at
    FROM pggit.backups b
    LEFT JOIN pggit.commits c ON b.commit_hash = c.hash
    WHERE b.backup_id = p_backup_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_backup_info IS 'Get detailed information about a specific backup';

-- =====================================================
-- Views: Backup Coverage Analysis
-- =====================================================

-- Helper view: Which branches point to commits that have backups
CREATE OR REPLACE VIEW pggit.branch_backup_coverage AS
SELECT
    b.id AS branch_id,
    b.name AS branch_name,
    b.head_commit_hash,
    COUNT(bk.backup_id) AS backups_at_head,
    MAX(bk.completed_at) AS last_backup_at,
    COUNT(bk.backup_id) FILTER (WHERE bk.backup_type = 'full') AS full_backups_at_head,
    SUM(bk.backup_size) FILTER (WHERE bk.status = 'completed') AS total_backup_size
FROM pggit.branches b
LEFT JOIN pggit.backups bk ON b.head_commit_hash = bk.commit_hash
    AND bk.status = 'completed'
GROUP BY b.id, b.name, b.head_commit_hash
ORDER BY last_backup_at DESC NULLS LAST;

COMMENT ON VIEW pggit.branch_backup_coverage IS 'Shows backup coverage for each branch HEAD';

-- View showing backup coverage per commit
CREATE OR REPLACE VIEW pggit.commit_backup_coverage AS
SELECT
    c.hash AS commit_hash,
    c.message AS commit_message,
    c.committed_at,
    ARRAY_AGG(DISTINCT b.name) FILTER (WHERE b.name IS NOT NULL) AS branches,
    COUNT(bk.backup_id) AS total_backups,
    COUNT(bk.backup_id) FILTER (WHERE bk.status = 'completed') AS completed_backups,
    COUNT(bk.backup_id) FILTER (WHERE bk.backup_type = 'full') AS full_backups,
    MAX(bk.completed_at) FILTER (WHERE bk.status = 'completed') AS last_backup_at,
    SUM(bk.backup_size) FILTER (WHERE bk.status = 'completed') AS total_backup_size,
    -- Risk indicators
    CASE
        WHEN COUNT(bk.backup_id) FILTER (WHERE bk.status = 'completed') = 0 THEN 'no_backup'
        WHEN COUNT(bk.backup_id) FILTER (WHERE bk.backup_type = 'full' AND bk.status = 'completed') = 0 THEN 'no_full_backup'
        ELSE 'ok'
    END AS backup_status
FROM pggit.commits c
LEFT JOIN pggit.branches b ON b.head_commit_hash = c.hash
LEFT JOIN pggit.backups bk ON c.hash = bk.commit_hash
GROUP BY c.hash, c.message, c.committed_at
ORDER BY c.committed_at DESC;

COMMENT ON VIEW pggit.commit_backup_coverage IS 'Shows backup coverage analysis per commit with risk indicators';

-- =====================================================
-- Grants
-- =====================================================

-- Grant access to backup tables (assuming public schema access)
-- Note: In production, adjust these grants based on security requirements

GRANT SELECT, INSERT, UPDATE ON pggit.backups TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON pggit.backup_dependencies TO PUBLIC;
GRANT SELECT, INSERT ON pggit.backup_verifications TO PUBLIC;
GRANT SELECT, INSERT, DELETE ON pggit.backup_tags TO PUBLIC;

GRANT SELECT ON pggit.branch_backup_coverage TO PUBLIC;
GRANT SELECT ON pggit.commit_backup_coverage TO PUBLIC;

GRANT EXECUTE ON FUNCTION pggit.register_backup TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.complete_backup TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.fail_backup TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.list_backups TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_backup_info TO PUBLIC;
