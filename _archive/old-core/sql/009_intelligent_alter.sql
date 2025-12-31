-- Intelligent ALTER Generation Instead of DROP/CREATE
-- Addresses Viktor's criticism about destructive operations

-- ============================================
-- PART 1: Schema Diff Analysis
-- ============================================

-- Schema difference types
CREATE TYPE pggit.schema_diff_type AS ENUM (
    'ADD_COLUMN',
    'DROP_COLUMN', 
    'ALTER_COLUMN_TYPE',
    'ALTER_COLUMN_NULL',
    'ALTER_COLUMN_DEFAULT',
    'RENAME_COLUMN',
    'ADD_CONSTRAINT',
    'DROP_CONSTRAINT',
    'ADD_INDEX',
    'DROP_INDEX',
    'RENAME_TABLE',
    'NO_CHANGE'
);

-- Schema difference details
CREATE TABLE IF NOT EXISTS pggit.schema_diffs (
    id SERIAL PRIMARY KEY,
    from_commit_id UUID,
    to_commit_id UUID,
    object_name TEXT NOT NULL,
    diff_type pggit.schema_diff_type NOT NULL,
    diff_details JSONB NOT NULL,
    is_destructive BOOLEAN DEFAULT false,
    requires_data_migration BOOLEAN DEFAULT false,
    estimated_duration_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_schema_diffs_commits ON pggit.schema_diffs(from_commit_id, to_commit_id);
CREATE INDEX idx_schema_diffs_object ON pggit.schema_diffs(object_name);
CREATE INDEX idx_schema_diffs_type ON pggit.schema_diffs(diff_type);

-- ============================================
-- PART 2: Table Structure Comparison
-- ============================================

-- Compare two table structures in detail
CREATE OR REPLACE FUNCTION pggit.compare_table_structures(
    p_table1_ast JSONB,
    p_table2_ast JSONB
) RETURNS TABLE (
    diff_type pggit.schema_diff_type,
    diff_details JSONB,
    is_destructive BOOLEAN,
    requires_data_migration BOOLEAN,
    sql_command TEXT
) AS $$
DECLARE
    v_column1 JSONB;
    v_column2 JSONB;
    v_constraint1 JSONB;
    v_constraint2 JSONB;
    v_table_name TEXT;
BEGIN
    v_table_name := p_table2_ast->>'table_name';
    
    -- Compare columns
    FOR v_column1 IN SELECT * FROM jsonb_array_elements(p_table1_ast->'columns') LOOP
        -- Check if column exists in table2
        SELECT * INTO v_column2 
        FROM jsonb_array_elements(p_table2_ast->'columns') 
        WHERE (value->>'name') = (v_column1->>'name')
        LIMIT 1;
        
        IF v_column2 IS NULL THEN
            -- Column was dropped
            RETURN QUERY SELECT 
                'DROP_COLUMN'::pggit.schema_diff_type,
                jsonb_build_object(
                    'column_name', v_column1->>'name',
                    'old_definition', v_column1
                ),
                true, -- Destructive
                true, -- May require data migration
                format('ALTER TABLE %I DROP COLUMN %I', 
                    v_table_name, 
                    v_column1->>'name'
                );
        ELSIF v_column1 != v_column2 THEN
            -- Column was modified - analyze what changed
            FOR diff_type, diff_details, is_destructive, requires_data_migration, sql_command IN
                SELECT * FROM pggit.analyze_column_changes(
                    v_table_name,
                    v_column1,
                    v_column2
                )
            LOOP
                RETURN QUERY SELECT diff_type, diff_details, is_destructive, requires_data_migration, sql_command;
            END LOOP;
        END IF;
    END LOOP;
    
    -- Check for new columns in table2
    FOR v_column2 IN SELECT * FROM jsonb_array_elements(p_table2_ast->'columns') LOOP
        -- Check if column exists in table1
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_table1_ast->'columns') 
            WHERE (value->>'name') = (v_column2->>'name')
        ) THEN
            -- Column was added
            RETURN QUERY SELECT 
                'ADD_COLUMN'::pggit.schema_diff_type,
                jsonb_build_object(
                    'column_name', v_column2->>'name',
                    'new_definition', v_column2
                ),
                false, -- Not destructive
                (v_column2->>'not_null')::boolean AND (v_column2->>'default_value') IS NULL, -- Requires migration if NOT NULL without default
                pggit.generate_add_column_sql(v_table_name, v_column2);
        END IF;
    END LOOP;
    
    -- Compare constraints (simplified for demo)
    FOR v_constraint1 IN SELECT * FROM jsonb_array_elements(COALESCE(p_table1_ast->'constraints', '[]'::jsonb)) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(COALESCE(p_table2_ast->'constraints', '[]'::jsonb))
            WHERE (value->>'name') = (v_constraint1->>'name')
        ) THEN
            -- Constraint was dropped
            RETURN QUERY SELECT 
                'DROP_CONSTRAINT'::pggit.schema_diff_type,
                jsonb_build_object(
                    'constraint_name', v_constraint1->>'name',
                    'constraint_definition', v_constraint1
                ),
                CASE WHEN v_constraint1->>'type' IN ('PRIMARY_KEY', 'FOREIGN_KEY') THEN true ELSE false END,
                false,
                format('ALTER TABLE %I DROP CONSTRAINT %I', 
                    v_table_name, 
                    v_constraint1->>'name'
                );
        END IF;
    END LOOP;
    
    -- Check for new constraints
    FOR v_constraint2 IN SELECT * FROM jsonb_array_elements(COALESCE(p_table2_ast->'constraints', '[]'::jsonb)) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(COALESCE(p_table1_ast->'constraints', '[]'::jsonb))
            WHERE (value->>'name') = (v_constraint2->>'name')
        ) THEN
            -- Constraint was added
            RETURN QUERY SELECT 
                'ADD_CONSTRAINT'::pggit.schema_diff_type,
                jsonb_build_object(
                    'constraint_name', v_constraint2->>'name',
                    'constraint_definition', v_constraint2
                ),
                false,
                CASE WHEN v_constraint2->>'type' = 'CHECK' THEN true ELSE false END, -- CHECK constraints may require validation
                format('ALTER TABLE %I ADD CONSTRAINT %I %s', 
                    v_table_name, 
                    v_constraint2->>'name',
                    v_constraint2->>'definition'
                );
        END IF;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Analyze specific column changes
CREATE OR REPLACE FUNCTION pggit.analyze_column_changes(
    p_table_name TEXT,
    p_old_column JSONB,
    p_new_column JSONB
) RETURNS TABLE (
    diff_type pggit.schema_diff_type,
    diff_details JSONB,
    is_destructive BOOLEAN,
    requires_data_migration BOOLEAN,
    sql_command TEXT
) AS $$
DECLARE
    v_column_name TEXT;
    v_old_type TEXT;
    v_new_type TEXT;
    v_old_null BOOLEAN;
    v_new_null BOOLEAN;
    v_old_default TEXT;
    v_new_default TEXT;
BEGIN
    v_column_name := p_new_column->>'name';
    v_old_type := p_old_column->>'data_type';
    v_new_type := p_new_column->>'data_type';
    v_old_null := (p_old_column->>'not_null')::boolean;
    v_new_null := (p_new_column->>'not_null')::boolean;
    v_old_default := p_old_column->>'default_value';
    v_new_default := p_new_column->>'default_value';
    
    -- Check data type changes
    IF v_old_type != v_new_type THEN
        RETURN QUERY SELECT 
            'ALTER_COLUMN_TYPE'::pggit.schema_diff_type,
            jsonb_build_object(
                'column_name', v_column_name,
                'old_type', v_old_type,
                'new_type', v_new_type,
                'compatible', pggit.are_types_compatible(v_old_type, v_new_type)
            ),
            NOT pggit.are_types_compatible(v_old_type, v_new_type), -- Destructive if incompatible
            true, -- Usually requires data migration
            CASE 
                WHEN pggit.are_types_compatible(v_old_type, v_new_type) THEN
                    format('ALTER TABLE %I ALTER COLUMN %I TYPE %s', 
                        p_table_name, v_column_name, v_new_type)
                ELSE
                    format('-- MANUAL INTERVENTION REQUIRED: ALTER TABLE %I ALTER COLUMN %I TYPE %s USING (%I::%s)', 
                        p_table_name, v_column_name, v_new_type, v_column_name, v_new_type)
            END;
    END IF;
    
    -- Check nullability changes
    IF v_old_null != v_new_null THEN
        IF v_new_null AND NOT v_old_null THEN
            -- Adding NOT NULL constraint
            RETURN QUERY SELECT 
                'ALTER_COLUMN_NULL'::pggit.schema_diff_type,
                jsonb_build_object(
                    'column_name', v_column_name,
                    'change', 'add_not_null'
                ),
                true, -- Destructive - may fail if NULL values exist
                true, -- Requires data migration to handle NULLs
                format('-- Check for NULLs first, then: ALTER TABLE %I ALTER COLUMN %I SET NOT NULL', 
                    p_table_name, v_column_name);
        ELSE
            -- Removing NOT NULL constraint
            RETURN QUERY SELECT 
                'ALTER_COLUMN_NULL'::pggit.schema_diff_type,
                jsonb_build_object(
                    'column_name', v_column_name,
                    'change', 'drop_not_null'
                ),
                false, -- Not destructive
                false, -- No data migration needed
                format('ALTER TABLE %I ALTER COLUMN %I DROP NOT NULL', 
                    p_table_name, v_column_name);
        END IF;
    END IF;
    
    -- Check default value changes
    IF v_old_default IS DISTINCT FROM v_new_default THEN
        RETURN QUERY SELECT 
            'ALTER_COLUMN_DEFAULT'::pggit.schema_diff_type,
            jsonb_build_object(
                'column_name', v_column_name,
                'old_default', v_old_default,
                'new_default', v_new_default
            ),
            false, -- Not destructive
            false, -- No data migration needed
            CASE 
                WHEN v_new_default IS NULL THEN
                    format('ALTER TABLE %I ALTER COLUMN %I DROP DEFAULT', 
                        p_table_name, v_column_name)
                ELSE
                    format('ALTER TABLE %I ALTER COLUMN %I SET DEFAULT %s', 
                        p_table_name, v_column_name, v_new_default)
            END;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Check if data types are compatible for casting
CREATE OR REPLACE FUNCTION pggit.are_types_compatible(
    p_old_type TEXT,
    p_new_type TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Simplified compatibility check
    -- In production, this would be much more comprehensive
    
    -- Same type is always compatible
    IF p_old_type = p_new_type THEN
        RETURN true;
    END IF;
    
    -- Compatible numeric types
    IF p_old_type ~ '^(integer|bigint|smallint)' AND p_new_type ~ '^(integer|bigint|smallint)' THEN
        RETURN true;
    END IF;
    
    -- String types
    IF p_old_type ~ '^(varchar|text|char)' AND p_new_type ~ '^(varchar|text|char)' THEN
        RETURN true;
    END IF;
    
    -- Timestamp types
    IF p_old_type ~ '^timestamp' AND p_new_type ~ '^timestamp' THEN
        RETURN true;
    END IF;
    
    -- Default to incompatible for safety
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- Generate ADD COLUMN SQL
CREATE OR REPLACE FUNCTION pggit.generate_add_column_sql(
    p_table_name TEXT,
    p_column_def JSONB
) RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format('ALTER TABLE %I ADD COLUMN %I %s',
        p_table_name,
        p_column_def->>'name',
        p_column_def->>'data_type'
    );
    
    -- Add NOT NULL if specified
    IF (p_column_def->>'not_null')::boolean THEN
        v_sql := v_sql || ' NOT NULL';
    END IF;
    
    -- Add DEFAULT if specified
    IF p_column_def->>'default_value' IS NOT NULL THEN
        v_sql := v_sql || ' DEFAULT ' || (p_column_def->>'default_value');
    END IF;
    
    RETURN v_sql;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Safe Migration Planning
-- ============================================

-- Migration plan for schema changes
CREATE TABLE IF NOT EXISTS pggit.migration_plans (
    id SERIAL PRIMARY KEY,
    from_commit_id UUID NOT NULL,
    to_commit_id UUID NOT NULL,
    migration_steps JSONB NOT NULL, -- Array of migration steps
    total_steps INTEGER NOT NULL,
    estimated_duration_ms INTEGER,
    risk_level TEXT CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    requires_downtime BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Generate safe migration plan
CREATE OR REPLACE FUNCTION pggit.generate_migration_plan(
    p_from_commit_id UUID,
    p_to_commit_id UUID
) RETURNS TABLE (
    step_order INTEGER,
    step_type TEXT,
    sql_command TEXT,
    is_destructive BOOLEAN,
    estimated_duration_ms INTEGER,
    risk_level TEXT,
    description TEXT
) AS $$
DECLARE
    v_diff_record RECORD;
    v_step_order INTEGER := 1;
    v_total_risk_score INTEGER := 0;
BEGIN
    -- Get all differences between commits
    FOR v_diff_record IN
        WITH commit_diffs AS (
            SELECT 
                b1.object_schema || '.' || b1.object_name as object_name,
                pggit.parse_create_table(b1.object_definition) as old_ast,
                pggit.parse_create_table(b2.object_definition) as new_ast
            FROM pggit.commits c1
            JOIN pggit.trees t1 ON t1.tree_hash = c1.tree_hash
            JOIN pggit.blobs b1 ON b1.blob_hash = ANY(
                SELECT jsonb_array_elements_text(t1.schema_snapshot->'blobs')
            )
            JOIN pggit.commits c2 ON c2.id = p_to_commit_id
            JOIN pggit.trees t2 ON t2.tree_hash = c2.tree_hash
            JOIN pggit.blobs b2 ON b2.blob_hash = ANY(
                SELECT jsonb_array_elements_text(t2.schema_snapshot->'blobs')
            )
            WHERE c1.id = p_from_commit_id
            AND b1.object_type = 'TABLE'
            AND b2.object_type = 'TABLE'
            AND b1.object_schema || '.' || b1.object_name = b2.object_schema || '.' || b2.object_name
            AND b1.object_definition != b2.object_definition
        )
        SELECT 
            cd.object_name,
            ts.diff_type,
            ts.diff_details,
            ts.is_destructive,
            ts.requires_data_migration,
            ts.sql_command
        FROM commit_diffs cd
        CROSS JOIN LATERAL pggit.compare_table_structures(cd.old_ast, cd.new_ast) ts
        ORDER BY 
            -- Order by safety: non-destructive first
            ts.is_destructive ASC,
            -- Then by type priority
            CASE ts.diff_type
                WHEN 'ADD_COLUMN' THEN 1
                WHEN 'ALTER_COLUMN_DEFAULT' THEN 2
                WHEN 'DROP_CONSTRAINT' THEN 3
                WHEN 'ADD_CONSTRAINT' THEN 4
                WHEN 'ALTER_COLUMN_NULL' THEN 5
                WHEN 'ALTER_COLUMN_TYPE' THEN 6
                WHEN 'DROP_COLUMN' THEN 7
                ELSE 8
            END
    LOOP
        RETURN QUERY SELECT 
            v_step_order,
            v_diff_record.diff_type::TEXT,
            v_diff_record.sql_command,
            v_diff_record.is_destructive,
            CASE v_diff_record.diff_type
                WHEN 'ADD_COLUMN' THEN 100
                WHEN 'ALTER_COLUMN_DEFAULT' THEN 50
                WHEN 'DROP_CONSTRAINT' THEN 200
                WHEN 'ADD_CONSTRAINT' THEN 500
                WHEN 'ALTER_COLUMN_NULL' THEN 1000
                WHEN 'ALTER_COLUMN_TYPE' THEN 2000
                WHEN 'DROP_COLUMN' THEN 100
                ELSE 1000
            END,
            CASE 
                WHEN v_diff_record.is_destructive THEN 'HIGH'
                WHEN v_diff_record.requires_data_migration THEN 'MEDIUM'
                ELSE 'LOW'
            END,
            format('%s on %s (%s)', 
                v_diff_record.diff_type::TEXT,
                v_diff_record.object_name,
                CASE WHEN v_diff_record.is_destructive THEN 'DESTRUCTIVE' ELSE 'SAFE' END
            );
        
        v_step_order := v_step_order + 1;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Data Migration Handling
-- ============================================

-- Generate data migration scripts for schema changes
CREATE OR REPLACE FUNCTION pggit.generate_data_migration(
    p_table_name TEXT,
    p_diff_type pggit.schema_diff_type,
    p_diff_details JSONB
) RETURNS TEXT AS $$
DECLARE
    v_migration_sql TEXT;
    v_column_name TEXT;
    v_old_type TEXT;
    v_new_type TEXT;
BEGIN
    CASE p_diff_type
        WHEN 'ALTER_COLUMN_TYPE' THEN
            v_column_name := p_diff_details->>'column_name';
            v_old_type := p_diff_details->>'old_type';
            v_new_type := p_diff_details->>'new_type';
            
            v_migration_sql := format(
                'UPDATE %I SET %I = %I::%s WHERE %I IS NOT NULL',
                p_table_name, v_column_name, v_column_name, v_new_type, v_column_name
            );
            
        WHEN 'ALTER_COLUMN_NULL' THEN
            v_column_name := p_diff_details->>'column_name';
            
            IF p_diff_details->>'change' = 'add_not_null' THEN
                v_migration_sql := format(
                    '-- Handle NULL values before adding NOT NULL constraint\n' ||
                    'UPDATE %I SET %I = ''DEFAULT_VALUE'' WHERE %I IS NULL;\n' ||
                    '-- Then add constraint:\n' ||
                    'ALTER TABLE %I ALTER COLUMN %I SET NOT NULL;',
                    p_table_name, v_column_name, v_column_name,
                    p_table_name, v_column_name
                );
            END IF;
            
        WHEN 'ADD_COLUMN' THEN
            v_column_name := p_diff_details->>'column_name';
            
            -- Check if column is NOT NULL without default
            IF (p_diff_details->'new_definition'->>'not_null')::boolean 
               AND (p_diff_details->'new_definition'->>'default_value') IS NULL THEN
                v_migration_sql := format(
                    '-- Add column with default first, then remove default\n' ||
                    'ALTER TABLE %I ADD COLUMN %I %s DEFAULT ''TEMP_DEFAULT'';\n' ||
                    'UPDATE %I SET %I = ''ACTUAL_VALUE'' WHERE %I = ''TEMP_DEFAULT'';\n' ||
                    'ALTER TABLE %I ALTER COLUMN %I DROP DEFAULT;',
                    p_table_name, v_column_name, p_diff_details->'new_definition'->>'data_type',
                    p_table_name, v_column_name, v_column_name,
                    p_table_name, v_column_name
                );
            END IF;
            
        ELSE
            v_migration_sql := '-- No data migration required';
    END CASE;
    
    RETURN COALESCE(v_migration_sql, '-- No migration script generated');
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Enhanced Apply Functions
-- ============================================

-- Enhanced apply that uses intelligent ALTERs
CREATE OR REPLACE FUNCTION pggit.apply_tree_state_intelligent(
    p_tree_hash TEXT
) RETURNS TEXT AS $$
DECLARE
    v_current_commit UUID;
    v_migration_plan RECORD;
    v_commands_executed INTEGER := 0;
    v_errors INTEGER := 0;
BEGIN
    -- Get current commit
    SELECT current_commit_id INTO v_current_commit FROM pggit.HEAD;
    
    IF v_current_commit IS NULL THEN
        -- No current state, do full apply
        RETURN pggit.apply_tree_state(p_tree_hash);
    END IF;
    
    -- Generate and execute migration plan
    FOR v_migration_plan IN 
        SELECT * FROM pggit.generate_migration_plan(
            v_current_commit,
            (SELECT id FROM pggit.commits WHERE tree_hash = p_tree_hash LIMIT 1)
        )
        ORDER BY step_order
    LOOP
        BEGIN
            RAISE NOTICE 'Executing step %: %', 
                v_migration_plan.step_order, 
                v_migration_plan.description;
            
            EXECUTE v_migration_plan.sql_command;
            v_commands_executed := v_commands_executed + 1;
            
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            RAISE WARNING 'Failed to execute migration step %: %\\nSQL: %\\nError: %',
                v_migration_plan.step_order,
                v_migration_plan.description,
                v_migration_plan.sql_command,
                SQLERRM;
        END;
    END LOOP;
    
    RETURN format('Applied intelligent migration: %s steps executed, %s errors',
        v_commands_executed, v_errors);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.compare_table_structures IS 'Generate detailed schema differences between table structures';
COMMENT ON FUNCTION pggit.generate_migration_plan IS 'Create safe migration plan with ordered steps';
COMMENT ON FUNCTION pggit.apply_tree_state_intelligent IS 'Apply schema changes using intelligent ALTERs instead of DROP/CREATE';