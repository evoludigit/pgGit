-- ============================================
-- pgGit v2: Useful Views for Developers
-- ============================================
-- Pre-built views for common queries and insights
-- Supports development workflows and monitoring
--
-- Week 4 Deliverable: 10+ views for:
-- - Development insights
-- - Activity tracking
-- - Data quality monitoring
-- - Quick status checks

-- ============================================
-- DEVELOPMENT INSIGHTS VIEWS
-- ============================================

-- View: Recent commits by author
CREATE OR REPLACE VIEW pggit_v0.recent_commits_by_author AS
SELECT
    author,
    COUNT(*) as commit_count,
    MAX(committed_at) as last_commit,
    MIN(committed_at) as first_commit,
    EXTRACT(DAY FROM MAX(committed_at) - MIN(committed_at))::INT as days_active
FROM pggit_v0.commit_graph
GROUP BY author
ORDER BY commit_count DESC, last_commit DESC;

COMMENT ON VIEW pggit_v0.recent_commits_by_author IS
'Developer activity summary: who made how many commits, when they were most/least active.';

-- View: Most changed objects
CREATE OR REPLACE VIEW pggit_v0.most_changed_objects AS
SELECT
    object_schema,
    object_name,
    COUNT(*) as change_count,
    MAX(committed_at) as last_changed,
    array_agg(DISTINCT change_type) as change_types
FROM pggit_audit.changes
JOIN pggit_v0.commit_graph ON commit_graph.commit_sha = changes.commit_sha
GROUP BY object_schema, object_name
ORDER BY change_count DESC;

COMMENT ON VIEW pggit_v0.most_changed_objects IS
'Objects with highest change frequency: useful for identifying volatile or frequently-updated schema elements.';

-- View: Branch comparison summary
CREATE OR REPLACE VIEW pggit_v0.branch_comparison AS
SELECT
    r.ref_name as branch_name,
    r.commit_sha as head_sha,
    cg.author as head_author,
    cg.committed_at as head_commit_time,
    (SELECT COUNT(*) FROM pggit_v0.commit_graph
     WHERE committed_at <= cg.committed_at) as total_commits_to_head,
    cg.message as head_message
FROM pggit_v0.refs r
JOIN pggit_v0.commit_graph cg ON cg.commit_sha = r.commit_sha
WHERE r.ref_type = 'branch'
ORDER BY cg.committed_at DESC;

COMMENT ON VIEW pggit_v0.branch_comparison IS
'Quick overview of all branches: HEAD commit, author, timestamp, and message.';

-- ============================================
-- ACTIVITY TRACKING VIEWS
-- ============================================

-- View: Daily change summary
CREATE OR REPLACE VIEW pggit_v0.daily_change_summary AS
SELECT
    DATE(cg.committed_at) as change_date,
    COUNT(DISTINCT cg.commit_sha) as commits,
    COUNT(DISTINCT c.change_id) as changes,
    COUNT(DISTINCT cg.author) as contributors,
    array_agg(DISTINCT c.change_type) as change_types,
    ROUND(COUNT(DISTINCT c.change_id)::NUMERIC /
          NULLIF(COUNT(DISTINCT cg.commit_sha), 0), 2) as avg_changes_per_commit
FROM pggit_v0.commit_graph cg
LEFT JOIN pggit_audit.changes c ON c.commit_sha = cg.commit_sha
GROUP BY DATE(cg.committed_at)
ORDER BY change_date DESC;

COMMENT ON VIEW pggit_v0.daily_change_summary IS
'Daily activity metrics: commits, changes, contributors, and change distribution by day.';

-- View: Schema growth history
CREATE OR REPLACE VIEW pggit_v0.schema_growth_history AS
WITH commit_objects AS (
    SELECT
        cg.commit_sha,
        cg.committed_at,
        COUNT(DISTINCT (te.path)) as object_count
    FROM pggit_v0.commit_graph cg
    LEFT JOIN pggit_v0.tree_entries te ON te.tree_sha = cg.tree_sha
    GROUP BY cg.commit_sha, cg.committed_at
)
SELECT
    commit_sha,
    committed_at,
    object_count,
    LAG(object_count) OVER (ORDER BY committed_at) as previous_count,
    object_count - LAG(object_count) OVER (ORDER BY committed_at) as object_change,
    ROUND(100.0 * (object_count - LAG(object_count) OVER (ORDER BY committed_at)) /
        NULLIF(LAG(object_count) OVER (ORDER BY committed_at), 0), 2) as pct_change
FROM commit_objects
ORDER BY committed_at DESC;

COMMENT ON VIEW pggit_v0.schema_growth_history IS
'Track schema size over time: object count per commit with growth metrics and percentage changes.';

-- View: Author activity timeline
CREATE OR REPLACE VIEW pggit_v0.author_activity AS
SELECT
    cg.author,
    DATE(cg.committed_at) as activity_date,
    COUNT(*) as commits,
    COUNT(DISTINCT c.object_schema) as schemas_touched,
    COUNT(DISTINCT c.object_name) as objects_modified,
    array_agg(DISTINCT c.object_schema) as schemas,
    string_agg(DISTINCT c.change_type, ', ') as operations
FROM pggit_v0.commit_graph cg
LEFT JOIN pggit_audit.changes c ON c.commit_sha = cg.commit_sha
GROUP BY cg.author, DATE(cg.committed_at)
ORDER BY cg.author, activity_date DESC;

COMMENT ON VIEW pggit_v0.author_activity IS
'Track who changed what: author activity by date with schemas and objects modified.';

-- ============================================
-- DATA QUALITY & AUDIT VIEWS
-- ============================================

-- View: Commits without messages
CREATE OR REPLACE VIEW pggit_v0.commits_without_message AS
SELECT
    commit_sha,
    author,
    committed_at,
    COALESCE(message, '(no message)') as message_status
FROM pggit_v0.commit_graph
WHERE message IS NULL OR TRIM(message) = ''
ORDER BY committed_at DESC;

COMMENT ON VIEW pggit_v0.commits_without_message IS
'Data quality check: find commits missing or empty messages for better documentation practices.';

-- View: Orphaned objects (not referenced in any commit)
CREATE OR REPLACE VIEW pggit_v0.orphaned_objects AS
SELECT DISTINCT
    o.sha,
    o.type,
    o.size,
    o.created_at,
    'Unreferenced in tree entries' as reason
FROM pggit_v0.objects o
LEFT JOIN pggit_v0.tree_entries te ON te.object_sha = o.sha
WHERE te.object_sha IS NULL
ORDER BY o.created_at DESC;

COMMENT ON VIEW pggit_v0.orphaned_objects IS
'Data integrity check: objects not referenced in any tree (potential cleanup candidates).';

-- View: Large commits (affecting many objects)
CREATE OR REPLACE VIEW pggit_v0.large_commits AS
SELECT
    cg.commit_sha,
    cg.author,
    cg.committed_at,
    cg.message,
    COUNT(DISTINCT c.change_id) as change_count,
    COUNT(DISTINCT c.object_schema) as schemas_affected,
    array_agg(DISTINCT c.change_type) as change_types,
    ROUND(SUM(
        CASE
            WHEN c.old_definition IS NULL THEN 0
            ELSE LENGTH(c.old_definition)
        END +
        CASE
            WHEN c.new_definition IS NULL THEN 0
            ELSE LENGTH(c.new_definition)
        END
    )::NUMERIC / 1024, 2) as total_definition_size_kb
FROM pggit_v0.commit_graph cg
LEFT JOIN pggit_audit.changes c ON c.commit_sha = cg.commit_sha
GROUP BY cg.commit_sha, cg.author, cg.committed_at, cg.message
HAVING COUNT(DISTINCT c.change_id) > 5
ORDER BY change_count DESC;

COMMENT ON VIEW pggit_v0.large_commits IS
'Find large commits affecting many objects: useful for identifying big refactoring work.';

-- ============================================
-- STATUS & QUICK REFERENCE VIEWS
-- ============================================

-- View: Current HEAD information
CREATE OR REPLACE VIEW pggit_v0.current_head_info AS
SELECT
    cg.commit_sha as head_sha,
    cg.author,
    cg.committed_at,
    cg.message,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - cg.committed_at))::INT as days_since_head,
    (SELECT COUNT(*) FROM pggit_v0.tree_entries WHERE tree_sha = cg.tree_sha) as object_count
FROM pggit_v0.commit_graph cg
ORDER BY cg.committed_at DESC
LIMIT 1;

COMMENT ON VIEW pggit_v0.current_head_info IS
'Quick snapshot: current HEAD commit details and schema object count.';

-- View: Branch status summary
CREATE OR REPLACE VIEW pggit_v0.branch_status_summary AS
SELECT
    'Branches' as metric,
    COUNT(*)::TEXT as value
FROM pggit_v0.refs
WHERE ref_type = 'branch'
UNION ALL
SELECT
    'Tags' as metric,
    COUNT(*)::TEXT as value
FROM pggit_v0.refs
WHERE ref_type = 'tag'
UNION ALL
SELECT
    'Total Commits' as metric,
    COUNT(*)::TEXT as value
FROM pggit_v0.commit_graph
UNION ALL
SELECT
    'Total Objects' as metric,
    COUNT(*)::TEXT as value
FROM pggit_v0.objects
UNION ALL
SELECT
    'Total Changes Tracked' as metric,
    COUNT(*)::TEXT as value
FROM pggit_audit.changes;

COMMENT ON VIEW pggit_v0.branch_status_summary IS
'Overall system status summary: branches, tags, commits, objects, and tracked changes.';

-- View: Recent activity summary
CREATE OR REPLACE VIEW pggit_v0.recent_activity_summary AS
SELECT
    COUNT(DISTINCT CASE WHEN cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
                        THEN cg.commit_sha END) as commits_last_24h,
    COUNT(DISTINCT CASE WHEN cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
                        THEN cg.commit_sha END) as commits_last_7d,
    COUNT(DISTINCT CASE WHEN cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
                        THEN cg.author END) as authors_last_24h,
    COUNT(DISTINCT CASE WHEN c.committed_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
                        THEN c.change_id END) as changes_last_24h,
    (SELECT MAX(committed_at) FROM pggit_v0.commit_graph) as last_activity
FROM pggit_v0.commit_graph cg
LEFT JOIN pggit_audit.changes c ON c.commit_sha = cg.commit_sha;

COMMENT ON VIEW pggit_v0.recent_activity_summary IS
'Activity in recent time windows: commits, authors, and changes in last 24h and 7 days.';

-- ============================================
-- METADATA
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit v2 Views loaded successfully';
    RAISE NOTICE 'Available: 11 views for insights, activity tracking, and data quality monitoring';
    RAISE NOTICE 'Ready for developer use';
END $$;
