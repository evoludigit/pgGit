-- ============================================================================
-- PHASE 5: History & Audit API
-- ============================================================================
-- Provides comprehensive history, audit trails, and time-travel capabilities
-- Created: 2025-12-26
-- Status: Implementation Phase
-- ============================================================================

-- ============================================================================
-- Function 1: pggit.get_commit_history()
-- Purpose: Query commit history with advanced filtering, pagination, and analytics
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_commit_history(
    p_branch_name TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_author_name TEXT DEFAULT NULL,
    p_search_message TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_order_by TEXT DEFAULT 'author_time DESC'
) RETURNS TABLE (
    commit_id BIGINT,
    commit_hash CHAR(64),
    branch_name TEXT,
    parent_commit_hash CHAR(64),
    author_name TEXT,
    author_time TIMESTAMP,
    commit_message TEXT,
    objects_changed INTEGER,
    objects_added INTEGER,
    objects_deleted INTEGER,
    objects_modified INTEGER,
    merge_info TEXT,
    ancestry_depth INTEGER
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_branch_id BIGINT;
    v_limit INTEGER;
BEGIN
    -- Parameter validation
    IF p_limit IS NULL OR p_limit < 1 THEN
        v_limit := 50;
    ELSIF p_limit > 1000 THEN
        v_limit := 1000;
    ELSE
        v_limit := p_limit;
    END IF;

    -- Verify branch exists if specified
    IF p_branch_name IS NOT NULL THEN
        SELECT branch_id INTO v_branch_id
        FROM pggit.branches
        WHERE branch_name = p_branch_name;

        IF v_branch_id IS NULL THEN
            RAISE EXCEPTION 'Branch % does not exist', p_branch_name;
        END IF;
    END IF;

    -- Return commit history with computed metrics
    RETURN QUERY
    WITH commit_base AS (
        -- Base commit query
        SELECT
            c.commit_id,
            c.commit_hash,
            b.branch_name,
            c.parent_commit_hash,
            c.author_name,
            c.author_time,
            c.commit_message,
            c.branch_id,
            b.parent_branch_id
        FROM pggit.commits c
        JOIN pggit.branches b ON c.branch_id = b.branch_id
        WHERE (v_branch_id IS NULL OR c.branch_id = v_branch_id)
            AND (p_since_timestamp IS NULL OR c.author_time >= p_since_timestamp)
            AND (p_until_timestamp IS NULL OR c.author_time <= p_until_timestamp)
            AND (p_author_name IS NULL OR c.author_name ILIKE '%' || p_author_name || '%')
            AND (p_search_message IS NULL OR c.commit_message ILIKE '%' || p_search_message || '%')
    ),
    commit_metrics AS (
        -- Calculate change counts from object_history
        SELECT
            cb.commit_id,
            cb.commit_hash,
            cb.branch_name,
            cb.parent_commit_hash,
            cb.author_name,
            cb.author_time,
            cb.commit_message,
            cb.branch_id,
            cb.parent_branch_id,
            COUNT(DISTINCT oh.object_id)::INTEGER AS objects_changed,
            COALESCE(SUM(CASE WHEN oh.change_type = 'CREATE' THEN 1 ELSE 0 END), 0)::INTEGER AS objects_added,
            COALESCE(SUM(CASE WHEN oh.change_type = 'DROP' THEN 1 ELSE 0 END), 0)::INTEGER AS objects_deleted,
            COALESCE(SUM(CASE WHEN oh.change_type = 'ALTER' THEN 1 ELSE 0 END), 0)::INTEGER AS objects_modified
        FROM commit_base cb
        LEFT JOIN pggit.object_history oh ON cb.commit_hash = oh.commit_hash
            AND cb.branch_id = oh.branch_id
        GROUP BY cb.commit_id, cb.commit_hash, cb.branch_name, cb.parent_commit_hash,
                 cb.author_name, cb.author_time, cb.commit_message, cb.branch_id, cb.parent_branch_id
    ),
    commit_ancestry AS (
        -- Calculate ancestry depth using recursive CTE
        SELECT
            cm.commit_id,
            cm.commit_hash,
            cm.branch_name,
            cm.parent_commit_hash,
            cm.author_name,
            cm.author_time,
            cm.commit_message,
            cm.objects_changed,
            cm.objects_added,
            cm.objects_deleted,
            cm.objects_modified,
            -- Calculate depth from branch to root
            (WITH RECURSIVE branch_path AS (
                SELECT branch_id, parent_branch_id, 0 AS depth
                FROM pggit.branches
                WHERE branch_id = cm.branch_id
                UNION ALL
                SELECT b.branch_id, b.parent_branch_id, bp.depth + 1
                FROM pggit.branches b
                INNER JOIN branch_path bp ON b.branch_id = bp.parent_branch_id
                WHERE bp.parent_branch_id IS NOT NULL
            )
            SELECT COALESCE(MAX(depth), 0) FROM branch_path) AS ancestry_depth
        FROM commit_metrics cm
    ),
    commit_with_merge AS (
        -- Add merge information
        SELECT
            ca.commit_id,
            ca.commit_hash,
            ca.branch_name,
            ca.parent_commit_hash,
            ca.author_name,
            ca.author_time,
            ca.commit_message,
            ca.objects_changed,
            ca.objects_added,
            ca.objects_deleted,
            ca.objects_modified,
            NULL::TEXT AS merge_info,
            ca.ancestry_depth
        FROM commit_ancestry ca
    )
    SELECT
        cwm.commit_id,
        cwm.commit_hash,
        cwm.branch_name,
        cwm.parent_commit_hash,
        cwm.author_name,
        cwm.author_time,
        cwm.commit_message,
        cwm.objects_changed,
        cwm.objects_added,
        cwm.objects_deleted,
        cwm.objects_modified,
        cwm.merge_info,
        cwm.ancestry_depth
    FROM commit_with_merge cwm
    ORDER BY cwm.author_time DESC, cwm.commit_id DESC
    LIMIT v_limit
    OFFSET p_offset;
END;
$$ SECURITY DEFINER;

-- ============================================================================
-- Function 2: pggit.get_audit_trail()
-- Purpose: Complete immutable audit trail of all object changes with before/after
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_audit_trail(
    p_object_type TEXT DEFAULT NULL,
    p_schema_name TEXT DEFAULT NULL,
    p_object_name TEXT DEFAULT NULL,
    p_branch_name TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_limit INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    history_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    branch_name TEXT,
    change_type TEXT,
    change_severity TEXT,
    before_hash CHAR(64),
    after_hash CHAR(64),
    before_definition TEXT,
    after_definition TEXT,
    definition_diff_summary TEXT,
    commit_hash CHAR(64),
    commit_message TEXT,
    author_name TEXT,
    changed_at TIMESTAMP,
    change_reason TEXT,
    is_breaking_change BOOLEAN
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_branch_id BIGINT;
    v_limit INTEGER;
BEGIN
    -- Parameter validation
    IF p_limit IS NULL OR p_limit < 1 THEN
        v_limit := 100;
    ELSIF p_limit > 1000 THEN
        v_limit := 1000;
    ELSE
        v_limit := p_limit;
    END IF;

    -- Validate change_type if specified
    IF p_change_type IS NOT NULL THEN
        IF p_change_type NOT IN ('CREATE', 'ALTER', 'DROP') THEN
            RAISE EXCEPTION 'Invalid change_type: %. Must be CREATE, ALTER, or DROP', p_change_type;
        END IF;
    END IF;

    -- Verify branch exists if specified
    IF p_branch_name IS NOT NULL THEN
        SELECT branch_id INTO v_branch_id
        FROM pggit.branches
        WHERE branch_name = p_branch_name;

        IF v_branch_id IS NULL THEN
            RAISE EXCEPTION 'Branch % does not exist', p_branch_name;
        END IF;
    END IF;

    -- Return audit trail with enriched metadata
    RETURN QUERY
    WITH audit_base AS (
        SELECT
            oh.history_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name AS full_name,
            b.branch_name,
            oh.change_type,
            oh.before_hash,
            oh.after_hash,
            oh.before_definition,
            oh.after_definition,
            oh.commit_hash,
            oh.change_reason,
            oh.created_at,
            oh.branch_id,
            c.author_name,
            c.commit_message
        FROM pggit.object_history oh
        JOIN pggit.schema_objects so ON oh.object_id = so.object_id
        JOIN pggit.commits c ON oh.commit_hash = c.commit_hash
        JOIN pggit.branches b ON oh.branch_id = b.branch_id
        WHERE (p_object_type IS NULL OR so.object_type = p_object_type)
            AND (p_schema_name IS NULL OR so.schema_name ILIKE p_schema_name)
            AND (p_object_name IS NULL OR so.object_name ILIKE p_object_name)
            AND (v_branch_id IS NULL OR oh.branch_id = v_branch_id)
            AND (p_change_type IS NULL OR oh.change_type = p_change_type)
            AND (p_since_timestamp IS NULL OR oh.created_at >= p_since_timestamp)
            AND (p_until_timestamp IS NULL OR oh.created_at <= p_until_timestamp)
    ),
    audit_with_severity AS (
        SELECT
            ab.*,
            CASE
                WHEN ab.change_type = 'CREATE' THEN 'MINOR'
                WHEN ab.change_type = 'DROP' THEN 'BREAKING'
                WHEN ab.change_type = 'ALTER' THEN
                    CASE
                        WHEN ab.before_definition IS NULL OR ab.after_definition IS NULL THEN 'MAJOR'
                        WHEN ab.before_definition = ab.after_definition THEN 'PATCH'
                        ELSE 'MAJOR'
                    END
                ELSE 'PATCH'
            END AS change_severity
        FROM audit_base ab
    ),
    audit_with_diff AS (
        SELECT
            aws.*,
            -- Generate diff summary
            CASE
                WHEN aws.change_type = 'CREATE' THEN 'New object created'
                WHEN aws.change_type = 'DROP' THEN 'Object dropped'
                WHEN aws.change_type = 'ALTER' THEN
                    'Modified from ' || COALESCE(LENGTH(aws.before_definition), 0) ||
                    ' to ' || COALESCE(LENGTH(aws.after_definition), 0) || ' characters'
                ELSE 'Unknown change'
            END AS definition_diff_summary
        FROM audit_with_severity aws
    ),
    audit_with_breaking AS (
        SELECT
            awd.*,
            -- Detect breaking changes
            (awd.change_type = 'DROP') AS is_breaking_change
        FROM audit_with_diff awd
    )
    SELECT
        awb.history_id,
        awb.object_type,
        awb.schema_name,
        awb.object_name,
        awb.full_name,
        awb.branch_name,
        awb.change_type,
        awb.change_severity,
        awb.before_hash,
        awb.after_hash,
        awb.before_definition,
        awb.after_definition,
        awb.definition_diff_summary,
        awb.commit_hash,
        awb.commit_message,
        awb.author_name,
        awb.created_at,
        awb.change_reason,
        awb.is_breaking_change
    FROM audit_with_breaking awb
    ORDER BY awb.created_at DESC
    LIMIT v_limit
    OFFSET p_offset;
END;
$$ SECURITY DEFINER;

-- ============================================================================
-- Function 3: pggit.get_object_timeline()
-- Purpose: View the complete evolution of a specific object across versions
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_object_timeline(
    p_object_name TEXT,
    p_branch_name TEXT DEFAULT NULL,
    p_include_merged_history BOOLEAN DEFAULT FALSE,
    p_limit INTEGER DEFAULT 100
) RETURNS TABLE (
    timeline_version INTEGER,
    change_type TEXT,
    change_severity TEXT,
    version_major INT,
    version_minor INT,
    version_patch INT,
    current_definition TEXT,
    previous_definition TEXT,
    objects_hash CHAR(64),
    commit_hash CHAR(64),
    commit_message TEXT,
    author_name TEXT,
    changed_at TIMESTAMP,
    time_since_last_change INTERVAL,
    object_status TEXT,
    merge_source_branch TEXT
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_object_id BIGINT;
    v_branch_id BIGINT;
    v_schema_name TEXT;
    v_object_name TEXT;
    v_limit INTEGER;
BEGIN
    -- Parameter validation
    IF p_object_name IS NULL THEN
        RAISE EXCEPTION 'p_object_name is required';
    END IF;

    IF p_limit IS NULL OR p_limit < 1 THEN
        v_limit := 100;
    ELSIF p_limit > 10000 THEN
        v_limit := 10000;
    ELSE
        v_limit := p_limit;
    END IF;

    -- Parse object name (handle both "table" and "schema.table" formats)
    IF p_object_name LIKE '%.%' THEN
        v_schema_name := SPLIT_PART(p_object_name, '.', 1);
        v_object_name := SPLIT_PART(p_object_name, '.', 2);
    ELSE
        v_schema_name := 'public';
        v_object_name := p_object_name;
    END IF;

    -- Find object_id
    SELECT object_id INTO v_object_id
    FROM pggit.schema_objects
    WHERE schema_name = v_schema_name AND object_name = v_object_name;

    IF v_object_id IS NULL THEN
        RAISE EXCEPTION 'Object %.% not found', v_schema_name, v_object_name;
    END IF;

    -- Determine branch_id
    IF p_branch_name IS NOT NULL THEN
        SELECT branch_id INTO v_branch_id
        FROM pggit.branches
        WHERE branch_name = p_branch_name;

        IF v_branch_id IS NULL THEN
            RAISE EXCEPTION 'Branch % does not exist', p_branch_name;
        END IF;
    ELSE
        -- Default to main branch
        SELECT branch_id INTO v_branch_id
        FROM pggit.branches
        WHERE branch_name = 'main';
    END IF;

    -- Return object timeline
    RETURN QUERY
    WITH object_history_seq AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY oh.created_at ASC) AS timeline_version,
            oh.change_type,
            oh.before_definition,
            oh.after_definition,
            oh.after_hash,
            oh.commit_hash,
            oh.created_at,
            oh.branch_id,
            c.author_name,
            c.commit_message,
            b.branch_name,
            LAG(oh.created_at) OVER (ORDER BY oh.created_at ASC) AS prev_created_at
        FROM pggit.object_history oh
        JOIN pggit.commits c ON oh.commit_hash = c.commit_hash
        JOIN pggit.branches b ON oh.branch_id = b.branch_id
        WHERE oh.object_id = v_object_id
            AND oh.branch_id = v_branch_id
        ORDER BY oh.created_at ASC
    ),
    timeline_with_version AS (
        SELECT
            ohs.timeline_version,
            ohs.change_type,
            CASE
                WHEN ohs.change_type = 'CREATE' THEN 'MINOR'
                WHEN ohs.change_type = 'DROP' THEN 'BREAKING'
                WHEN ohs.change_type = 'ALTER' THEN 'MAJOR'
                ELSE 'PATCH'
            END AS change_severity,
            ohs.timeline_version AS version_major,
            0 AS version_minor,
            0 AS version_patch,
            ohs.after_definition,
            ohs.before_definition,
            ohs.after_hash,
            ohs.commit_hash,
            ohs.commit_message,
            ohs.author_name,
            ohs.created_at,
            (ohs.created_at - ohs.prev_created_at) AS time_since_last_change,
            -- Determine object status
            CASE
                WHEN ohs.change_type = 'DROP' THEN 'DELETED'
                ELSE 'ACTIVE'
            END AS object_status,
            NULL::TEXT AS merge_source_branch
        FROM object_history_seq ohs
    )
    SELECT
        twv.timeline_version,
        twv.change_type,
        twv.change_severity,
        twv.version_major,
        twv.version_minor,
        twv.version_patch,
        twv.after_definition,
        twv.before_definition,
        twv.after_hash,
        twv.commit_hash,
        twv.commit_message,
        twv.author_name,
        twv.created_at,
        twv.time_since_last_change,
        twv.object_status,
        twv.merge_source_branch
    FROM timeline_with_version twv
    ORDER BY twv.timeline_version ASC
    LIMIT v_limit;
END;
$$ SECURITY DEFINER;

-- ============================================================================
-- Function 4: pggit.query_at_timestamp()
-- Purpose: Time-travel query - reconstruct complete schema state at any point
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.query_at_timestamp(
    p_branch_name TEXT,
    p_target_timestamp TIMESTAMP,
    p_object_type TEXT DEFAULT NULL,
    p_schema_filter TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'object_name ASC'
) RETURNS TABLE (
    object_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    definition TEXT,
    content_hash CHAR(64),
    version_major INT,
    version_minor INT,
    version_patch INT,
    was_active BOOLEAN,
    created_at TIMESTAMP,
    last_modified_at TIMESTAMP,
    last_modified_by TEXT,
    time_to_current INTERVAL
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_branch_id BIGINT;
    v_branch_created_at TIMESTAMP;
BEGIN
    -- Parameter validation
    IF p_branch_name IS NULL THEN
        RAISE EXCEPTION 'p_branch_name is required';
    END IF;

    IF p_target_timestamp IS NULL THEN
        RAISE EXCEPTION 'p_target_timestamp is required';
    END IF;

    -- Verify target timestamp is in the past
    IF p_target_timestamp > NOW() THEN
        RAISE EXCEPTION 'Cannot query future timestamp: %', p_target_timestamp;
    END IF;

    -- Find branch and verify it existed at target timestamp
    SELECT branch_id, created_at INTO v_branch_id, v_branch_created_at
    FROM pggit.branches
    WHERE branch_name = p_branch_name;

    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % does not exist', p_branch_name;
    END IF;

    IF p_target_timestamp < v_branch_created_at THEN
        RAISE EXCEPTION 'Branch % did not exist at timestamp %', p_branch_name, p_target_timestamp;
    END IF;

    -- Reconstruct schema state at timestamp
    RETURN QUERY
    WITH object_state AS (
        -- For each object, find the most recent change <= target_timestamp
        SELECT
            so.object_id,
            so.object_type,
            so.schema_name,
            so.object_name,
            so.schema_name || '.' || so.object_name AS full_name,
            -- Find last change for this object on this branch
            (
                SELECT oh2.after_definition
                FROM pggit.object_history oh2
                WHERE oh2.object_id = so.object_id
                    AND oh2.branch_id = v_branch_id
                    AND oh2.created_at <= p_target_timestamp
                ORDER BY oh2.created_at DESC
                LIMIT 1
            ) AS definition,
            (
                SELECT oh2.after_hash
                FROM pggit.object_history oh2
                WHERE oh2.object_id = so.object_id
                    AND oh2.branch_id = v_branch_id
                    AND oh2.created_at <= p_target_timestamp
                ORDER BY oh2.created_at DESC
                LIMIT 1
            ) AS content_hash,
            1 AS version_major,
            0 AS version_minor,
            0 AS version_patch,
            -- Determine if object was active (not deleted) at that time
            (
                SELECT oh2.change_type != 'DROP'
                FROM pggit.object_history oh2
                WHERE oh2.object_id = so.object_id
                    AND oh2.branch_id = v_branch_id
                    AND oh2.created_at <= p_target_timestamp
                ORDER BY oh2.created_at DESC
                LIMIT 1
            ) AS was_active,
            so.created_at,
            (
                SELECT oh2.created_at
                FROM pggit.object_history oh2
                WHERE oh2.object_id = so.object_id
                    AND oh2.branch_id = v_branch_id
                    AND oh2.created_at <= p_target_timestamp
                ORDER BY oh2.created_at DESC
                LIMIT 1
            ) AS last_modified_at,
            (
                SELECT c2.author_name
                FROM pggit.object_history oh2
                JOIN pggit.commits c2 ON oh2.commit_hash = c2.commit_hash
                WHERE oh2.object_id = so.object_id
                    AND oh2.branch_id = v_branch_id
                    AND oh2.created_at <= p_target_timestamp
                ORDER BY oh2.created_at DESC
                LIMIT 1
            ) AS last_modified_by
        FROM pggit.schema_objects so
    ),
    object_state_filtered AS (
        SELECT
            os.object_id,
            os.object_type,
            os.schema_name,
            os.object_name,
            os.full_name,
            os.definition,
            os.content_hash,
            os.version_major,
            os.version_minor,
            os.version_patch,
            os.was_active,
            os.created_at,
            os.last_modified_at,
            os.last_modified_by,
            (NOW() - p_target_timestamp) AS time_to_current
        FROM object_state os
        WHERE os.was_active = TRUE
            AND (p_object_type IS NULL OR os.object_type = p_object_type)
            AND (p_schema_filter IS NULL OR os.schema_name ILIKE p_schema_filter)
    )
    SELECT
        osf.object_id,
        osf.object_type,
        osf.schema_name,
        osf.object_name,
        osf.full_name,
        osf.definition,
        osf.content_hash,
        osf.version_major,
        osf.version_minor,
        osf.version_patch,
        osf.was_active,
        osf.created_at,
        osf.last_modified_at,
        osf.last_modified_by,
        osf.time_to_current
    FROM object_state_filtered osf
    ORDER BY
        CASE
            WHEN p_order_by = 'object_name ASC' THEN osf.object_name
            WHEN p_order_by = 'object_type ASC' THEN osf.object_type
            ELSE osf.object_name
        END ASC,
        osf.object_type ASC;
END;
$$ SECURITY DEFINER;

-- ============================================================================
-- Performance Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_object_history_object_created
    ON pggit.object_history(object_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_object_history_branch_created
    ON pggit.object_history(branch_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_object_history_commit_hash
    ON pggit.object_history(commit_hash);

CREATE INDEX IF NOT EXISTS idx_commits_branch_time
    ON pggit.commits(branch_id, author_time DESC);

CREATE INDEX IF NOT EXISTS idx_commits_author_time
    ON pggit.commits(author_name, author_time DESC);

CREATE INDEX IF NOT EXISTS idx_commits_commit_hash
    ON pggit.commits(commit_hash);

-- ============================================================================
-- End of Phase 5 Implementation
-- ============================================================================
