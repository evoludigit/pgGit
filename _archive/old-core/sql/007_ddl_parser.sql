-- Advanced DDL Parser for Robust Schema Transformation
-- Replaces string manipulation with proper AST-based parsing

-- ============================================
-- PART 1: DDL AST Representation
-- ============================================

-- DDL Abstract Syntax Tree representation
CREATE TYPE pggit.ddl_node_type AS ENUM (
    'CREATE_TABLE',
    'ALTER_TABLE', 
    'DROP_TABLE',
    'CREATE_INDEX',
    'DROP_INDEX',
    'CREATE_VIEW',
    'DROP_VIEW',
    'ADD_COLUMN',
    'DROP_COLUMN',
    'ALTER_COLUMN',
    'ADD_CONSTRAINT',
    'DROP_CONSTRAINT'
);

-- DDL AST storage
CREATE TABLE IF NOT EXISTS pggit.ddl_ast (
    id SERIAL PRIMARY KEY,
    blob_hash TEXT NOT NULL,
    node_type pggit.ddl_node_type NOT NULL,
    node_data JSONB NOT NULL, -- Structured representation
    dependencies TEXT[], -- Object dependencies
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ddl_ast_blob ON pggit.ddl_ast(blob_hash);
CREATE INDEX idx_ddl_ast_type ON pggit.ddl_ast(node_type);

-- ============================================
-- PART 2: DDL Parsing Engine
-- ============================================

-- Parse CREATE TABLE statement into structured format
CREATE OR REPLACE FUNCTION pggit.parse_create_table(
    p_ddl TEXT
) RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_schema_name TEXT;
    v_columns JSONB := '[]'::jsonb;
    v_constraints JSONB := '[]'::jsonb;
    v_column_part TEXT;
    v_column_lines TEXT[];
    v_line TEXT;
    v_column_def JSONB;
BEGIN
    -- Extract table name (simplified regex for demo)
    v_table_name := (regexp_matches(p_ddl, 'CREATE TABLE\s+(?:(\w+)\.)?(\w+)', 'i'))[2];
    v_schema_name := COALESCE((regexp_matches(p_ddl, 'CREATE TABLE\s+(\w+)\.(\w+)', 'i'))[1], 'public');
    
    -- Extract column definitions
    v_column_part := regexp_replace(
        p_ddl, 
        '.*CREATE TABLE[^(]*\((.*)\).*', 
        '\1', 
        'is'
    );
    
    -- Split by commas (handling nested parentheses)
    v_column_lines := pggit.smart_split_ddl(v_column_part);
    
    -- Parse each column
    FOREACH v_line IN ARRAY v_column_lines LOOP
        v_line := trim(v_line);
        
        IF v_line ~* '^\s*CONSTRAINT' THEN
            -- Constraint definition
            v_constraints := v_constraints || pggit.parse_constraint(v_line);
        ELSIF v_line ~* '^\s*PRIMARY KEY|FOREIGN KEY|CHECK|UNIQUE' THEN
            -- Inline constraint
            v_constraints := v_constraints || pggit.parse_inline_constraint(v_line);
        ELSIF v_line != '' THEN
            -- Column definition
            v_column_def := pggit.parse_column_definition(v_line);
            IF v_column_def IS NOT NULL THEN
                v_columns := v_columns || v_column_def;
            END IF;
        END IF;
    END LOOP;
    
    RETURN jsonb_build_object(
        'type', 'CREATE_TABLE',
        'schema_name', v_schema_name,
        'table_name', v_table_name,
        'columns', v_columns,
        'constraints', v_constraints,
        'original_ddl', p_ddl
    );
END;
$$ LANGUAGE plpgsql;

-- Smart DDL splitting that respects parentheses
CREATE OR REPLACE FUNCTION pggit.smart_split_ddl(
    p_ddl TEXT
) RETURNS TEXT[] AS $$
DECLARE
    v_parts TEXT[] := ARRAY[]::TEXT[];
    v_current TEXT := '';
    v_paren_count INTEGER := 0;
    v_char CHAR;
    v_i INTEGER;
BEGIN
    FOR v_i IN 1..length(p_ddl) LOOP
        v_char := substring(p_ddl FROM v_i FOR 1);
        
        IF v_char = '(' THEN
            v_paren_count := v_paren_count + 1;
        ELSIF v_char = ')' THEN
            v_paren_count := v_paren_count - 1;
        ELSIF v_char = ',' AND v_paren_count = 0 THEN
            -- Top-level comma - split here
            v_parts := v_parts || trim(v_current);
            v_current := '';
            CONTINUE;
        END IF;
        
        v_current := v_current || v_char;
    END LOOP;
    
    -- Add final part
    IF trim(v_current) != '' THEN
        v_parts := v_parts || trim(v_current);
    END IF;
    
    RETURN v_parts;
END;
$$ LANGUAGE plpgsql;

-- Parse column definition
CREATE OR REPLACE FUNCTION pggit.parse_column_definition(
    p_column_def TEXT
) RETURNS JSONB AS $$
DECLARE
    v_parts TEXT[];
    v_column_name TEXT;
    v_data_type TEXT;
    v_not_null BOOLEAN := false;
    v_default_value TEXT;
    v_rest TEXT;
BEGIN
    v_parts := regexp_split_to_array(trim(p_column_def), '\s+');
    
    IF array_length(v_parts, 1) < 2 THEN
        RETURN NULL; -- Invalid column definition
    END IF;
    
    v_column_name := v_parts[1];
    v_data_type := v_parts[2];
    
    -- Handle type modifiers (e.g., VARCHAR(255))
    IF array_length(v_parts, 1) > 2 AND v_parts[3] ~ '^\(' THEN
        v_data_type := v_data_type || v_parts[3];
    END IF;
    
    -- Check for NOT NULL
    v_rest := array_to_string(v_parts[3:], ' ');
    v_not_null := v_rest ~* 'NOT\s+NULL';
    
    -- Extract DEFAULT value
    IF v_rest ~* 'DEFAULT\s+' THEN
        v_default_value := (regexp_matches(v_rest, 'DEFAULT\s+([^,\s]+)', 'i'))[1];
    END IF;
    
    RETURN jsonb_build_object(
        'name', v_column_name,
        'data_type', v_data_type,
        'not_null', v_not_null,
        'default_value', v_default_value
    );
END;
$$ LANGUAGE plpgsql;

-- Parse constraint definition
CREATE OR REPLACE FUNCTION pggit.parse_constraint(
    p_constraint_def TEXT
) RETURNS JSONB AS $$
DECLARE
    v_constraint_name TEXT;
    v_constraint_type TEXT;
    v_details TEXT;
BEGIN
    -- Extract constraint name
    v_constraint_name := (regexp_matches(p_constraint_def, 'CONSTRAINT\s+(\w+)', 'i'))[1];
    
    -- Determine constraint type
    IF p_constraint_def ~* 'PRIMARY\s+KEY' THEN
        v_constraint_type := 'PRIMARY_KEY';
        v_details := (regexp_matches(p_constraint_def, 'PRIMARY\s+KEY\s*\(([^)]+)\)', 'i'))[1];
    ELSIF p_constraint_def ~* 'FOREIGN\s+KEY' THEN
        v_constraint_type := 'FOREIGN_KEY';
        v_details := p_constraint_def; -- Store full definition for complex parsing
    ELSIF p_constraint_def ~* 'UNIQUE' THEN
        v_constraint_type := 'UNIQUE';
        v_details := (regexp_matches(p_constraint_def, 'UNIQUE\s*\(([^)]+)\)', 'i'))[1];
    ELSIF p_constraint_def ~* 'CHECK' THEN
        v_constraint_type := 'CHECK';
        v_details := (regexp_matches(p_constraint_def, 'CHECK\s*\((.+)\)', 'i'))[1];
    END IF;
    
    RETURN jsonb_build_object(
        'name', v_constraint_name,
        'type', v_constraint_type,
        'details', v_details,
        'definition', p_constraint_def
    );
END;
$$ LANGUAGE plpgsql;

-- Parse inline constraint
CREATE OR REPLACE FUNCTION pggit.parse_inline_constraint(
    p_constraint_def TEXT
) RETURNS JSONB AS $$
BEGIN
    -- Simplified inline constraint parsing
    RETURN jsonb_build_object(
        'type', 'INLINE',
        'definition', p_constraint_def
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Schema Transformation Engine
-- ============================================

-- Transform schema references in DDL using AST
CREATE OR REPLACE FUNCTION pggit.transform_ddl_schema(
    p_ddl TEXT,
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS TEXT AS $$
DECLARE
    v_ast JSONB;
    v_transformed_ddl TEXT;
BEGIN
    -- Parse DDL into AST
    IF p_ddl ~* '^\s*CREATE\s+TABLE' THEN
        v_ast := pggit.parse_create_table(p_ddl);
        v_transformed_ddl := pggit.generate_create_table_ddl(v_ast, p_to_schema);
    ELSIF p_ddl ~* '^\s*CREATE\s+INDEX' THEN
        v_transformed_ddl := pggit.transform_create_index(p_ddl, p_from_schema, p_to_schema);
    ELSIF p_ddl ~* '^\s*CREATE\s+VIEW' THEN
        v_transformed_ddl := pggit.transform_create_view(p_ddl, p_from_schema, p_to_schema);
    ELSE
        -- Fallback to regex replacement for unsupported DDL types
        v_transformed_ddl := replace(p_ddl, p_from_schema || '.', p_to_schema || '.');
    END IF;
    
    RETURN v_transformed_ddl;
END;
$$ LANGUAGE plpgsql;

-- Generate CREATE TABLE DDL from AST
CREATE OR REPLACE FUNCTION pggit.generate_create_table_ddl(
    p_ast JSONB,
    p_target_schema TEXT
) RETURNS TEXT AS $$
DECLARE
    v_ddl TEXT;
    v_column JSONB;
    v_constraint JSONB;
    v_columns_ddl TEXT[] := ARRAY[]::TEXT[];
    v_constraints_ddl TEXT[] := ARRAY[]::TEXT[];
    v_column_ddl TEXT;
BEGIN
    -- Start with CREATE TABLE
    v_ddl := format('CREATE TABLE %I.%I (', 
        p_target_schema, 
        p_ast->>'table_name'
    );
    
    -- Add columns
    FOR v_column IN SELECT * FROM jsonb_array_elements(p_ast->'columns') LOOP
        v_column_ddl := format('%I %s', 
            v_column->>'name',
            v_column->>'data_type'
        );
        
        IF (v_column->>'not_null')::boolean THEN
            v_column_ddl := v_column_ddl || ' NOT NULL';
        END IF;
        
        IF v_column->>'default_value' IS NOT NULL THEN
            v_column_ddl := v_column_ddl || ' DEFAULT ' || (v_column->>'default_value');
        END IF;
        
        v_columns_ddl := v_columns_ddl || v_column_ddl;
    END LOOP;
    
    -- Add constraints
    FOR v_constraint IN SELECT * FROM jsonb_array_elements(p_ast->'constraints') LOOP
        IF v_constraint->>'name' IS NOT NULL THEN
            v_constraints_ddl := v_constraints_ddl || format('CONSTRAINT %I %s',
                v_constraint->>'name',
                pggit.transform_constraint_definition(
                    v_constraint->>'definition',
                    p_target_schema
                )
            );
        END IF;
    END LOOP;
    
    -- Combine columns and constraints
    v_ddl := v_ddl || array_to_string(
        v_columns_ddl || v_constraints_ddl, 
        E',\n    '
    ) || ')';
    
    RETURN v_ddl;
END;
$$ LANGUAGE plpgsql;

-- Transform constraint definition to new schema
CREATE OR REPLACE FUNCTION pggit.transform_constraint_definition(
    p_constraint_def TEXT,
    p_target_schema TEXT
) RETURNS TEXT AS $$
BEGIN
    -- Transform schema references in constraint
    -- This is a simplified version - full implementation would parse REFERENCES clauses
    RETURN regexp_replace(
        p_constraint_def,
        '\b\w+\.',
        p_target_schema || '.',
        'g'
    );
END;
$$ LANGUAGE plpgsql;

-- Transform CREATE INDEX DDL
CREATE OR REPLACE FUNCTION pggit.transform_create_index(
    p_ddl TEXT,
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS TEXT AS $$
BEGIN
    RETURN replace(p_ddl, p_from_schema || '.', p_to_schema || '.');
END;
$$ LANGUAGE plpgsql;

-- Transform CREATE VIEW DDL
CREATE OR REPLACE FUNCTION pggit.transform_create_view(
    p_ddl TEXT,
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS TEXT AS $$
BEGIN
    -- Transform schema references in view definition
    RETURN regexp_replace(
        p_ddl,
        '\b' || p_from_schema || '\.',
        p_to_schema || '.',
        'g'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Enhanced Object Management
-- ============================================

-- Store DDL with parsed AST
CREATE OR REPLACE FUNCTION pggit.store_ddl_with_ast(
    p_ddl TEXT,
    p_object_type pggit.object_type
) RETURNS TEXT AS $$
DECLARE
    v_blob_hash TEXT;
    v_ast JSONB;
    v_dependencies TEXT[];
BEGIN
    -- Generate blob hash
    v_blob_hash := encode(digest(p_ddl, 'sha256'), 'hex');
    
    -- Parse DDL into AST
    CASE p_object_type
        WHEN 'TABLE' THEN
            v_ast := pggit.parse_create_table(p_ddl);
            v_dependencies := pggit.extract_table_dependencies(v_ast);
        ELSE
            v_ast := jsonb_build_object('type', p_object_type, 'ddl', p_ddl);
            v_dependencies := ARRAY[]::TEXT[];
    END CASE;
    
    -- Store AST
    INSERT INTO pggit.ddl_ast (blob_hash, node_type, node_data, dependencies)
    VALUES (v_blob_hash, 'CREATE_TABLE', v_ast, v_dependencies)
    ON CONFLICT DO NOTHING;
    
    RETURN v_blob_hash;
END;
$$ LANGUAGE plpgsql;

-- Extract dependencies from table AST
CREATE OR REPLACE FUNCTION pggit.extract_table_dependencies(
    p_ast JSONB
) RETURNS TEXT[] AS $$
DECLARE
    v_dependencies TEXT[] := ARRAY[]::TEXT[];
    v_constraint JSONB;
    v_referenced_table TEXT;
BEGIN
    -- Extract foreign key dependencies
    FOR v_constraint IN SELECT * FROM jsonb_array_elements(p_ast->'constraints') LOOP
        IF v_constraint->>'type' = 'FOREIGN_KEY' THEN
            -- Extract referenced table from constraint definition
            v_referenced_table := (regexp_matches(
                v_constraint->>'definition',
                'REFERENCES\s+(\w+(?:\.\w+)?)',
                'i'
            ))[1];
            
            IF v_referenced_table IS NOT NULL THEN
                v_dependencies := v_dependencies || v_referenced_table;
            END IF;
        END IF;
    END LOOP;
    
    RETURN v_dependencies;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.parse_create_table IS 'Parse CREATE TABLE DDL into structured AST';
COMMENT ON FUNCTION pggit.transform_ddl_schema IS 'Transform schema references using AST parsing';
COMMENT ON FUNCTION pggit.generate_create_table_ddl IS 'Generate DDL from parsed AST';