-- File: benchmarks/baseline.sql
-- pgGit Performance Baseline Benchmark

-- This benchmark establishes performance baselines for pgGit operations
-- Run this after installation to establish starting performance metrics

\timing on

-- ============================================
-- SETUP: Create test schema and data
-- ============================================

CREATE SCHEMA IF NOT EXISTS benchmark;
SET search_path TO benchmark, public;

-- Create test tables of various sizes
CREATE TABLE small_table (id SERIAL PRIMARY KEY, data TEXT);
CREATE TABLE medium_table (id SERIAL PRIMARY KEY, data TEXT);
CREATE TABLE large_table (id SERIAL PRIMARY KEY, data TEXT);

-- Populate with test data
INSERT INTO small_table (data)
SELECT 'Small table test data ' || generate_series(1, 100);

INSERT INTO medium_table (data)
SELECT 'Medium table test data ' || generate_series(1, 10000);

INSERT INTO large_table (data)
SELECT 'Large table test data ' || generate_series(1, 100000);

-- ============================================
-- BENCHMARK 1: DDL Tracking Performance
-- ============================================

-- Test 1.1: Small table operations
\echo '=== Test 1.1: Small table DDL operations ==='

-- Measure DDL tracking on small table
SELECT clock_timestamp() as start_time;
CREATE INDEX idx_small_data ON benchmark.small_table (data);
SELECT clock_timestamp() as end_time;

-- Verify tracking
SELECT COUNT(*) as tracked_operations FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 minute';

-- Test 1.2: Medium table operations
\echo '=== Test 1.2: Medium table DDL operations ==='

SELECT clock_timestamp() as start_time;
CREATE INDEX idx_medium_data ON benchmark.medium_table (data);
SELECT clock_timestamp() as end_time;

SELECT COUNT(*) as tracked_operations FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 minute';

-- Test 1.3: Large table operations
\echo '=== Test 1.3: Large table DDL operations ==='

SELECT clock_timestamp() as start_time;
CREATE INDEX idx_large_data ON benchmark.large_table (data);
SELECT clock_timestamp() as end_time;

SELECT COUNT(*) as tracked_operations FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 minute';

-- ============================================
-- BENCHMARK 2: Query Performance
-- ============================================

-- Test 2.1: Object lookup performance
\echo '=== Test 2.1: Object lookup queries ==='

-- Measure time for object existence queries
SELECT clock_timestamp() as start_time;

SELECT COUNT(*) FROM pggit.objects
WHERE object_name LIKE 'benchmark.%';

SELECT COUNT(*) FROM pggit.objects
WHERE object_type = 'table' AND schema_name = 'benchmark';

SELECT clock_timestamp() as end_time;

-- Test 2.2: History query performance
\echo '=== Test 2.2: History query performance ==='

SELECT clock_timestamp() as start_time;

-- Recent changes
SELECT COUNT(*) FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 hour';

-- Changes by type
SELECT change_type, COUNT(*) FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY change_type;

-- Object-specific history
SELECT COUNT(*) FROM pggit.get_history('benchmark.small_table');

SELECT clock_timestamp() as end_time;

-- ============================================
-- BENCHMARK 3: System Resource Usage
-- ============================================

-- Test 3.1: Memory and cache statistics
\echo '=== Test 3.1: System resource usage ==='

-- Check cache hit ratios
SELECT * FROM pggit.cache_hit_ratio();

-- Check index usage
SELECT * FROM pggit.check_index_usage();

-- Connection statistics
SELECT * FROM pggit.connection_stats();

-- ============================================
-- BENCHMARK 4: Concurrent Operations
-- ============================================

-- Test 4.1: Concurrent DDL operations
\echo '=== Test 4.2: Concurrent DDL operations ==='

-- Note: This would typically be run from a separate script
-- to simulate concurrent users

-- ============================================
-- CLEANUP: Remove test data
-- ============================================

\echo '=== Cleanup: Removing test data ==='

DROP SCHEMA benchmark CASCADE;

-- ============================================
-- REPORT: Performance Summary
-- ============================================

\echo '=== Performance Report ==='

-- Overall statistics
SELECT
    'Total objects tracked' as metric,
    COUNT(*) as value
FROM pggit.objects

UNION ALL

SELECT
    'Total history entries' as metric,
    COUNT(*) as value
FROM pggit.history

UNION ALL

SELECT
    'Database size' as metric,
    pg_size_pretty(pg_database_size(current_database())) as value

UNION ALL

SELECT
    'pgGit schema size' as metric,
    pg_size_pretty(pg_total_relation_size('pggit', 'pggit')) as value;

-- Performance metrics
SELECT * FROM pggit.analyze_slow_queries(100);

\echo '=== Baseline benchmark complete ==='
\echo 'Use this output as a reference for future performance comparisons'