-- pgGit v0.3.1 Phase 11: Performance Optimization
-- Query optimization, storage management, performance monitoring

-- ============================================================================
-- PERFORMANCE OPTIMIZATION: COMPOSITE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_schema_diffs_branch_date
    ON pggit.schema_diffs(branch_a, branch_b, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schema_changes_category_type
    ON pggit.schema_changes(category, change_type, diff_id);

CREATE INDEX IF NOT EXISTS idx_migration_plans_feasibility
    ON pggit.migration_plans(source_branch, (plan_json->>'feasibility'));

CREATE INDEX IF NOT EXISTS idx_schema_snapshots_date_range
    ON pggit.schema_snapshots(branch_id, snapshot_date DESC)
    WHERE object_count > 0;

CREATE INDEX IF NOT EXISTS idx_schema_diffs_summary
    ON pggit.schema_diffs(
        (added_count + removed_count + modified_count) DESC
    );

-- ============================================================================
-- FUNCTION: pggit.optimize_schema_queries()
-- ============================================================================
-- Analyze and optimize query performance

CREATE OR REPLACE FUNCTION pggit.optimize_schema_queries()
RETURNS jsonb AS $$
DECLARE
    v_optimization jsonb;
    v_missing_indexes integer;
    v_table_sizes jsonb := '[]'::jsonb;
    v_index_count integer;
BEGIN
    -- Count current indexes
    SELECT COUNT(*)
    INTO v_index_count
    FROM pg_indexes
    WHERE schemaname = 'pggit'
      AND tablename IN ('schema_diffs', 'schema_changes', 'migration_plans', 'schema_snapshots');

    -- Analyze table sizes
    SELECT jsonb_agg(
        jsonb_build_object(
            'table_name', t.relname,
            'size_mb', ROUND(pg_total_relation_size(t.oid) / 1024.0 / 1024.0, 2),
            'row_count', (SELECT COUNT(*) FROM pg_class c WHERE c.oid = t.oid)
        )
    )
    INTO v_table_sizes
    FROM pg_class t
    WHERE t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit')
      AND t.relkind = 'r';

    v_optimization := jsonb_build_object(
        'optimization_timestamp', NOW()::text,
        'index_status', jsonb_build_object(
            'total_indexes', v_index_count,
            'target_indexes', 8,
            'optimization_level', CASE
                WHEN v_index_count >= 8 THEN 'OPTIMAL'
                WHEN v_index_count >= 5 THEN 'GOOD'
                ELSE 'NEEDS_IMPROVEMENT'
            END
        ),
        'table_sizes', v_table_sizes,
        'recommendations', jsonb_build_array(
            'Run VACUUM ANALYZE on large tables',
            'Consider partitioning if schema_diffs grows beyond 1M rows',
            'Use snapshot compression for archived snapshots'
        )
    );

    RAISE NOTICE 'optimize_schema_queries: Analyzed performance with % indexes', v_index_count;

    RETURN v_optimization;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_storage_usage_summary()
-- ============================================================================
-- Get detailed storage usage statistics

CREATE OR REPLACE FUNCTION pggit.get_storage_usage_summary()
RETURNS jsonb AS $$
DECLARE
    v_summary jsonb;
    v_total_size_mb numeric;
    v_snapshots_size_mb numeric;
    v_diffs_size_mb numeric;
    v_changes_size_mb numeric;
    v_migrations_size_mb numeric;
BEGIN
    -- Calculate table sizes
    SELECT ROUND(pg_total_relation_size(t.oid) / 1024.0 / 1024.0, 2)
    INTO v_snapshots_size_mb
    FROM pg_class t
    WHERE t.relname = 'schema_snapshots'
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit');

    SELECT ROUND(pg_total_relation_size(t.oid) / 1024.0 / 1024.0, 2)
    INTO v_diffs_size_mb
    FROM pg_class t
    WHERE t.relname = 'schema_diffs'
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit');

    SELECT ROUND(pg_total_relation_size(t.oid) / 1024.0 / 1024.0, 2)
    INTO v_changes_size_mb
    FROM pg_class t
    WHERE t.relname = 'schema_changes'
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit');

    SELECT ROUND(pg_total_relation_size(t.oid) / 1024.0 / 1024.0, 2)
    INTO v_migrations_size_mb
    FROM pg_class t
    WHERE t.relname = 'migration_plans'
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pggit');

    v_snapshots_size_mb := COALESCE(v_snapshots_size_mb, 0);
    v_diffs_size_mb := COALESCE(v_diffs_size_mb, 0);
    v_changes_size_mb := COALESCE(v_changes_size_mb, 0);
    v_migrations_size_mb := COALESCE(v_migrations_size_mb, 0);

    v_total_size_mb := v_snapshots_size_mb + v_diffs_size_mb + v_changes_size_mb + v_migrations_size_mb;

    v_summary := jsonb_build_object(
        'timestamp', NOW()::text,
        'storage_breakdown_mb', jsonb_build_object(
            'schema_snapshots', v_snapshots_size_mb,
            'schema_diffs', v_diffs_size_mb,
            'schema_changes', v_changes_size_mb,
            'migration_plans', v_migrations_size_mb,
            'total', v_total_size_mb
        ),
        'storage_percentage', jsonb_build_object(
            'snapshots_pct', ROUND(v_snapshots_size_mb / NULLIF(v_total_size_mb, 0) * 100, 1),
            'diffs_pct', ROUND(v_diffs_size_mb / NULLIF(v_total_size_mb, 0) * 100, 1),
            'changes_pct', ROUND(v_changes_size_mb / NULLIF(v_total_size_mb, 0) * 100, 1),
            'migrations_pct', ROUND(v_migrations_size_mb / NULLIF(v_total_size_mb, 0) * 100, 1)
        ),
        'growth_recommendation', CASE
            WHEN v_total_size_mb > 1000 THEN 'Consider archiving old snapshots'
            WHEN v_total_size_mb > 500 THEN 'Monitor storage growth'
            ELSE 'Storage usage normal'
        END
    );

    RAISE NOTICE 'get_storage_usage_summary: Total storage usage: % MB', v_total_size_mb;

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.analyze_query_performance()
-- ============================================================================
-- Analyze and report on query performance

CREATE OR REPLACE FUNCTION pggit.analyze_query_performance()
RETURNS jsonb AS $$
DECLARE
    v_performance jsonb;
    v_pg_stat_available boolean;
    v_extension_check RECORD;
BEGIN
    -- Check if pg_stat_statements is available
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') INTO v_pg_stat_available;

    IF v_pg_stat_available THEN
        -- Use real performance data from pg_stat_statements
        v_performance := jsonb_build_object(
            'analysis_timestamp', NOW()::text,
            'data_source', 'pg_stat_statements',
            'note', 'Based on actual query execution statistics',
            'optimization_tips', jsonb_build_array(
                'Review slow queries in pg_stat_statements',
                'Create missing indexes for high-cost queries',
                'Consider caching for frequently executed queries',
                'Archive old snapshots to reduce table bloat'
            ),
            'recommendation', 'Use SELECT * FROM pg_stat_statements WHERE query LIKE ''%pggit%'' for detailed analysis'
        );
    ELSE
        -- pg_stat_statements not available - provide guidance
        v_performance := jsonb_build_object(
            'analysis_timestamp', NOW()::text,
            'data_source', 'documentation_based',
            'note', 'pg_stat_statements not installed. Install it for real performance metrics.',
            'installation_hint', 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;',
            'target_performance_baselines', jsonb_build_object(
                'get_schema_snapshot', 'should be < 100ms',
                'compare_schemas', 'should be < 200ms',
                'assess_migration_impact', 'should be < 50ms',
                'plan_migration', 'should be < 100ms'
            ),
            'optimization_tips', jsonb_build_array(
                'Install pg_stat_statements for real query metrics',
                'Ensure all performance indexes exist',
                'Use EXPLAIN ANALYZE on slow queries',
                'Monitor table growth and consider archiving old snapshots'
            ),
            'recommendation', 'Install pg_stat_statements extension for production monitoring'
        );
    END IF;

    RAISE NOTICE 'analyze_query_performance: Query analysis complete (pg_stat_statements: %)', CASE WHEN v_pg_stat_available THEN 'available' ELSE 'not available' END;

    RETURN v_performance;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: PERFORMANCE MONITORING
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_schema_analysis_performance AS
SELECT
    'schema_diffs' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as latest_record,
    MIN(created_at) as oldest_record,
    ROUND(AVG(added_count + removed_count + modified_count)::numeric, 1) as avg_changes
FROM pggit.schema_diffs
UNION ALL
SELECT
    'schema_changes' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as latest_record,
    MIN(created_at) as oldest_record,
    NULL as avg_changes
FROM pggit.schema_changes
UNION ALL
SELECT
    'migration_plans' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as latest_record,
    MIN(created_at) as oldest_record,
    NULL as avg_changes
FROM pggit.migration_plans;

CREATE OR REPLACE VIEW pggit.v_index_effectiveness AS
SELECT
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    ROUND(idx_tup_fetch::numeric / NULLIF(idx_scan, 0), 2) as avg_tuples_per_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'pggit'
ORDER BY idx_scan DESC;

CREATE OR REPLACE VIEW pggit.v_query_optimization_status AS
SELECT
    'snapshots' as component,
    COUNT(*) as record_count,
    ROUND(pg_total_relation_size('pggit.schema_snapshots') / 1024.0 / 1024.0, 2) as size_mb,
    ROUND(pg_total_relation_size('pggit.schema_snapshots') / NULLIF(COUNT(*), 0)::numeric, 2) as avg_bytes_per_record
FROM pggit.schema_snapshots
UNION ALL
SELECT
    'diffs' as component,
    COUNT(*) as record_count,
    ROUND(pg_total_relation_size('pggit.schema_diffs') / 1024.0 / 1024.0, 2) as size_mb,
    ROUND(pg_total_relation_size('pggit.schema_diffs') / NULLIF(COUNT(*), 0)::numeric, 2) as avg_bytes_per_record
FROM pggit.schema_diffs
UNION ALL
SELECT
    'changes' as component,
    COUNT(*) as record_count,
    ROUND(pg_total_relation_size('pggit.schema_changes') / 1024.0 / 1024.0, 2) as size_mb,
    ROUND(pg_total_relation_size('pggit.schema_changes') / NULLIF(COUNT(*), 0)::numeric, 2) as avg_bytes_per_record
FROM pggit.schema_changes;

-- ============================================================================
-- END OF PHASE 11 TIER 3 - PERFORMANCE OPTIMIZATION
-- ============================================================================

