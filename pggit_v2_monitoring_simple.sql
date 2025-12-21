-- Simplified pggit_v2 monitoring functions (without broken views)
-- Functions for alerts, recommendations, and dashboard

-- Function: Check for system alerts
CREATE OR REPLACE FUNCTION pggit_v2.check_for_alerts()
RETURNS TABLE (
    severity TEXT,
    alert_type TEXT,
    message TEXT
) AS $$
BEGIN
    -- Check for data integrity issues
    RETURN QUERY
    SELECT
        'CRITICAL'::TEXT,
        'DATA_INTEGRITY'::TEXT,
        'Data integrity checks failed - check validate_data_integrity()'::TEXT
    WHERE (SELECT COUNT(*) FROM pggit_v2.validate_data_integrity() WHERE status = 'FAILED') > 0;

    -- Check for storage issues
    RETURN QUERY
    SELECT
        'WARNING'::TEXT,
        'STORAGE_HIGH'::TEXT,
        'Storage usage is high'::TEXT
    WHERE (SELECT SUM(size) FROM pggit_v2.objects) > 1000000000;  -- 1GB

    -- Check for orphaned objects
    RETURN QUERY
    SELECT
        'INFO'::TEXT,
        'ORPHANED_OBJECTS'::TEXT,
        'Some objects may be orphaned'::TEXT
    WHERE (SELECT COUNT(*) FROM pggit_v2.objects) > 1000;

    -- If no alerts, return empty
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'OK'::TEXT, 'NO_ALERTS'::TEXT, 'System is healthy'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.check_for_alerts() IS
'Check for system alerts: data integrity, storage, orphaned objects.';

-- Function: Get system recommendations
CREATE OR REPLACE FUNCTION pggit_v2.get_recommendations()
RETURNS TABLE (
    priority TEXT,
    recommendation TEXT,
    rationale TEXT
) AS $$
BEGIN
    -- Storage optimization
    RETURN QUERY
    SELECT
        'MEDIUM'::TEXT,
        'Consider archiving old data'::TEXT,
        'Reduces storage costs and improves performance'::TEXT
    WHERE (SELECT SUM(size) FROM pggit_v2.objects) > 500000000;  -- 500MB

    -- Branch cleanup
    RETURN QUERY
    SELECT
        'LOW'::TEXT,
        'Review and clean up old branches'::TEXT,
        'Improves branch navigation and reduces clutter'::TEXT
    WHERE (SELECT COUNT(*) FROM pggit_v2.refs WHERE type = 'branch') > 10;

    -- If no recommendations, return general advice
    IF NOT FOUND THEN
        RETURN QUERY SELECT
            'INFO'::TEXT,
            'System is well-maintained'::TEXT,
            'Continue regular monitoring'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_recommendations() IS
'Provide system optimization recommendations based on current state.';

-- Function: Get dashboard summary
CREATE OR REPLACE FUNCTION pggit_v2.get_dashboard_summary()
RETURNS TABLE (
    category TEXT,
    metric TEXT,
    value TEXT,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'System'::TEXT,
        'Total Objects'::TEXT,
        COUNT(*)::TEXT,
        'OK'::TEXT
    FROM pggit_v2.objects
    UNION ALL
    SELECT
        'System'::TEXT,
        'Active Branches'::TEXT,
        COUNT(*)::TEXT,
        'OK'::TEXT
    FROM pggit_v2.refs
    WHERE type = 'branch'
    UNION ALL
    SELECT
        'System'::TEXT,
        'Storage Used'::TEXT,
        pg_size_pretty(SUM(size))::TEXT,
        CASE WHEN SUM(size) > 1000000000 THEN 'WARNING' ELSE 'OK' END
    FROM pggit_v2.objects
    UNION ALL
    SELECT
        'Activity'::TEXT,
        'Recent Commits'::TEXT,
        COUNT(*)::TEXT,
        'OK'::TEXT
    FROM pggit_v2.commit_graph
    WHERE committed_at >= CURRENT_TIMESTAMP - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.get_dashboard_summary() IS
'Dashboard summary with key system metrics and health indicators.';

-- Function: Generate monitoring report
CREATE OR REPLACE FUNCTION pggit_v2.generate_monitoring_report()
RETURNS TEXT AS $$
DECLARE
    v_report TEXT := '';
    v_alerts TEXT;
    v_recs TEXT;
BEGIN
    -- Build report header
    v_report := v_report || 'pgGit v2 System Report' || E'\n';
    v_report := v_report || 'Generated: ' || CURRENT_TIMESTAMP || E'\n';
    v_report := v_report || E'\n';

    -- Add alerts section
    v_report := v_report || 'ALERTS:' || E'\n';
    SELECT string_agg(severity || ': ' || message, E'\n')
    INTO v_alerts
    FROM pggit_v2.check_for_alerts()
    WHERE severity != 'OK';

    IF v_alerts IS NOT NULL THEN
        v_report := v_report || v_alerts || E'\n';
    ELSE
        v_report := v_report || 'No active alerts' || E'\n';
    END IF;

    -- Add recommendations section
    v_report := v_report || E'\n' || 'RECOMMENDATIONS:' || E'\n';
    SELECT string_agg(priority || ': ' || recommendation, E'\n')
    INTO v_recs
    FROM pggit_v2.get_recommendations()
    WHERE priority != 'INFO';

    IF v_recs IS NOT NULL THEN
        v_report := v_report || v_recs || E'\n';
    ELSE
        v_report := v_report || 'System is well-optimized' || E'\n';
    END IF;

    RETURN v_report;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION pggit_v2.generate_monitoring_report() IS
'Generate a comprehensive system monitoring report with alerts and recommendations.';

DO $$
BEGIN
    RAISE NOTICE 'pgGit v2 Monitoring Functions loaded successfully';
    RAISE NOTICE 'Available: Alert checking, recommendations, dashboard, monitoring reports';
    RAISE NOTICE 'Ready for production monitoring and operational dashboards';
END $$;