-- pggit Size Management Demo
-- Shows how AI-powered pruning recommendations help manage database growth

-- Setup: Create some test branches with varying activity
\echo 'Creating test branches to demonstrate size management...'

-- Create an old feature branch (will be marked for deletion)
SELECT pggit.create_branch('feature/old-experiment', 'main');
SELECT pggit.checkout('feature/old-experiment');

CREATE TABLE experiment_data (
    id SERIAL PRIMARY KEY,
    data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add some data
INSERT INTO experiment_data (data) 
SELECT jsonb_build_object('value', i, 'description', 'Test data ' || i)
FROM generate_series(1, 1000) i;

SELECT pggit.commit('Added experimental data table');

-- Simulate this branch being merged
UPDATE pggit.branches SET status = 'MERGED' WHERE name = 'feature/old-experiment';

-- Create an inactive branch (will be marked for archival)
SELECT pggit.create_branch('feature/abandoned-work', 'main');
SELECT pggit.checkout('feature/abandoned-work');

CREATE TABLE abandoned_feature (
    id BIGSERIAL PRIMARY KEY,
    large_data TEXT,
    metadata JSONB
);

-- Create large index
CREATE INDEX idx_abandoned_gin ON abandoned_feature USING GIN(metadata);

SELECT pggit.commit('Started abandoned feature');

-- Simulate inactivity by backdating the commit
UPDATE pggit.commits 
SET commit_date = CURRENT_TIMESTAMP - INTERVAL '200 days'
WHERE branch_id = (SELECT id FROM pggit.branches WHERE name = 'feature/abandoned-work');

-- Create an active branch (should be kept)
SELECT pggit.create_branch('feature/active-development', 'main');
SELECT pggit.checkout('feature/active-development');

CREATE TABLE active_feature (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100)
);

SELECT pggit.commit('Active development');

-- Return to main
SELECT pggit.checkout('main');

\echo ''
\echo '=== Database Size Overview ==='
SELECT * FROM pggit.database_size_overview;

\echo ''
\echo '=== Branch Size Metrics ==='
SELECT 
    branch_name,
    pg_size_pretty(total_size_bytes) as total_size,
    commit_count,
    last_commit_date,
    EXTRACT(DAY FROM CURRENT_TIMESTAMP - last_commit_date) as days_inactive
FROM pggit.update_branch_metrics()
ORDER BY total_size_bytes DESC;

\echo ''
\echo '=== Top Space Consumers ==='
SELECT * FROM pggit.top_space_consumers;

\echo ''
\echo '=== AI-Generated Pruning Recommendations ==='
SELECT * FROM pggit.generate_pruning_recommendations(
    p_size_threshold_mb := 0,  -- Low threshold for demo
    p_inactive_days := 30      -- 30 days for demo
);

\echo ''
\echo '=== Detailed Branch Analysis ==='
WITH branch_analysis AS (
    SELECT 
        name,
        pggit.analyze_branch_for_pruning(name) as analysis
    FROM pggit.branches
)
SELECT 
    name as branch,
    (analysis).recommendation,
    (analysis).reason,
    (analysis).confidence,
    pg_size_pretty((analysis).space_savings_bytes) as potential_savings,
    (analysis).risk_level,
    (analysis).priority
FROM branch_analysis
ORDER BY (analysis).priority DESC;

\echo ''
\echo '=== Migration Analysis with Size Impact ==='
SELECT * FROM pggit.analyze_migration_with_ai_enhanced(
    'large_table_migration',
    'CREATE TABLE large_events (
        id BIGSERIAL PRIMARY KEY,
        event_data JSONB NOT NULL,
        raw_payload TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX idx_events_data ON large_events USING GIN(event_data);
    CREATE INDEX idx_events_created ON large_events(created_at);',
    'demo'
);

\echo ''
\echo '=== Simulating Cleanup of Merged Branches (Dry Run) ==='
SELECT * FROM pggit.cleanup_merged_branches(p_dry_run := true);

\echo ''
\echo '=== Unreferenced Blobs ==='
SELECT 
    COUNT(*) as unreferenced_blob_count,
    pg_size_pretty(SUM(size_bytes)) as total_size
FROM pggit.find_unreferenced_blobs();

\echo ''
\echo '=== Running Maintenance (Simulation) ==='
-- This would actually clean things up if run
-- SELECT pggit.run_size_maintenance();

\echo ''
\echo 'Demo complete! Key takeaways:'
\echo '1. pggit tracks size metrics for all branches automatically'
\echo '2. AI analyzes branch activity and recommends pruning actions'
\echo '3. Different recommendation types: DELETE, ARCHIVE, COMPRESS, KEEP'
\echo '4. Risk levels and confidence scores guide decision making'
\echo '5. Migration analysis includes size impact predictions'
\echo '6. Automated maintenance can apply safe recommendations'
\echo ''
\echo 'To apply recommendations manually:'
\echo '  SELECT pggit.apply_pruning_recommendation(recommendation_id);'
\echo ''
\echo 'To run full maintenance:'
\echo '  SELECT pggit.run_size_maintenance();'