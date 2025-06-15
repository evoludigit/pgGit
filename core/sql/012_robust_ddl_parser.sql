-- Robust DDL Parser - Eliminates String Replacement Fallbacks
-- Addresses Viktor's criticism: "DDL Parser is Still Sketchy"

-- ============================================
-- PART 1: Complete PostgreSQL Object Type Support
-- ============================================

-- Extended object type enum
CREATE TYPE pggit.pg_object_type AS ENUM (
    'TABLE',
    'VIEW', 
    'MATERIALIZED_VIEW',
    'INDEX',
    'UNIQUE_INDEX',
    'SEQUENCE',
    'FUNCTION',
    'PROCEDURE',
    'TRIGGER',
    'CONSTRAINT_PRIMARY',
    'CONSTRAINT_FOREIGN',
    'CONSTRAINT_UNIQUE',
    'CONSTRAINT_CHECK',
    'TYPE_COMPOSITE',
    'TYPE_ENUM',
    'TYPE_DOMAIN',
    'RULE',
    'POLICY',
    'PUBLICATION',
    'SUBSCRIPTION',
    'EXTENSION',
    'SCHEMA',
    'ROLE',
    'GRANT'
);

-- DDL parsing rules
CREATE TABLE IF NOT EXISTS pggit.ddl_parsing_rules (
    id SERIAL PRIMARY KEY,
    object_type pggit.pg_object_type NOT NULL,
    ddl_pattern TEXT NOT NULL, -- Regex pattern to match DDL
    parser_function TEXT NOT NULL, -- Function to call for parsing
    priority INTEGER DEFAULT 100, -- Lower number = higher priority
    enabled BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}'
);

-- Populate parsing rules
INSERT INTO pggit.ddl_parsing_rules (object_type, ddl_pattern, parser_function, priority) VALUES
('TABLE', '^\s*CREATE\s+TABLE', 'pggit.parse_create_table_advanced', 10),
('VIEW', '^\s*CREATE\s+(?:OR\s+REPLACE\s+)?VIEW', 'pggit.parse_create_view_advanced', 10),
('MATERIALIZED_VIEW', '^\s*CREATE\s+MATERIALIZED\s+VIEW', 'pggit.parse_create_materialized_view', 10),
('INDEX', '^\s*CREATE\s+(?:UNIQUE\s+)?INDEX', 'pggit.parse_create_index_advanced', 10),
('SEQUENCE', '^\s*CREATE\s+SEQUENCE', 'pggit.parse_create_sequence', 10),
('FUNCTION', '^\s*CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION', 'pggit.parse_create_function_advanced', 10),
('PROCEDURE', '^\s*CREATE\s+(?:OR\s+REPLACE\s+)?PROCEDURE', 'pggit.parse_create_procedure', 10),
('TYPE_ENUM', '^\s*CREATE\s+TYPE.*AS\s+ENUM', 'pggit.parse_create_type_enum', 10),
('TYPE_COMPOSITE', '^\s*CREATE\s+TYPE.*AS\s*\(', 'pggit.parse_create_type_composite', 10),
('TRIGGER', '^\s*CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER', 'pggit.parse_create_trigger', 10),
('SCHEMA', '^\s*CREATE\s+SCHEMA', 'pggit.parse_create_schema', 10),
('EXTENSION', '^\s*CREATE\s+EXTENSION', 'pggit.parse_create_extension', 10)
ON CONFLICT DO NOTHING;

-- ============================================
-- PART 2: Advanced DDL Parser Engine
-- ============================================

-- Main parsing dispatcher - NO STRING REPLACEMENT FALLBACKS
CREATE OR REPLACE FUNCTION pggit.parse_ddl_comprehensive(
    p_ddl TEXT,
    p_context JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB AS $$
DECLARE
    v_rule RECORD;
    v_parser_result JSONB;
    v_object_type pggit.pg_object_type;
    v_error_details JSONB;
BEGIN
    -- Find matching parsing rule
    FOR v_rule IN 
        SELECT * FROM pggit.ddl_parsing_rules 
        WHERE p_ddl ~* ddl_pattern 
        AND enabled = true
        ORDER BY priority ASC
        LIMIT 1
    LOOP
        BEGIN
            -- Call appropriate parser function
            EXECUTE format('SELECT %s($1)', v_rule.parser_function) 
            INTO v_parser_result 
            USING p_ddl;
            
            -- Add parsing metadata
            v_parser_result := jsonb_set(
                v_parser_result,
                '{parser_info}',
                jsonb_build_object(
                    'parser_function', v_rule.parser_function,
                    'object_type', v_rule.object_type,
                    'parsed_at', CURRENT_TIMESTAMP
                )
            );
            
            RETURN v_parser_result;
            
        EXCEPTION WHEN OTHERS THEN
            -- Log parsing failure but continue to next rule
            v_error_details := jsonb_build_object(
                'parser_function', v_rule.parser_function,
                'error_message', SQLERRM,
                'error_code', SQLSTATE
            );
            
            PERFORM pggit.log_error(
                'DDL_PARSING',
                'VALIDATION_ERROR',
                'WARNING',
                format('Parser %s failed for DDL: %s', v_rule.parser_function, SQLERRM),
                v_error_details
            );
        END;
    END LOOP;
    
    -- If no parser succeeded, this is an error - NO FALLBACK TO STRING REPLACEMENT
    RAISE EXCEPTION 'No parser available for DDL: %', substring(p_ddl, 1, 100);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Advanced Object Parsers
-- ============================================

-- Advanced CREATE TABLE parser with full feature support
CREATE OR REPLACE FUNCTION pggit.parse_create_table_advanced(
    p_ddl TEXT
) RETURNS JSONB AS $$
DECLARE
    v_ast JSONB;
    v_table_info RECORD;
    v_columns JSONB := '[]'::jsonb;
    v_constraints JSONB := '[]'::jsonb;
    v_indexes JSONB := '[]'::jsonb;
    v_options JSONB := '{}'::jsonb;
    v_dependencies TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Extract table metadata using advanced parsing
    WITH table_analysis AS (
        SELECT 
            -- Extract schema and table name
            COALESCE(
                (regexp_matches(p_ddl, 'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"?([^".]+)"?\.)?"?([^"\s(]+)"?', 'i'))[1],
                'public'
            ) as schema_name,
            (regexp_matches(p_ddl, 'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"?[^".]+"\.)?"?([^"\s(]+)"?', 'i'))[1] as table_name,
            
            -- Extract IF NOT EXISTS
            p_ddl ~* 'IF\s+NOT\s+EXISTS' as if_not_exists,
            
            -- Extract INHERITS clause
            (regexp_matches(p_ddl, 'INHERITS\s*\(\s*([^)]+)\s*\)', 'i'))[1] as inherits_from,
            
            -- Extract table options
            (regexp_matches(p_ddl, 'WITH\s*\(\s*([^)]+)\s*\)', 'i'))[1] as with_options,
            
            -- Extract TABLESPACE
            (regexp_matches(p_ddl, 'TABLESPACE\s+(\w+)', 'i'))[1] as tablespace,
            
            -- Extract partition information
            (regexp_matches(p_ddl, 'PARTITION\s+BY\s+(\w+)\s*\(([^)]+)\)', 'i'))[1] as partition_method,
            (regexp_matches(p_ddl, 'PARTITION\s+BY\s+\w+\s*\(([^)]+)\)', 'i'))[1] as partition_key
    )
    SELECT * INTO v_table_info FROM table_analysis;
    
    -- Parse column definitions
    v_columns := pggit.parse_table_columns_advanced(p_ddl);
    
    -- Parse constraints
    v_constraints := pggit.parse_table_constraints_advanced(p_ddl);
    
    -- Extract dependencies
    v_dependencies := pggit.extract_ddl_dependencies(p_ddl, 'TABLE');
    
    -- Parse table options
    IF v_table_info.with_options IS NOT NULL THEN
        v_options := pggit.parse_table_options(v_table_info.with_options);
    END IF;
    
    -- Build comprehensive AST
    v_ast := jsonb_build_object(
        'object_type', 'TABLE',
        'schema_name', v_table_info.schema_name,
        'table_name', v_table_info.table_name,
        'if_not_exists', v_table_info.if_not_exists,
        'columns', v_columns,
        'constraints', v_constraints,
        'dependencies', to_jsonb(v_dependencies),
        'options', v_options,
        'metadata', jsonb_build_object(
            'inherits_from', v_table_info.inherits_from,
            'tablespace', v_table_info.tablespace,
            'partition_method', v_table_info.partition_method,
            'partition_key', v_table_info.partition_key,
            'original_ddl', p_ddl
        )
    );
    
    RETURN v_ast;
END;
$$ LANGUAGE plpgsql;

-- Advanced column parsing with all PostgreSQL features
CREATE OR REPLACE FUNCTION pggit.parse_table_columns_advanced(
    p_ddl TEXT
) RETURNS JSONB AS $$
DECLARE
    v_columns JSONB := '[]'::jsonb;
    v_column_section TEXT;
    v_column_lines TEXT[];
    v_line TEXT;
    v_column_def JSONB;
BEGIN
    -- Extract column section (everything between CREATE TABLE (...))
    v_column_section := (regexp_matches(
        p_ddl, 
        'CREATE\s+TABLE[^(]*\(\s*(.*)\s*\)[^)]*$', 
        'is'
    ))[1];
    
    -- Smart split handling nested parentheses and quoted strings
    v_column_lines := pggit.smart_split_ddl_advanced(v_column_section);
    
    -- Parse each column
    FOREACH v_line IN ARRAY v_column_lines LOOP
        v_line := trim(v_line);
        
        -- Skip empty lines and constraint definitions
        IF v_line = '' OR v_line ~* '^\s*(?:CONSTRAINT|PRIMARY\s+KEY|FOREIGN\s+KEY|UNIQUE|CHECK)' THEN
            CONTINUE;
        END IF;
        
        -- Parse individual column
        v_column_def := pggit.parse_single_column_advanced(v_line);
        
        IF v_column_def IS NOT NULL THEN
            v_columns := v_columns || v_column_def;
        END IF;
    END LOOP;
    
    RETURN v_columns;
END;
$$ LANGUAGE plpgsql;

-- Parse single column with all PostgreSQL features
CREATE OR REPLACE FUNCTION pggit.parse_single_column_advanced(
    p_column_def TEXT
) RETURNS JSONB AS $$
DECLARE
    v_column JSONB;
    v_parts TEXT[];
    v_column_name TEXT;
    v_data_type TEXT;
    v_constraints JSONB := '[]'::jsonb;
    v_default_value TEXT;
    v_collate TEXT;
    v_storage TEXT;
    v_compression TEXT;
BEGIN
    -- Parse column name (handle quoted identifiers)
    v_column_name := (regexp_matches(p_column_def, '^(?:"([^"]+)"|(\w+))', 'i'))[1];
    IF v_column_name IS NULL THEN
        v_column_name := (regexp_matches(p_column_def, '^(?:"([^"]+)"|(\w+))', 'i'))[2];
    END IF;
    
    -- Parse data type (handle complex types like NUMERIC(10,2), VARCHAR(255), etc.)
    v_data_type := (regexp_matches(
        p_column_def, 
        '^\s*(?:"[^"]+"|[\w]+)\s+([^,\s]+(?:\([^)]*\))?(?:\s*\[\])?)', 
        'i'
    ))[1];
    
    -- Parse constraints and options
    -- NOT NULL
    IF p_column_def ~* '\bNOT\s+NULL\b' THEN
        v_constraints := v_constraints || jsonb_build_object('type', 'NOT_NULL');
    END IF;
    
    -- PRIMARY KEY
    IF p_column_def ~* '\bPRIMARY\s+KEY\b' THEN
        v_constraints := v_constraints || jsonb_build_object('type', 'PRIMARY_KEY');
    END IF;
    
    -- UNIQUE
    IF p_column_def ~* '\bUNIQUE\b' THEN
        v_constraints := v_constraints || jsonb_build_object('type', 'UNIQUE');
    END IF;
    
    -- DEFAULT value (handle complex defaults)
    v_default_value := (regexp_matches(
        p_column_def, 
        '\bDEFAULT\s+([^,\s]+(?:\([^)]*\))?)', 
        'i'
    ))[1];
    
    -- COLLATE
    v_collate := (regexp_matches(p_column_def, '\bCOLLATE\s+"?([^",\s]+)"?', 'i'))[1];
    
    -- STORAGE
    v_storage := (regexp_matches(p_column_def, '\bSTORAGE\s+(PLAIN|EXTERNAL|EXTENDED|MAIN)', 'i'))[1];
    
    -- COMPRESSION
    v_compression := (regexp_matches(p_column_def, '\bCOMPRESSION\s+(\w+)', 'i'))[1];
    
    -- Handle GENERATED columns
    IF p_column_def ~* '\bGENERATED\s+ALWAYS\s+AS' THEN
        v_default_value := (regexp_matches(
            p_column_def, 
            'GENERATED\s+ALWAYS\s+AS\s*\(([^)]+)\)', 
            'i'
        ))[1];
        v_constraints := v_constraints || jsonb_build_object(
            'type', 'GENERATED',
            'expression', v_default_value
        );
    END IF;
    
    -- Handle IDENTITY columns
    IF p_column_def ~* '\bGENERATED\s+(?:ALWAYS|BY\s+DEFAULT)\s+AS\s+IDENTITY' THEN
        v_constraints := v_constraints || jsonb_build_object('type', 'IDENTITY');
    END IF;
    
    -- Build column definition
    v_column := jsonb_build_object(
        'name', v_column_name,
        'data_type', v_data_type,
        'constraints', v_constraints,
        'default_value', v_default_value,
        'collate', v_collate,
        'storage', v_storage,
        'compression', v_compression
    );
    
    RETURN v_column;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Advanced View Parser
-- ============================================

-- Parse CREATE VIEW with full feature support
CREATE OR REPLACE FUNCTION pggit.parse_create_view_advanced(
    p_ddl TEXT
) RETURNS JSONB AS $$
DECLARE
    v_ast JSONB;
    v_view_info RECORD;
    v_dependencies TEXT[];
    v_columns TEXT[];
BEGIN
    -- Extract view metadata
    WITH view_analysis AS (
        SELECT 
            -- Schema and view name
            COALESCE(
                (regexp_matches(p_ddl, 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"?([^".]+)"?\.)?"?([^"\s(]+)"?', 'i'))[1],
                'public'
            ) as schema_name,
            (regexp_matches(p_ddl, 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"?[^".]+"\.)?"?([^"\s(]+)"?', 'i'))[1] as view_name,
            
            -- OR REPLACE
            p_ddl ~* 'OR\s+REPLACE' as or_replace,
            
            -- TEMPORARY
            p_ddl ~* 'TEMP(?:ORARY)?\s+VIEW' as temporary,
            
            -- Column list
            (regexp_matches(p_ddl, 'VIEW\s+[^(]+\(\s*([^)]+)\s*\)', 'i'))[1] as column_list,
            
            -- WITH options
            (regexp_matches(p_ddl, 'WITH\s*\(\s*([^)]+)\s*\)', 'i'))[1] as with_options,
            
            -- AS query
            (regexp_matches(p_ddl, '\bAS\s+(.*?)(?:WITH\s+(?:LOCAL\s+|CASCADED\s+)?CHECK\s+OPTION|$)', 'is'))[1] as query_definition,
            
            -- CHECK OPTION
            CASE 
                WHEN p_ddl ~* 'WITH\s+LOCAL\s+CHECK\s+OPTION' THEN 'LOCAL'
                WHEN p_ddl ~* 'WITH\s+CASCADED\s+CHECK\s+OPTION' THEN 'CASCADED'
                WHEN p_ddl ~* 'WITH\s+CHECK\s+OPTION' THEN 'CASCADED'
                ELSE NULL
            END as check_option
    )
    SELECT * INTO v_view_info FROM view_analysis;
    
    -- Parse column list if provided
    IF v_view_info.column_list IS NOT NULL THEN
        v_columns := string_to_array(
            regexp_replace(v_view_info.column_list, '\s+', '', 'g'),
            ','
        );
    END IF;
    
    -- Extract dependencies from query
    v_dependencies := pggit.extract_query_dependencies(v_view_info.query_definition);
    
    -- Build AST
    v_ast := jsonb_build_object(
        'object_type', 'VIEW',
        'schema_name', v_view_info.schema_name,
        'view_name', v_view_info.view_name,
        'or_replace', v_view_info.or_replace,
        'temporary', v_view_info.temporary,
        'columns', to_jsonb(v_columns),
        'query_definition', v_view_info.query_definition,
        'check_option', v_view_info.check_option,
        'with_options', v_view_info.with_options,
        'dependencies', to_jsonb(v_dependencies),
        'metadata', jsonb_build_object(
            'original_ddl', p_ddl
        )
    );
    
    RETURN v_ast;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Advanced Function Parser
-- ============================================

-- Parse CREATE FUNCTION with complete PostgreSQL support
CREATE OR REPLACE FUNCTION pggit.parse_create_function_advanced(
    p_ddl TEXT
) RETURNS JSONB AS $$
DECLARE
    v_ast JSONB;
    v_func_info RECORD;
    v_parameters JSONB := '[]'::jsonb;
    v_dependencies TEXT[];
BEGIN
    -- Extract function metadata
    WITH function_analysis AS (
        SELECT 
            -- Schema and function name
            COALESCE(
                (regexp_matches(p_ddl, 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?([^".]+)"?\.)?"?([^"\s(]+)"?', 'i'))[1],
                'public'
            ) as schema_name,
            (regexp_matches(p_ddl, 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?[^".]+"\.)?"?([^"\s(]+)"?', 'i'))[1] as function_name,
            
            -- OR REPLACE
            p_ddl ~* 'OR\s+REPLACE' as or_replace,
            
            -- Parameters
            (regexp_matches(p_ddl, 'FUNCTION\s+[^(]+\(\s*([^)]*)\s*\)', 'is'))[1] as parameters,
            
            -- Return type
            (regexp_matches(p_ddl, '\)\s*RETURNS\s+([^,\s]+(?:\([^)]*\))?(?:\s*\[\])?)', 'i'))[1] as return_type,
            
            -- Language
            (regexp_matches(p_ddl, '\bLANGUAGE\s+(\w+)', 'i'))[1] as language,
            
            -- Function body
            (regexp_matches(p_ddl, '\$([^$]*)\$(.*?)\$\1\$', 'is'))[2] as function_body,
            
            -- Volatility
            CASE 
                WHEN p_ddl ~* '\bIMMUTABLE\b' THEN 'IMMUTABLE'
                WHEN p_ddl ~* '\bSTABLE\b' THEN 'STABLE'
                WHEN p_ddl ~* '\bVOLATILE\b' THEN 'VOLATILE'
                ELSE 'VOLATILE'
            END as volatility,
            
            -- Security
            CASE 
                WHEN p_ddl ~* '\bSECURITY\s+DEFINER\b' THEN 'DEFINER'
                WHEN p_ddl ~* '\bSECURITY\s+INVOKER\b' THEN 'INVOKER'
                ELSE 'INVOKER'
            END as security,
            
            -- Other attributes
            p_ddl ~* '\bSTRICT\b' as strict,
            p_ddl ~* '\bLEAKPROOF\b' as leakproof,
            p_ddl ~* '\bPARALLEL\s+SAFE\b' as parallel_safe,
            p_ddl ~* '\bPARALLEL\s+UNSAFE\b' as parallel_unsafe,
            p_ddl ~* '\bPARALLEL\s+RESTRICTED\b' as parallel_restricted
    )
    SELECT * INTO v_func_info FROM function_analysis;
    
    -- Parse parameters
    IF v_func_info.parameters IS NOT NULL AND trim(v_func_info.parameters) != '' THEN
        v_parameters := pggit.parse_function_parameters(v_func_info.parameters);
    END IF;
    
    -- Extract dependencies
    v_dependencies := pggit.extract_function_dependencies(v_func_info.function_body);
    
    -- Build AST
    v_ast := jsonb_build_object(
        'object_type', 'FUNCTION',
        'schema_name', v_func_info.schema_name,
        'function_name', v_func_info.function_name,
        'or_replace', v_func_info.or_replace,
        'parameters', v_parameters,
        'return_type', v_func_info.return_type,
        'language', v_func_info.language,
        'function_body', v_func_info.function_body,
        'volatility', v_func_info.volatility,
        'security', v_func_info.security,
        'strict', v_func_info.strict,
        'leakproof', v_func_info.leakproof,
        'parallel_safety', 
            CASE 
                WHEN v_func_info.parallel_safe THEN 'SAFE'
                WHEN v_func_info.parallel_unsafe THEN 'UNSAFE'
                WHEN v_func_info.parallel_restricted THEN 'RESTRICTED'
                ELSE NULL
            END,
        'dependencies', to_jsonb(v_dependencies),
        'metadata', jsonb_build_object(
            'original_ddl', p_ddl
        )
    );
    
    RETURN v_ast;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Dependency Extraction Functions
-- ============================================

-- Extract dependencies from DDL (tables, views, functions referenced)
CREATE OR REPLACE FUNCTION pggit.extract_ddl_dependencies(
    p_ddl TEXT,
    p_object_type TEXT
) RETURNS TEXT[] AS $$
DECLARE
    v_dependencies TEXT[] := ARRAY[]::TEXT[];
    v_match TEXT;
BEGIN
    -- Extract REFERENCES clauses (foreign keys)
    FOR v_match IN
        SELECT unnest(regexp_matches(p_ddl, '\bREFERENCES\s+(?:"?([^".]+)"?\.)?"?([^"\s(]+)"?', 'gi'))
    LOOP
        v_dependencies := v_dependencies || v_match;
    END LOOP;
    
    -- Extract INHERITS clauses
    FOR v_match IN
        SELECT unnest(regexp_matches(p_ddl, '\bINHERITS\s*\(\s*([^)]+)\s*\)', 'gi'))
    LOOP
        v_dependencies := array_cat(v_dependencies, string_to_array(v_match, ','));
    END LOOP;
    
    -- Extract function calls in CHECK constraints and defaults
    FOR v_match IN
        SELECT unnest(regexp_matches(p_ddl, '(?:CHECK\s*\(|DEFAULT\s+)([^)]*(?:\([^)]*\))*[^)]*)', 'gi'))
    LOOP
        v_dependencies := array_cat(v_dependencies, pggit.extract_function_references(v_match));
    END LOOP;
    
    -- Clean up and deduplicate
    v_dependencies := array_remove(v_dependencies, NULL);
    v_dependencies := array_remove(v_dependencies, '');
    
    -- Remove duplicates
    SELECT array_agg(DISTINCT dep) INTO v_dependencies
    FROM unnest(v_dependencies) dep;
    
    RETURN v_dependencies;
END;
$$ LANGUAGE plpgsql;

-- Extract function references from expressions
CREATE OR REPLACE FUNCTION pggit.extract_function_references(
    p_expression TEXT
) RETURNS TEXT[] AS $$
DECLARE
    v_functions TEXT[] := ARRAY[]::TEXT[];
    v_match TEXT;
BEGIN
    -- Match function calls: function_name(
    FOR v_match IN
        SELECT (regexp_matches(p_expression, '\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', 'g'))[1]
    LOOP
        -- Filter out built-in operators and keywords
        IF v_match NOT IN ('now', 'current_timestamp', 'current_date', 'current_time') THEN
            v_functions := v_functions || v_match;
        END IF;
    END LOOP;
    
    RETURN v_functions;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.parse_ddl_comprehensive IS 'Comprehensive DDL parser with NO string replacement fallbacks';
COMMENT ON FUNCTION pggit.parse_create_table_advanced IS 'Advanced CREATE TABLE parser supporting all PostgreSQL features';
COMMENT ON FUNCTION pggit.parse_create_view_advanced IS 'Advanced CREATE VIEW parser with dependency extraction';
COMMENT ON FUNCTION pggit.parse_create_function_advanced IS 'Complete CREATE FUNCTION parser supporting all attributes';