#!/bin/bash
# Test pggit AI Migration Analysis using Podman
# 100% containerized, no local dependencies

set -e

echo "🤖 pggit AI Migration Analysis Test (Podman)"
echo "============================================"

# Configuration
CONTAINER_NAME="pggit-ai-test"
TEST_PORT="5435"

# Stop any existing container
podman stop $CONTAINER_NAME 2>/dev/null || true
podman rm $CONTAINER_NAME 2>/dev/null || true

echo "🐘 Starting PostgreSQL 17 container..."
podman run -d \
    --name $CONTAINER_NAME \
    -p $TEST_PORT:5432 \
    -e POSTGRES_PASSWORD=test123 \
    -e POSTGRES_DB=pggit_ai_test \
    postgres:17

echo "⏳ Waiting for PostgreSQL to start..."
for i in {1..30}; do
    if podman exec $CONTAINER_NAME pg_isready -U postgres > /dev/null 2>&1; then
        echo "✅ PostgreSQL is ready!"
        break
    fi
    sleep 1
done

echo ""
echo "🔧 Installing pggit with AI features..."

# Copy extension files
podman cp pggit.control $CONTAINER_NAME:/usr/share/postgresql/17/extension/
podman cp pggit--1.0.0.sql $CONTAINER_NAME:/usr/share/postgresql/17/extension/

# Create extension
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "CREATE EXTENSION pggit CASCADE;"

# Load AI analysis functions
podman cp sql/030_ai_migration_analysis.sql $CONTAINER_NAME:/tmp/
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -f /tmp/030_ai_migration_analysis.sql

echo ""
echo "🧪 Running AI Migration Analysis Tests..."
echo "========================================"

# Test 1: Analyze various migration patterns
echo "📋 Test 1: Migration Pattern Analysis"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    migration_name,
    (analysis_result->>'intent')::TEXT as intent,
    (analysis_result->>'confidence')::DECIMAL as confidence,
    (analysis_result->>'risk_level')::TEXT as risk,
    (analysis_result->>'risk_score')::INTEGER as score
FROM pggit.demo_ai_migration_analysis()
ORDER BY (analysis_result->>'risk_score')::INTEGER DESC;
"

# Test 2: Check AI decisions audit log
echo ""
echo "📊 Test 2: AI Decision Audit Log"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    migration_id,
    confidence,
    model_version,
    inference_time_ms
FROM pggit.ai_decisions
ORDER BY created_at DESC
LIMIT 5;
"

# Test 3: Edge cases that need review
echo ""
echo "🚨 Test 3: Edge Cases Detection"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    migration_id,
    case_type,
    risk_level,
    confidence,
    CASE 
        WHEN confidence < 0.6 THEN '🚫 Block'
        WHEN confidence < 0.8 THEN '⚠️  Review'
        ELSE '✅ Approve'
    END as action
FROM pggit.ai_edge_cases
WHERE review_status = 'PENDING'
ORDER BY confidence ASC;
"

# Test 4: Pattern learning
echo ""
echo "📚 Test 4: Migration Pattern Learning"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    pattern_type,
    source_tool,
    usage_count,
    confidence_threshold
FROM pggit.migration_patterns
WHERE usage_count > 0
ORDER BY usage_count DESC
LIMIT 10;
"

# Test 5: Complex migration analysis
echo ""
echo "🔬 Test 5: Complex Migration Analysis"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
WITH complex_migration AS (
    SELECT pggit.analyze_migration_with_ai(
        'complex_refactor.sql',
        'BEGIN;
         ALTER TABLE users RENAME TO users_old;
         CREATE TABLE users AS SELECT * FROM users_old WHERE active = true;
         ALTER TABLE users ADD PRIMARY KEY (id);
         CREATE INDEX idx_users_email ON users(email);
         UPDATE users SET updated_at = CURRENT_TIMESTAMP;
         DROP TABLE users_old CASCADE;
         COMMIT;',
        'manual'
    ) AS result
)
SELECT 
    'Complex Refactor' as migration,
    (result).intent,
    (result).confidence,
    (result).risk_level,
    (result).risk_score,
    (result).requires_downtime,
    (result).estimated_duration_seconds || ' seconds' as duration
FROM complex_migration;
"

# Test 6: Performance stats
echo ""
echo "⚡ Test 6: AI Performance Statistics"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    COUNT(*) as total_analyses,
    ROUND(AVG(confidence)::numeric, 2) as avg_confidence,
    ROUND(AVG(inference_time_ms)::numeric, 0) as avg_time_ms,
    MIN(inference_time_ms) as min_ms,
    MAX(inference_time_ms) as max_ms
FROM pggit.ai_decisions;
"

# Test 7: Risk distribution
echo ""
echo "📈 Test 7: Risk Distribution"
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -c "
SELECT 
    risk_level,
    COUNT(*) as count,
    ROUND(AVG(confidence)::numeric, 2) as avg_confidence,
    STRING_AGG(migration_id, ', ' ORDER BY confidence) as migrations
FROM pggit.ai_edge_cases
GROUP BY risk_level
ORDER BY 
    CASE risk_level 
        WHEN 'HIGH' THEN 1 
        WHEN 'MEDIUM' THEN 2 
        ELSE 3 
    END;
"

echo ""
echo "🎯 AI Analysis Summary"
echo "====================="
podman exec $CONTAINER_NAME psql -U postgres -d pggit_ai_test -t -c "
WITH stats AS (
    SELECT 
        COUNT(DISTINCT ad.migration_id) as migrations_analyzed,
        COUNT(DISTINCT ec.id) as edge_cases_found,
        COUNT(DISTINCT mp.id) as patterns_learned,
        AVG(ad.confidence) as avg_confidence
    FROM pggit.ai_decisions ad
    LEFT JOIN pggit.ai_edge_cases ec ON ad.migration_id = ec.migration_id
    CROSS JOIN pggit.migration_patterns mp
)
SELECT 
    '✅ Migrations analyzed: ' || migrations_analyzed || E'\n' ||
    '⚠️  Edge cases found: ' || edge_cases_found || E'\n' ||
    '📚 Patterns learned: ' || patterns_learned || E'\n' ||
    '🎯 Average confidence: ' || ROUND(avg_confidence::numeric * 100, 1) || '%'
FROM stats;
"

# Ask if user wants to keep container
echo ""
read -p "Keep container running for manual testing? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔄 Container $CONTAINER_NAME running on port $TEST_PORT"
    echo ""
    echo "Connect with:"
    echo "  psql -h localhost -p $TEST_PORT -U postgres -d pggit_ai_test"
    echo ""
    echo "Try these queries:"
    echo "  SELECT * FROM pggit.demo_ai_migration_analysis();"
    echo "  SELECT * FROM pggit.ai_analysis_summary;"
    echo "  SELECT * FROM pggit.pending_ai_reviews;"
    echo ""
    echo "Stop container:"
    echo "  podman stop $CONTAINER_NAME"
else
    echo "🛑 Stopping container..."
    podman stop $CONTAINER_NAME
    podman rm $CONTAINER_NAME
fi

echo ""
echo "✅ AI Migration Analysis test complete!"