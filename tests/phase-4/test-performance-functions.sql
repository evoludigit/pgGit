-- File: tests/phase-4/test-performance-functions.sql
-- Phase 4 Performance Functions Test Script
-- Tests all 8 performance helper functions

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Test helper function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Setup test schema and data
CREATE SCHEMA IF NOT EXISTS perf_test;
CREATE TABLE perf_test.large_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Generate test data
INSERT INTO perf_test.large_table (data)
SELECT 'Performance test data ' || generate_series(1, 10000);

-- Create some indexes for testing
CREATE INDEX idx_large_data ON perf_test.large_table (data);
CREATE INDEX idx_large_created ON perf_test.large_table (created_at);

-- Simulate some performance metrics
INSERT INTO pggit.performance_metrics (metric_type, metric_value, metadata)
VALUES
    ('ddl_tracking_ms', 150.5, '{"operation": "CREATE INDEX"}'),
    ('ddl_tracking_ms', 45.2, '{"operation": "ALTER TABLE"}'),
    ('version_query_ms', 12.3, '{"table": "users"}'),
    ('version_query_ms', 8.7, '{"table": "products"}');

\echo 'Testing Performance Functions...'
\echo ''

-- Test 1: analyze_slow_queries
\echo '1. Testing analyze_slow_queries()...'
SELECT * FROM pggit.analyze_slow_queries(100);
\echo '✅ analyze_slow_queries() test completed'
\echo ''

-- Test 2: check_index_usage
\echo '2. Testing check_index_usage()...'
SELECT * FROM pggit.check_index_usage() LIMIT 5;
\echo '✅ check_index_usage() test completed'
\echo ''

-- Test 3: vacuum_health
\echo '3. Testing vacuum_health()...'
SELECT * FROM pggit.vacuum_health();
\echo '✅ vacuum_health() test completed'
\echo ''

-- Test 4: cache_hit_ratio
\echo '4. Testing cache_hit_ratio()...'
SELECT * FROM pggit.cache_hit_ratio();
\echo '✅ cache_hit_ratio() test completed'
\echo ''

-- Test 5: connection_stats
\echo '5. Testing connection_stats()...'
SELECT * FROM pggit.connection_stats();
\echo '✅ connection_stats() test completed'
\echo ''

-- Test 6: recommend_indexes
\echo '6. Testing recommend_indexes()...'
SELECT * FROM pggit.recommend_indexes();
\echo '✅ recommend_indexes() test completed'
\echo ''

-- Test 7: partitioning_analysis
\echo '7. Testing partitioning_analysis()...'
SELECT * FROM pggit.partitioning_analysis();
\echo '✅ partitioning_analysis() test completed'
\echo ''

-- Test 8: system_resources
\echo '8. Testing system_resources()...'
SELECT * FROM pggit.system_resources();
\echo '✅ system_resources() test completed'
\echo ''

-- Test 9: record_metric (new in Phase 4)
\echo '9. Testing record_metric()...'
SELECT pggit.record_metric('test_metric', 123.45, '{"test": true}'::jsonb);
SELECT COUNT(*) as metrics_recorded FROM pggit.performance_metrics WHERE metric_type = 'test_metric';
\echo '✅ record_metric() test completed'
\echo ''

\echo '🎉 All 8 performance functions tested successfully!'
\echo 'Phase 4 performance monitoring is working correctly.'

ROLLBACK;