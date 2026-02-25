-- pgGit Advanced Indexing Strategy
-- File: 028_advanced_indexes.sql
-- Purpose: BRIN, covering, and partial indexes for production performance

-- ============================================================================
-- BRIN Indexes for Append-Only Time-Series Data
-- ============================================================================

-- BRIN index for history table (time-series append-only pattern)
-- BRIN is perfect for history because:
-- 1. Data is naturally ordered by created_at (append-only)
-- 2. Much smaller than B-tree (MB vs GB for large tables)
-- 3. Efficient for range queries (last N days)
-- 4. Minimal maintenance overhead

CREATE INDEX IF NOT EXISTS idx_history_brin 
ON pggit.history USING BRIN (created_at) 
WITH (pages_per_range = 128);

COMMENT ON INDEX pggit.idx_history_brin IS 
    'BRIN index for efficient time-range queries on history table. 
     50-100x smaller than B-tree for append-only time-series data.';

-- BRIN index for archive_log
CREATE INDEX IF NOT EXISTS idx_archive_log_brin 
ON pggit.archive_log USING BRIN (started_at) 
WITH (pages_per_range = 128);

-- BRIN index for metrics (time-series)
CREATE INDEX IF NOT EXISTS idx_metrics_brin 
ON pggit.metrics USING BRIN (recorded_at) 
WITH (pages_per_range = 128);

-- ============================================================================
-- Covering Indexes for Common Queries
-- ============================================================================

-- Covering index: Fast object lookups with all needed fields
-- Includes content_hash and version to avoid table lookups
CREATE INDEX IF NOT EXISTS idx_objects_lookup_covering 
ON pggit.objects (schema_name, object_name, branch_id, is_active) 
INCLUDE (content_hash, version, object_type, updated_at);

COMMENT ON INDEX pggit.idx_objects_lookup_covering IS 
    'Covering index for object lookups. Eliminates table access for most queries.';

-- Covering index: History queries with object details
CREATE INDEX IF NOT EXISTS idx_history_object_covering 
ON pggit.history (object_id, created_at DESC) 
INCLUDE (change_type, severity, ddl_normalized);

-- Covering index: Branch metadata queries
CREATE INDEX IF NOT EXISTS idx_branches_lookup 
ON pggit.branches (name, status) 
INCLUDE (parent_branch_id, created_at, head_commit_hash);

-- ============================================================================
-- Partial Indexes for Filtered Queries
-- ============================================================================

-- Partial index: Active objects only (most queries filter by is_active)
CREATE INDEX IF NOT EXISTS idx_objects_active_partial 
ON pggit.objects (schema_name, object_name, branch_id) 
WHERE is_active = true;

COMMENT ON INDEX pggit.idx_objects_active_partial IS 
    'Partial index for active objects only. Much smaller than full index.';

-- Partial index: Pending merges only
CREATE INDEX IF NOT EXISTS idx_merge_history_pending 
ON pggit.merge_history (source_branch, target_branch, initiated_at) 
WHERE status IN ('in_progress', 'awaiting_resolution');

-- Partial index: Conflicts needing resolution
CREATE INDEX IF NOT EXISTS idx_merge_conflicts_pending 
ON pggit.merge_conflicts (merge_id, table_name) 
WHERE resolution = 'CONFLICT_PENDING';

-- Partial index: Failed/cancelled metrics (for alerting)
CREATE INDEX IF NOT EXISTS idx_metrics_failures 
ON pggit.metrics (metric_name, recorded_at) 
WHERE labels->>'success' = 'false';

-- ============================================================================
-- Expression Indexes for Computed Values
-- ============================================================================

-- Expression index: Lowercase object names (for case-insensitive search)
CREATE INDEX IF NOT EXISTS idx_objects_name_lower 
ON pggit.objects (lower(schema_name), lower(object_name));

-- Expression index: Date truncation for daily aggregations
CREATE INDEX IF NOT EXISTS idx_history_daily 
ON pggit.history (date_trunc('day', created_at), change_type);

-- Expression index: Full-text search on DDL (for searching schema changes)
CREATE INDEX IF NOT EXISTS idx_history_ddl_search 
ON pggit.history USING gin(to_tsvector('english', ddl_normalized));

COMMENT ON INDEX pggit.idx_history_ddl_search IS 
    'Full-text search index for DDL statements. Enables searching schema changes by keywords.';

-- ============================================================================
-- Multi-Column Indexes for Sorting and Filtering
-- ============================================================================

-- Multi-column: Recent history with object type filtering
CREATE INDEX IF NOT EXISTS idx_history_recent_by_type 
ON pggit.history (created_at DESC, change_type) 
INCLUDE (object_id);

-- Multi-column: Objects by type and update time
CREATE INDEX IF NOT EXISTS idx_objects_by_type_time 
ON pggit.objects (object_type, updated_at DESC) 
WHERE is_active = true;

-- Multi-column: Commits by branch and time
CREATE INDEX IF NOT EXISTS idx_commits_branch_time 
ON pggit.commits (branch_id, created_at DESC) 
INCLUDE (commit_hash, commit_message);

-- ============================================================================
-- Index Statistics and Maintenance
-- ============================================================================

-- Function to analyze index usage
CREATE OR REPLACE FUNCTION pggit.analyze_index_usage()
RETURNS TABLE (
    index_name TEXT,
    table_name TEXT,
    index_size TEXT,
    idx_scan BIGINT,
    idx_tup_read BIGINT,
    idx_tup_fetch BIGINT,
    usage_ratio NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        schemaname || '.' || indexrelname AS index_name,
        schemaname || '.' || relname AS table_name,
        pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch,
        CASE 
            WHEN seq_scan + idx_scan = 0 THEN 0
            ELSE round(idx_scan::NUMERIC / (seq_scan + idx_scan) * 100, 2)
        END AS usage_ratio
    FROM pg_stat_user_indexes
    WHERE schemaname = 'pggit'
    ORDER BY pg_relation_size(indexrelid) DESC;
END;
$$ LANGUAGE plpgsql
STABLE;

COMMENT ON FUNCTION pggit.analyze_index_usage() IS 
    'Analyze index usage statistics to identify unused or inefficient indexes.';

-- Function to rebuild BRIN indexes (needed periodically for optimal performance)
CREATE OR REPLACE FUNCTION pggit.rebuild_brin_indexes()
RETURNS TABLE (index_name TEXT, status TEXT) AS $$
DECLARE
    v_index RECORD;
BEGIN
    FOR v_index IN 
        SELECT indexname 
        FROM pg_indexes 
        WHERE schemaname = 'pggit' 
        AND indexname LIKE 'idx_%_brin'
    LOOP
        BEGIN
            EXECUTE format('REINDEX INDEX pggit.%I', v_index.indexname);
            RETURN QUERY SELECT v_index.indexname, 'rebuilt'::TEXT;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT v_index.indexname, format('error: %s', SQLERRM)::TEXT;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql
VOLATILE;

COMMENT ON FUNCTION pggit.rebuild_brin_indexes() IS 
    'Rebuild all BRIN indexes for optimal performance. Run weekly for large tables.';

-- ============================================================================
-- Index Size Monitoring
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_index_sizes()
RETURNS TABLE (
    index_name TEXT,
    table_name TEXT,
    size_bytes BIGINT,
    size_pretty TEXT,
    estimated_rows BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        schemaname || '.' || indexrelname AS index_name,
        schemaname || '.' || relname AS table_name,
        pg_relation_size(indexrelid) AS size_bytes,
        pg_size_pretty(pg_relation_size(indexrelid)) AS size_pretty,
        (SELECT reltuples::BIGINT FROM pg_class WHERE oid = relid) AS estimated_rows
    FROM pg_stat_user_indexes
    WHERE schemaname = 'pggit'
    ORDER BY pg_relation_size(indexrelid) DESC;
END;
$$ LANGUAGE plpgsql
STABLE;

COMMENT ON FUNCTION pggit.get_index_sizes() IS 
    'Get sizes of all indexes in pggit schema for capacity planning.';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION pggit.analyze_index_usage() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.rebuild_brin_indexes() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_index_sizes() TO PUBLIC;
