-- Test suite for pgGit CQRS Support
-- Tests Command Query Responsibility Segregation tracking features

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

-- Setup CQRS architecture
CREATE SCHEMA command;
CREATE SCHEMA command_staging;
CREATE SCHEMA query;
CREATE SCHEMA query_cache;
CREATE SCHEMA reference;

\echo 'Testing CQRS Support...'

-- Test 1: Basic CQRS change tracking
\echo '  Test 1: Basic CQRS change tracking'
DO $$
DECLARE
    v_changeset_id uuid;
    change pggit.cqrs_change;
BEGIN
    -- Define a CQRS change
    change.description := 'Add user status field';
    change.version := '1.0.0';
    change.command_operations := ARRAY[
        'CREATE TABLE command.users (id serial PRIMARY KEY, name text)',
        'ALTER TABLE command.users ADD COLUMN status text DEFAULT ''active'''
    ];
    change.query_operations := ARRAY[
        'CREATE MATERIALIZED VIEW query.active_users AS SELECT * FROM command.users WHERE status = ''active'''
    ];
    
    -- Track the change
    v_changeset_id := pggit.track_cqrs_change(change, atomic => true);
    
    -- Verify changeset was created
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.cqrs_changesets cs WHERE cs.changeset_id = v_changeset_id),
        'CQRS changeset should be created'
    );
    
    -- Verify operations were tracked
    PERFORM test_assert(
        (SELECT COUNT(*) FROM pggit.cqrs_operations co WHERE co.changeset_id = v_changeset_id) = 3,
        'All CQRS operations should be tracked'
    );
    
    -- Check changeset status
    PERFORM test_assert(
        (SELECT status FROM pggit.cqrs_changesets WHERE changeset_id = v_changeset_id) = 'completed',
        'CQRS changeset should be completed successfully'
    );
    
    -- Verify objects were created
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM command.users),
        'Command side table should be created'
    );
    
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pg_matviews WHERE schemaname = 'query' AND matviewname = 'active_users'),
        'Query side materialized view should be created'
    );
END $$;

-- Test 2: CQRS change with deployment mode
\echo '  Test 2: CQRS change with deployment mode'
DO $$
DECLARE
    deployment_id uuid;
    v_changeset_id uuid;
    change pggit.cqrs_change;
    commit_count_before int;
    commit_count_after int;
BEGIN
    -- Get current commit count
    SELECT COUNT(*) INTO commit_count_before FROM pggit.commits;
    
    -- Start deployment
    deployment_id := pggit.begin_deployment('CQRS Feature Release', auto_commit => true);
    
    -- Track multiple CQRS changes
    change.description := 'Add order system';
    change.command_operations := ARRAY[
        'CREATE TABLE command.orders (id serial PRIMARY KEY, user_id int, total decimal)',
        'CREATE TABLE command.order_items (id serial PRIMARY KEY, order_id int, product text, quantity int)'
    ];
    change.query_operations := ARRAY[
        'CREATE MATERIALIZED VIEW query.order_summary AS SELECT user_id, COUNT(*) as order_count, SUM(total) as total_spent FROM command.orders GROUP BY user_id'
    ];
    
    v_changeset_id := pggit.track_cqrs_change(change, atomic => true);
    
    -- End deployment
    PERFORM pggit.end_deployment('CQRS changes deployed');
    
    -- Verify single commit was created
    SELECT COUNT(*) INTO commit_count_after FROM pggit.commits;
    PERFORM test_assert(
        commit_count_after = commit_count_before + 1,
        'CQRS changes in deployment mode should create single commit'
    );
END $$;

-- Test 3: Non-atomic CQRS execution
\echo '  Test 3: Non-atomic CQRS execution'
DO $$
DECLARE
    v_changeset_id uuid;
    change pggit.cqrs_change;
BEGIN
    -- Create change but don't execute
    change.description := 'Deferred CQRS change';
    change.command_operations := ARRAY[
        'CREATE TABLE command.products (id serial PRIMARY KEY, name text, price decimal)'
    ];
    change.query_operations := ARRAY[
        'CREATE VIEW query.product_list AS SELECT * FROM command.products'
    ];
    
    v_changeset_id := pggit.track_cqrs_change(change, atomic => false);
    
    -- Verify changeset is pending
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.cqrs_changesets 
               WHERE cs.changeset_id = v_changeset_id AND status = 'pending'),
        'Non-atomic changeset should be pending'
    );
    
    -- Execute manually
    PERFORM pggit.execute_cqrs_changeset(changeset_id);
    
    -- Verify execution
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pggit.cqrs_changesets 
               WHERE cs.changeset_id = v_changeset_id AND status = 'completed'),
        'Manually executed changeset should be completed'
    );
END $$;

-- Test 4: CQRS operation failure handling
\echo '  Test 4: CQRS operation failure handling'
DO $$
DECLARE
    v_changeset_id uuid;
    change pggit.cqrs_change;
    error_caught boolean := false;
BEGIN
    -- Create change with failing operation
    change.description := 'Change with error';
    change.command_operations := ARRAY[
        'CREATE TABLE command.test_fail (id int)',
        'ALTER TABLE command.nonexistent ADD COLUMN fail text'  -- This will fail
    ];
    
    -- Try to execute
    BEGIN
        v_changeset_id := pggit.track_cqrs_change(change, atomic => true);
    EXCEPTION WHEN OTHERS THEN
        error_caught := true;
    END;
    
    PERFORM test_assert(error_caught, 'Failed CQRS change should raise exception');
    
    -- Verify rollback
    PERFORM test_assert(
        NOT EXISTS(SELECT 1 FROM command.test_fail),
        'Failed CQRS change should rollback all operations'
    );
END $$;

-- Test 5: Query side refresh helpers
\echo '  Test 5: Query side refresh helpers'
DO $$
BEGIN
    -- Create base data
    INSERT INTO command.users (name, status) VALUES ('Alice', 'active'), ('Bob', 'inactive');
    
    -- Refresh without tracking
    PERFORM pggit.refresh_query_side('query.active_users', skip_tracking => true);
    
    -- Verify data was refreshed
    PERFORM test_assert(
        (SELECT COUNT(*) FROM query.active_users) = 1,
        'Materialized view should be refreshed'
    );
    
    -- Verify no new version was created
    PERFORM test_assert(
        NOT EXISTS(SELECT 1 FROM pggit.version_history vh
                   JOIN pggit.versioned_objects vo ON vo.object_id = vh.object_id
                   WHERE vo.object_name = 'query.active_users'
                   AND vh.created_at > now() - interval '1 minute'),
        'Refresh with skip_tracking should not create version'
    );
END $$;

-- Test 6: CQRS dependency analysis
\echo '  Test 6: CQRS dependency analysis'
DO $$
DECLARE
    dep_count int;
BEGIN
    -- Create dependencies
    CREATE TABLE command.customers (id serial PRIMARY KEY, name text);
    CREATE MATERIALIZED VIEW query.customer_view AS SELECT * FROM command.customers;
    
    -- Analyze dependencies
    SELECT COUNT(*) INTO dep_count
    FROM pggit.analyze_cqrs_dependencies('command', 'query');
    
    PERFORM test_assert(
        dep_count > 0,
        'Should detect CQRS dependencies'
    );
END $$;

-- Test 7: CQRS changeset history
\echo '  Test 7: CQRS changeset history'
DO $$
DECLARE
    history_count int;
BEGIN
    -- Check history view
    SELECT COUNT(*) INTO history_count FROM pggit.cqrs_history;
    
    PERFORM test_assert(
        history_count > 0,
        'CQRS history should show changesets'
    );
    
    -- Verify history includes all changesets
    PERFORM test_assert(
        (SELECT COUNT(*) FROM pggit.cqrs_history WHERE status = 'completed') > 0,
        'History should show completed changesets'
    );
END $$;

-- Test 8: Complex CQRS pattern
\echo '  Test 8: Complex CQRS pattern'
DO $$
DECLARE
    v_changeset_id uuid;
    change pggit.cqrs_change;
BEGIN
    -- Simulate real-world CQRS update
    change.description := 'Add inventory tracking with eventual consistency';
    change.version := '2.0.0';
    change.command_operations := ARRAY[
        'CREATE TABLE command.inventory (id serial PRIMARY KEY, product_id int, quantity int, updated_at timestamptz DEFAULT now())',
        'CREATE TABLE command.inventory_events (id serial PRIMARY KEY, inventory_id int, event_type text, quantity_change int, occurred_at timestamptz DEFAULT now())',
        'CREATE INDEX idx_inventory_events_time ON command.inventory_events(occurred_at)'
    ];
    change.query_operations := ARRAY[
        'CREATE MATERIALIZED VIEW query.inventory_summary AS 
         SELECT product_id, SUM(quantity) as total_quantity, MAX(updated_at) as last_updated 
         FROM command.inventory GROUP BY product_id',
        'CREATE MATERIALIZED VIEW query.inventory_history AS 
         SELECT DATE(occurred_at) as date, COUNT(*) as event_count 
         FROM command.inventory_events GROUP BY DATE(occurred_at)'
    ];
    
    v_changeset_id := pggit.track_cqrs_change(change, atomic => true);
    
    -- Verify complex pattern was tracked
    PERFORM test_assert(
        (SELECT command_ops_count + query_ops_count 
         FROM pggit.cqrs_history 
         WHERE cs.changeset_id = v_changeset_id) = 5,
        'Complex CQRS pattern should track all operations'
    );
END $$;

-- Test 9: CQRS with reference data
\echo '  Test 9: CQRS with reference data'
DO $$
DECLARE
    change pggit.cqrs_change;
BEGIN
    -- Reference data that both sides use
    CREATE TABLE reference.countries (code char(2) PRIMARY KEY, name text);
    INSERT INTO reference.countries VALUES ('US', 'United States'), ('UK', 'United Kingdom');
    
    -- CQRS change using reference
    change.description := 'Add location tracking';
    change.command_operations := ARRAY[
        'ALTER TABLE command.users ADD COLUMN country_code char(2) REFERENCES reference.countries(code)'
    ];
    change.query_operations := ARRAY[
        'CREATE VIEW query.users_with_country AS 
         SELECT u.*, c.name as country_name 
         FROM command.users u 
         LEFT JOIN reference.countries c ON u.country_code = c.code'
    ];
    
    PERFORM pggit.track_cqrs_change(change, atomic => true);
    
    -- Verify cross-schema references work
    PERFORM test_assert(
        EXISTS(SELECT 1 FROM pg_views WHERE schemaname = 'query' AND viewname = 'users_with_country'),
        'CQRS should handle reference schema correctly'
    );
END $$;

-- Test 10: CQRS version tracking
\echo '  Test 10: CQRS version tracking'
DO $$
DECLARE
    v1_count int;
    v2_count int;
BEGIN
    -- Count versions
    SELECT COUNT(*) INTO v1_count 
    FROM pggit.cqrs_changesets 
    WHERE version LIKE '1.%';
    
    SELECT COUNT(*) INTO v2_count 
    FROM pggit.cqrs_changesets 
    WHERE version LIKE '2.%';
    
    PERFORM test_assert(
        v1_count > 0 AND v2_count > 0,
        'CQRS changesets should track versions'
    );
END $$;

-- Cleanup
DROP SCHEMA command CASCADE;
DROP SCHEMA command_staging CASCADE;
DROP SCHEMA query CASCADE;
DROP SCHEMA query_cache CASCADE;
DROP SCHEMA reference CASCADE;

\echo 'CQRS Support Tests: PASSED'

ROLLBACK;