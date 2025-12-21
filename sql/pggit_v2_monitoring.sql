-- ============================================
-- pgGit v2: Monitoring & Dashboard Setup
-- ============================================
-- Monitoring views and alert functions for production readiness
-- Supports dashboard integration and operational health checks
--
-- Week 5 Deliverable: Monitoring functions for:
-- - Current system state summary
-- - Health check summary
-- - Alert detection
-- - Performance recommendations

-- ============================================
-- MONITORING VIEWS
-- ============================================

-- View: Current system state summary
CREATE OR REPLACE VIEW pggit_v2.current_state_summary AS
SELECT
    'System Health' as category,
    'Current Commits' as metric,
    COUNT(DISTINCT cg.commit_sha)::TEXT as value
FROM pggit_v2.commit_graph cg
UNION ALL
SELECT
    'System Health',
    'Active Branches',
    COUNT(*)::TEXT
FROM pggit_v2.refs
WHERE ref_type = 'branch'
UNION ALL
SELECT
    'System Health',
    'Objects Stored',
    COUNT(*)::TEXT
FROM pggit_v2.objects
UNION ALL
SELECT
    'System Health',
    'Tracked Changes',
    COUNT(*)::TEXT
FROM pggit_audit.changes
UNION ALL
SELECT
    'System Health',
    'Storage Used (GB)',
    ROUND((SUM(size)::NUMERIC / 1024 / 1024 / 1024), 2)::TEXT
FROM pggit_v2.objects
UNION ALL
SELECT
    'Activity',
    'Commits Last 24h',
    COUNT(*)::TEXT
FROM pggit_v2.commit_graph
WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Activity',
    'Authors Active Last 24h',
    COUNT(DISTINCT author)::TEXT
FROM pggit_v2.commit_graph
WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Activity',
    'Changes Last 24h',
    COUNT(*)::TEXT
FROM pggit_audit.changes c
JOIN pggit_v2.commit_graph cg ON cg.commit_sha = c.commit_sha
WHERE cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Latest',
    'HEAD Commit',
    commit_sha
FROM pggit_v2.commit_graph
ORDER BY committed_at DESC
LIMIT 1
UNION ALL
SELECT
    'Latest',
    'HEAD Timestamp',
    committed_at::TEXT
FROM pggit_v2.commit_graph
ORDER BY committed_at DESC
LIMIT 1;

COMMENT ON VIEW pggit_v2.current_state_summary IS
'Quick snapshot of current system state: counts, storage, recent activity, and latest commit.';

-- View: Health check summary
CREATE OR REPLACE VIEW pggit_v2.health_check_summary AS
WITH integrity_checks AS (
    SELECT
        'OK'::TEXT as status,
        'Data Integrity' as check_name,
        COUNT(*) as issue_count
    FROM pggit_v2.validate_data_integrity()
    WHERE status = 'OK'
    UNION ALL
    SELECT
        'FAILED',
        'Data Integrity',
        COUNT(*)
    FROM pggit_v2.validate_data_integrity()
    WHERE status = 'FAILED'
),
anomaly_checks AS (
    SELECT
        'WARNING'::TEXT as status,
        'Anomaly Detection' as check_name,
        COUNT(*) as issue_count
    FROM pggit_v2.detect_anomalies()
),
storage_check AS (
    SELECT
        CASE
            WHEN total_size > 107374182400 THEN 'WARNING'  -- > 100 GB
            ELSE 'OK'
        END::TEXT as status,
        'Storage Usage' as check_name,
        CASE WHEN total_size > 107374182400 THEN 1 ELSE 0 END as issue_count
    FROM pggit_v2.analyze_storage_usage()
),
ref_check AS (
    SELECT
        CASE WHEN COUNT(*) = 0 THEN 'WARNING' ELSE 'OK' END::TEXT as status,
        'Branches Exist' as check_name,
        CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END as issue_count
    FROM pggit_v2.refs
    WHERE ref_type = 'branch'
)
SELECT
    status,
    check_name,
    issue_count
FROM integrity_checks
UNION ALL
SELECT * FROM anomaly_checks
UNION ALL
SELECT * FROM storage_check
UNION ALL
SELECT * FROM ref_check
ORDER BY status DESC, check_name;

COMMENT ON VIEW pggit_v2.health_check_summary IS
'Health check results: data integrity, anomalies, storage, and reference counts.';

-- View: Recent activity summary
CREATE OR REPLACE VIEW pggit_v2.recent_activity_summary AS
SELECT
    'Commits' as activity_type,
    COUNT(*)::TEXT as count_last_24h,
    COUNT(DISTINCT author)::TEXT as contributors,
    MAX(committed_at)::TEXT as last_activity
FROM pggit_v2.commit_graph
WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Objects Created',
    COUNT(*)::TEXT,
    'N/A',
    MAX(created_at)::TEXT
FROM pggit_v2.objects
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Changes Tracked',
    COUNT(*)::TEXT,
    COUNT(DISTINCT author)::TEXT,
    MAX(committed_at)::TEXT
FROM pggit_audit.changes c
JOIN pggit_v2.commit_graph cg ON cg.commit_sha = c.commit_sha
WHERE cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
UNION ALL
SELECT
    'Branches Updated',
    COUNT(DISTINCT r.ref_name)::TEXT,
    'N/A',
    MAX(cg.committed_at)::TEXT
FROM pggit_v2.refs r
JOIN pggit_v2.commit_graph cg ON cg.commit_sha = r.commit_sha
WHERE cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
  AND r.ref_type = 'branch';

COMMENT ON VIEW pggit_v2.recent_activity_summary IS
'Activity metrics for last 24 hours: commits, objects, changes, and updated branches.';

-- ============================================
-- ALERT FUNCTIONS
-- ============================================

-- Function: Check for operational alerts
CREATE OR REPLACE FUNCTION pggit_v2.check_for_alerts()
RETURNS TABLE (
    alert_level TEXT,
    alert_message TEXT
) AS $$
BEGIN
    -- Alert 1: No commits in last 24 hours
    RETURN QUERY
    SELECT
        'WARNING'::TEXT,
        'No commits in last 24 hours - system may be inactive'::TEXT
    WHERE NOT EXISTS (
        SELECT 1 FROM pggit_v2.commit_graph
        WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
    );

    -- Alert 2: Very large objects
    RETURN QUERY
    SELECT
        'WARNING'::TEXT,
        format('Object %s is very large (%s bytes)', sha, size)::TEXT
    FROM pggit_v2.objects
    WHERE size > 52428800  -- 50 MB
    ORDER BY size DESC
    LIMIT 5;

    -- Alert 3: Data integrity issues
    RETURN QUERY
    SELECT
        'CRITICAL'::TEXT,
        details
    FROM pggit_v2.validate_data_integrity()
    WHERE status = 'FAILED';

    -- Alert 4: Storage growing rapidly
    RETURN QUERY
    SELECT
        'INFO'::TEXT,
        format('Storage growth detected: %s GB total used',
            ROUND((SELECT SUM(size)::NUMERIC / 1024 / 1024 / 1024 FROM pggit_v2.objects), 2))::TEXT
    WHERE (
        SELECT SUM(size) FROM pggit_v2.objects
    ) > 10737418240;  -- > 10 GB

    -- Alert 5: Commits without messages
    RETURN QUERY
    SELECT
        'INFO'::TEXT,
        format('Found %s commits without messages - recommend adding documentation', COUNT(*))::TEXT
    FROM pggit_v2.commits_without_message
    GROUP BY COUNT(*);

    -- Alert 6: Open merge requests with conflicts
    RETURN QUERY
    SELECT
        'WARNING'::TEXT,
        format('Merge request %s has %s conflicts - manual resolution needed',
            mr_id, (SELECT COUNT(*) FROM pggit_v2.detect_merge_conflicts(source_branch, target_branch)))::TEXT
    FROM pggit_v2.merge_requests
    WHERE status IN ('OPEN', 'DRAFT')
      AND conflicts_found = true;

    -- Alert 7: Very old branches (not updated in 90 days)
    RETURN QUERY
    SELECT
        'INFO'::TEXT,
        format('Branch %s last updated %s days ago - consider cleanup',
            ref_name, EXTRACT(DAY FROM (CURRENT_TIMESTAMP - cg.committed_at))::INT)::TEXT
    FROM pggit_v2.refs r
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = r.commit_sha
    WHERE r.ref_type = 'branch'
      AND r.ref_name NOT IN ('main', 'master')
      AND cg.committed_at < CURRENT_TIMESTAMP - INTERVAL '90 days'
    LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.check_for_alerts() IS
'Check for operational alerts: inactivity, large objects, integrity issues, conflicts, old branches.';

-- ============================================
-- RECOMMENDATION FUNCTIONS
-- ============================================

-- Function: Get optimization recommendations
CREATE OR REPLACE FUNCTION pggit_v2.get_recommendations()
RETURNS TABLE (
    recommendation TEXT,
    priority INT,
    impact TEXT
) AS $$
BEGIN
    -- Recommendation 1: Data deduplication efficiency
    RETURN QUERY
    SELECT
        'Current storage can be optimized: consider analyzing object reuse patterns'::TEXT,
        2,
        'Improves storage efficiency'::TEXT
    WHERE EXISTS (SELECT 1 FROM pggit_v2.objects WHERE size > 1048576);

    -- Recommendation 2: Index usage
    RETURN QUERY
    SELECT
        'Verify index performance on frequently accessed commits'::TEXT,
        3,
        'Improves query performance'::TEXT
    WHERE (SELECT COUNT(*) FROM pggit_v2.commit_graph) > 1000;

    -- Recommendation 3: Commit message quality
    RETURN QUERY
    SELECT
        format('Enforce commit message requirements: %s commits lack messages', COUNT(*))::TEXT,
        2,
        'Improves auditability and compliance'::TEXT
    FROM pggit_v2.commits_without_message
    HAVING COUNT(*) > 0;

    -- Recommendation 4: Cleanup old branches
    RETURN QUERY
    SELECT
        format('Clean up %s old branches (not updated in 90 days)', COUNT(*))::TEXT,
        3,
        'Reduces clutter and improves branch navigation'::TEXT
    FROM pggit_v2.refs r
    JOIN pggit_v2.commit_graph cg ON cg.commit_sha = r.commit_sha
    WHERE r.ref_type = 'branch'
      AND r.ref_name NOT IN ('main', 'master')
      AND cg.committed_at < CURRENT_TIMESTAMP - INTERVAL '90 days'
    HAVING COUNT(*) > 0;

    -- Recommendation 5: Monitor storage growth
    RETURN QUERY
    SELECT
        'Monitor and plan for increasing storage: implement retention policies'::TEXT,
        2,
        'Ensures long-term operational sustainability'::TEXT
    WHERE (SELECT SUM(size) FROM pggit_v2.objects) > 5368709120;  -- > 5 GB

    -- Recommendation 6: Review large commits
    RETURN QUERY
    SELECT
        format('Review large commits: %s commits modified >5 objects', COUNT(*))::TEXT,
        3,
        'Improves code review quality and change tracking'::TEXT
    FROM pggit_v2.large_commits
    HAVING COUNT(*) > 0;

    -- Recommendation 7: Archive historical data
    RETURN QUERY
    SELECT
        'Consider archiving commits older than 1 year for historical analysis'::TEXT,
        4,
        'Improves operational performance'::TEXT
    WHERE (SELECT COUNT(*) FROM pggit_v2.commit_graph
           WHERE committed_at < CURRENT_TIMESTAMP - INTERVAL '1 year') > 100;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_recommendations() IS
'Get optimization recommendations prioritized by impact: storage, deduplication, quality, cleanup.';

-- ============================================
-- DASHBOARD QUERY TEMPLATES
-- ============================================

-- Function: Get dashboard data summary
CREATE OR REPLACE FUNCTION pggit_v2.get_dashboard_summary()
RETURNS TABLE (
    metric_name TEXT,
    metric_value TEXT,
    trend TEXT,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'Total Commits'::TEXT,
        COUNT(DISTINCT commit_sha)::TEXT,
        'Stable'::TEXT,
        'OK'::TEXT
    FROM pggit_v2.commit_graph
    UNION ALL
    SELECT
        'Active Branches',
        COUNT(*)::TEXT,
        'Stable',
        'OK'
    FROM pggit_v2.refs
    WHERE ref_type = 'branch'
    UNION ALL
    SELECT
        'Storage Used (MB)',
        ROUND((SUM(size)::NUMERIC / 1024 / 1024), 2)::TEXT,
        'Growing',
        CASE WHEN SUM(size) > 10737418240 THEN 'WARNING' ELSE 'OK' END
    FROM pggit_v2.objects
    UNION ALL
    SELECT
        'Commits Last 7 Days',
        COUNT(*)::TEXT,
        'Growing',
        'OK'
    FROM pggit_v2.commit_graph
    WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    UNION ALL
    SELECT
        'Health Status',
        'GOOD'::TEXT,
        'Stable',
        'OK'
    WHERE (SELECT COUNT(*) FROM pggit_v2.validate_data_integrity() WHERE status = 'FAILED') = 0;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_dashboard_summary() IS
'Get dashboard-ready summary of key metrics, trends, and system health status.';

-- ============================================
-- SCHEDULED MONITORING HELPERS
-- ============================================

-- Function: Generate monitoring report
CREATE OR REPLACE FUNCTION pggit_v2.generate_monitoring_report()
RETURNS TEXT AS $$
DECLARE
    v_report TEXT;
    v_timestamp TIMESTAMP;
BEGIN
    v_timestamp := CURRENT_TIMESTAMP;
    v_report := '';

    -- Header
    v_report := v_report || format('pgGit v2 Monitoring Report - %s'::TEXT, v_timestamp) || E'\n';
    v_report := v_report || '=' || repeat('=', 50) || E'\n\n';

    -- System Status
    v_report := v_report || 'SYSTEM STATUS' || E'\n';
    v_report := v_report || '-' || repeat('-', 50) || E'\n';
    WITH status AS (SELECT * FROM pggit_v2.current_state_summary)
    SELECT v_report || string_agg(metric || ': ' || value, E'\n') INTO v_report
    FROM status
    WHERE category = 'System Health';
    v_report := v_report || E'\n\n';

    -- Alerts
    v_report := v_report || 'ALERTS' || E'\n';
    v_report := v_report || '-' || repeat('-', 50) || E'\n';
    WITH alerts AS (SELECT * FROM pggit_v2.check_for_alerts() LIMIT 5)
    SELECT v_report || COALESCE(string_agg('[' || alert_level || '] ' || alert_message, E'\n'), 'No alerts')
    INTO v_report
    FROM alerts;
    v_report := v_report || E'\n\n';

    -- Recommendations
    v_report := v_report || 'RECOMMENDATIONS' || E'\n';
    v_report := v_report || '-' || repeat('-', 50) || E'\n';
    WITH recs AS (SELECT * FROM pggit_v2.get_recommendations() LIMIT 3)
    SELECT v_report || COALESCE(string_agg('P' || priority::TEXT || ': ' || recommendation, E'\n'), 'No recommendations')
    INTO v_report
    FROM recs;

    RETURN v_report;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.generate_monitoring_report() IS
'Generate comprehensive monitoring report with status, alerts, and recommendations.';

-- ============================================
-- METADATA
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit v2 Monitoring & Dashboard setup loaded successfully';
    RAISE NOTICE 'Available: Monitoring views, alert functions, recommendations, dashboard data';
    RAISE NOTICE 'Ready for production monitoring and operational dashboards';
END $$;
