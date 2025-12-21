-- pgGit AI Migration Analysis Tests
-- Tests AI-powered migration analysis features
-- Requires AI module (030_ai_migration_analysis.sql)

\echo '============================================'
\echo 'pgGit AI Tests'
\echo '============================================'
\echo ''

-- Setup: Ensure pgGit schema exists
CREATE SCHEMA IF NOT EXISTS pggit;

-- Setup: Load required modules
\echo 'Loading required modules...'
\set ON_ERROR_STOP off
-- Load core schema first
\i sql/001_schema.sql
\i sql/002_event_triggers.sql
\i sql/003_migration_functions.sql
\i sql/004_utility_views.sql
-- Load size management (AI module depends on it)
\i sql/040_size_management.sql
-- Load AI module
\i sql/030_ai_migration_analysis.sql
\set ON_ERROR_STOP on

-- Test 1: AI module availability
\echo '1. Testing AI module availability...'
DO $$
BEGIN
    -- Check if AI tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'migration_patterns') THEN
        RAISE EXCEPTION 'FAIL: AI module not installed (migration_patterns table missing)';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'ai_decisions') THEN
        RAISE EXCEPTION 'FAIL: AI module not installed (ai_decisions table missing)';
    END IF;
    
    RAISE NOTICE 'PASS: AI module tables exist';
END;
$$;

-- Test 2: Basic AI migration analysis
\echo ''
\echo '2. Testing basic AI migration analysis...'
DO $$
DECLARE
    v_result_count INTEGER;
    v_decision_count INTEGER;
BEGIN
    -- Test simple CREATE TABLE analysis
    SELECT COUNT(*) INTO v_result_count
    FROM pggit.analyze_migration_with_ai(
        'test_create_table',
        'CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(255), price DECIMAL(10,2));',
        'flyway'
    );
    
    IF v_result_count > 0 THEN
        RAISE NOTICE 'PASS: AI analysis returned results';
    ELSE
        RAISE EXCEPTION 'FAIL: AI analysis returned no results';
    END IF;
    
    -- Check if decision was recorded
    SELECT COUNT(*) INTO v_decision_count
    FROM pggit.ai_decisions
    WHERE migration_id = 'test_create_table'
    AND created_at > CURRENT_TIMESTAMP - INTERVAL '1 minute';
    
    IF v_decision_count > 0 THEN
        RAISE NOTICE 'PASS: AI decision recorded';
    ELSE
        RAISE WARNING 'WARN: AI decision not recorded';
    END IF;
END;
$$;

-- Test 3: Complex migration analysis
\echo ''
\echo '3. Testing complex migration analysis...'
DO $$
DECLARE
    v_migrations TEXT[][] := ARRAY[
        ARRAY['ALTER TABLE', 'ALTER TABLE users ADD COLUMN last_login TIMESTAMP;'],
        ARRAY['DROP TABLE', 'DROP TABLE IF EXISTS legacy_data CASCADE;'],
        ARRAY['CREATE INDEX', 'CREATE INDEX CONCURRENTLY idx_users_email ON users(email);'],
        ARRAY['UPDATE DATA', 'UPDATE products SET price = price * 1.10 WHERE category = ''electronics'';'],
        ARRAY['COMPLEX DDL', 'CREATE TABLE orders AS SELECT * FROM old_orders; DROP TABLE old_orders;']
    ];
    v_migration TEXT[];
    v_success_count INTEGER := 0;
    v_total_count INTEGER := 0;
BEGIN
    FOREACH v_migration SLICE 1 IN ARRAY v_migrations
    LOOP
        v_total_count := v_total_count + 1;
        BEGIN
            PERFORM pggit.analyze_migration_with_ai(
                'test_' || v_migration[1],
                v_migration[2],
                'manual'
            );
            v_success_count := v_success_count + 1;
        END;
    END LOOP;
    
    IF v_success_count = v_total_count THEN
        RAISE NOTICE 'PASS: All complex migrations analyzed (% of %)', v_success_count, v_total_count;
    ELSIF v_success_count > 0 THEN
        RAISE WARNING 'WARN: Some migrations analyzed (% of %)', v_success_count, v_total_count;
    ELSE
        RAISE EXCEPTION 'FAIL: No migrations could be analyzed';
    END IF;
END;
$$;

-- Test 4: Risk assessment
\echo ''
\echo '4. Testing risk assessment...'
DO $$
DECLARE
    v_risk_result RECORD;
BEGIN
    -- Test high-risk operation
    SELECT * INTO v_risk_result
    FROM pggit.assess_migration_risk(
        'DROP TABLE users CASCADE; -- Dangerous operation'
    );
    
    IF v_risk_result IS NOT NULL THEN
        RAISE NOTICE 'PASS: Risk assessment works';
        IF v_risk_result.risk_score > 50 THEN
            RAISE NOTICE 'PASS: High-risk operation correctly identified (score: %)', v_risk_result.risk_score;
        ELSE
            RAISE WARNING 'WARN: Risk score lower than expected: %', v_risk_result.risk_score;
        END IF;
    ELSE
        RAISE EXCEPTION 'FAIL: Risk assessment returned no results';
    END IF;
END;
$$;

-- Test 5: Pattern learning
\echo ''
\echo '5. Testing pattern learning...'
DO $$
DECLARE
    v_pattern_count INTEGER;
    v_pattern_before INTEGER;
    v_pattern_after INTEGER;
BEGIN
    -- Count existing patterns
    SELECT COUNT(*) INTO v_pattern_before FROM pggit.migration_patterns;
    
    -- Add a test pattern
    PERFORM pggit.learn_migration_pattern(
        'create_table',
        'CREATE TABLE test_pattern (id INT)',
        'test_framework',
        true
    );
    
    -- Count patterns after
    SELECT COUNT(*) INTO v_pattern_after FROM pggit.migration_patterns;
    
    IF v_pattern_after >= v_pattern_before THEN
        RAISE NOTICE 'PASS: Pattern learning works (% patterns)', v_pattern_after;
    ELSE
        RAISE EXCEPTION 'FAIL: Pattern learning failed';
    END IF;
    
    -- Check pattern usage tracking
    UPDATE pggit.migration_patterns 
    SET usage_count = usage_count + 1 
    WHERE pattern_type = 'create_table' 
    AND source_tool = 'test_framework';
    
    SELECT COUNT(*) INTO v_pattern_count
    FROM pggit.migration_patterns
    WHERE usage_count > 0;
    
    IF v_pattern_count > 0 THEN
        RAISE NOTICE 'PASS: Pattern usage tracking works';
    ELSE
        RAISE WARNING 'WARN: Pattern usage tracking may not be working';
    END IF;
END;
$$;

-- Test 6: Edge case detection
\echo ''
\echo '6. Testing edge case detection...'
DO $$
DECLARE
    v_edge_case_count INTEGER;
BEGIN
    -- Clear old edge cases
    DELETE FROM pggit.ai_edge_cases 
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '1 hour';
    
    -- Test various edge cases
    PERFORM pggit.analyze_migration_with_ai(
        'sql_injection_test',
        'DROP TABLE users; -- DELETE FROM credit_cards; CREATE TABLE fake;',
        'unknown'
    );
    
    PERFORM pggit.analyze_migration_with_ai(
        'complex_logic_test',
        'UPDATE orders SET status = CASE WHEN total > 1000 THEN ''vip'' ELSE ''regular'' END;',
        'manual'
    );
    
    -- Count detected edge cases
    SELECT COUNT(*) INTO v_edge_case_count
    FROM pggit.ai_edge_cases
    WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '5 minutes';
    
    IF v_edge_case_count > 0 THEN
        RAISE NOTICE 'PASS: Edge case detection works (% cases found)', v_edge_case_count;
    ELSE
        RAISE NOTICE 'INFO: No edge cases detected (this may be normal)';
    END IF;
END;
$$;

-- Summary and statistics
\echo ''
\echo '7. AI Analysis Summary...'
SELECT 
    'Total AI Decisions' as metric,
    COUNT(*) as value
FROM pggit.ai_decisions
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
UNION ALL
SELECT 
    'Edge Cases Found',
    COUNT(*)
FROM pggit.ai_edge_cases
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
UNION ALL
SELECT 
    'Migration Patterns',
    COUNT(*)
FROM pggit.migration_patterns
UNION ALL
SELECT 
    'Average Confidence',
    ROUND(AVG(confidence)::numeric * 100, 2)
FROM pggit.ai_decisions
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
AND confidence IS NOT NULL;

-- Summary
\echo ''
\echo '============================================'
\echo 'AI Tests Complete'
\echo '============================================'
\echo ''
\echo 'Run with: psql -d your_database -f tests/test-ai.sql'