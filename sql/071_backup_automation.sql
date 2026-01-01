-- =====================================================
-- pgGit Backup Integration - Phase 2: Automation
-- =====================================================
--
-- This module provides automated backup execution via a reliable
-- job queue system. External backup listener service polls the
-- job queue and executes backups using the appropriate tools.
--
-- Features:
-- - Persistent job queue (survives restarts)
-- - Retry logic with exponential backoff
-- - Job status tracking
-- - Support for pgBackRest, Barman, and pg_dump
-- - Command generation for each backup tool
-- - Metadata parsing and update callbacks
--
-- Architecture:
-- 1. User calls backup function (e.g., backup_pgbackrest())
-- 2. Function creates backup record and job queue entry
-- 3. External listener polls queue and executes jobs
-- 4. Listener updates job status and backup metadata
--
-- =====================================================

-- =====================================================
-- Job Queue Schema
-- =====================================================

-- Backup job queue for reliable execution
CREATE TABLE IF NOT EXISTS pggit.backup_jobs (
    job_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,

    -- Job details
    job_type TEXT NOT NULL CHECK (job_type IN ('backup', 'verify', 'cleanup')),
    command TEXT NOT NULL,
    tool TEXT NOT NULL,

    -- Status tracking
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cancelled')),

    -- Retry logic
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 3,
    next_retry_at TIMESTAMPTZ,
    last_error TEXT,

    -- Timing
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Constraints
    CONSTRAINT valid_retry CHECK (
        (status = 'failed' AND next_retry_at IS NOT NULL AND attempts < max_attempts) OR
        (status != 'failed' OR attempts >= max_attempts)
    )
);

COMMENT ON TABLE pggit.backup_jobs IS 'Persistent job queue for backup execution with retry logic';

-- Indexes for job processing
CREATE INDEX IF NOT EXISTS idx_backup_jobs_status ON pggit.backup_jobs(status, next_retry_at) WHERE status IN ('queued', 'failed');
CREATE INDEX IF NOT EXISTS idx_backup_jobs_backup ON pggit.backup_jobs(backup_id);
CREATE INDEX IF NOT EXISTS idx_backup_jobs_created ON pggit.backup_jobs(created_at DESC);

-- =====================================================
-- Job Queue Functions
-- =====================================================

-- Enqueue a backup job
CREATE OR REPLACE FUNCTION pggit.enqueue_backup_job(
    p_backup_id UUID,
    p_command TEXT,
    p_tool TEXT,
    p_max_attempts INTEGER DEFAULT 3,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_job_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO pggit.backup_jobs (
        job_id,
        backup_id,
        job_type,
        command,
        tool,
        max_attempts,
        metadata,
        next_retry_at
    ) VALUES (
        v_job_id,
        p_backup_id,
        'backup',
        p_command,
        p_tool,
        p_max_attempts,
        p_metadata,
        CURRENT_TIMESTAMP  -- Available immediately
    );

    RAISE NOTICE 'Enqueued backup job % for backup %', v_job_id, p_backup_id;

    RETURN v_job_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.enqueue_backup_job IS 'Enqueue a backup job for execution by the backup listener';

-- Get next job to process (called by listener)
CREATE OR REPLACE FUNCTION pggit.get_next_backup_job(
    p_worker_id TEXT DEFAULT 'default-worker'
) RETURNS TABLE (
    job_id UUID,
    backup_id UUID,
    command TEXT,
    tool TEXT,
    attempts INTEGER,
    metadata JSONB
) AS $$
DECLARE
    v_job_id UUID;
BEGIN
    -- Find next available job and lock it
    SELECT j.job_id INTO v_job_id
    FROM pggit.backup_jobs j
    WHERE j.status IN ('queued', 'failed')
      AND (j.next_retry_at IS NULL OR j.next_retry_at <= CURRENT_TIMESTAMP)
      AND j.attempts < j.max_attempts
    ORDER BY
        CASE WHEN j.status = 'queued' THEN 0 ELSE 1 END,  -- Queued jobs first
        j.created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_job_id IS NULL THEN
        -- No jobs available
        RETURN;
    END IF;

    -- Mark as running
    UPDATE pggit.backup_jobs j
    SET status = 'running',
        started_at = CURRENT_TIMESTAMP,
        attempts = j.attempts + 1,
        metadata = j.metadata || jsonb_build_object('worker_id', p_worker_id)
    WHERE j.job_id = v_job_id;

    -- Return job details
    RETURN QUERY
    SELECT
        j.job_id,
        j.backup_id,
        j.command,
        j.tool,
        j.attempts,
        j.metadata
    FROM pggit.backup_jobs j
    WHERE j.job_id = v_job_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_next_backup_job IS 'Get next job to process (used by backup listener service)';

-- Mark job as completed
CREATE OR REPLACE FUNCTION pggit.complete_backup_job(
    p_job_id UUID,
    p_output TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backup_jobs
    SET status = 'completed',
        completed_at = CURRENT_TIMESTAMP,
        metadata = metadata || jsonb_build_object(
            'output', p_output,
            'completed_by', current_setting('application_name', true)
        )
    WHERE job_id = p_job_id
      AND status = 'running';

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.complete_backup_job IS 'Mark a backup job as completed';

-- Mark job as failed with retry logic
CREATE OR REPLACE FUNCTION pggit.fail_backup_job(
    p_job_id UUID,
    p_error TEXT,
    p_retry_delay_seconds INTEGER DEFAULT 300  -- 5 minutes
) RETURNS BOOLEAN AS $$
DECLARE
    v_attempts INTEGER;
    v_max_attempts INTEGER;
BEGIN
    -- Get current attempt count
    SELECT attempts, max_attempts INTO v_attempts, v_max_attempts
    FROM pggit.backup_jobs
    WHERE job_id = p_job_id;

    IF v_attempts < v_max_attempts THEN
        -- Schedule retry with exponential backoff
        UPDATE pggit.backup_jobs
        SET status = 'failed',
            last_error = p_error,
            next_retry_at = CURRENT_TIMESTAMP + (p_retry_delay_seconds * POWER(2, attempts - 1) || ' seconds')::INTERVAL,
            metadata = metadata || jsonb_build_object(
                'last_failure_at', CURRENT_TIMESTAMP,
                'failure_reason', p_error
            )
        WHERE job_id = p_job_id
          AND status = 'running';
    ELSE
        -- Max retries exceeded, permanently failed
        UPDATE pggit.backup_jobs
        SET status = 'failed',
            completed_at = CURRENT_TIMESTAMP,
            last_error = p_error,
            metadata = metadata || jsonb_build_object(
                'permanently_failed', true,
                'final_error', p_error
            )
        WHERE job_id = p_job_id
          AND status = 'running';

        -- Also mark the backup as failed
        UPDATE pggit.backups
        SET status = 'failed',
            error_message = 'Job failed after ' || v_max_attempts || ' attempts: ' || p_error
        WHERE backup_id = (SELECT backup_id FROM pggit.backup_jobs WHERE job_id = p_job_id);
    END IF;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.fail_backup_job IS 'Mark a job as failed with automatic retry scheduling';

-- =====================================================
-- pgBackRest Integration
-- =====================================================

-- Trigger pgBackRest backup
CREATE OR REPLACE FUNCTION pggit.backup_pgbackrest(
    p_backup_type TEXT DEFAULT 'full',  -- 'full', 'incr', 'diff'
    p_branch_name TEXT DEFAULT 'main',
    p_stanza TEXT DEFAULT 'main',
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_job_id UUID;
    v_backup_name TEXT;
    v_command TEXT;
    v_commit_hash TEXT;
BEGIN
    -- Generate backup name
    v_backup_name := format('pgbackrest-%s-%s', p_backup_type,
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    -- Get commit hash from branch
    SELECT head_commit_hash INTO v_commit_hash
    FROM pggit.branches
    WHERE name = p_branch_name;

    IF v_commit_hash IS NULL THEN
        RAISE EXCEPTION 'Branch % not found or has no commits', p_branch_name;
    END IF;

    -- Register backup (will be in 'in_progress' state)
    v_backup_id := pggit.register_backup(
        v_backup_name,
        CASE p_backup_type
            WHEN 'full' THEN 'full'
            WHEN 'incr' THEN 'incremental'
            WHEN 'diff' THEN 'differential'
        END,
        'pgbackrest',
        format('pgbackrest://%s/%s', p_stanza, v_backup_name),
        v_commit_hash,
        NULL,
        FALSE,  -- No temporal snapshot for automated backups
        p_options || jsonb_build_object('stanza', p_stanza)
    );

    -- Build pgBackRest command
    v_command := format('pgbackrest --stanza=%s --type=%s backup',
                       p_stanza,
                       p_backup_type);

    -- Add any additional options
    IF p_options ? 'repo' THEN
        v_command := v_command || ' --repo=' || (p_options->>'repo');
    END IF;

    -- Enqueue job
    v_job_id := pggit.enqueue_backup_job(
        v_backup_id,
        v_command,
        'pgbackrest',
        3,  -- max attempts
        jsonb_build_object(
            'backup_type', p_backup_type,
            'stanza', p_stanza,
            'branch', p_branch_name
        )
    );

    RAISE NOTICE 'Created pgBackRest backup job % for backup %', v_job_id, v_backup_id;
    RAISE NOTICE 'Command: %', v_command;

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.backup_pgbackrest IS 'Schedule an automated pgBackRest backup';

-- Parse pgBackRest info output and update metadata
CREATE OR REPLACE FUNCTION pggit.update_pgbackrest_metadata(
    p_backup_id UUID,
    p_info_json JSONB
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backups
    SET metadata = metadata || jsonb_build_object(
        'pgbackrest_info', p_info_json,
        'database_size', (p_info_json->'database'->>'size')::BIGINT,
        'backup_reference', p_info_json->>'reference',
        'checksum', p_info_json->>'checksum'
    ),
    backup_size = COALESCE((p_info_json->'database'->>'size')::BIGINT, backup_size),
    compressed_size = COALESCE((p_info_json->'repo'->>'size')::BIGINT, compressed_size)
    WHERE backup_id = p_backup_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.update_pgbackrest_metadata IS 'Update backup metadata from pgBackRest info output';

-- =====================================================
-- Barman Integration
-- =====================================================

-- Trigger Barman backup
CREATE OR REPLACE FUNCTION pggit.backup_barman(
    p_server_name TEXT,
    p_branch_name TEXT DEFAULT 'main',
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_job_id UUID;
    v_backup_name TEXT;
    v_command TEXT;
    v_commit_hash TEXT;
BEGIN
    v_backup_name := format('barman-%s-%s', p_server_name,
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    -- Get commit hash
    SELECT head_commit_hash INTO v_commit_hash
    FROM pggit.branches
    WHERE name = p_branch_name;

    IF v_commit_hash IS NULL THEN
        RAISE EXCEPTION 'Branch % not found or has no commits', p_branch_name;
    END IF;

    -- Register backup
    v_backup_id := pggit.register_backup(
        v_backup_name,
        'full',
        'barman',
        format('barman://%s/latest', p_server_name),
        v_commit_hash,
        NULL,
        FALSE,
        p_options || jsonb_build_object('server', p_server_name)
    );

    -- Build Barman command
    v_command := format('barman backup %s', p_server_name);

    -- Add options
    IF p_options ? 'wait' AND (p_options->>'wait')::boolean THEN
        v_command := v_command || ' --wait';
    END IF;

    -- Enqueue job
    v_job_id := pggit.enqueue_backup_job(
        v_backup_id,
        v_command,
        'barman',
        3,
        jsonb_build_object(
            'server', p_server_name,
            'branch', p_branch_name
        )
    );

    RAISE NOTICE 'Created Barman backup job % for backup %', v_job_id, v_backup_id;

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.backup_barman IS 'Schedule an automated Barman backup';

-- =====================================================
-- pg_dump Integration
-- =====================================================

-- Trigger pg_dump backup
CREATE OR REPLACE FUNCTION pggit.backup_pg_dump(
    p_branch_name TEXT DEFAULT 'main',
    p_schema TEXT DEFAULT NULL,
    p_format TEXT DEFAULT 'custom',  -- 'custom', 'tar', 'plain'
    p_output_path TEXT DEFAULT '/backups',
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_job_id UUID;
    v_backup_name TEXT;
    v_command TEXT;
    v_commit_hash TEXT;
    v_filename TEXT;
    v_location TEXT;
BEGIN
    v_backup_name := format('pg_dump-%s-%s',
                           COALESCE(p_schema, 'all'),
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    v_filename := format('%s.dump', v_backup_name);
    v_location := format('file://%s/%s', p_output_path, v_filename);

    -- Get commit hash
    SELECT head_commit_hash INTO v_commit_hash
    FROM pggit.branches
    WHERE name = p_branch_name;

    IF v_commit_hash IS NULL THEN
        RAISE EXCEPTION 'Branch % not found or has no commits', p_branch_name;
    END IF;

    -- Register backup
    v_backup_id := pggit.register_backup(
        v_backup_name,
        'snapshot',
        'pg_dump',
        v_location,
        v_commit_hash,
        NULL,
        FALSE,
        p_options || jsonb_build_object(
            'format', p_format,
            'schema', p_schema
        )
    );

    -- Build pg_dump command
    v_command := format('pg_dump --format=%s --file=%s/%s',
                       CASE p_format
                           WHEN 'custom' THEN 'c'
                           WHEN 'tar' THEN 't'
                           WHEN 'plain' THEN 'p'
                       END,
                       p_output_path,
                       v_filename);

    -- Add schema filter if specified
    IF p_schema IS NOT NULL THEN
        v_command := v_command || format(' --schema=%s', p_schema);
    END IF;

    -- Add compression for custom format
    IF p_format = 'custom' AND p_options ? 'compression_level' THEN
        v_command := v_command || format(' --compress=%s', p_options->>'compression_level');
    END IF;

    -- Add database name (from connection)
    v_command := v_command || ' $PGDATABASE';

    -- Enqueue job
    v_job_id := pggit.enqueue_backup_job(
        v_backup_id,
        v_command,
        'pg_dump',
        3,
        jsonb_build_object(
            'format', p_format,
            'schema', p_schema,
            'output_path', p_output_path,
            'branch', p_branch_name
        )
    );

    RAISE NOTICE 'Created pg_dump backup job % for backup %', v_job_id, v_backup_id;

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.backup_pg_dump IS 'Schedule an automated pg_dump backup';

-- =====================================================
-- Job Monitoring Views
-- =====================================================

-- View of current job queue status
CREATE OR REPLACE VIEW pggit.backup_job_queue AS
SELECT
    j.job_id,
    j.backup_id,
    b.backup_name,
    j.tool,
    j.status,
    j.attempts,
    j.max_attempts,
    j.next_retry_at,
    j.last_error,
    j.created_at,
    j.started_at,
    j.completed_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - j.created_at)) AS age_seconds,
    CASE
        WHEN j.status = 'queued' THEN 'ready'
        WHEN j.status = 'running' THEN 'in_progress'
        WHEN j.status = 'failed' AND j.attempts < j.max_attempts THEN 'will_retry'
        WHEN j.status = 'failed' AND j.attempts >= j.max_attempts THEN 'permanently_failed'
        WHEN j.status = 'completed' THEN 'done'
        ELSE j.status
    END AS job_state
FROM pggit.backup_jobs j
LEFT JOIN pggit.backups b ON j.backup_id = b.backup_id
ORDER BY
    CASE j.status
        WHEN 'running' THEN 0
        WHEN 'queued' THEN 1
        WHEN 'failed' THEN 2
        WHEN 'completed' THEN 3
        ELSE 4
    END,
    j.created_at DESC;

COMMENT ON VIEW pggit.backup_job_queue IS 'Current status of all backup jobs in the queue';

-- =====================================================
-- Grants
-- =====================================================

GRANT SELECT, INSERT, UPDATE ON pggit.backup_jobs TO PUBLIC;
GRANT SELECT ON pggit.backup_job_queue TO PUBLIC;

GRANT EXECUTE ON FUNCTION pggit.enqueue_backup_job TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_next_backup_job TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.complete_backup_job TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.fail_backup_job TO PUBLIC;

GRANT EXECUTE ON FUNCTION pggit.backup_pgbackrest TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.backup_barman TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.backup_pg_dump TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.update_pgbackrest_metadata TO PUBLIC;
