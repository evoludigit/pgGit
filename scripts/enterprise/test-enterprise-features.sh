#!/bin/bash
# Test All Enterprise Features

set -e

echo "🏢 Testing pggit Enterprise Features..."
echo "======================================"

# Test with local PostgreSQL
psql -d postgres << 'EOF'
-- Enterprise Features Test Suite
\echo '🏢 Testing Enterprise Features...\n'

DROP EXTENSION IF EXISTS pggit CASCADE;
CREATE EXTENSION pggit CASCADE;

-- Load all enterprise features
\echo '📦 Loading Enterprise Modules...'
\i sql/050_cicd_integration.sql
\i sql/051_enterprise_auth_rbac.sql
\i sql/052_compliance_reporting.sql

-- Test 1: CI/CD Integration
\echo '\n🚀 Test 1: CI/CD Pipeline Integration'
\echo '======================================'

-- Create a deployment pipeline
SELECT deployment_id, status, message 
FROM pggit.cli_deploy('main', 'development', '{"deployed_by": "test_user"}');

-- Show pipeline stages
SELECT ps.stage_name, ps.stage_order, ps.status
FROM pggit.pipeline_stages ps
JOIN pggit.deployments d ON ps.deployment_id = d.deployment_id
WHERE d.created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute'
ORDER BY ps.stage_order;

-- Generate CI/CD configs
\echo '\n📄 Jenkins Pipeline Config (first 500 chars):'
SELECT left(pggit.generate_cicd_config('jenkins'), 500) || '...' as jenkins_config;

\echo '\n📄 GitHub Actions Config (first 500 chars):'
SELECT left(pggit.generate_cicd_config('github'), 500) || '...' as github_config;

-- Test 2: Authentication & RBAC
\echo '\n🔐 Test 2: Enterprise Authentication & RBAC'
\echo '==========================================='

-- Create test users
SELECT * FROM pggit.create_user('alice', 'alice@company.com', 'SecurePass123!', 'Alice Admin');
SELECT * FROM pggit.create_user('bob', 'bob@company.com', 'SecurePass456!', 'Bob Developer');

-- Test authentication
SELECT authenticated, user_id, message, array_length(permissions, 1) as permission_count
FROM pggit.authenticate_user('alice', 'SecurePass123!');

-- Grant roles
SELECT pggit.grant_role(
    (SELECT id FROM pggit.users WHERE username = 'alice'), 
    'admin'
);
SELECT pggit.grant_role(
    (SELECT id FROM pggit.users WHERE username = 'bob'), 
    'developer'
);

-- Check permissions
WITH users AS (
    SELECT id, username FROM pggit.users WHERE username IN ('alice', 'bob')
)
SELECT 
    u.username,
    pggit.check_permission(u.id, 'branch.create') as can_create_branch,
    pggit.check_permission(u.id, 'deployment.approve') as can_approve,
    pggit.check_permission(u.id, 'config.write') as can_modify_config
FROM users u
ORDER BY u.username;

-- Show user permissions summary
\echo '\n👥 User Permissions Summary:'
SELECT 
    username,
    string_agg(DISTINCT role_name, ', ') as roles,
    COUNT(DISTINCT permission) as total_permissions
FROM pggit.user_permissions
GROUP BY username
ORDER BY username;

-- Test 3: Compliance Reporting
\echo '\n📋 Test 3: Compliance Reporting System'
\echo '======================================'

-- Auto-classify data
SELECT * FROM pggit.auto_classify_data() LIMIT 5;

-- Run compliance checks
\echo '\n✅ SOX Compliance Check:'
SELECT control_id, control_name, status, left(details, 60) || '...' as details
FROM pggit.check_sox_compliance()
ORDER BY control_id;

\echo '\n✅ HIPAA Compliance Check:'
SELECT control_id, control_name, status, left(details, 60) || '...' as details
FROM pggit.check_hipaa_compliance()
ORDER BY control_id;

\echo '\n✅ GDPR Compliance Check:'
SELECT control_id, control_name, status, left(details, 60) || '...' as details
FROM pggit.check_gdpr_compliance()
ORDER BY control_id;

-- Generate compliance report summary
\echo '\n📊 Compliance Report Summary:'
WITH report AS (
    SELECT pggit.generate_compliance_report('SOX', 
        CURRENT_DATE - INTERVAL '30 days', 
        CURRENT_DATE, 
        'json')::jsonb as data
)
SELECT 
    data->>'framework' as framework,
    data->'period'->>'start_date' as period_start,
    data->'period'->>'end_date' as period_end,
    data->'summary'->>'total_controls' as total_controls,
    data->'summary'->>'passed' as passed,
    data->'summary'->>'failed' as failed,
    data->'summary'->>'warnings' as warnings
FROM report;

-- Test 4: Enterprise Integration Demo
\echo '\n🎯 Test 4: Enterprise Integration Features'
\echo '========================================='

-- Simulate LDAP authentication
SELECT * FROM pggit.authenticate_ldap('john.doe', 'ldap_password');

-- Create API token
SELECT 
    left(token, 20) || '...' as token_preview,
    token_id,
    expires_at
FROM pggit.create_api_token(
    (SELECT id FROM pggit.users WHERE username = 'alice'),
    'CI/CD Token',
    ARRAY['deployment.create', 'deployment.execute'],
    90
);

-- Show security audit log
\echo '\n🔍 Recent Security Audit Events:'
SELECT 
    to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') as timestamp,
    COALESCE(u.username, 'anonymous') as user,
    action,
    success,
    COALESCE(resource, '-') as resource
FROM pggit.security_audit_log sal
LEFT JOIN pggit.users u ON sal.user_id = u.id
WHERE sal.created_at > CURRENT_TIMESTAMP - INTERVAL '10 minutes'
ORDER BY sal.created_at DESC
LIMIT 10;

-- Test 5: Comprehensive Demo Results
\echo '\n📈 Test 5: Run All Demo Functions'
\echo '================================='

\echo '\n🚀 CI/CD Demo:'
SELECT * FROM pggit.demo_cicd_pipeline();

\echo '\n🔐 Auth/RBAC Demo:'
SELECT * FROM pggit.demo_auth_rbac();

\echo '\n📋 Compliance Demo:'
SELECT * FROM pggit.demo_compliance_reporting();

-- Summary Statistics
\echo '\n📊 Enterprise Features Summary:'
\echo '=============================='
WITH stats AS (
    SELECT 
        (SELECT COUNT(*) FROM pggit.deployment_configs) as deployment_configs,
        (SELECT COUNT(*) FROM pggit.users) as total_users,
        (SELECT COUNT(*) FROM pggit.roles) as total_roles,
        (SELECT COUNT(*) FROM pggit.compliance_frameworks) as compliance_frameworks,
        (SELECT COUNT(*) FROM pggit.data_classifications) as classified_columns,
        (SELECT COUNT(*) FROM pggit.security_audit_log) as audit_events
)
SELECT 
    'Deployment Configurations' as feature,
    deployment_configs as count
FROM stats
UNION ALL
SELECT 'Users', total_users FROM stats
UNION ALL
SELECT 'Roles', total_roles FROM stats
UNION ALL
SELECT 'Compliance Frameworks', compliance_frameworks FROM stats
UNION ALL
SELECT 'Classified Data Columns', classified_columns FROM stats
UNION ALL
SELECT 'Security Audit Events', audit_events FROM stats
ORDER BY feature;

\echo '\n✅ All Enterprise Features Tests Complete!'
\echo '========================================='
EOF

echo "✨ Enterprise features test completed successfully!"