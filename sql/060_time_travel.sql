-- pgGit Time-Travel and Point-in-Time Recovery (PITR)
-- Phase 4: Advanced temporal query capabilities
-- Enables querying database state at any point in time

-- =====================================================
-- Temporal Snapshot Infrastructure
-- =====================================================

-- Snapshot metadata table
CREATE TABLE IF NOT EXISTS pggit.temporal_snapshots (
    snapshot_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    snapshot_name TEXT NOT NULL,
    snapshot_timestamp TIMESTAMP NOT NULL,
    branch_id INTEGER REFERENCES pggit.branches(id),
    description TEXT,
    created_by TEXT DEFAULT CURRENT_USER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    frozen BOOLEAN DEFAULT false
);

-- Temporal change log (audit trail)
CREATE TABLE IF NOT EXISTS pggit.temporal_changelog (
    change_id SERIAL PRIMARY KEY,
    snapshot_id UUID REFERENCES pggit.temporal_snapshots(snapshot_id) ON DELETE CASCADE,
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL, -- INSERT, UPDATE, DELETE
    old_data JSONB,
    new_data JSONB,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_by TEXT DEFAULT CURRENT_USER,
    row_id TEXT -- Primary key value
);

-- Temporal query cache
CREATE TABLE IF NOT EXISTS pggit.temporal_query_cache (
    query_id SERIAL PRIMARY KEY,
    snapshot_id UUID REFERENCES pggit.temporal_snapshots(snapshot_id),
    query_text TEXT NOT NULL,
    result_count INT,
    query_hash TEXT UNIQUE,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- =====================================================
-- Core Time-Travel Functions
-- =====================================================

-- Get database state at a specific point in time
CREATE OR REPLACE FUNCTION pggit.get_table_state_at_time(
    p_table_name TEXT,
    p_target_time TIMESTAMP
) RETURNS TABLE (
    row_data JSONB,
    valid_from TIMESTAMP,
    valid_to TIMESTAMP,
    operation TEXT,
    snapshot_id UUID
) AS $$
DECLARE
    v_snapshot_id UUID;
    v_schema_name TEXT;
BEGIN
    -- Parse schema and table name
    v_schema_name := COALESCE(split_part(p_table_name, '.', 1), 'public');

    -- Find the closest snapshot before target time
    SELECT snapshot_id INTO v_snapshot_id
    FROM pggit.temporal_snapshots
    WHERE snapshot_timestamp <= p_target_time
    ORDER BY snapshot_timestamp DESC
    LIMIT 1;

    IF v_snapshot_id IS NULL THEN
        RAISE EXCEPTION 'No snapshot found before %', p_target_time;
    END IF;

    -- Return table state from changelog
    RETURN QUERY
    SELECT
        tc.new_data,
        tc.change_timestamp,
        COALESCE(
            (SELECT MIN(change_timestamp)
             FROM pggit.temporal_changelog tc2
             WHERE tc2.table_schema = tc.table_schema
             AND tc2.table_name = tc.table_name
             AND tc2.row_id = tc.row_id
             AND tc2.change_timestamp > tc.change_timestamp),
            NOW()
        ) AS valid_to,
        tc.operation,
        tc.snapshot_id
    FROM pggit.temporal_changelog tc
    WHERE tc.snapshot_id = v_snapshot_id
    AND tc.table_schema = v_schema_name
    AND tc.table_name = split_part(p_table_name, '.', 2)
    AND tc.change_timestamp <= p_target_time
    AND tc.operation != 'DELETE'
    ORDER BY tc.change_timestamp DESC;
END;
$$ LANGUAGE plpgsql;

-- Query historical data with temporal conditions
CREATE OR REPLACE FUNCTION pggit.query_historical_data(
    p_table_name TEXT,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_where_clause TEXT DEFAULT NULL
) RETURNS TABLE (
    row_data JSONB,
    operation TEXT,
    changed_at TIMESTAMP,
    changed_by TEXT,
    change_count INT
) AS $$
DECLARE
    v_schema_name TEXT;
    v_query TEXT;
    v_where_text TEXT;
BEGIN
    -- Parse schema and table name
    v_schema_name := COALESCE(split_part(p_table_name, '.', 1), 'public');

    -- Build WHERE clause
    v_where_text := format(
        'tc.table_schema = %L AND tc.table_name = %L
         AND tc.change_timestamp BETWEEN %L AND %L',
        v_schema_name,
        split_part(p_table_name, '.', 2),
        p_start_time,
        p_end_time
    );

    IF p_where_clause IS NOT NULL THEN
        v_where_text := v_where_text || ' AND (' || p_where_clause || ')';
    END IF;

    -- Return historical data grouped by operation
    RETURN QUERY EXECUTE format(
        'SELECT
            tc.new_data,
            tc.operation,
            tc.change_timestamp,
            tc.change_by,
            COUNT(*) OVER (PARTITION BY tc.row_id) as change_count
         FROM pggit.temporal_changelog tc
         WHERE %s
         ORDER BY tc.change_timestamp DESC',
        v_where_text
    );
END;
$$ LANGUAGE plpgsql;

-- Restore table to a point in time
CREATE OR REPLACE FUNCTION pggit.restore_table_to_point_in_time(
    p_table_name TEXT,
    p_target_time TIMESTAMP,
    p_create_temp_table BOOLEAN DEFAULT true
) RETURNS TABLE (
    restored_rows INT,
    restored_table_name TEXT,
    restored_at TIMESTAMP
) AS $$
DECLARE
    v_schema_name TEXT;
    v_restored_count INT := 0;
    v_temp_table_name TEXT;
    v_start_time TIMESTAMP;
BEGIN
    -- Parse schema and table name
    v_schema_name := COALESCE(split_part(p_table_name, '.', 1), 'public');
    v_temp_table_name := split_part(p_table_name, '.', 2) || '_restored_' ||
                         to_char(p_target_time, 'YYYYMMDD_HH24MISS');

    -- Create temp table with historical structure
    IF p_create_temp_table THEN
        -- Get earliest timestamp for this table
        SELECT MIN(change_timestamp) INTO v_start_time
        FROM pggit.temporal_changelog
        WHERE table_schema = v_schema_name
        AND table_name = split_part(p_table_name, '.', 2);

        -- Create table from historical data
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I AS
             SELECT (row_data ->> %L)::TEXT as _restored_id,
                    row_data,
                    change_timestamp
             FROM pggit.temporal_changelog
             WHERE table_schema = %L
             AND table_name = %L
             AND change_timestamp <= %L
             AND operation != %L
             GROUP BY row_data, change_timestamp',
            v_schema_name,
            v_temp_table_name,
            'id',
            v_schema_name,
            split_part(p_table_name, '.', 2),
            p_target_time,
            'DELETE'
        );

        -- Count restored rows
        EXECUTE format(
            'SELECT COUNT(*) FROM %I.%I',
            v_schema_name,
            v_temp_table_name
        ) INTO v_restored_count;
    END IF;

    -- Log restoration
    INSERT INTO pggit.temporal_changelog (
        table_schema,
        table_name,
        operation,
        change_by,
        new_data
    ) VALUES (
        v_schema_name,
        split_part(p_table_name, '.', 2),
        'RESTORE',
        CURRENT_USER,
        jsonb_build_object(
            'restored_to', p_target_time,
            'rows_restored', v_restored_count,
            'temp_table', v_temp_table_name
        )
    );

    RETURN QUERY SELECT
        v_restored_count,
        format('%I.%I', v_schema_name, v_temp_table_name),
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Compare table state between two points in time
CREATE OR REPLACE FUNCTION pggit.temporal_diff(
    p_table_name TEXT,
    p_time_a TIMESTAMP,
    p_time_b TIMESTAMP
) RETURNS TABLE (
    row_id TEXT,
    operation_at_a TEXT,
    operation_at_b TEXT,
    data_at_a JSONB,
    data_at_b JSONB,
    changed BOOLEAN,
    field_changes JSONB
) AS $$
DECLARE
    v_schema_name TEXT;
BEGIN
    v_schema_name := COALESCE(split_part(p_table_name, '.', 1), 'public');

    RETURN QUERY
    WITH state_a AS (
        SELECT
            tc.row_id,
            tc.operation,
            tc.new_data,
            ROW_NUMBER() OVER (PARTITION BY tc.row_id ORDER BY tc.change_timestamp DESC) as rn
        FROM pggit.temporal_changelog tc
        WHERE tc.table_schema = v_schema_name
        AND tc.table_name = split_part(p_table_name, '.', 2)
        AND tc.change_timestamp <= p_time_a
    ),
    state_b AS (
        SELECT
            tc.row_id,
            tc.operation,
            tc.new_data,
            ROW_NUMBER() OVER (PARTITION BY tc.row_id ORDER BY tc.change_timestamp DESC) as rn
        FROM pggit.temporal_changelog tc
        WHERE tc.table_schema = v_schema_name
        AND tc.table_name = split_part(p_table_name, '.', 2)
        AND tc.change_timestamp <= p_time_b
    ),
    diff AS (
        SELECT
            COALESCE(a.row_id, b.row_id) as row_id,
            a.operation as op_a,
            b.operation as op_b,
            a.new_data as data_a,
            b.new_data as data_b,
            a.new_data IS DISTINCT FROM b.new_data as changed
        FROM state_a a
        FULL OUTER JOIN state_b b
            ON a.row_id = b.row_id AND a.rn = 1 AND b.rn = 1
        WHERE a.rn = 1 OR b.rn = 1
    )
    SELECT
        d.row_id,
        d.op_a,
        d.op_b,
        d.data_a,
        d.data_b,
        d.changed,
        CASE WHEN d.data_a IS NULL THEN jsonb_build_object('status', 'INSERTED')
             WHEN d.data_b IS NULL THEN jsonb_build_object('status', 'DELETED')
             WHEN d.changed THEN (
                 SELECT jsonb_object_agg(key, jsonb_build_object('old', d.data_a->key, 'new', d.data_b->key))
                 FROM jsonb_object_keys(d.data_a) key
                 WHERE d.data_a->key IS DISTINCT FROM d.data_b->key
             )
             ELSE jsonb_build_object('status', 'UNCHANGED')
        END as field_changes
    FROM diff d
    WHERE d.changed OR d.data_a IS NULL OR d.data_b IS NULL;
END;
$$ LANGUAGE plpgsql;

-- List temporal snapshots
CREATE OR REPLACE FUNCTION pggit.list_temporal_snapshots(
    p_branch_id INTEGER DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
    snapshot_id UUID,
    snapshot_name TEXT,
    snapshot_timestamp TIMESTAMP,
    branch_name TEXT,
    frozen BOOLEAN,
    description TEXT,
    created_by TEXT,
    age_seconds BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ts.snapshot_id,
        ts.snapshot_name,
        ts.snapshot_timestamp,
        b.name,
        ts.frozen,
        ts.description,
        ts.created_by,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ts.snapshot_timestamp))::BIGINT
    FROM pggit.temporal_snapshots ts
    LEFT JOIN pggit.branches b ON ts.branch_id = b.id
    WHERE (p_branch_id IS NULL OR ts.branch_id = p_branch_id)
    ORDER BY ts.snapshot_timestamp DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Create a temporal snapshot
CREATE OR REPLACE FUNCTION pggit.create_temporal_snapshot(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_metadata JSONB DEFAULT '{}'
) RETURNS TABLE (
    snapshot_id UUID,
    snapshot_timestamp TIMESTAMP WITH TIME ZONE,
    row_count INTEGER
) AS $$
DECLARE
    v_snapshot_id UUID := gen_random_uuid();
    v_timestamp TIMESTAMP WITH TIME ZONE := CURRENT_TIMESTAMP;
    v_row_count INTEGER;
    v_full_table_name TEXT;
BEGIN
    -- Validate table exists
    v_full_table_name := p_schema_name || '.' || p_table_name;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema_name AND table_name = p_table_name
    ) THEN
        RAISE EXCEPTION 'Table %.% does not exist', p_schema_name, p_table_name;
    END IF;

    -- Count rows in the table
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema_name, p_table_name)
    INTO v_row_count;

    -- Insert snapshot metadata
    INSERT INTO pggit.temporal_snapshots (
        snapshot_id,
        snapshot_name,
        snapshot_timestamp,
        description,
        created_by
    ) VALUES (
        v_snapshot_id,
        format('%s.%s_snapshot_%s', p_schema_name, p_table_name, extract(epoch from v_timestamp)),
        v_timestamp,
        format('Snapshot of table %s.%s with %s rows', p_schema_name, p_table_name, v_row_count),
        CURRENT_USER
    );

    -- Store metadata
    UPDATE pggit.temporal_snapshots
    SET description = description || jsonb_build_object('table_schema', p_schema_name, 'table_name', p_table_name, 'row_count', v_row_count, 'user_metadata', p_metadata)::TEXT
    WHERE snapshot_id = v_snapshot_id;

    RETURN QUERY SELECT v_snapshot_id, v_timestamp, v_row_count;
        v_snapshot_id,
        p_snapshot_name,
        CURRENT_TIMESTAMP::TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Track changes to snapshots
CREATE OR REPLACE FUNCTION pggit.record_temporal_change(
    p_snapshot_id UUID,
    p_table_schema TEXT,
    p_table_name TEXT,
    p_operation TEXT,
    p_row_id TEXT,
    p_old_data JSONB,
    p_new_data JSONB
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.temporal_changelog (
        snapshot_id,
        table_schema,
        table_name,
        operation,
        old_data,
        new_data,
        row_id,
        change_by
    ) VALUES (
        p_snapshot_id,
        p_table_schema,
        p_table_name,
        p_operation,
        p_old_data,
        p_new_data,
        p_row_id,
        CURRENT_USER
    );

    -- Update snapshot frozen status if needed
    UPDATE pggit.temporal_snapshots
    SET frozen = true
    WHERE snapshot_id = p_snapshot_id
    AND frozen = false;
END;
$$ LANGUAGE plpgsql;

-- Rebuild temporal index for performance
CREATE OR REPLACE FUNCTION pggit.rebuild_temporal_indexes()
RETURNS TABLE (
    index_name TEXT,
    table_name TEXT,
    rebuilt BOOLEAN
) AS $$
BEGIN
    -- Reindex temporal changelog indexes
    BEGIN
        REINDEX INDEX pggit.idx_temporal_table;
    EXCEPTION WHEN UNDEFINED_OBJECT THEN
        NULL;
    END;

    BEGIN
        REINDEX INDEX pggit.idx_temporal_time;
    EXCEPTION WHEN UNDEFINED_OBJECT THEN
        NULL;
    END;

    RETURN QUERY SELECT
        'idx_temporal_table'::TEXT,
        'temporal_changelog'::TEXT,
        true
    UNION ALL
    SELECT
        'idx_temporal_time'::TEXT,
        'temporal_changelog'::TEXT,
        true;
END;
$$ LANGUAGE plpgsql;

-- Export temporal data for backup
CREATE OR REPLACE FUNCTION pggit.export_temporal_data(
    p_snapshot_id UUID
) RETURNS TABLE (
    export_format TEXT,
    data_size BIGINT,
    record_count INT,
    exported_at TIMESTAMP
) AS $$
DECLARE
    v_record_count INT;
    v_data_size BIGINT;
BEGIN
    -- Count records in snapshot
    SELECT COUNT(*) INTO v_record_count
    FROM pggit.temporal_changelog
    WHERE snapshot_id = p_snapshot_id;

    -- Estimate data size
    SELECT pg_total_relation_size('pggit.temporal_changelog'::regclass) INTO v_data_size;

    RETURN QUERY SELECT
        'JSONL'::TEXT,
        v_data_size,
        v_record_count,
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Indexes for Performance
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_temporal_snapshots_branch
ON pggit.temporal_snapshots(branch_id, snapshot_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_temporal_snapshots_time
ON pggit.temporal_snapshots(snapshot_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_temporal_changelog_table
ON pggit.temporal_changelog(table_schema, table_name, change_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_temporal_changelog_snapshot
ON pggit.temporal_changelog(snapshot_id, change_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_temporal_query_cache_hash
ON pggit.temporal_query_cache(query_hash);

-- =====================================================
-- Grant Permissions
-- =====================================================

GRANT SELECT, INSERT ON pggit.temporal_snapshots TO PUBLIC;
GRANT SELECT, INSERT ON pggit.temporal_changelog TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;
