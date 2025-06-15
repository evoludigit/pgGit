#!/bin/bash
# Viktor's Comprehensive Test Suite
# "I test everything, and I mean EVERYTHING"

set -e

echo "======================================"
echo "Viktor's Comprehensive pggit Test"
echo "======================================"
echo ""

# Test results tracking
PASSED=0
FAILED=0
WARNINGS=0

# Function to run test and check result
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    
    echo -n "Testing $test_name... "
    
    if result=$(eval "$test_command" 2>&1); then
        if echo "$result" | grep -q "$expected_pattern"; then
            echo "✅ PASSED"
            ((PASSED++))
        else
            echo "❌ FAILED - Expected pattern not found: $expected_pattern"
            echo "Result: $result" | head -3
            ((FAILED++))
        fi
    else
        echo "❌ FAILED - Command error or timeout"
        echo "Error: $result" | head -3
        ((FAILED++))
    fi
}

# Setup
echo "🔧 Setting up test environment..."
psql -d postgres -c "DROP EXTENSION IF EXISTS pggit CASCADE;" > /dev/null 2>&1
psql -d postgres -c "CREATE EXTENSION pggit CASCADE;" > /dev/null 2>&1

# Load all enterprise modules
echo "📦 Loading enterprise modules..."
for module in sql/030_ai_migration_analysis.sql \
              sql/040_enterprise_impact_analysis.sql \
              sql/041_zero_downtime_deployment.sql \
              sql/042_cost_optimization_dashboard.sql \
              sql/050_cicd_integration.sql \
              sql/051_enterprise_auth_rbac.sql \
              sql/052_compliance_reporting.sql \
              sql/053_compliance_fixes.sql; do
    if [ -f "$module" ]; then
        psql -d postgres -f "$module" > /dev/null 2>&1
    fi
done

echo ""
echo "🧪 Running Viktor's Test Suite..."
echo "================================="
echo ""

# Test 1: Core Git functionality  
run_test "Core: Version tracking setup" \
    "psql -d postgres -t -c \"SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'viktor_table'); SELECT object_name FROM pggit.get_version('viktor_table');\"" \
    "public.viktor_table"

run_test "Core: Migration generation" \
    "psql -d postgres -t -c \"SELECT length(pggit.generate_migration()) > 10;\"" \
    "t"

# Test 2: AI Migration Analysis
run_test "AI: Migration analysis" \
    "psql -d postgres -t -c \"SELECT (pggit.analyze_migration_with_ai('test', 'CREATE TABLE users (id INT);', 'manual')).confidence > 0.8;\"" \
    "t"

run_test "AI: Risk assessment" \
    "psql -d postgres -t -c \"SELECT (pggit.assess_migration_risk('DROP TABLE users;')).risk_score > 30;\"" \
    "t"

# Test 3: Enterprise Impact Analysis
run_test "Impact: Financial calculation" \
    "psql -d postgres -t -c \"SELECT (pggit.calculate_financial_impact(10, '{\\\"cost_per_minute_usd\\\": 1000}'::jsonb)) > 0;\"" \
    "t"

run_test "Impact: SLA assessment" \
    "psql -d postgres -t -c \"SELECT pggit.calculate_sla_impact(10, '{\\\"sla_percentage\\\": 99.9}'::jsonb) LIKE '%budget%';\"" \
    "t"

# Test 4: Zero-Downtime Deployment
run_test "Zero-DT: Shadow table analysis" \
    "psql -d postgres -t -c \"SELECT COUNT(*) FROM pggit.analyze_shadow_table_requirement('ALTER TABLE users ALTER COLUMN id TYPE BIGINT;') WHERE requires_shadow = true;\"" \
    "1"

run_test "Zero-DT: Strategy selection" \
    "psql -d postgres -t -c \"SELECT (pggit.zero_downtime_strategy('main', 'feature')).deployment_strategy IS NOT NULL;\"" \
    "t"

# Test 5: Cost Optimization
run_test "Cost: Compression analysis" \
    "psql -d postgres -t -c \"SELECT (pggit.analyze_table_compression('pg_class')).lz4_savings_percent > 0;\"" \
    "t"

run_test "Cost: Cloud pricing" \
    "psql -d postgres -t -c \"SELECT (pggit.calculate_storage_cost(1.0, 'aws', 'gp3')).monthly_storage_cost_usd > 0;\"" \
    "t"

# Test 6: CI/CD Integration
run_test "CI/CD: Jenkins config" \
    "psql -d postgres -t -c \"SELECT pggit.generate_cicd_config('jenkins') LIKE '%pipeline%';\"" \
    "t"

run_test "CI/CD: Deployment validation" \
    "psql -d postgres -t -c \"SELECT COUNT(*) FROM pggit.validate_deployment('main', 'development') WHERE status = 'pass';\"" \
    "[0-9]"

# Test 7: Authentication & RBAC
run_test "Auth: User creation" \
    "psql -d postgres -t -c \"SELECT (pggit.create_user('test_user', 'test@example.com', 'Pass123!', 'Test User')).created;\"" \
    "t"

run_test "Auth: Authentication" \
    "psql -d postgres -t -c \"SELECT (pggit.authenticate_user('test_user', 'Pass123!')).authenticated;\"" \
    "t"

run_test "Auth: Permission check" \
    "psql -d postgres -t -c \"SELECT pggit.check_permission(1, 'branch.create');\"" \
    "[tf]"

# Test 8: Compliance
run_test "Compliance: GDPR check" \
    "psql -d postgres -t -c \"SELECT COUNT(*) FROM pggit.check_gdpr_compliance() WHERE status IN ('PASS', 'WARN', 'FAIL');\"" \
    "4"

run_test "Compliance: Data classification" \
    "psql -d postgres -t -c \"SELECT COUNT(*) >= 0 FROM pggit.auto_classify_data();\"" \
    "t"

# Test 9: Performance
echo ""
echo "⚡ Performance Tests..."
start_time=$(date +%s%N)
psql -d postgres -c "SELECT pggit.analyze_migration_with_ai('perf', 'CREATE TABLE t (id INT);', 'test');" > /dev/null 2>&1
end_time=$(date +%s%N)
elapsed_ms=$(( ($end_time - $start_time) / 1000000 ))

if [ $elapsed_ms -lt 10 ]; then
    echo "✅ AI Analysis Performance: ${elapsed_ms}ms (< 10ms target)"
    ((PASSED++))
else
    echo "❌ AI Analysis Performance: ${elapsed_ms}ms (exceeds 10ms target)"
    ((FAILED++))
fi

# Test 10: Integration
echo ""
echo "🔗 Integration Tests..."

# Create a full workflow
if psql -d postgres > /dev/null 2>&1 << 'EOF'
-- Create user and grant role
SELECT pggit.create_user('int_user', 'int@test.com', 'IntTest123!', 'Integration User');
SELECT pggit.grant_role(
    (SELECT user_id FROM pggit.create_user('int_user2', 'int2@test.com', 'IntTest123!', 'Integration User 2')),
    'developer'
);

-- Create test table to track
CREATE TABLE integration_test (id SERIAL PRIMARY KEY, data JSONB);

-- Analyze a migration
SELECT pggit.analyze_migration_with_ai(
    'int_migration',
    'CREATE TABLE integration_test (id SERIAL PRIMARY KEY, data JSONB);',
    'manual'
);

-- Check impact
SELECT pggit.enterprise_migration_analysis(
    'CREATE TABLE integration_test (id SERIAL PRIMARY KEY, data JSONB);',
    '{"cost_per_minute_usd": 1000}'::jsonb
);

-- Generate CI/CD config
SELECT length(pggit.generate_cicd_config('github')) > 100;
EOF
then
    echo "✅ Integration workflow completed"
    ((PASSED++))
else
    echo "❌ Integration workflow failed"
    ((FAILED++))
fi

# Summary
echo ""
echo "======================================"
echo "Viktor's Test Results"
echo "======================================"
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"
echo "⚠️  Warnings: $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 Viktor's Verdict: ALL TESTS PASSED!"
    echo ""
    echo "\"Finally, software that actually works when I test it.\""
    echo "\"Still needs production validation, but this is acceptable.\""
    exit 0
else
    echo "😤 Viktor's Verdict: FIX YOUR BUGS!"
    echo ""
    echo "\"$FAILED tests failed. This is not production ready.\""
    echo "\"Come back when everything passes.\""
    exit 1
fi