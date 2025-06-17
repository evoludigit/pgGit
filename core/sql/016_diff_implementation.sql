-- ============================================
-- pgGit Diff Implementation
-- ============================================
-- Implements comprehensive diff functionality for schema and data

-- ============================================
-- SCHEMA DIFF FUNCTIONALITY
-- ============================================

-- Function to diff schemas
CREATE OR REPLACE FUNCTION pggit.diff_schemas(
    p_source_schema TEXT,
    p_target_schema TEXT
) RETURNS TABLE (
    object_name TEXT,
    object_type TEXT,
    change_type TEXT,
    details JSONB
) AS $$
BEGIN
    -- Find objects only in target (ADDITIONS)
    RETURN QUERY
    SELECT 
        t.table_name::TEXT AS object_name,
        'TABLE'::TEXT AS object_type,
        'ADD'::TEXT AS change_type,
        jsonb_build_object(
            'schema', p_target_schema,
            'action', 'CREATE TABLE'
        ) AS details
    FROM information_schema.tables t
    WHERE t.table_schema = p_target_schema
    AND t.table_type = 'BASE TABLE'
    AND NOT EXISTS (
        SELECT 1 FROM information_schema.tables s
        WHERE s.table_schema = p_source_schema
        AND s.table_name = t.table_name
        AND s.table_type = 'BASE TABLE'
    );

    -- Find objects only in source (DELETIONS)
    RETURN QUERY
    SELECT 
        s.table_name::TEXT AS object_name,
        'TABLE'::TEXT AS object_type,
        'DROP'::TEXT AS change_type,
        jsonb_build_object(
            'schema', p_source_schema,
            'action', 'DROP TABLE'
        ) AS details
    FROM information_schema.tables s
    WHERE s.table_schema = p_source_schema
    AND s.table_type = 'BASE TABLE'
    AND NOT EXISTS (
        SELECT 1 FROM information_schema.tables t
        WHERE t.table_schema = p_target_schema
        AND t.table_name = s.table_name
        AND t.table_type = 'BASE TABLE'
    );

    -- Find modified tables (column changes)
    RETURN QUERY
    WITH source_cols AS (
        SELECT 
            table_name,
            jsonb_agg(jsonb_build_object(
                'column_name', column_name,
                'data_type', data_type,
                'character_maximum_length', character_maximum_length,
                'numeric_precision', numeric_precision,
                'numeric_scale', numeric_scale,
                'is_nullable', is_nullable,
                'column_default', column_default
            ) ORDER BY ordinal_position) AS columns
        FROM information_schema.columns
        WHERE table_schema = p_source_schema
        GROUP BY table_name
    ),
    target_cols AS (
        SELECT 
            table_name,
            jsonb_agg(jsonb_build_object(
                'column_name', column_name,
                'data_type', data_type,
                'character_maximum_length', character_maximum_length,
                'numeric_precision', numeric_precision,
                'numeric_scale', numeric_scale,
                'is_nullable', is_nullable,
                'column_default', column_default
            ) ORDER BY ordinal_position) AS columns
        FROM information_schema.columns
        WHERE table_schema = p_target_schema
        GROUP BY table_name
    )
    SELECT 
        COALESCE(s.table_name, t.table_name)::TEXT AS object_name,
        'TABLE'::TEXT AS object_type,
        'MODIFY'::TEXT AS change_type,
        jsonb_build_object(
            'source_columns', s.columns,
            'target_columns', t.columns,
            'action', 'ALTER TABLE'
        ) AS details
    FROM source_cols s
    JOIN target_cols t ON s.table_name = t.table_name
    WHERE s.columns IS DISTINCT FROM t.columns;

    -- Find column additions
    RETURN QUERY
    SELECT 
        t.table_name || '.' || t.column_name AS object_name,
        'COLUMN'::TEXT AS object_type,
        'ADD_COLUMN'::TEXT AS change_type,
        jsonb_build_object(
            'table', t.table_name,
            'column', t.column_name,
            'data_type', t.data_type,
            'is_nullable', t.is_nullable,
            'column_default', t.column_default
        ) AS details
    FROM information_schema.columns t
    WHERE t.table_schema = p_target_schema
    AND EXISTS (
        -- Table exists in both schemas
        SELECT 1 FROM information_schema.tables st
        WHERE st.table_schema = p_source_schema
        AND st.table_name = t.table_name
    )
    AND NOT EXISTS (
        -- But column doesn't exist in source
        SELECT 1 FROM information_schema.columns s
        WHERE s.table_schema = p_source_schema
        AND s.table_name = t.table_name
        AND s.column_name = t.column_name
    );

    -- Find constraint differences
    RETURN QUERY
    WITH source_constraints AS (
        SELECT 
            tc.table_name,
            tc.constraint_name,
            tc.constraint_type,
            CASE 
                WHEN tc.constraint_type = 'CHECK' THEN cc.check_clause
                ELSE NULL
            END AS definition
        FROM information_schema.table_constraints tc
        LEFT JOIN information_schema.check_constraints cc
            ON tc.constraint_schema = cc.constraint_schema
            AND tc.constraint_name = cc.constraint_name
        WHERE tc.table_schema = p_source_schema
    ),
    target_constraints AS (
        SELECT 
            tc.table_name,
            tc.constraint_name,
            tc.constraint_type,
            CASE 
                WHEN tc.constraint_type = 'CHECK' THEN cc.check_clause
                ELSE NULL
            END AS definition
        FROM information_schema.table_constraints tc
        LEFT JOIN information_schema.check_constraints cc
            ON tc.constraint_schema = cc.constraint_schema
            AND tc.constraint_name = cc.constraint_name
        WHERE tc.table_schema = p_target_schema
    )
    SELECT 
        COALESCE(t.table_name, s.table_name) || '.' || COALESCE(t.constraint_name, s.constraint_name) AS object_name,
        'CONSTRAINT'::TEXT AS object_type,
        CASE 
            WHEN s.constraint_name IS NULL THEN 'ADD_CONSTRAINT'
            WHEN t.constraint_name IS NULL THEN 'DROP_CONSTRAINT'
            ELSE 'MODIFY_CONSTRAINT'
        END AS change_type,
        jsonb_build_object(
            'table', COALESCE(t.table_name, s.table_name),
            'constraint_name', COALESCE(t.constraint_name, s.constraint_name),
            'constraint_type', COALESCE(t.constraint_type, s.constraint_type),
            'definition', COALESCE(t.definition, s.definition)
        ) AS details
    FROM target_constraints t
    FULL OUTER JOIN source_constraints s
        ON t.table_name = s.table_name
        AND t.constraint_name = s.constraint_name
    WHERE (s.constraint_name IS NULL OR t.constraint_name IS NULL 
           OR s.definition IS DISTINCT FROM t.definition);

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DATA DIFF FUNCTIONALITY
-- ============================================

-- Function to diff table data
CREATE OR REPLACE FUNCTION pggit.diff_table_data(
    p_source_schema TEXT,
    p_target_schema TEXT,
    p_table_name TEXT
) RETURNS TABLE (
    change_type TEXT,
    primary_key_values JSONB,
    old_values JSONB,
    new_values JSONB
) AS $$
DECLARE
    v_pk_columns TEXT[];
    v_all_columns TEXT[];
    v_pk_list TEXT;
    v_column_list TEXT;
    v_sql TEXT;
BEGIN
    -- Get primary key columns
    SELECT array_agg(a.attname::TEXT ORDER BY array_position(i.indkey, a.attnum))
    INTO v_pk_columns
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = (p_source_schema || '.' || p_table_name)::regclass
    AND i.indisprimary;

    -- If no primary key, use all columns
    IF v_pk_columns IS NULL THEN
        SELECT array_agg(column_name::TEXT ORDER BY ordinal_position)
        INTO v_pk_columns
        FROM information_schema.columns
        WHERE table_schema = p_source_schema
        AND table_name = p_table_name;
    END IF;

    -- Get all columns
    SELECT array_agg(column_name::TEXT ORDER BY ordinal_position)
    INTO v_all_columns
    FROM information_schema.columns
    WHERE table_schema = p_source_schema
    AND table_name = p_table_name;

    -- Build column lists
    v_pk_list := array_to_string(v_pk_columns, ', ');
    v_column_list := array_to_string(v_all_columns, ', ');

    -- Build dynamic SQL for data comparison
    v_sql := format($SQL$
        WITH source_data AS (
            SELECT 
                jsonb_build_object(%s) AS pk_values,
                jsonb_build_object(%s) AS row_data
            FROM %I.%I
        ),
        target_data AS (
            SELECT 
                jsonb_build_object(%s) AS pk_values,
                jsonb_build_object(%s) AS row_data
            FROM %I.%I
        ),
        all_keys AS (
            SELECT DISTINCT pk_values FROM source_data
            UNION
            SELECT DISTINCT pk_values FROM target_data
        )
        SELECT 
            CASE 
                WHEN s.pk_values IS NULL THEN 'INSERT'
                WHEN t.pk_values IS NULL THEN 'DELETE'
                WHEN s.row_data != t.row_data THEN 'UPDATE'
            END AS change_type,
            k.pk_values AS primary_key_values,
            s.row_data AS old_values,
            t.row_data AS new_values
        FROM all_keys k
        LEFT JOIN source_data s ON k.pk_values = s.pk_values
        LEFT JOIN target_data t ON k.pk_values = t.pk_values
        WHERE s.row_data IS DISTINCT FROM t.row_data
    $SQL$,
        -- Source PK parameters
        (SELECT string_agg(format('%L, %I', col, col), ', ') 
         FROM unnest(v_pk_columns) AS col),
        -- Source all columns
        (SELECT string_agg(format('%L, %I', col, col), ', ') 
         FROM unnest(v_all_columns) AS col),
        p_source_schema, p_table_name,
        -- Target PK parameters  
        (SELECT string_agg(format('%L, %I', col, col), ', ') 
         FROM unnest(v_pk_columns) AS col),
        -- Target all columns
        (SELECT string_agg(format('%L, %I', col, col), ', ') 
         FROM unnest(v_all_columns) AS col),
        p_target_schema, p_table_name
    );

    RETURN QUERY EXECUTE v_sql;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- ENHANCED DIFF FUNCTION
-- ============================================

-- Drop the old simple diff function
DROP FUNCTION IF EXISTS pggit.diff(UUID, UUID);

-- Create enhanced diff function that handles both schema and data
CREATE OR REPLACE FUNCTION pggit.diff(
    p_from_commit UUID DEFAULT NULL,
    p_to_commit UUID DEFAULT NULL,
    p_include_data BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    diff_text TEXT,
    object_type TEXT,
    details JSONB
) AS $$
DECLARE
    v_from_schema TEXT;
    v_to_schema TEXT;
    v_working_schema TEXT;
BEGIN
    -- Get working schema
    SELECT working_schema INTO v_working_schema FROM pggit.HEAD;
    
    -- If no from_commit, use HEAD
    IF p_from_commit IS NULL THEN
        SELECT current_commit_id INTO p_from_commit FROM pggit.HEAD;
    END IF;
    
    -- Determine schemas to compare
    IF p_from_commit IS NOT NULL THEN
        -- Get schema snapshot from commit
        SELECT 'pggit_snapshot_' || substring(p_from_commit::TEXT, 1, 8) INTO v_from_schema;
    ELSE
        v_from_schema := v_working_schema;
    END IF;
    
    IF p_to_commit IS NULL THEN
        -- Compare against working directory
        v_to_schema := v_working_schema;
    ELSE
        -- Get schema snapshot from commit
        SELECT 'pggit_snapshot_' || substring(p_to_commit::TEXT, 1, 8) INTO v_to_schema;
    END IF;
    
    -- Return schema differences
    RETURN QUERY
    SELECT 
        ds.object_name,
        ds.change_type,
        CASE 
            WHEN ds.change_type = 'ADD' THEN format('Added %s %s', ds.object_type, ds.object_name)
            WHEN ds.change_type = 'DROP' THEN format('Removed %s %s', ds.object_type, ds.object_name)
            WHEN ds.change_type = 'MODIFY' THEN format('Modified %s %s', ds.object_type, ds.object_name)
            ELSE format('%s %s %s', ds.change_type, ds.object_type, ds.object_name)
        END AS diff_text,
        ds.object_type,
        ds.details
    FROM pggit.diff_schemas(v_from_schema, v_to_schema) ds;
    
    -- Optionally include data differences
    IF p_include_data THEN
        RETURN QUERY
        WITH tables_to_check AS (
            SELECT DISTINCT table_name 
            FROM information_schema.tables
            WHERE table_schema IN (v_from_schema, v_to_schema)
            AND table_type = 'BASE TABLE'
        )
        SELECT 
            t.table_name || ' (data)',
            td.change_type,
            format('%s %s row(s) in %s', 
                CASE td.change_type
                    WHEN 'INSERT' THEN 'Added'
                    WHEN 'DELETE' THEN 'Removed'
                    WHEN 'UPDATE' THEN 'Updated'
                END,
                COUNT(*), t.table_name
            ),
            'DATA'::TEXT,
            jsonb_build_object(
                'table', t.table_name,
                'row_count', COUNT(*),
                'changes', jsonb_agg(jsonb_build_object(
                    'pk', td.primary_key_values,
                    'old', td.old_values,
                    'new', td.new_values
                ))
            )
        FROM tables_to_check t
        CROSS JOIN LATERAL pggit.diff_table_data(v_from_schema, v_to_schema, t.table_name) td
        GROUP BY t.table_name, td.change_type;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to generate SQL for applying diffs
CREATE OR REPLACE FUNCTION pggit.generate_diff_sql(
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS TABLE (
    sequence_order INTEGER,
    sql_statement TEXT,
    change_type TEXT,
    object_name TEXT
) AS $$
DECLARE
    v_order INTEGER := 0;
BEGIN
    -- Generate DROP statements first (in reverse dependency order)
    FOR object_name, change_type IN
        SELECT ds.object_name, ds.change_type
        FROM pggit.diff_schemas(p_from_schema, p_to_schema) ds
        WHERE ds.change_type = 'DROP'
        ORDER BY 
            CASE ds.object_type
                WHEN 'CONSTRAINT' THEN 1
                WHEN 'INDEX' THEN 2
                WHEN 'VIEW' THEN 3
                WHEN 'TABLE' THEN 4
            END
    LOOP
        v_order := v_order + 1;
        RETURN QUERY SELECT v_order, 
                           format('DROP %s IF EXISTS %s;', 
                                  CASE WHEN change_type = 'DROP' THEN 'TABLE' ELSE 'OBJECT' END,
                                  object_name),
                           change_type,
                           object_name;
    END LOOP;
    
    -- Generate CREATE statements (in dependency order)
    FOR object_name, change_type IN
        SELECT ds.object_name, ds.change_type
        FROM pggit.diff_schemas(p_from_schema, p_to_schema) ds
        WHERE ds.change_type = 'ADD'
        ORDER BY 
            CASE ds.object_type
                WHEN 'TABLE' THEN 1
                WHEN 'VIEW' THEN 2
                WHEN 'INDEX' THEN 3
                WHEN 'CONSTRAINT' THEN 4
            END
    LOOP
        v_order := v_order + 1;
        -- This is simplified - real implementation would generate proper DDL
        RETURN QUERY SELECT v_order,
                           format('-- CREATE %s %s', 'TABLE', object_name),
                           change_type,
                           object_name;
    END LOOP;
    
    -- Generate ALTER statements
    FOR object_name, change_type IN
        SELECT ds.object_name, ds.change_type
        FROM pggit.diff_schemas(p_from_schema, p_to_schema) ds
        WHERE ds.change_type NOT IN ('ADD', 'DROP')
    LOOP
        v_order := v_order + 1;
        RETURN QUERY SELECT v_order,
                           format('-- ALTER %s', object_name),
                           change_type,
                           object_name;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Add comment
COMMENT ON FUNCTION pggit.diff IS 'Compare schemas and optionally data between commits or working directory';
COMMENT ON FUNCTION pggit.diff_schemas IS 'Compare two schemas and return differences';
COMMENT ON FUNCTION pggit.diff_table_data IS 'Compare data in a specific table between two schemas';
COMMENT ON FUNCTION pggit.generate_diff_sql IS 'Generate SQL statements to transform one schema to another';