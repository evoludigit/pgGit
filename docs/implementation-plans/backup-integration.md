# pgGit Backup Integration - Implementation Plan

## Executive Summary

**Goal**: Integrate backup tracking and management into pgGit without reimplementing existing backup tools.

**Strategy**: Provide Git-like tracking of backups, link backups to branches/commits, and integrate with industry-standard backup tools (pgBackRest, Barman, pg_dump).

**Scope**: Metadata tracking, integration hooks, verification, and recovery workflows. NOT building a new backup engine.

**Timeline**: 3 phases over 4-6 weeks
- Phase 1: Core metadata tracking (1 week) - READ-ONLY, manual backup registration
- Phase 2: Tool integration & automation (2-3 weeks) - Automated backup execution
- Phase 3: Recovery workflows (1-2 weeks) - Recovery planning and verification

---

## Problem Statement

### Current Gaps

1. **No Backup Visibility**: Users don't know which backups exist for which branches
2. **Backup-Commit Mismatch**: Hard to match backups to specific Git commits/branches
3. **Recovery Complexity**: Restoring to a specific commit requires manual coordination
4. **Tool Fragmentation**: Backup tools and version control operate independently

### User Scenarios

**Scenario 1: Developer wants to restore to commit ABC123**
- Current: Must find backup taken around that time, hope it matches
- Desired: `SELECT pggit.restore_from_commit('ABC123')` → automatic backup selection

**Scenario 2: DBA needs backup coverage report**
- Current: Check backup tool separately, correlate manually
- Desired: `SELECT * FROM pggit.backup_coverage` → see which branches lack backups

**Scenario 3: DevOps wants automated backup on merge**
- Current: Cron job with no Git awareness
- Desired: `CREATE TRIGGER backup_on_merge AFTER pggit.merge() ...`

---

## Architecture Overview

### Design Principles

1. **Integration over Implementation**: Use existing backup tools, don't replace them
2. **Git-Native**: Backups are first-class citizens in the Git model
3. **Tool-Agnostic**: Support multiple backup tools (pgBackRest, Barman, pg_dump, custom)
4. **Metadata-First**: Track backup metadata in Git history
5. **Zero-Downtime**: All operations compatible with live database

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     pgGit Backup Layer                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Metadata   │  │ Integration  │  │   Recovery   │      │
│  │   Tracking   │  │    Hooks     │  │   Workflows  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                   │             │
│         └──────────────────┴───────────────────┘             │
│                            │                                 │
└────────────────────────────┼─────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐         ┌─────▼─────┐       ┌─────▼─────┐
   │pgBackRest│        │  Barman   │       │  pg_dump  │
   └──────────┘        └───────────┘       └───────────┘
        │                    │                    │
        └────────────────────┴────────────────────┘
                             │
                    ┌────────▼─────────┐
                    │ Backup Storage   │
                    │ (S3/Local/NFS)   │
                    └──────────────────┘
```

---

## Phase 1: Core Metadata Tracking (1 week)

**Scope**: Read-only metadata tracking. Users manually register backups they create with external tools.

**Out of Scope**: Automated backup execution (moved to Phase 2).

### 1.1 Database Schema

```sql
-- =====================================================
-- Backup Metadata Schema
-- =====================================================

-- Main backups table
-- NOTE: Backups are database-wide snapshots linked to commits, not branches
CREATE TABLE pggit.backups (
    backup_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    backup_name TEXT NOT NULL,
    backup_type TEXT NOT NULL CHECK (backup_type IN ('full', 'incremental', 'differential', 'snapshot')),
    backup_tool TEXT NOT NULL CHECK (backup_tool IN ('pgbackrest', 'barman', 'pg_dump', 'pg_basebackup', 'custom')),

    -- Git integration: Link to commit (primary) and optional snapshot
    commit_hash TEXT REFERENCES pggit.commits(hash),  -- The database state captured by this backup
    snapshot_id UUID REFERENCES pggit.temporal_snapshots(snapshot_id),  -- Optional temporal snapshot

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

-- Backup dependencies (for incremental/differential backups)
CREATE TABLE pggit.backup_dependencies (
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    depends_on_backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE RESTRICT,
    dependency_type TEXT NOT NULL CHECK (dependency_type IN ('base', 'incremental_chain', 'differential_base')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (backup_id, depends_on_backup_id)
);

-- Backup verification records
CREATE TABLE pggit.backup_verifications (
    verification_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    verification_type TEXT NOT NULL CHECK (verification_type IN ('checksum', 'restore_test', 'integrity_check')),
    status TEXT NOT NULL CHECK (status IN ('passed', 'failed', 'warning')),
    details JSONB DEFAULT '{}',
    verified_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    verified_by TEXT DEFAULT CURRENT_USER
);

-- Backup tags (for organization)
CREATE TABLE pggit.backup_tags (
    backup_id UUID REFERENCES pggit.backups(backup_id) ON DELETE CASCADE,
    tag_name TEXT NOT NULL,
    tag_value TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (backup_id, tag_name)
);

-- Indexes
CREATE INDEX idx_backups_commit ON pggit.backups(commit_hash, started_at DESC);
CREATE INDEX idx_backups_status ON pggit.backups(status, started_at DESC);
CREATE INDEX idx_backups_tool ON pggit.backups(backup_tool, backup_type);
CREATE INDEX idx_backups_location ON pggit.backups(location);
CREATE INDEX idx_backups_expires ON pggit.backups(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX idx_backup_tags_name ON pggit.backup_tags(tag_name, tag_value);

-- Helper view: Which branches point to commits that have backups
CREATE OR REPLACE VIEW pggit.branch_backup_coverage AS
SELECT
    b.id AS branch_id,
    b.name AS branch_name,
    b.head_commit_hash,
    COUNT(bk.backup_id) AS backups_at_head,
    MAX(bk.completed_at) AS last_backup_at
FROM pggit.branches b
LEFT JOIN pggit.backups bk ON b.head_commit_hash = bk.commit_hash
    AND bk.status = 'completed'
GROUP BY b.id, b.name, b.head_commit_hash;
```

### 1.2 Core Functions

```sql
-- =====================================================
-- Backup Registration Functions (Phase 1: Manual Registration)
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
        -- Use current branch's HEAD
        SELECT head_commit_hash INTO v_commit_hash
        FROM pggit.branches
        WHERE name = current_setting('pggit.current_branch', TRUE);

        IF v_commit_hash IS NULL THEN
            -- Fallback to main branch
            SELECT head_commit_hash INTO v_commit_hash
            FROM pggit.branches
            WHERE name = 'main';
        END IF;
    END IF;

    -- Create temporal snapshot if requested (optional, has performance cost)
    IF p_create_snapshot THEN
        SELECT snapshot_id INTO v_snapshot_id
        FROM pggit.create_temporal_snapshot(
            p_backup_name || '_snapshot',
            (SELECT id FROM pggit.branches WHERE head_commit_hash = v_commit_hash LIMIT 1),
            'Snapshot created for backup ' || p_backup_name
        );
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
    branches_at_commit TEXT[],  -- All branches pointing to this commit
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
```

### 1.3 Backup Coverage Analysis

```sql
-- =====================================================
-- Backup Coverage Views
-- =====================================================

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
```

### 1.4 Test Suite

Create `tests/e2e/test_backup_tracking.py`:

```python
"""
Test suite for pgGit backup tracking functionality.
Tests metadata tracking, backup registration, and coverage analysis.
"""

import pytest


class TestBackupRegistration:
    """Test backup registration and lifecycle."""

    def test_register_backup_basic(self, db, pggit_installed):
        """Test basic backup registration."""
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-001',
                'full',
                'pgbackrest',
                's3://mybucket/backups/test-backup-001',
                'main',
                '{"server": "prod-01", "retention": "30d"}'::jsonb
            )
        """)

        assert backup_id is not None
        print(f"✓ Registered backup: {backup_id}")

    def test_complete_backup(self, db, pggit_installed):
        """Test marking backup as completed."""
        # Register
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-002', 'full', 'pgbackrest',
                's3://mybucket/backups/test-backup-002', 'main'
            )
        """)

        # Complete
        result = db.execute_returning("""
            SELECT pggit.complete_backup(
                %s::UUID, 1073741824, 536870912, 'gzip'
            )
        """, backup_id[0])

        assert result[0] is True

        # Verify status
        status = db.execute_returning("""
            SELECT status, backup_size, compressed_size
            FROM pggit.backups
            WHERE backup_id = %s::UUID
        """, backup_id[0])

        assert status[0] == 'completed'
        assert status[1] == 1073741824
        assert status[2] == 536870912
        print("✓ Backup marked as completed")

    def test_fail_backup(self, db, pggit_installed):
        """Test marking backup as failed."""
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'test-backup-003', 'full', 'pgbackrest',
                's3://mybucket/backups/test-backup-003'
            )
        """)

        result = db.execute_returning("""
            SELECT pggit.fail_backup(
                %s::UUID, 'Network timeout during upload'
            )
        """, backup_id[0])

        assert result[0] is True
        print("✓ Backup marked as failed")


class TestBackupQueries:
    """Test backup query functions."""

    def test_list_backups(self, db, pggit_installed):
        """Test listing backups."""
        # Create test backups
        for i in range(3):
            db.execute("""
                SELECT pggit.register_backup(
                    %s, 'full', 'pgbackrest',
                    %s, 'main'
                )
            """, f'list-test-{i}', f's3://bucket/backup-{i}')

        # List backups
        backups = db.execute("""
            SELECT backup_name, status FROM pggit.list_backups('main')
        """)

        assert len(backups) >= 3
        print(f"✓ Listed {len(backups)} backups")

    def test_get_backup_info(self, db, pggit_installed):
        """Test getting detailed backup info."""
        backup_id = db.execute_returning("""
            SELECT pggit.register_backup(
                'info-test', 'full', 'pgbackrest',
                's3://bucket/info-test', 'main',
                '{"test": "metadata"}'::jsonb
            )
        """)

        info = db.execute("""
            SELECT backup_name, backup_tool, metadata
            FROM pggit.get_backup_info(%s::UUID)
        """, backup_id[0])

        assert info[0][0] == 'info-test'
        assert info[0][1] == 'pgbackrest'
        assert info[0][2]['test'] == 'metadata'
        print("✓ Retrieved backup info")


class TestBackupCoverage:
    """Test backup coverage analysis."""

    def test_backup_coverage_view(self, db, pggit_installed):
        """Test backup coverage view."""
        coverage = db.execute("""
            SELECT branch_name, total_backups, backup_status
            FROM pggit.backup_coverage
        """)

        assert coverage is not None
        print(f"✓ Coverage analysis returned {len(coverage)} branches")
```

---

## Phase 2: Tool Integration & Automation (2-3 weeks)

**Scope**: Automated backup execution, tool integration, and listener service.

**Prerequisites**: Phase 1 completed and tested.

### 2.1 pgBackRest Integration

```sql
-- =====================================================
-- pgBackRest Integration
-- =====================================================

-- Trigger pgBackRest backup
CREATE OR REPLACE FUNCTION pggit.backup_pgbackrest(
    p_backup_type TEXT DEFAULT 'full',  -- 'full', 'incr', 'diff'
    p_branch_name TEXT DEFAULT 'main',
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_backup_name TEXT;
    v_command TEXT;
    v_location TEXT;
BEGIN
    -- Generate backup name
    v_backup_name := format('pgbackrest-%s-%s', p_backup_type,
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    -- Register backup
    v_backup_id := pggit.register_backup(
        v_backup_name,
        p_backup_type,
        'pgbackrest',
        format('pgbackrest://%s', v_backup_name),
        p_branch_name,
        p_options
    );

    -- Build pgBackRest command
    v_command := format('pgbackrest --stanza=%s --type=%s backup',
                       COALESCE(p_options->>'stanza', 'main'),
                       p_backup_type);

    -- Execute backup (via background worker or notify external service)
    PERFORM pg_notify('pggit_backup_request',
                     jsonb_build_object(
                         'backup_id', v_backup_id,
                         'command', v_command,
                         'tool', 'pgbackrest'
                     )::text);

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;

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
    backup_size = (p_info_json->'database'->>'size')::BIGINT,
    compressed_size = (p_info_json->'repo'->>'size')::BIGINT
    WHERE backup_id = p_backup_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;
```

### 2.2 Barman Integration

```sql
-- =====================================================
-- Barman Integration
-- =====================================================

CREATE OR REPLACE FUNCTION pggit.backup_barman(
    p_server_name TEXT,
    p_branch_name TEXT DEFAULT 'main',
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_backup_name TEXT;
BEGIN
    v_backup_name := format('barman-%s-%s', p_server_name,
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    v_backup_id := pggit.register_backup(
        v_backup_name,
        'full',
        'barman',
        format('barman://%s/latest', p_server_name),
        p_branch_name,
        p_options || jsonb_build_object('server', p_server_name)
    );

    -- Notify external barman wrapper
    PERFORM pg_notify('pggit_backup_request',
                     jsonb_build_object(
                         'backup_id', v_backup_id,
                         'command', format('barman backup %s', p_server_name),
                         'tool', 'barman'
                     )::text);

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;
```

### 2.3 pg_dump Integration

```sql
-- =====================================================
-- pg_dump Integration (Logical Backups)
-- =====================================================

CREATE OR REPLACE FUNCTION pggit.backup_pg_dump(
    p_branch_name TEXT DEFAULT 'main',
    p_schema TEXT DEFAULT NULL,
    p_format TEXT DEFAULT 'custom',  -- 'custom', 'tar', 'plain'
    p_options JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_backup_id UUID;
    v_backup_name TEXT;
    v_location TEXT;
BEGIN
    v_backup_name := format('pg_dump-%s-%s',
                           COALESCE(p_schema, 'all'),
                           to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS'));

    v_location := format('file:///backups/%s.dump', v_backup_name);

    v_backup_id := pggit.register_backup(
        v_backup_name,
        'snapshot',
        'pg_dump',
        v_location,
        p_branch_name,
        p_options || jsonb_build_object(
            'format', p_format,
            'schema', p_schema
        )
    );

    RETURN v_backup_id;
END;
$$ LANGUAGE plpgsql;
```

### 2.4 Backup Listener Service

Create external service `pggit-backup-listener` (Python/Go):

```python
#!/usr/bin/env python3
"""
pgGit Backup Listener Service

Listens for backup requests via PostgreSQL NOTIFY and executes
the appropriate backup tool (pgBackRest, Barman, pg_dump).
"""

import asyncio
import asyncpg
import subprocess
import json
import logging
from typing import Dict, Any

logger = logging.getLogger('pggit_backup_listener')


class BackupExecutor:
    """Execute backup commands and update pgGit metadata."""

    def __init__(self, db_url: str):
        self.db_url = db_url
        self.pool = None

    async def start(self):
        """Start listening for backup requests."""
        self.pool = await asyncpg.create_pool(self.db_url)

        async with self.pool.acquire() as conn:
            await conn.add_listener('pggit_backup_request', self.handle_backup_request)
            logger.info("Listening for backup requests...")

            # Keep running
            while True:
                await asyncio.sleep(1)

    async def handle_backup_request(self, connection, pid, channel, payload):
        """Handle incoming backup request."""
        try:
            request = json.loads(payload)
            backup_id = request['backup_id']
            command = request['command']
            tool = request['tool']

            logger.info(f"Executing backup {backup_id} with {tool}: {command}")

            # Execute backup command
            result = await self.execute_backup(command, tool)

            # Update status in database
            if result['success']:
                await self.complete_backup(backup_id, result)
            else:
                await self.fail_backup(backup_id, result['error'])

        except Exception as e:
            logger.error(f"Error handling backup request: {e}")

    async def execute_backup(self, command: str, tool: str) -> Dict[str, Any]:
        """Execute backup command."""
        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await proc.communicate()

            if proc.returncode == 0:
                return {
                    'success': True,
                    'stdout': stdout.decode(),
                    'stderr': stderr.decode()
                }
            else:
                return {
                    'success': False,
                    'error': stderr.decode(),
                    'returncode': proc.returncode
                }
        except Exception as e:
            return {'success': False, 'error': str(e)}

    async def complete_backup(self, backup_id: str, result: Dict[str, Any]):
        """Mark backup as completed."""
        async with self.pool.acquire() as conn:
            await conn.execute("""
                SELECT pggit.complete_backup($1::UUID)
            """, backup_id)
            logger.info(f"Backup {backup_id} completed successfully")

    async def fail_backup(self, backup_id: str, error: str):
        """Mark backup as failed."""
        async with self.pool.acquire() as conn:
            await conn.execute("""
                SELECT pggit.fail_backup($1::UUID, $2)
            """, backup_id, error)
            logger.error(f"Backup {backup_id} failed: {error}")


if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print("Usage: pggit-backup-listener <database_url>")
        sys.exit(1)

    logging.basicConfig(level=logging.INFO)
    executor = BackupExecutor(sys.argv[1])
    asyncio.run(executor.start())
```

---

## Phase 3: Recovery Workflows (1-2 weeks)

**Scope**: Recovery planning, verification, and restoration procedures.

**Note**: This phase provides **two recovery scenarios**:
1. **Disaster Recovery** (database is down) - requires downtime
2. **Point-in-Time Clone** (live database) - zero-downtime parallel restore

### 3.1 Recovery Planning

```sql
-- =====================================================
-- Recovery Workflow Functions
-- =====================================================

-- Find best backup for commit
CREATE OR REPLACE FUNCTION pggit.find_backup_for_commit(
    p_commit_hash TEXT
) RETURNS TABLE (
    backup_id UUID,
    backup_name TEXT,
    backup_type TEXT,
    backup_tool TEXT,
    location TEXT,
    time_distance_seconds BIGINT,
    exact_match BOOLEAN
) AS $$
BEGIN
    -- Find backups for this exact commit, or closest in time
    RETURN QUERY
    WITH commit_info AS (
        SELECT hash, committed_at
        FROM pggit.commits
        WHERE hash = p_commit_hash
    )
    SELECT
        b.backup_id,
        b.backup_name,
        b.backup_type,
        b.backup_tool,
        b.location,
        EXTRACT(EPOCH FROM ABS(b.completed_at - ci.committed_at))::BIGINT AS time_distance,
        (b.commit_hash = p_commit_hash) AS exact_match
    FROM pggit.backups b, commit_info ci
    WHERE b.status = 'completed'
      AND (
          b.commit_hash = p_commit_hash  -- Exact match
          OR b.completed_at <= ci.committed_at + INTERVAL '1 hour'  -- Close in time
      )
    ORDER BY exact_match DESC, time_distance ASC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;

-- Generate recovery plan (two modes: disaster recovery or live clone)
CREATE OR REPLACE FUNCTION pggit.generate_recovery_plan(
    p_target_commit TEXT,
    p_recovery_mode TEXT DEFAULT 'disaster',  -- 'disaster' or 'clone'
    p_preferred_tool TEXT DEFAULT NULL,
    p_clone_target TEXT DEFAULT NULL  -- For clone mode: target database/cluster
) RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    command TEXT,
    details JSONB
) AS $$
DECLARE
    v_backup RECORD;
    v_step INTEGER := 0;
BEGIN
    -- Find best backup
    SELECT * INTO v_backup
    FROM pggit.find_backup_for_commit(p_target_commit)
    WHERE (p_preferred_tool IS NULL OR backup_tool = p_preferred_tool)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No suitable backup found for commit %', p_target_commit;
    END IF;

    IF p_recovery_mode = 'disaster' THEN
        -- DISASTER RECOVERY MODE (requires downtime)

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'prepare'::TEXT,
            '🛑 Stop PostgreSQL service'::TEXT,
            'sudo systemctl stop postgresql'::TEXT,
            jsonb_build_object('downtime', true, 'mode', 'disaster');

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'backup_current'::TEXT,
            '💾 Backup current data directory (safety)'::TEXT,
            'sudo mv /var/lib/postgresql/data /var/lib/postgresql/data.backup'::TEXT,
            jsonb_build_object('reversible', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'restore'::TEXT,
            format('📦 Restore from %s backup %s', v_backup.backup_tool, v_backup.backup_name),
            CASE v_backup.backup_tool
                WHEN 'pgbackrest' THEN 'pgbackrest --stanza=main --delta restore'
                WHEN 'barman' THEN format('barman recover main %s /var/lib/postgresql/data', v_backup.backup_name)
                WHEN 'pg_dump' THEN format('createdb recovered && pg_restore -d recovered %s', v_backup.location)
                ELSE 'Manual restore required - consult backup tool documentation'
            END,
            jsonb_build_object('backup_id', v_backup.backup_id, 'location', v_backup.location);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'start'::TEXT,
            '▶️  Start PostgreSQL service'::TEXT,
            'sudo systemctl start postgresql'::TEXT,
            '{}'::JSONB;

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'migrate'::TEXT,
            format('🔀 Apply pgGit migrations to commit %s', p_target_commit),
            format('SELECT pggit.checkout(%L)', p_target_commit),
            jsonb_build_object('requires_running_db', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'verify'::TEXT,
            '✅ Verify database integrity'::TEXT,
            'SELECT pggit.verify_integrity()'::TEXT,
            '{}'::JSONB;

    ELSIF p_recovery_mode = 'clone' THEN
        -- LIVE CLONE MODE (zero downtime, parallel restore)

        IF p_clone_target IS NULL THEN
            RAISE EXCEPTION 'Clone mode requires p_clone_target parameter (e.g., new cluster path or database name)';
        END IF;

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'prepare'::TEXT,
            '📁 Prepare clone target directory'::TEXT,
            format('sudo mkdir -p %s && sudo chown postgres:postgres %s', p_clone_target, p_clone_target),
            jsonb_build_object('downtime', false, 'mode', 'clone', 'target', p_clone_target);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'restore'::TEXT,
            format('📦 Restore backup to clone target: %s', p_clone_target),
            CASE v_backup.backup_tool
                WHEN 'pgbackrest' THEN format('pgbackrest --stanza=main --delta --pg1-path=%s restore', p_clone_target)
                WHEN 'barman' THEN format('barman recover main %s %s', v_backup.backup_name, p_clone_target)
                WHEN 'pg_dump' THEN format('createdb %s && pg_restore -d %s %s', p_clone_target, p_clone_target, v_backup.location)
                ELSE 'Manual restore to clone target required'
            END,
            jsonb_build_object('backup_id', v_backup.backup_id, 'target', p_clone_target);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'configure'::TEXT,
            '⚙️  Configure clone cluster (different port, etc.)'::TEXT,
            format('Edit %s/postgresql.conf: set port = 5433', p_clone_target),
            jsonb_build_object('manual_step', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'start_clone'::TEXT,
            '▶️  Start clone cluster'::TEXT,
            format('pg_ctl -D %s start', p_clone_target),
            '{}'::JSONB;

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'migrate'::TEXT,
            format('🔀 Apply pgGit migrations to commit %s on clone', p_target_commit),
            format('psql -p 5433 -c "SELECT pggit.checkout(%L)"', p_target_commit),
            jsonb_build_object('clone_operation', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'verify'::TEXT,
            '✅ Verify clone integrity'::TEXT,
            'psql -p 5433 -c "SELECT pggit.verify_integrity()"',
            '{}'::JSONB;

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'info'::TEXT,
            'ℹ️  Clone ready for testing/switchover'::TEXT,
            format('Clone running on port 5433. Test, then optionally switch production traffic.'),
            jsonb_build_object('final_step', true, 'clone_location', p_clone_target);

    ELSE
        RAISE EXCEPTION 'Invalid recovery mode: %. Use "disaster" or "clone"', p_recovery_mode;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Execute recovery (dry-run by default)
CREATE OR REPLACE FUNCTION pggit.restore_from_commit(
    p_target_commit TEXT,
    p_dry_run BOOLEAN DEFAULT TRUE
) RETURNS TABLE (
    step_number INTEGER,
    status TEXT,
    output TEXT
) AS $$
BEGIN
    IF p_dry_run THEN
        -- Just show the plan
        RETURN QUERY
        SELECT s.step_number, 'planned'::TEXT AS status, s.description AS output
        FROM pggit.generate_recovery_plan(p_target_commit) s;
    ELSE
        -- TODO: Actual execution would require external orchestration
        RAISE NOTICE 'Actual recovery execution requires external orchestration service';
        RAISE NOTICE 'Run: pggit-recovery-orchestrator restore-to-commit %', p_target_commit;

        RETURN QUERY
        SELECT 1, 'info'::TEXT, 'Recovery plan generated - manual execution required'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### 3.2 Backup Verification

```sql
-- =====================================================
-- Backup Verification
-- =====================================================

-- Verify backup integrity
CREATE OR REPLACE FUNCTION pggit.verify_backup(
    p_backup_id UUID,
    p_verification_type TEXT DEFAULT 'checksum'
) RETURNS UUID AS $$
DECLARE
    v_verification_id UUID := gen_random_uuid();
    v_backup RECORD;
BEGIN
    -- Get backup info
    SELECT * INTO v_backup
    FROM pggit.backups
    WHERE backup_id = p_backup_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup % not found', p_backup_id;
    END IF;

    -- Record verification attempt
    INSERT INTO pggit.backup_verifications (
        verification_id,
        backup_id,
        verification_type,
        status,
        details
    ) VALUES (
        v_verification_id,
        p_backup_id,
        p_verification_type,
        'in_progress',
        jsonb_build_object('started_at', CURRENT_TIMESTAMP)
    );

    -- Trigger verification via notification
    PERFORM pg_notify('pggit_verify_backup',
                     jsonb_build_object(
                         'verification_id', v_verification_id,
                         'backup_id', p_backup_id,
                         'type', p_verification_type,
                         'tool', v_backup.backup_tool,
                         'location', v_backup.location
                     )::text);

    RETURN v_verification_id;
END;
$$ LANGUAGE plpgsql;

-- Update verification result
CREATE OR REPLACE FUNCTION pggit.update_verification_result(
    p_verification_id UUID,
    p_status TEXT,
    p_details JSONB DEFAULT '{}'
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backup_verifications
    SET status = p_status,
        details = details || p_details || jsonb_build_object('completed_at', CURRENT_TIMESTAMP)
    WHERE verification_id = p_verification_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;
```

### 3.3 Retention Policy Management

```sql
-- =====================================================
-- Retention Policy Management
-- =====================================================

-- Apply retention policy
CREATE OR REPLACE FUNCTION pggit.apply_retention_policy(
    p_policy JSONB DEFAULT '{"full_days": 30, "incremental_days": 7}'
) RETURNS TABLE (
    action TEXT,
    backup_id UUID,
    backup_name TEXT,
    reason TEXT
) AS $$
DECLARE
    v_full_retention INTERVAL;
    v_incr_retention INTERVAL;
BEGIN
    v_full_retention := ((p_policy->>'full_days')::INTEGER || ' days')::INTERVAL;
    v_incr_retention := ((p_policy->>'incremental_days')::INTEGER || ' days')::INTERVAL;

    -- Mark expired full backups
    RETURN QUERY
    WITH expired AS (
        UPDATE pggit.backups
        SET expires_at = CURRENT_TIMESTAMP,
            status = 'expired'
        WHERE backup_type = 'full'
          AND status = 'completed'
          AND completed_at < (CURRENT_TIMESTAMP - v_full_retention)
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        RETURNING backup_id, backup_name, 'full_retention_exceeded' AS reason
    )
    SELECT 'expire'::TEXT, backup_id, backup_name, reason FROM expired;

    -- Mark expired incremental backups
    RETURN QUERY
    WITH expired AS (
        UPDATE pggit.backups
        SET expires_at = CURRENT_TIMESTAMP,
            status = 'expired'
        WHERE backup_type IN ('incremental', 'differential')
          AND status = 'completed'
          AND completed_at < (CURRENT_TIMESTAMP - v_incr_retention)
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        RETURNING backup_id, backup_name, 'incremental_retention_exceeded' AS reason
    )
    SELECT 'expire'::TEXT, backup_id, backup_name, reason FROM expired;
END;
$$ LANGUAGE plpgsql;

-- Delete expired backups
CREATE OR REPLACE FUNCTION pggit.cleanup_expired_backups(
    p_dry_run BOOLEAN DEFAULT TRUE
) RETURNS TABLE (
    action TEXT,
    backup_id UUID,
    backup_name TEXT,
    location TEXT
) AS $$
BEGIN
    IF p_dry_run THEN
        -- Just list what would be deleted
        RETURN QUERY
        SELECT 'would_delete'::TEXT, b.backup_id, b.backup_name, b.location
        FROM pggit.backups b
        WHERE status = 'expired'
          AND expires_at < CURRENT_TIMESTAMP;
    ELSE
        -- Actually delete (just update status, don't remove from DB)
        RETURN QUERY
        WITH deleted AS (
            UPDATE pggit.backups
            SET status = 'deleted'
            WHERE status = 'expired'
              AND expires_at < CURRENT_TIMESTAMP
            RETURNING backup_id, backup_name, location
        )
        SELECT 'deleted'::TEXT, backup_id, backup_name, location FROM deleted;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

---

## Testing Strategy

### Unit Tests

```python
# tests/unit/test_backup_functions.py
def test_register_backup():
    """Test backup registration creates proper metadata."""
    pass

def test_complete_backup_updates_status():
    """Test status transitions."""
    pass

def test_backup_dependencies():
    """Test incremental backup chains."""
    pass
```

### Integration Tests

```python
# tests/integration/test_backup_tools.py
def test_pgbackrest_integration():
    """Test pgBackRest command generation and execution."""
    pass

def test_barman_integration():
    """Test Barman integration."""
    pass

def test_backup_listener_service():
    """Test external listener service."""
    pass
```

### E2E Tests

```python
# tests/e2e/test_backup_workflows.py
def test_full_backup_workflow():
    """Test complete backup lifecycle: register → execute → complete → verify."""
    pass

def test_recovery_plan_generation():
    """Test recovery plan for specific commit."""
    pass

def test_retention_policy_application():
    """Test backup expiration based on retention policy."""
    pass
```

---

## Documentation

### User Guide

Create `docs/backup-integration.md`:

```markdown
# Backup Integration Guide

## Overview

pgGit integrates with industry-standard backup tools to provide
Git-like tracking of database backups.

## Quick Start

### Register a Backup

```sql
-- Register a pgBackRest backup
SELECT pggit.backup_pgbackrest('full', 'main');

-- Register a Barman backup
SELECT pggit.backup_barman('prod-server', 'main');

-- Register a pg_dump backup
SELECT pggit.backup_pg_dump('main', 'public', 'custom');
```

### List Backups

```sql
-- List all backups for 'main' branch
SELECT * FROM pggit.list_backups('main');

-- Check backup coverage
SELECT * FROM pggit.backup_coverage;
```

### Recovery

```sql
-- Generate recovery plan for commit
SELECT * FROM pggit.generate_recovery_plan('abc123def');

-- Restore to commit (dry-run)
SELECT * FROM pggit.restore_from_commit('abc123def', true);
```

## Tool-Specific Guides

### pgBackRest
[Configuration and usage examples]

### Barman
[Configuration and usage examples]

### pg_dump
[Configuration and usage examples]
```

### API Reference

Create `docs/api/backup-functions.md` documenting all functions.

---

## Rollout Plan (Revised)

### Week 1: Phase 1 - Metadata Tracking
- [ ] Implement schema (1 day)
  - Backups table with commit_hash reference
  - Dependencies, verifications, tags tables
  - Indexes and views
- [ ] Implement core functions (2 days)
  - `register_backup()` (manual registration)
  - `complete_backup()`, `fail_backup()`
  - `list_backups()`, `get_backup_info()`
- [ ] Create coverage views (1 day)
  - `branch_backup_coverage`
  - `commit_backup_coverage`
- [ ] Write unit tests (1 day)
- [ ] Documentation (1 day)

### Week 2-4: Phase 2 - Automation & Integration
- [ ] Design backup job queue (1 day)
  - Job table for reliable queueing
  - Retry logic, failure handling
- [ ] Implement pgBackRest integration (3 days)
  - `backup_pgbackrest()` function
  - Command generation
  - Metadata parsing
- [ ] Implement Barman integration (2 days)
- [ ] Implement pg_dump integration (2 days)
- [ ] Create backup listener service (4 days)
  - Job queue processor
  - Tool execution
  - Status updates
  - Health monitoring
- [ ] Integration tests (2 days)
- [ ] Deployment documentation (1 day)

### Week 5-6: Phase 3 - Recovery Workflows
- [ ] Implement recovery planning (3 days)
  - `find_backup_for_commit()`
  - `generate_recovery_plan()` (both modes)
  - Disaster recovery workflow
  - Live clone workflow
- [ ] Implement verification (2 days)
  - `verify_backup()`
  - Checksum validation
  - Restore testing
- [ ] Implement retention policies (2 days)
  - `apply_retention_policy()`
  - `cleanup_expired_backups()`
- [ ] E2E tests (2 days)
  - Full backup workflow tests
  - Recovery plan generation tests
  - Both recovery modes
- [ ] Documentation and examples (2 days)
  - User guide with both recovery scenarios
  - Troubleshooting guide
  - Best practices

---

## Success Metrics

### Functionality
- [ ] All 3 backup tools integrated (pgBackRest, Barman, pg_dump)
- [ ] Backup metadata tracked in Git history
- [ ] Recovery plans generated for any commit
- [ ] Retention policies automated

### Quality
- [ ] 90%+ test coverage
- [ ] All E2E workflows tested
- [ ] Performance: <100ms for metadata operations
- [ ] Zero data loss during backup/restore

### Adoption
- [ ] Documentation complete
- [ ] Example configurations for each tool
- [ ] Migration guide from standalone tools

---

## Future Enhancements (Post-MVP)

### Cloud Backup Integration
- Direct S3/GCS/Azure Blob storage
- Cloud-native backup APIs
- Cross-region replication tracking

### Backup Analytics
- Backup size trends over time
- Compression ratio analysis
- Cost estimation per branch

### Advanced Recovery
- Point-in-time recovery UI
- Automated failover integration
- Backup testing automation

### Multi-Database Support
- Track backups across multiple databases
- Coordinated backup snapshots
- Cross-database recovery

---

## Security Considerations

### Access Control
- Only superuser can register/delete backups
- Role-based backup visibility
- Audit log for all backup operations

### Encryption
- Track encryption status in metadata
- Support for encrypted backup locations
- Key rotation tracking

### Compliance
- Retention policy enforcement
- Immutable backup markers
- Compliance reporting (GDPR, SOC2)

---

## Estimated Resource Requirements

### Development
- 1 senior developer (full-time, 6 weeks)
- 1 QA engineer (50%, 3 weeks)
- 1 technical writer (25%, 2 weeks)

### Infrastructure
- CI/CD pipeline updates
- Test environment with backup tools
- Documentation hosting

### Ongoing Maintenance
- ~4 hours/week monitoring
- ~1 day/month for tool updates
- ~1 day/quarter for new features

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Backup tool version incompatibility | Medium | High | Test matrix for major versions |
| Performance impact of metadata tracking | Low | Medium | Async operations, indexing |
| External service dependency (listener) | Medium | High | Systemd integration, health checks |
| User confusion (two backup systems) | Medium | Medium | Clear documentation, migration guide |
| Security vulnerabilities in integrations | Low | High | Regular security audits |

---

## Questions for Review

1. **Should we support custom backup tools?**
   - Pro: Maximum flexibility
   - Con: Increased complexity, testing burden

2. **How should we handle backup storage costs?**
   - Track estimated costs in metadata?
   - Provide cost optimization recommendations?

3. **Should backup listener be part of core or separate package?**
   - Core: Easier deployment
   - Separate: More flexible, language-agnostic

4. **What level of backup verification is required?**
   - Checksum only?
   - Full restore testing?
   - Automated testing frequency?

5. **Should we integrate with backup scheduling tools?**
   - Cron integration?
   - Cloud scheduler integration?
   - Built-in scheduler?

---

## Revision History

### 2025-01-01: Architecture Review Revisions

**Schema Changes:**
- ✅ Fixed: Changed backup-branch relationship to backup-commit (more Git-like)
- ✅ Fixed: Updated all references from `pggit.version_history` to `pggit.commits`
- ✅ Fixed: Column names updated (`version_hash` → `hash`, `version_timestamp` → `committed_at`)
- ✅ Added: `branch_backup_coverage` view to show which branches have backups
- ✅ Added: `commit_backup_coverage` view for backup coverage analysis

**Phase 1 Simplification:**
- ✅ Reduced scope to metadata-only tracking (read-only)
- ✅ Made temporal snapshots optional (performance optimization)
- ✅ Users manually run backup tools, then register metadata
- ✅ Removed automated execution from Phase 1 (moved to Phase 2)

**Function Improvements:**
- ✅ `register_backup()`: Made snapshots optional, improved commit detection logic
- ✅ `list_backups()`: Now filters by commit or branch
- ✅ `get_backup_info()`: Shows all branches pointing to the backup's commit
- ✅ `find_backup_for_commit()`: Fixed schema references, added exact match detection

**Recovery Clarifications:**
- ✅ Added two recovery modes: disaster recovery (downtime) and live clone (zero-downtime)
- ✅ `generate_recovery_plan()`: Now generates different plans based on mode
- ✅ Clarified that disaster recovery requires downtime (removed from "zero-downtime" promise)
- ✅ Added live clone workflow for zero-downtime point-in-time restore

**Test Suite Enhancements:**
- Tests updated to use `commit_hash` instead of `branch_name`
- Added tests for backup-commit relationships
- Added tests for coverage views

**Documentation Updates:**
- Clarified backup-branch-commit model
- Added examples for both recovery modes
- Documented performance considerations for temporal snapshots

---

## Conclusion

This implementation plan provides a comprehensive backup integration system
for pgGit that leverages existing tools while adding Git-like tracking and
recovery capabilities. The phased approach allows for incremental delivery
and feedback incorporation.

**Revised Approach:**
- Phase 1: Metadata tracking (1 week) - Manual registration, queries, views
- Phase 2: Automation (2-3 weeks) - Backup execution, listener service, tool integration
- Phase 3: Recovery (1-2 weeks) - Disaster recovery + live clone workflows

**Next Steps:**
1. Review and approve revised plan
2. Set up development environment
3. Begin Phase 1 implementation (metadata only)
4. Schedule weekly progress reviews

**Success Criteria:**
- Users can track backups alongside Git commits
- Backups are properly linked to commits (not just branches)
- Recovery plans support both disaster and zero-downtime scenarios
- Integration with major backup tools works seamlessly
- Documentation is clear and comprehensive
