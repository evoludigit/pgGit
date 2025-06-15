#!/bin/bash
# Test Zero-Downtime Deployment Strategy in Podman

set -e

echo "🚀 Testing pggit Zero-Downtime Deployment Strategy..."
echo "=================================================="

# Create test SQL
cat > /tmp/test_zero_downtime.sql << 'EOF'
-- Test Zero-Downtime Deployment Strategy
\echo '🔍 Testing Zero-Downtime Deployment Strategy...'

-- Ensure extension is installed
DROP EXTENSION IF EXISTS pggit CASCADE;
CREATE EXTENSION pggit CASCADE;

-- Load zero-downtime deployment functions
\i /pggit/sql/041_zero_downtime_deployment.sql

-- Test 1: Shadow table requirement analysis
\echo '\n🔍 Test 1: Shadow Table Requirement Analysis'
SELECT * FROM pggit.analyze_shadow_table_requirement(
    'ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(500);'
);

-- Test 2: Blue-green feasibility check
\echo '\n🔵 Test 2: Blue-Green Feasibility Check'
SELECT * FROM pggit.check_blue_green_feasibility('main', 'feature/upgrade');

-- Test 3: Pre-deployment validations
\echo '\n✅ Test 3: Pre-Deployment Validations'
SELECT * FROM pggit.generate_pre_deployment_validations(
    E'ALTER TABLE users ADD COLUMN status VARCHAR(50) NOT NULL;\n' ||
    E'CREATE INDEX idx_users_status ON users(status);\n' ||
    E'ALTER TABLE users DROP COLUMN old_field;',
    'production'
);

-- Test 4: Deployment timeline calculation
\echo '\n⏱️  Test 4: Deployment Timeline'
SELECT * FROM pggit.calculate_deployment_timeline(
    'ALTER TABLE users ALTER COLUMN email TYPE VARCHAR(500);',
    'shadow_table',
    10.5  -- 10.5 GB database
);

-- Test 5: Complete zero-downtime strategy
\echo '\n🚀 Test 5: Complete Zero-Downtime Strategy Analysis'
SELECT 
    deployment_strategy,
    shadow_table_required,
    blue_green_feasible,
    estimated_total_time_minutes,
    array_length(pre_deployment_validations, 1) as validation_count,
    jsonb_array_length(deployment_phases) as phase_count,
    rollback_plan,
    risk_assessment
FROM pggit.zero_downtime_strategy('main', 'feature/new-schema');

-- Test 6: Demo various scenarios
\echo '\n📊 Test 6: Demo Various Deployment Scenarios'
SELECT * FROM pggit.demo_zero_downtime_deployment();

-- Test 7: Shadow table creation (simulation)
\echo '\n👻 Test 7: Shadow Table Creation Simulation'
-- Create a test table first
CREATE TABLE IF NOT EXISTS test_users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some test data
INSERT INTO test_users (email) 
SELECT 'user' || i || '@example.com'
FROM generate_series(1, 10) i;

-- Create shadow table
SELECT pggit.create_shadow_table(
    'test_users',
    '(id INTEGER PRIMARY KEY, email VARCHAR(500), created_at TIMESTAMP, migrated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)'
);

-- Verify shadow table and triggers exist
\echo '\n🔍 Verifying shadow table setup:'
SELECT 
    original_table,
    shadow_table,
    sync_strategy,
    created_at
FROM pggit.shadow_tables
ORDER BY created_at DESC
LIMIT 1;

-- Test deployment strategy selection
\echo '\n🎯 Test 8: Strategy Selection for Different Operations'
WITH operations AS (
    SELECT unnest(ARRAY[
        'CREATE INDEX CONCURRENTLY idx_test ON users(email);',
        'ALTER TABLE users ADD COLUMN phone VARCHAR(20);',
        'ALTER TABLE users ALTER COLUMN email TYPE TEXT;',
        'DROP TABLE old_logs CASCADE;',
        'UPDATE users SET status = ''active'' WHERE status IS NULL;'
    ]) AS sql
)
SELECT 
    sql,
    (pggit.zero_downtime_strategy('main', 'feature/test')).deployment_strategy as strategy,
    (pggit.zero_downtime_strategy('main', 'feature/test')).risk_assessment as risk
FROM operations;

-- Show deployment history summary
\echo '\n📈 Deployment Strategy Summary:'
SELECT 
    strategy_name,
    complexity_level,
    average_duration_minutes,
    success_rate_percent,
    description
FROM pggit.deployment_strategies
ORDER BY success_rate_percent DESC;

\echo '\n✅ Zero-Downtime Deployment Strategy Tests Complete!'
EOF

# Run test in Podman
echo "🐳 Starting PostgreSQL 17 container..."
podman run --rm -d \
    --name pggit-zero-downtime-test \
    -e POSTGRES_PASSWORD=postgres \
    -v $(pwd):/pggit:ro \
    -v /tmp/test_zero_downtime.sql:/test_zero_downtime.sql:ro \
    postgres:17

# Wait for PostgreSQL
echo "⏳ Waiting for PostgreSQL to start..."
sleep 5

# Install dependencies
echo "📦 Installing build dependencies..."
podman exec pggit-zero-downtime-test bash -c "
    apt-get update -qq && \
    apt-get install -y -qq postgresql-server-dev-17 make gcc > /dev/null 2>&1
"

# Build and install extension
echo "🔨 Building pggit extension..."
podman exec -w /pggit pggit-zero-downtime-test make clean
podman exec -w /pggit pggit-zero-downtime-test make
podman exec -w /pggit pggit-zero-downtime-test make install

# Run tests
echo -e "\n🧪 Running Zero-Downtime Deployment Tests...\n"
podman exec -u postgres pggit-zero-downtime-test psql -f /test_zero_downtime.sql

# Cleanup
echo -e "\n🧹 Cleaning up..."
podman stop pggit-zero-downtime-test
rm -f /tmp/test_zero_downtime.sql

echo -e "\n✨ Zero-Downtime Deployment Test Complete!"