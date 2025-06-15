-- pggit Local AI Demo
-- Demonstrate real AI-powered migrations using local LLMs

-- ==================================================
-- Prerequisites Check
-- ==================================================

-- Check if AI extensions are available
DO $$
BEGIN
    -- Check for required extensions
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'plpython3u') THEN
        RAISE NOTICE 'Missing plpython3u extension - install postgresql-plpython3';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
        RAISE NOTICE 'Missing vector extension - install pgvector';
    END IF;
    
    -- Check for AI functions
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'call_local_llm') THEN
        RAISE NOTICE 'Missing AI functions - run sql/033_local_llm_integration.sql';
    END IF;
    
    RAISE NOTICE 'AI prerequisite check complete';
END $$;

-- ==================================================
-- Demo 1: Single Migration Analysis
-- ==================================================

-- Analyze a Flyway migration
SELECT 
    '=== Single Migration Analysis ===' as demo_section,
    '' as spacer;

SELECT * FROM pggit.analyze_migration_with_llm(
    'CREATE TABLE customers (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );',
    'flyway',
    'V1__create_customers.sql'
);

-- Analyze a Rails migration
SELECT * FROM pggit.analyze_migration_with_llm(
    'class AddLoyaltyPointsToCustomers < ActiveRecord::Migration[7.0]
      def change
        add_column :customers, :loyalty_points, :integer, default: 0
        add_index :customers, :loyalty_points
      end
    end',
    'rails',
    '20240315_add_loyalty_points_to_customers.rb'
);

-- Analyze a complex Liquibase changeset
SELECT * FROM pggit.analyze_migration_with_llm(
    '<changeSet id="47" author="developer">
        <createTable tableName="orders">
            <column name="id" type="BIGSERIAL">
                <constraints primaryKey="true"/>
            </column>
            <column name="customer_id" type="BIGINT">
                <constraints nullable="false"/>
            </column>
            <column name="total_amount" type="DECIMAL(10,2)"/>
            <column name="status" type="VARCHAR(20)" defaultValue="pending"/>
        </createTable>
        <addForeignKeyConstraint
            baseTableName="orders"
            baseColumnNames="customer_id"
            referencedTableName="customers"
            referencedColumnNames="id"/>
    </changeSet>',
    'liquibase',
    'changelog-47-create-orders.xml'
);

-- ==================================================
-- Demo 2: Batch Migration Processing
-- ==================================================

SELECT 
    '=== Batch Migration Processing ===' as demo_section,
    '' as spacer;

-- Process a batch of typical e-commerce migrations
SELECT * FROM pggit.ai_migrate_batch(
    '[
        {
            "name": "V1__create_users.sql",
            "content": "CREATE TABLE users (id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE, password_hash VARCHAR(255));"
        },
        {
            "name": "V2__create_products.sql", 
            "content": "CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(255), price DECIMAL(10,2), category_id INT);"
        },
        {
            "name": "V3__add_user_profiles.sql",
            "content": "ALTER TABLE users ADD COLUMN first_name VARCHAR(100), ADD COLUMN last_name VARCHAR(100), ADD COLUMN phone VARCHAR(20);"
        },
        {
            "name": "V4__create_orders.sql",
            "content": "CREATE TABLE orders (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id), total DECIMAL(10,2), status VARCHAR(20) DEFAULT ''pending'');"
        },
        {
            "name": "V5__add_indexes.sql",
            "content": "CREATE INDEX idx_users_email ON users(email); CREATE INDEX idx_orders_user_id ON orders(user_id); CREATE INDEX idx_orders_status ON orders(status);"
        }
    ]'::jsonb,
    'flyway',
    'main'
);

-- ==================================================
-- Demo 3: AI Pattern Recognition
-- ==================================================

SELECT 
    '=== AI Pattern Recognition ===' as demo_section,
    '' as spacer;

-- Show how AI recognizes different patterns
WITH test_migrations AS (
    SELECT 
        'Add Column' as migration_type,
        'ALTER TABLE products ADD COLUMN description TEXT;' as sql_content,
        'flyway' as source_tool
    UNION ALL
    SELECT 
        'Create Index',
        'CREATE INDEX idx_products_category ON products(category_id);',
        'flyway'
    UNION ALL
    SELECT
        'Rename Column',
        'ALTER TABLE users RENAME COLUMN email TO email_address;',
        'generic'
    UNION ALL
    SELECT
        'Complex Logic',
        'CREATE OR REPLACE FUNCTION update_user_stats() RETURNS TRIGGER AS $$ BEGIN UPDATE user_stats SET login_count = login_count + 1 WHERE user_id = NEW.id; RETURN NEW; END; $$ LANGUAGE plpgsql;',
        'generic'
)
SELECT 
    tm.migration_type,
    ai.pattern_type,
    ai.confidence,
    ai.risk_assessment,
    CASE 
        WHEN ai.confidence >= 0.9 THEN 'AUTO-APPLY'
        WHEN ai.confidence >= 0.7 THEN 'REVIEW'
        ELSE 'MANUAL'
    END as recommended_action
FROM test_migrations tm
CROSS JOIN LATERAL pggit.analyze_migration_with_llm(
    tm.sql_content,
    tm.source_tool,
    tm.migration_type || '_test'
) ai;

-- ==================================================
-- Demo 4: Edge Case Detection
-- ==================================================

SELECT 
    '=== Edge Case Detection ===' as demo_section,
    '' as spacer;

-- Test with challenging migrations that should trigger manual review
SELECT * FROM pggit.analyze_migration_with_llm(
    '-- This migration has business logic embedded
    BEGIN;
    
    -- Add new column
    ALTER TABLE orders ADD COLUMN discount_applied BOOLEAN DEFAULT false;
    
    -- Complex business logic that AI should flag
    UPDATE orders 
    SET discount_applied = true,
        total = total * 0.9
    WHERE created_at > ''2024-01-01'' 
      AND customer_id IN (
          SELECT id FROM customers 
          WHERE loyalty_tier = ''gold'' 
            AND total_spent > 1000
      );
    
    -- Create audit trigger
    CREATE OR REPLACE FUNCTION audit_discount_changes() 
    RETURNS TRIGGER AS $$
    BEGIN
        IF OLD.discount_applied != NEW.discount_applied THEN
            INSERT INTO audit_log (table_name, operation, old_values, new_values)
            VALUES (''orders'', ''discount_change'', row_to_json(OLD), row_to_json(NEW));
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    
    CREATE TRIGGER orders_discount_audit
        AFTER UPDATE ON orders
        FOR EACH ROW
        EXECUTE FUNCTION audit_discount_changes();
    
    COMMIT;',
    'flyway',
    'V47__complex_discount_logic.sql'
);

-- Check what edge cases were detected
SELECT 
    case_type,
    risk_level,
    review_status,
    LEFT(ai_suggestion, 100) || '...' as ai_suggestion_preview
FROM pggit.ai_edge_cases
WHERE migration_id = 'V47__complex_discount_logic.sql';

-- ==================================================
-- Demo 5: Migration Optimization
-- ==================================================

SELECT 
    '=== Migration Optimization Detection ===' as demo_section,
    '' as spacer;

-- Test AI's ability to detect optimization opportunities
SELECT * FROM pggit.analyze_migration_with_llm(
    '-- Inefficient: Multiple ALTER statements
    ALTER TABLE users ADD COLUMN created_at TIMESTAMP;
    ALTER TABLE users ADD COLUMN updated_at TIMESTAMP;
    ALTER TABLE users ADD COLUMN last_login TIMESTAMP;
    
    -- Inefficient: Creating index after data load
    INSERT INTO users (email, created_at) 
    SELECT email, CURRENT_TIMESTAMP 
    FROM temp_users;
    
    CREATE INDEX idx_users_email ON users(email);
    CREATE INDEX idx_users_created_at ON users(created_at);',
    'flyway',
    'V23__inefficient_user_updates.sql'
);

-- ==================================================
-- Demo 6: Confidence Scoring Analysis
-- ==================================================

SELECT 
    '=== Confidence Scoring Analysis ===' as demo_section,
    '' as spacer;

-- Show confidence distribution across different migration types
WITH confidence_analysis AS (
    SELECT 
        migration_id,
        confidence,
        CASE 
            WHEN confidence >= 0.95 THEN 'Very High (≥95%)'
            WHEN confidence >= 0.9 THEN 'High (90-95%)'
            WHEN confidence >= 0.8 THEN 'Medium (80-90%)'
            WHEN confidence >= 0.7 THEN 'Low (70-80%)'
            ELSE 'Very Low (<70%)'
        END as confidence_category
    FROM pggit.ai_decisions
    WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
)
SELECT 
    confidence_category,
    COUNT(*) as migration_count,
    ROUND(AVG(confidence * 100), 1) as avg_confidence_pct,
    ROUND(MIN(confidence * 100), 1) as min_confidence_pct,
    ROUND(MAX(confidence * 100), 1) as max_confidence_pct
FROM confidence_analysis
GROUP BY confidence_category
ORDER BY AVG(confidence) DESC;

-- ==================================================
-- Demo 7: Performance Metrics
-- ==================================================

SELECT 
    '=== AI Performance Metrics ===' as demo_section,
    '' as spacer;

-- Show AI processing performance
SELECT 
    COUNT(*) as total_migrations_analyzed,
    ROUND(AVG(confidence * 100), 1) as avg_confidence_pct,
    ROUND(AVG(inference_time_ms), 0) as avg_inference_time_ms,
    ROUND(MAX(inference_time_ms), 0) as max_inference_time_ms,
    COUNT(*) FILTER (WHERE confidence >= 0.9) as high_confidence_count,
    COUNT(*) FILTER (WHERE confidence < 0.8) as needs_review_count,
    ROUND(
        (COUNT(*) FILTER (WHERE confidence >= 0.9))::DECIMAL / COUNT(*) * 100, 
        1
    ) as auto_approval_rate_pct
FROM pggit.ai_decisions
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- ==================================================
-- Demo 8: Human Override Tracking
-- ==================================================

SELECT 
    '=== Human Override Analysis ===' as demo_section,
    '' as spacer;

-- Show cases where humans overrode AI decisions
SELECT 
    migration_id,
    confidence,
    human_override,
    COALESCE(override_reason, 'No override') as override_reason,
    LEFT(ai_response, 50) || '...' as ai_response_preview
FROM pggit.ai_decisions
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
ORDER BY confidence DESC;

-- ==================================================
-- Demo 9: Pattern Learning
-- ==================================================

SELECT 
    '=== Pattern Learning Analytics ===' as demo_section,
    '' as spacer;

-- Show which patterns are most commonly used
SELECT 
    pattern_type,
    source_tool,
    semantic_meaning,
    usage_count,
    confidence_threshold
FROM pggit.migration_patterns
WHERE usage_count > 0
ORDER BY usage_count DESC;

-- ==================================================
-- Demo 10: Real-time AI Migration
-- ==================================================

SELECT 
    '=== Real-time AI Migration Demo ===' as demo_section,
    '' as spacer;

-- Simulate a complete migration workflow
DO $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_result RECORD;
BEGIN
    v_start_time := clock_timestamp();
    
    RAISE NOTICE 'Starting AI-powered migration simulation...';
    
    -- Simulate migrating from Flyway
    FOR v_result IN 
        SELECT * FROM pggit.ai_migrate_batch(
            '[
                {
                    "name": "V1__baseline.sql",
                    "content": "CREATE SCHEMA IF NOT EXISTS demo; CREATE TABLE demo.migrations_test (id SERIAL PRIMARY KEY, name VARCHAR(255));"
                }
            ]'::jsonb,
            'flyway',
            'demo_branch'
        )
    LOOP
        RAISE NOTICE 'Migration: %, Status: %, Confidence: %', 
            v_result.migration_name, 
            v_result.status, 
            v_result.confidence;
    END LOOP;
    
    v_end_time := clock_timestamp();
    
    RAISE NOTICE 'AI migration completed in % ms', 
        EXTRACT(EPOCH FROM v_end_time - v_start_time) * 1000;
END $$;

-- ==================================================
-- Summary Report
-- ==================================================

SELECT 
    '=== AI Migration Demo Summary ===' as demo_section,
    '' as spacer;

-- Final summary of AI capabilities demonstrated
SELECT 
    'AI Features Demonstrated' as category,
    COUNT(DISTINCT migration_id) as migrations_processed,
    ROUND(AVG(confidence * 100), 1) as avg_confidence_pct,
    COUNT(DISTINCT migration_id) FILTER (WHERE confidence >= 0.9) as auto_approved,
    COUNT(DISTINCT migration_id) FILTER (WHERE confidence < 0.8) as needs_review,
    ROUND(AVG(inference_time_ms), 0) as avg_processing_time_ms
FROM pggit.ai_decisions
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- Cleanup demo data
-- DROP SCHEMA IF EXISTS demo CASCADE;

COMMENT ON SCHEMA pggit IS 'pggit Local AI Demo completed - Real AI-powered migrations using local LLMs';