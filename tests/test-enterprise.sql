-- pgGit Enterprise Features Tests
-- Tests branching, merging, and advanced features
-- Requires core pgGit installation

\echo '============================================'
\echo 'pgGit Enterprise Tests'
\echo '============================================'
\echo ''

-- Test 1: Branching functionality
\echo '1. Testing branching functionality...'
DO $$
DECLARE
    v_branch_count INTEGER;
BEGIN
    -- Check branches table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'branches') THEN
        RAISE EXCEPTION 'FAIL: pgGit.branches table missing';
    END IF;
    
    -- Create a test branch
    INSERT INTO pggit.branches (name, parent_branch_id, created_by)
    VALUES ('test-enterprise-branch', (SELECT id FROM pggit.branches WHERE name = 'main'), 'test-user')
    ON CONFLICT (name) DO NOTHING;
    
    -- Count branches
    SELECT COUNT(*) INTO v_branch_count FROM pggit.branches WHERE status = 'ACTIVE';
    IF v_branch_count > 0 THEN
        RAISE NOTICE 'PASS: Branch management works (% active branches)', v_branch_count;
    ELSE
        RAISE WARNING 'WARN: No active branches found';
    END IF;
    
    -- Cleanup
    DELETE FROM pggit.branches WHERE name = 'test-enterprise-branch';
END;
$$;

-- Test 2: Size management
\echo ''
\echo '2. Testing size management features...'
DO $$
DECLARE
    v_size_info RECORD;
BEGIN
    -- Test database size overview
    SELECT * INTO v_size_info FROM pggit.database_size_overview LIMIT 1;
    IF v_size_info IS NOT NULL THEN
        RAISE NOTICE 'PASS: Database size overview works';
    ELSE
        RAISE WARNING 'WARN: No size information available';
    END IF;
    
    -- Test pruning recommendations
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_pruning_recommendations' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'PASS: Pruning recommendations function exists';
    ELSE
        RAISE WARNING 'WARN: Pruning recommendations not available';
    END IF;
END;
$$;

-- Test 3: Performance optimizations
\echo ''
\echo '3. Testing performance features...'
DO $$
BEGIN
    -- Check for performance-related indexes
    IF EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE schemaname = 'pggit' 
        AND tablename = 'objects'
        AND indexname LIKE '%object_name%'
    ) THEN
        RAISE NOTICE 'PASS: Performance indexes exist';
    ELSE
        RAISE WARNING 'WARN: Performance indexes may be missing';
    END IF;
    
    -- Check for partitioning support
    IF EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'create_history_partitions' 
        AND pronamespace = 'pggit'::regnamespace
    ) THEN
        RAISE NOTICE 'PASS: Partitioning support available';
    ELSE
        RAISE NOTICE 'INFO: Partitioning not configured';
    END IF;
END;
$$;

-- Test 4: Complex schema handling
\echo ''
\echo '4. Testing complex schema handling...'
DO $$
DECLARE
    v_object_count INTEGER;
BEGIN
    -- Create complex schema
    CREATE SCHEMA IF NOT EXISTS test_enterprise;
    
    CREATE TABLE IF NOT EXISTS test_enterprise.customers (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(100) UNIQUE
    );
    
    CREATE TABLE IF NOT EXISTS test_enterprise.orders (
        id SERIAL PRIMARY KEY,
        customer_id INTEGER REFERENCES test_enterprise.customers(id),
        order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        total_amount DECIMAL(10,2)
    );
    
    CREATE INDEX IF NOT EXISTS idx_orders_customer 
    ON test_enterprise.orders(customer_id);
    
    -- Track objects
    PERFORM pggit.ensure_object('TABLE'::pggit.object_type, 'test_enterprise', 'customers');
    PERFORM pggit.ensure_object('TABLE'::pggit.object_type, 'test_enterprise', 'orders');
    
    -- Count tracked objects
    SELECT COUNT(*) INTO v_object_count 
    FROM pggit.objects 
    WHERE schema_name = 'test_enterprise';
    
    IF v_object_count >= 2 THEN
        RAISE NOTICE 'PASS: Complex schema tracking works (% objects)', v_object_count;
    ELSE
        RAISE WARNING 'WARN: Not all objects tracked';
    END IF;
    
    -- Cleanup
    DROP SCHEMA test_enterprise CASCADE;
END;
$$;

-- Test 5: Migration compatibility
\echo ''
\echo '5. Testing migration compatibility...'
DO $$
DECLARE
    v_migration_tools TEXT[] := ARRAY['flyway', 'liquibase', 'rails', 'django', 'alembic'];
    v_tool TEXT;
BEGIN
    -- Check if migration pattern tables exist
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'migration_patterns') THEN
        FOREACH v_tool IN ARRAY v_migration_tools
        LOOP
            INSERT INTO pggit.migration_patterns (
                pattern_type, 
                source_tool, 
                pattern_sql, 
                pggit_template
            ) VALUES (
                'create_table',
                v_tool,
                'CREATE TABLE test (id INT)',
                'pggit.ensure_object(''TABLE'', ''public'', ''test'')'
            ) ON CONFLICT DO NOTHING;
        END LOOP;
        RAISE NOTICE 'PASS: Migration compatibility framework ready';
    ELSE
        RAISE NOTICE 'INFO: Migration patterns table not found (AI module may not be loaded)';
    END IF;
END;
$$;

-- Summary
\echo ''
\echo '============================================'
\echo 'Enterprise Tests Complete'
\echo '============================================'
\echo ''
\echo 'Run with: psql -d your_database -f tests/test-enterprise.sql'