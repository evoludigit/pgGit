#!/bin/bash
# Full Cost Optimization Dashboard Test

set -e

echo "💰 Full Cost Optimization Dashboard Test..."
echo "=========================================="

# Test with local PostgreSQL
psql -d postgres << 'EOF'
-- Full Cost Optimization Test
\echo '💰 Testing Cost Optimization Dashboard with realistic data...'

DROP EXTENSION IF EXISTS pggit CASCADE;
CREATE EXTENSION pggit CASCADE;

-- Load cost optimization functions
\i sql/042_cost_optimization_dashboard.sql

-- Create realistic test tables
\echo '\n📊 Creating realistic test scenario...'

-- 1. Large JSONB table (simulating event logs)
DROP TABLE IF EXISTS production_events CASCADE;
CREATE TABLE production_events (
    id BIGSERIAL PRIMARY KEY,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    event_type VARCHAR(50),
    event_data JSONB,
    user_id INTEGER,
    session_id UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create unused indexes
CREATE INDEX idx_prod_events_user ON production_events(user_id);
CREATE INDEX idx_prod_events_session ON production_events(session_id);
CREATE INDEX idx_prod_events_type ON production_events(event_type);

-- Insert 100K events
INSERT INTO production_events (event_type, event_data, user_id, session_id)
SELECT 
    CASE (random() * 5)::INT 
        WHEN 0 THEN 'page_view'
        WHEN 1 THEN 'api_call'
        WHEN 2 THEN 'transaction'
        WHEN 3 THEN 'error'
        ELSE 'metric'
    END,
    jsonb_build_object(
        'timestamp', CURRENT_TIMESTAMP - (random() * INTERVAL '30 days'),
        'endpoint', '/api/v1/' || (ARRAY['users', 'products', 'orders', 'metrics'])[floor(random() * 4 + 1)],
        'response_time_ms', (random() * 1000)::INT,
        'status_code', (ARRAY[200, 201, 400, 404, 500])[floor(random() * 5 + 1)],
        'metadata', jsonb_build_object(
            'user_agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'ip_address', '10.0.0.' || (random() * 255)::INT,
            'country', (ARRAY['US', 'UK', 'DE', 'FR', 'JP'])[floor(random() * 5 + 1)],
            'payload', repeat('{"data": "example payload content"}', 10)::JSONB
        )
    ),
    (random() * 10000)::INT,
    gen_random_uuid()
FROM generate_series(1, 100000) i;

-- 2. Wide table with many columns (simulating user profiles)
DROP TABLE IF EXISTS user_profiles CASCADE;
CREATE TABLE user_profiles (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(50),
    address_line1 TEXT,
    address_line2 TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50),
    postal_code VARCHAR(20),
    preferences JSONB,
    settings JSONB,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    account_type VARCHAR(50),
    subscription_tier VARCHAR(50)
);

-- Insert user data
INSERT INTO user_profiles (email, first_name, last_name, preferences, settings, metadata)
SELECT 
    'user' || i || '@example.com',
    'FirstName' || i,
    'LastName' || i,
    jsonb_build_object('theme', 'dark', 'language', 'en', 'notifications', true),
    jsonb_build_object('privacy', 'public', 'two_factor', false),
    jsonb_build_object('signup_source', 'organic', 'cohort', '2024-Q1')
FROM generate_series(1, 50000) i;

-- 3. Table with dead tuples (simulating high-churn data)
DROP TABLE IF EXISTS session_tracking CASCADE;
CREATE TABLE session_tracking (
    id SERIAL PRIMARY KEY,
    session_id UUID,
    user_id INTEGER,
    last_activity TIMESTAMP,
    page_views INTEGER,
    duration_seconds INTEGER
);

-- Insert and update to create dead tuples
INSERT INTO session_tracking (session_id, user_id, last_activity, page_views, duration_seconds)
SELECT 
    gen_random_uuid(),
    (random() * 1000)::INT,
    CURRENT_TIMESTAMP - (random() * INTERVAL '7 days'),
    (random() * 50)::INT,
    (random() * 3600)::INT
FROM generate_series(1, 20000) i;

-- Create dead tuples by updating
UPDATE session_tracking SET page_views = page_views + 1 WHERE id % 3 = 0;
UPDATE session_tracking SET duration_seconds = duration_seconds + 100 WHERE id % 2 = 0;

-- Run analysis
\echo '\n🔍 Running Cost Optimization Analysis...'

-- 1. Compression analysis for all tables
\echo '\n📦 Compression Opportunities:'
SELECT 
    table_name,
    pg_size_pretty(current_storage_gb * 1024 * 1024 * 1024) as current_size,
    pg_size_pretty(projected_compressed_gb * 1024 * 1024 * 1024) as compressed_size,
    round(monthly_cost_savings_usd::numeric, 2) as monthly_savings_usd,
    compression_strategy,
    implementation_effort
FROM pggit.cost_optimization_analysis()
WHERE compression_strategy != 'None (Low benefit)'
ORDER BY monthly_cost_savings_usd DESC;

-- 2. All optimization opportunities
\echo '\n💡 All Optimization Opportunities:'
SELECT 
    optimization_type,
    COUNT(*) as opportunity_count,
    pg_size_pretty(SUM(current_size_gb * 1024 * 1024 * 1024)::BIGINT) as total_size,
    pg_size_pretty(SUM(potential_savings_gb * 1024 * 1024 * 1024)::BIGINT) as total_savings,
    round(SUM(potential_savings_usd)::numeric, 2) as annual_savings_usd
FROM pggit.identify_cost_optimizations(0.00001)
GROUP BY optimization_type
ORDER BY SUM(potential_savings_usd) DESC;

-- 3. Detailed recommendations
\echo '\n📋 Detailed Recommendations:'
SELECT 
    priority,
    category,
    recommendation,
    array_length(affected_objects, 1) as object_count,
    round(estimated_monthly_savings_usd::numeric, 2) as monthly_savings,
    implementation_time_hours as hours_to_implement,
    risk_level
FROM pggit.generate_cost_optimization_report()
ORDER BY priority;

-- 4. Specific table recommendations
\echo '\n🎯 Top 5 Tables to Optimize:'
SELECT 
    table_name,
    optimization_type,
    pg_size_pretty((current_size_gb * 1024 * 1024 * 1024)::BIGINT) as current_size,
    pg_size_pretty((potential_savings_gb * 1024 * 1024 * 1024)::BIGINT) as savings,
    recommendation
FROM pggit.identify_cost_optimizations(0.00001)
ORDER BY potential_savings_gb DESC
LIMIT 5;

-- 5. Partitioning script example
\echo '\n🔧 Example Partitioning Script:'
SELECT pggit.generate_partitioning_script('production_events', 'event_time', 'monthly');

-- 6. Cost summary
\echo '\n💰 Total Database Cost Analysis:'
SELECT 
    pg_size_pretty((database_size_gb * 1024 * 1024 * 1024)::BIGINT) as database_size,
    round(current_monthly_cost_usd::numeric, 2) as monthly_cost_usd,
    round(current_annual_cost_usd::numeric, 2) as annual_cost_usd,
    available_optimizations,
    round(potential_annual_savings_usd::numeric, 2) as potential_savings_usd,
    round(potential_savings_percent::numeric, 1) as savings_percent
FROM pggit.cost_summary;

-- 7. Cloud pricing comparison
\echo '\n☁️  Cost Across Cloud Providers:'
WITH db_size AS (
    SELECT pg_database_size(current_database()) / 1024.0 / 1024.0 / 1024.0 AS size_gb
)
SELECT 
    provider,
    storage_type,
    round((SELECT size_gb FROM db_size) * price_per_gb_month, 2) as monthly_cost,
    round((SELECT size_gb FROM db_size) * price_per_gb_month * 12, 2) as annual_cost
FROM pggit.cloud_pricing
WHERE storage_type IN ('gp3', 'pd-standard', 'standard-ssd')
ORDER BY provider, price_per_gb_month;

\echo '\n✅ Cost Optimization Full Test Complete!'
EOF

echo "✨ Full test completed successfully!"