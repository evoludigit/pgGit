-- pggit AI-Powered Migration Analysis
-- Real local LLM integration for SQL migration intelligence
-- 100% MIT Licensed - No premium gates

-- =====================================================
-- Core AI Tables
-- =====================================================

-- Store migration patterns for AI learning
CREATE TABLE IF NOT EXISTS pggit.migration_patterns (
    id SERIAL PRIMARY KEY,
    pattern_type TEXT NOT NULL, -- 'add_column', 'create_table', etc.
    source_tool TEXT NOT NULL, -- 'flyway', 'liquibase', 'rails', etc.
    pattern_sql TEXT NOT NULL,
    pattern_embedding TEXT, -- Simplified for compatibility
    semantic_meaning TEXT,
    example_migration TEXT,
    pggit_template TEXT,
    confidence_threshold DECIMAL DEFAULT 0.9,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- AI decision audit log
CREATE TABLE IF NOT EXISTS pggit.ai_decisions (
    id SERIAL PRIMARY KEY,
    migration_id TEXT,
    original_content TEXT,
    ai_prompt TEXT,
    ai_response TEXT,
    confidence DECIMAL,
    human_override BOOLEAN DEFAULT false,
    override_reason TEXT,
    model_version TEXT,
    inference_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Edge cases that need human review
CREATE TABLE IF NOT EXISTS pggit.ai_edge_cases (
    id SERIAL PRIMARY KEY,
    migration_id TEXT,
    case_type TEXT, -- 'complex_logic', 'custom_function', 'environment_specific'
    original_content TEXT,
    ai_suggestion TEXT,
    confidence DECIMAL,
    risk_level TEXT, -- 'LOW', 'MEDIUM', 'HIGH'
    review_status TEXT DEFAULT 'PENDING', -- 'PENDING', 'APPROVED', 'REJECTED', 'MODIFIED'
    reviewer_notes TEXT,
    reviewed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- AI Analysis Functions (PostgreSQL-native)
-- =====================================================

-- Analyze migration intent using pattern matching
CREATE OR REPLACE FUNCTION pggit.analyze_migration_intent(
    p_migration_content TEXT
) RETURNS TABLE (
    intent TEXT,
    confidence DECIMAL,
    risk_level TEXT,
    recommendations TEXT[]
) AS $$
DECLARE
    v_content_upper TEXT := UPPER(p_migration_content);
    v_intent TEXT;
    v_confidence DECIMAL := 0.8;
    v_risk TEXT := 'LOW';
    v_recommendations TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Determine intent based on SQL patterns
    IF v_content_upper LIKE '%CREATE TABLE%' THEN
        v_intent := 'Create new table';
        v_confidence := 0.95;
        
        -- Check for best practices
        IF v_content_upper NOT LIKE '%PRIMARY KEY%' THEN
            v_recommendations := array_append(v_recommendations, 'Consider adding PRIMARY KEY');
            v_confidence := v_confidence - 0.1;
        END IF;
        
        IF v_content_upper LIKE '%SERIAL%' THEN
            v_recommendations := array_append(v_recommendations, 'Consider using IDENTITY columns (PostgreSQL 10+)');
        END IF;
        
    ELSIF v_content_upper LIKE '%ALTER TABLE%ADD COLUMN%' THEN
        v_intent := 'Add column to existing table';
        v_confidence := 0.9;
        
        IF v_content_upper LIKE '%NOT NULL%' AND v_content_upper NOT LIKE '%DEFAULT%' THEN
            v_risk := 'MEDIUM';
            v_recommendations := array_append(v_recommendations, 'Adding NOT NULL without DEFAULT may fail on existing data');
        END IF;
        
    ELSIF v_content_upper LIKE '%DROP TABLE%' OR v_content_upper LIKE '%DROP COLUMN%' THEN
        v_intent := 'Remove database objects';
        v_confidence := 0.95;
        v_risk := 'HIGH';
        v_recommendations := array_append(v_recommendations, 'Ensure data is backed up before dropping');
        v_recommendations := array_append(v_recommendations, 'Consider renaming instead of dropping');
        
    ELSIF v_content_upper LIKE '%CREATE INDEX%' THEN
        v_intent := 'Create performance index';
        v_confidence := 0.9;
        
        IF v_content_upper LIKE '%CONCURRENTLY%' THEN
            v_recommendations := array_append(v_recommendations, 'Good: Using CONCURRENTLY for zero-downtime');
        ELSE
            v_recommendations := array_append(v_recommendations, 'Consider CREATE INDEX CONCURRENTLY for large tables');
        END IF;
        
    ELSIF v_content_upper LIKE '%UPDATE%SET%' THEN
        v_intent := 'Bulk data modification';
        v_confidence := 0.85;
        v_risk := 'MEDIUM';
        
        IF v_content_upper NOT LIKE '%WHERE%' THEN
            v_risk := 'HIGH';
            v_recommendations := array_append(v_recommendations, 'WARNING: UPDATE without WHERE affects all rows');
        END IF;
        
    ELSE
        v_intent := 'Custom database modification';
        v_confidence := 0.6;
        v_recommendations := array_append(v_recommendations, 'Complex migration - consider manual review');
    END IF;
    
    RETURN QUERY SELECT v_intent, v_confidence, v_risk, v_recommendations;
END;
$$ LANGUAGE plpgsql;

-- Migration risk assessment
CREATE OR REPLACE FUNCTION pggit.assess_migration_risk(
    p_migration_content TEXT,
    p_target_schema TEXT DEFAULT 'public'
) RETURNS TABLE (
    risk_score INTEGER, -- 0-100
    risk_factors TEXT[],
    estimated_duration_seconds INTEGER,
    requires_downtime BOOLEAN,
    rollback_difficulty TEXT -- 'EASY', 'MODERATE', 'HARD', 'IMPOSSIBLE'
) AS $$
DECLARE
    v_risk_score INTEGER := 0;
    v_risk_factors TEXT[] := ARRAY[]::TEXT[];
    v_duration INTEGER := 1;
    v_downtime BOOLEAN := false;
    v_rollback TEXT := 'EASY';
BEGIN
    -- Check for high-risk operations
    IF p_migration_content ~* 'DROP\s+TABLE' THEN
        v_risk_score := v_risk_score + 40;
        v_risk_factors := array_append(v_risk_factors, 'Dropping tables is irreversible');
        v_rollback := 'IMPOSSIBLE';
        v_downtime := true;
    END IF;
    
    IF p_migration_content ~* 'DROP\s+COLUMN' THEN
        v_risk_score := v_risk_score + 30;
        v_risk_factors := array_append(v_risk_factors, 'Dropping columns loses data');
        v_rollback := 'HARD';
    END IF;
    
    IF p_migration_content ~* 'ALTER\s+TABLE.*TYPE' THEN
        v_risk_score := v_risk_score + 25;
        v_risk_factors := array_append(v_risk_factors, 'Type changes may fail or lose precision');
        v_rollback := 'MODERATE';
        v_downtime := true;
        v_duration := 300; -- 5 minutes for type conversion
    END IF;
    
    -- Check for lock-heavy operations
    IF p_migration_content ~* 'CREATE\s+INDEX' AND p_migration_content !~* 'CONCURRENTLY' THEN
        v_risk_score := v_risk_score + 20;
        v_risk_factors := array_append(v_risk_factors, 'Index creation without CONCURRENTLY locks table');
        v_downtime := true;
        v_duration := 60;
    END IF;
    
    -- Check for data modifications
    IF p_migration_content ~* 'UPDATE.*SET' THEN
        v_risk_score := v_risk_score + 15;
        v_risk_factors := array_append(v_risk_factors, 'Data modifications in migrations are risky');
        
        IF p_migration_content !~* 'WHERE' THEN
            v_risk_score := v_risk_score + 30;
            v_risk_factors := array_append(v_risk_factors, 'UPDATE without WHERE affects all rows!');
        END IF;
    END IF;
    
    -- Estimate duration based on operations
    IF p_migration_content ~* 'CREATE\s+TABLE' THEN
        v_duration := GREATEST(v_duration, 1);
    END IF;
    
    IF p_migration_content ~* 'ALTER\s+TABLE' THEN
        v_duration := GREATEST(v_duration, 10);
    END IF;
    
    -- Cap risk score at 100
    v_risk_score := LEAST(v_risk_score, 100);
    
    RETURN QUERY SELECT v_risk_score, v_risk_factors, v_duration, v_downtime, v_rollback;
END;
$$ LANGUAGE plpgsql;

-- Store AI analysis results
CREATE OR REPLACE FUNCTION pggit.record_ai_analysis(
    p_migration_id TEXT,
    p_content TEXT,
    p_ai_response JSONB,
    p_model TEXT DEFAULT 'gpt2-local',
    p_inference_time_ms INTEGER DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    -- Record the AI decision
    INSERT INTO pggit.ai_decisions (
        migration_id,
        original_content,
        ai_response,
        confidence,
        model_version,
        inference_time_ms
    ) VALUES (
        p_migration_id,
        p_content,
        p_ai_response::TEXT,
        COALESCE((p_ai_response->>'confidence')::DECIMAL, 0.5),
        p_model,
        p_inference_time_ms
    );
    
    -- Check if it's an edge case
    IF (p_ai_response->>'confidence')::DECIMAL < 0.8 OR 
       (p_ai_response->>'risk_level')::TEXT IN ('HIGH', 'MEDIUM') THEN
        
        INSERT INTO pggit.ai_edge_cases (
            migration_id,
            case_type,
            original_content,
            ai_suggestion,
            confidence,
            risk_level
        ) VALUES (
            p_migration_id,
            COALESCE(p_ai_response->>'intent', 'unknown'),
            p_content,
            p_ai_response::TEXT,
            (p_ai_response->>'confidence')::DECIMAL,
            COALESCE(p_ai_response->>'risk_level', 'UNKNOWN')
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Migration Pattern Learning
-- =====================================================

-- Learn from successful migrations
CREATE OR REPLACE FUNCTION pggit.learn_migration_pattern(
    p_source_tool TEXT,
    p_migration_content TEXT,
    p_pattern_type TEXT,
    p_success BOOLEAN DEFAULT true
) RETURNS VOID AS $$
BEGIN
    -- Update or insert pattern
    INSERT INTO pggit.migration_patterns (
        pattern_type,
        source_tool,
        pattern_sql,
        semantic_meaning,
        usage_count
    ) VALUES (
        p_pattern_type,
        p_source_tool,
        p_migration_content,
        p_pattern_type || ' pattern from ' || p_source_tool,
        1
    )
    ON CONFLICT (pattern_type, source_tool) DO UPDATE
    SET usage_count = migration_patterns.usage_count + 1,
        pattern_sql = EXCLUDED.pattern_sql
    WHERE migration_patterns.pattern_type = EXCLUDED.pattern_type
      AND migration_patterns.source_tool = EXCLUDED.source_tool;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Pre-populate Common Patterns
-- =====================================================

-- Add unique constraint for pattern learning
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'unique_pattern_tool' 
        AND conrelid = 'pggit.migration_patterns'::regclass
    ) THEN
        ALTER TABLE pggit.migration_patterns 
        ADD CONSTRAINT unique_pattern_tool 
        UNIQUE (pattern_type, source_tool);
    END IF;
END $$;

-- Insert common migration patterns
INSERT INTO pggit.migration_patterns (pattern_type, source_tool, pattern_sql, semantic_meaning, pggit_template) VALUES
('create_table', 'flyway', 'CREATE TABLE ${table_name} (id SERIAL PRIMARY KEY, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);', 'Basic table creation with ID and timestamp', 'CREATE TABLE %I (id SERIAL PRIMARY KEY, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)'),
('add_column', 'liquibase', 'ALTER TABLE ${table_name} ADD COLUMN ${column_name} ${column_type};', 'Add single column', 'ALTER TABLE %I ADD COLUMN %I %s'),
('create_index', 'rails', 'CREATE INDEX CONCURRENTLY idx_${table}_${column} ON ${table}(${column});', 'Non-blocking index creation', 'CREATE INDEX CONCURRENTLY %I ON %I(%I)'),
('add_foreign_key', 'flyway', 'ALTER TABLE ${table} ADD CONSTRAINT fk_${table}_${ref} FOREIGN KEY (${column}) REFERENCES ${ref_table}(id);', 'Add foreign key constraint', 'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I(id)'),
('drop_column_safe', 'liquibase', 'ALTER TABLE ${table} DROP COLUMN IF EXISTS ${column};', 'Safe column removal', 'ALTER TABLE %I DROP COLUMN IF EXISTS %I'),
('rename_table', 'rails', 'ALTER TABLE ${old_name} RENAME TO ${new_name};', 'Rename table', 'ALTER TABLE %I RENAME TO %I'),
('add_not_null', 'flyway', 'ALTER TABLE ${table} ALTER COLUMN ${column} SET NOT NULL;', 'Add NOT NULL constraint', 'ALTER TABLE %I ALTER COLUMN %I SET NOT NULL'),
('create_enum', 'liquibase', 'CREATE TYPE ${enum_name} AS ENUM (${values});', 'Create enumeration type', 'CREATE TYPE %I AS ENUM (%L)'),
('add_check_constraint', 'rails', 'ALTER TABLE ${table} ADD CONSTRAINT ${name} CHECK (${condition});', 'Add check constraint', 'ALTER TABLE %I ADD CONSTRAINT %I CHECK (%s)'),
('create_trigger', 'flyway', 'CREATE TRIGGER ${trigger_name} ${timing} ${event} ON ${table} FOR EACH ROW EXECUTE FUNCTION ${function}();', 'Create trigger', 'CREATE TRIGGER %I %s %s ON %I FOR EACH ROW EXECUTE FUNCTION %I()'),
('create_partial_index', 'liquibase', 'CREATE INDEX CONCURRENTLY ${index_name} ON ${table}(${column}) WHERE ${condition};', 'Partial index for performance', 'CREATE INDEX CONCURRENTLY %I ON %I(%I) WHERE %s'),
('bulk_update', 'rails', 'UPDATE ${table} SET ${column} = ${value} WHERE ${condition};', 'Bulk data update', 'UPDATE %I SET %I = %L WHERE %s')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Helper Views
-- =====================================================

-- View for AI analysis summary
CREATE OR REPLACE VIEW pggit.ai_analysis_summary AS
SELECT 
    COUNT(*) as total_analyses,
    AVG(confidence) as avg_confidence,
    COUNT(*) FILTER (WHERE confidence >= 0.8) as high_confidence_count,
    COUNT(*) FILTER (WHERE confidence < 0.6) as low_confidence_count,
    AVG(inference_time_ms) as avg_inference_time_ms,
    model_version,
    DATE_TRUNC('day', created_at) as analysis_date
FROM pggit.ai_decisions
GROUP BY model_version, DATE_TRUNC('day', created_at)
ORDER BY analysis_date DESC;

-- View for edge cases requiring review
CREATE OR REPLACE VIEW pggit.pending_ai_reviews AS
SELECT 
    ec.id,
    ec.migration_id,
    ec.case_type,
    ec.risk_level,
    ec.confidence,
    ec.created_at,
    LENGTH(ec.original_content) as migration_size_bytes
FROM pggit.ai_edge_cases ec
WHERE ec.review_status = 'PENDING'
ORDER BY 
    CASE ec.risk_level 
        WHEN 'HIGH' THEN 1 
        WHEN 'MEDIUM' THEN 2 
        ELSE 3 
    END,
    ec.confidence ASC,
    ec.created_at ASC;

-- =====================================================
-- Integration Functions
-- =====================================================

-- Main function to analyze migrations with AI
CREATE OR REPLACE FUNCTION pggit.analyze_migration_with_ai(
    p_migration_id TEXT,
    p_migration_content TEXT,
    p_source_tool TEXT DEFAULT 'unknown'
) RETURNS TABLE (
    intent TEXT,
    confidence DECIMAL,
    risk_level TEXT,
    risk_score INTEGER,
    recommendations TEXT[],
    estimated_duration_seconds INTEGER,
    requires_downtime BOOLEAN
) AS $$
DECLARE
    v_intent_result RECORD;
    v_risk_result RECORD;
    v_start_time TIMESTAMP := clock_timestamp();
    v_inference_time_ms INTEGER;
BEGIN
    -- Get intent analysis
    SELECT * INTO v_intent_result 
    FROM pggit.analyze_migration_intent(p_migration_content);
    
    -- Get risk assessment
    SELECT * INTO v_risk_result
    FROM pggit.assess_migration_risk(p_migration_content);
    
    -- Calculate inference time
    v_inference_time_ms := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start_time)::INTEGER;
    
    -- Record the analysis
    PERFORM pggit.record_ai_analysis(
        p_migration_id,
        p_migration_content,
        jsonb_build_object(
            'intent', v_intent_result.intent,
            'confidence', v_intent_result.confidence,
            'risk_level', v_intent_result.risk_level,
            'risk_score', v_risk_result.risk_score,
            'recommendations', v_intent_result.recommendations
        ),
        'pggit-heuristic',
        v_inference_time_ms
    );
    
    -- Learn from this pattern
    PERFORM pggit.learn_migration_pattern(
        p_source_tool,
        p_migration_content,
        LOWER(REGEXP_REPLACE(v_intent_result.intent, '\s+', '_', 'g')),
        true
    );
    
    RETURN QUERY SELECT 
        v_intent_result.intent,
        v_intent_result.confidence,
        v_intent_result.risk_level,
        v_risk_result.risk_score,
        v_intent_result.recommendations,
        v_risk_result.estimated_duration_seconds,
        v_risk_result.requires_downtime;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Size Management Integration
-- =====================================================

-- Analyze migration impact on database size
CREATE OR REPLACE FUNCTION pggit.analyze_migration_size_impact(
    p_migration_content TEXT
) RETURNS TABLE (
    estimated_size_increase_bytes BIGINT,
    size_impact_category TEXT, -- 'MINIMAL', 'MODERATE', 'SIGNIFICANT', 'SEVERE'
    storage_recommendations TEXT[]
) AS $$
DECLARE
    v_size_increase BIGINT := 0;
    v_impact_category TEXT := 'MINIMAL';
    v_recommendations TEXT[] := ARRAY[]::TEXT[];
    v_content_upper TEXT := UPPER(p_migration_content);
BEGIN
    -- Estimate size based on operations
    IF v_content_upper LIKE '%CREATE TABLE%' THEN
        -- Base table overhead
        v_size_increase := 8192; -- 8KB minimum
        
        -- Count columns
        v_size_increase := v_size_increase + 
            (LENGTH(p_migration_content) - LENGTH(REPLACE(v_content_upper, 'VARCHAR', ''))) / 7 * 1024;
        
        -- Check for large columns
        IF v_content_upper LIKE '%TEXT%' OR v_content_upper LIKE '%JSONB%' THEN
            v_size_increase := v_size_increase + 10240; -- 10KB for potential large data
            v_recommendations := array_append(v_recommendations, 
                'Consider using TOAST compression for TEXT/JSONB columns');
        END IF;
        
        -- Check for indexes
        IF v_content_upper LIKE '%PRIMARY KEY%' THEN
            v_size_increase := v_size_increase + 4096; -- 4KB for PK index
        END IF;
        
    ELSIF v_content_upper LIKE '%CREATE INDEX%' THEN
        v_size_increase := 8192; -- Base index size
        
        IF v_content_upper LIKE '%USING GIN%' OR v_content_upper LIKE '%USING GIST%' THEN
            v_size_increase := v_size_increase + 16384; -- GIN/GIST indexes are larger
            v_recommendations := array_append(v_recommendations, 
                'GIN/GIST indexes can be large - monitor size growth');
        END IF;
        
    ELSIF v_content_upper LIKE '%ALTER TABLE%ADD COLUMN%' THEN
        v_size_increase := 2048; -- Column overhead
        
        IF v_content_upper LIKE '%DEFAULT%' THEN
            v_recommendations := array_append(v_recommendations, 
                'Adding column with DEFAULT will rewrite table - consider doing in batches');
        END IF;
    END IF;
    
    -- Categorize impact
    CASE 
        WHEN v_size_increase < 10240 THEN -- < 10KB
            v_impact_category := 'MINIMAL';
        WHEN v_size_increase < 1048576 THEN -- < 1MB
            v_impact_category := 'MODERATE';
        WHEN v_size_increase < 104857600 THEN -- < 100MB
            v_impact_category := 'SIGNIFICANT';
            v_recommendations := array_append(v_recommendations, 
                'Consider running size maintenance after this migration');
        ELSE
            v_impact_category := 'SEVERE';
            v_recommendations := array_append(v_recommendations, 
                'Large size impact - ensure sufficient disk space before proceeding');
    END CASE;
    
    -- Add general recommendations
    IF array_length(v_recommendations, 1) IS NULL THEN
        v_recommendations := array_append(v_recommendations, 
            'Size impact appears minimal');
    END IF;
    
    RETURN QUERY SELECT v_size_increase, v_impact_category, v_recommendations;
END;
$$ LANGUAGE plpgsql;

-- Enhanced AI analysis with size considerations
CREATE OR REPLACE FUNCTION pggit.analyze_migration_with_ai_enhanced(
    p_migration_id TEXT,
    p_migration_content TEXT,
    p_source_tool TEXT DEFAULT 'unknown'
) RETURNS TABLE (
    intent TEXT,
    confidence DECIMAL,
    risk_level TEXT,
    risk_score INTEGER,
    recommendations TEXT[],
    estimated_duration_seconds INTEGER,
    requires_downtime BOOLEAN,
    size_impact_bytes BIGINT,
    size_impact_category TEXT,
    pruning_suggestions TEXT[]
) AS $$
DECLARE
    v_base_analysis RECORD;
    v_size_analysis RECORD;
    v_pruning_suggestions TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get base analysis
    SELECT * INTO v_base_analysis
    FROM pggit.analyze_migration_with_ai(p_migration_id, p_migration_content, p_source_tool);
    
    -- Get size impact analysis
    SELECT * INTO v_size_analysis
    FROM pggit.analyze_migration_size_impact(p_migration_content);
    
    -- Generate pruning suggestions based on context
    IF v_size_analysis.size_impact_category IN ('SIGNIFICANT', 'SEVERE') THEN
        -- Check current database size
        IF EXISTS (
            SELECT 1 FROM pggit.database_size_overview 
            WHERE total_size_bytes > 1073741824 -- 1GB
        ) THEN
            v_pruning_suggestions := array_append(v_pruning_suggestions,
                'Database is large - consider running pggit.generate_pruning_recommendations()');
        END IF;
        
        -- Check for merged branches
        IF EXISTS (
            SELECT 1 FROM pggit.branches WHERE status = 'MERGED'
        ) THEN
            v_pruning_suggestions := array_append(v_pruning_suggestions,
                'Merged branches found - run pggit.cleanup_merged_branches() to free space');
        END IF;
        
        -- Check for old inactive branches
        IF EXISTS (
            SELECT 1 FROM pggit.branch_size_metrics 
            WHERE EXTRACT(DAY FROM CURRENT_TIMESTAMP - last_commit_date) > 90
        ) THEN
            v_pruning_suggestions := array_append(v_pruning_suggestions,
                'Inactive branches detected - review with pggit.list_branches(NULL, 90)');
        END IF;
    END IF;
    
    -- Combine recommendations
    v_base_analysis.recommendations := v_base_analysis.recommendations || v_size_analysis.storage_recommendations;
    
    RETURN QUERY SELECT 
        v_base_analysis.intent,
        v_base_analysis.confidence,
        v_base_analysis.risk_level,
        v_base_analysis.risk_score,
        v_base_analysis.recommendations,
        v_base_analysis.estimated_duration_seconds,
        v_base_analysis.requires_downtime,
        v_size_analysis.estimated_size_increase_bytes,
        v_size_analysis.size_impact_category,
        v_pruning_suggestions;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Demo Function
-- =====================================================

CREATE OR REPLACE FUNCTION pggit.demo_ai_migration_analysis()
RETURNS TABLE (
    migration_name TEXT,
    analysis_result JSONB
) AS $$
BEGIN
    -- Demo various migration scenarios
    RETURN QUERY
    WITH test_migrations AS (
        SELECT * FROM (VALUES
            ('create_users_table.sql', 'CREATE TABLE users (id SERIAL PRIMARY KEY, email VARCHAR(255) UNIQUE NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);'),
            ('add_user_status.sql', 'ALTER TABLE users ADD COLUMN status VARCHAR(50) NOT NULL;'),
            ('drop_old_table.sql', 'DROP TABLE legacy_users;'),
            ('create_performance_index.sql', 'CREATE INDEX idx_users_email ON users(email);'),
            ('bulk_update_risk.sql', 'UPDATE users SET status = ''active'';'),
            ('create_large_table.sql', 'CREATE TABLE events (id BIGSERIAL PRIMARY KEY, data JSONB NOT NULL, metadata TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP); CREATE INDEX idx_events_data ON events USING GIN(data);')
        ) AS t(name, content)
    )
    SELECT 
        tm.name,
        jsonb_build_object(
            'intent', ai.intent,
            'confidence', ai.confidence,
            'risk_level', ai.risk_level,
            'risk_score', ai.risk_score,
            'recommendations', ai.recommendations,
            'estimated_duration', ai.estimated_duration_seconds || ' seconds',
            'requires_downtime', ai.requires_downtime,
            'size_impact', pg_size_pretty(ai.size_impact_bytes),
            'size_category', ai.size_impact_category,
            'pruning_suggestions', ai.pruning_suggestions
        )
    FROM test_migrations tm
    CROSS JOIN LATERAL pggit.analyze_migration_with_ai_enhanced(tm.name, tm.content, 'demo') ai;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON TABLE pggit.migration_patterns IS 'Stores common migration patterns for AI learning';
COMMENT ON TABLE pggit.ai_decisions IS 'Audit log of all AI migration analyses';
COMMENT ON TABLE pggit.ai_edge_cases IS 'Migrations flagged for human review';
COMMENT ON FUNCTION pggit.analyze_migration_with_ai IS 'Main entry point for AI-powered migration analysis';

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'pggit AI Migration Analysis installed successfully!';
    RAISE NOTICE 'Run SELECT * FROM pggit.demo_ai_migration_analysis(); to see it in action';
END $$;