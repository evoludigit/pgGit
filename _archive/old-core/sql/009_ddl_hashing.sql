-- DDL Hashing Implementation for pggit
-- This adds hash-based change detection to improve efficiency

-- Ensure pgcrypto extension is available for hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================
-- PART 1: Schema Updates
-- ============================================

-- Add hash columns to objects table
ALTER TABLE pggit.objects 
ADD COLUMN IF NOT EXISTS ddl_hash TEXT,
ADD COLUMN IF NOT EXISTS structure_hash TEXT,
ADD COLUMN IF NOT EXISTS constraints_hash TEXT,
ADD COLUMN IF NOT EXISTS indexes_hash TEXT;

-- Add hash tracking to history
ALTER TABLE pggit.history
ADD COLUMN IF NOT EXISTS old_hash TEXT,
ADD COLUMN IF NOT EXISTS new_hash TEXT;

-- Create index for hash lookups
CREATE INDEX IF NOT EXISTS idx_objects_ddl_hash 
ON pggit.objects(ddl_hash) 
WHERE is_active = true;

-- ============================================
-- PART 2: DDL Normalization Functions
-- ============================================

-- Function to normalize table DDL for consistent hashing
CREATE OR REPLACE FUNCTION pggit.normalize_table_ddl(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_columns TEXT;
    v_normalized TEXT;
    v_table_exists BOOLEAN;
BEGIN
    -- Check if table exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema_name
        AND table_name = p_table_name
    ) INTO v_table_exists;
    
    IF NOT v_table_exists THEN
        RETURN NULL;
    END IF;
    
    -- Get columns in a normalized format with proper error handling
    -- Order by ordinal position for consistency
    BEGIN
        SELECT string_agg(
            format('%I %s%s%s',
                column_name,
                -- Normalize data types
                CASE 
                    WHEN data_type = 'character varying' THEN 'varchar' || 
                        CASE WHEN character_maximum_length IS NOT NULL 
                             THEN '(' || character_maximum_length || ')' 
                             ELSE '' 
                        END
                    WHEN data_type = 'character' THEN 'char(' || character_maximum_length || ')'
                    WHEN data_type = 'numeric' AND numeric_precision IS NOT NULL THEN 
                        'numeric(' || numeric_precision || 
                        CASE WHEN numeric_scale IS NOT NULL 
                             THEN ',' || numeric_scale 
                             ELSE '' 
                        END || ')'
                    ELSE data_type
                END,
                CASE WHEN is_nullable = 'NO' THEN ' not null' ELSE '' END,
                CASE WHEN column_default IS NOT NULL 
                     THEN ' default ' || 
                          -- Normalize defaults
                          regexp_replace(
                              regexp_replace(column_default, '::[\w\s\[\]]+', '', 'g'),
                              '\s+', ' ', 'g'
                          )
                     ELSE '' 
                END
            ),
            ', '
            ORDER BY ordinal_position
        ) INTO v_columns
        FROM information_schema.columns
        WHERE table_schema = p_schema_name
        AND table_name = p_table_name;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error normalizing table DDL for %.%: %', p_schema_name, p_table_name, SQLERRM;
        RETURN NULL;
    END;
    
    -- Ensure we have columns
    IF v_columns IS NULL OR v_columns = '' THEN
        RETURN NULL;
    END IF;
    
    -- Build normalized CREATE TABLE
    v_normalized := format('create table %I.%I (%s)', 
        p_schema_name, 
        p_table_name, 
        v_columns
    );
    
    -- Lowercase and remove extra spaces
    v_normalized := lower(v_normalized);
    v_normalized := regexp_replace(v_normalized, '\s+', ' ', 'g');
    
    RETURN v_normalized;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Critical error in normalize_table_ddl for %.%: %', p_schema_name, p_table_name, SQLERRM;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to normalize constraint definitions
CREATE OR REPLACE FUNCTION pggit.normalize_constraints(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_constraints TEXT;
BEGIN
    -- Get all constraints in normalized format
    SELECT string_agg(
        format('%s %s %s',
            contype,
            conname,
            -- Normalize constraint definition
            CASE contype
                WHEN 'c' THEN pg_get_constraintdef(oid, true)
                WHEN 'f' THEN pg_get_constraintdef(oid, true)
                WHEN 'p' THEN pg_get_constraintdef(oid, true)
                WHEN 'u' THEN pg_get_constraintdef(oid, true)
                ELSE ''
            END
        ),
        '; '
        ORDER BY contype, conname  -- Consistent ordering
    ) INTO v_constraints
    FROM pg_constraint
    WHERE conrelid = (p_schema_name || '.' || p_table_name)::regclass;
    
    RETURN COALESCE(lower(v_constraints), '');
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to normalize index definitions
CREATE OR REPLACE FUNCTION pggit.normalize_indexes(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_indexes TEXT;
    v_table_exists BOOLEAN;
BEGIN
    -- Check if table exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema_name
        AND table_name = p_table_name
    ) INTO v_table_exists;
    
    IF NOT v_table_exists THEN
        RETURN '';
    END IF;
    
    BEGIN
        -- Get all indexes in normalized format using pg_stat_user_indexes
        SELECT string_agg(
            -- Remove schema qualifiers and normalize
            regexp_replace(
                regexp_replace(
                    lower(pg_get_indexdef(ui.indexrelid, 0, true)),
                    p_schema_name || '\.', '', 'g'
                ),
                '\s+', ' ', 'g'
            ),
            '; '
            ORDER BY ui.indexrelname  -- Consistent ordering
        ) INTO v_indexes
        FROM pg_stat_user_indexes ui
        WHERE ui.schemaname = p_schema_name
        AND ui.relname = p_table_name
        -- Exclude primary key indexes (covered by constraints)
        AND ui.indexrelname NOT IN (
            SELECT conname 
            FROM pg_constraint 
            WHERE conrelid = (p_schema_name || '.' || p_table_name)::regclass
            AND contype = 'p'
        );
        
        RETURN COALESCE(v_indexes, '');
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error normalizing indexes for %.%: %', p_schema_name, p_table_name, SQLERRM;
        RETURN '';
    END;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to normalize view definitions
CREATE OR REPLACE FUNCTION pggit.normalize_view_ddl(
    p_schema_name TEXT,
    p_view_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_definition TEXT;
BEGIN
    -- Get view definition
    SELECT lower(pg_get_viewdef((p_schema_name || '.' || p_view_name)::regclass, true))
    INTO v_definition;
    
    -- Normalize whitespace
    v_definition := regexp_replace(v_definition, '\s+', ' ', 'g');
    
    -- Remove schema qualifiers for portability
    v_definition := regexp_replace(v_definition, p_schema_name || '\.', '', 'g');
    
    RETURN v_definition;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to normalize function definitions
CREATE OR REPLACE FUNCTION pggit.normalize_function_ddl(
    p_schema_name TEXT,
    p_function_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_definition TEXT;
    v_oid OID;
BEGIN
    BEGIN
        -- Get function OID (handling overloads by taking first match)
        SELECT p.oid INTO v_oid
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = p_schema_name
        AND p.proname = p_function_name
        LIMIT 1;
        
        IF v_oid IS NULL THEN
            RETURN NULL;
        END IF;
        
        -- Get normalized function definition
        SELECT lower(pg_get_functiondef(v_oid))
        INTO v_definition;
        
        -- Normalize whitespace
        v_definition := regexp_replace(v_definition, '\s+', ' ', 'g');
        
        -- Remove schema qualifiers
        v_definition := regexp_replace(v_definition, p_schema_name || '\.', '', 'g');
        
        RETURN v_definition;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error normalizing function DDL for %.%: %', p_schema_name, p_function_name, SQLERRM;
        RETURN NULL;
    END;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- PART 3: Hash Computation Functions
-- ============================================

-- Main hash computation function with enterprise-grade error handling
CREATE OR REPLACE FUNCTION pggit.compute_ddl_hash(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_normalized_ddl TEXT;
    v_hash_input_length INTEGER;
    v_start_time TIMESTAMP;
    v_max_hash_length CONSTANT INTEGER := 100000; -- 100KB limit for hash input
BEGIN
    -- Input validation
    IF p_schema_name IS NULL OR p_object_name IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Performance tracking
    v_start_time := clock_timestamp();
    
    BEGIN
        -- Get normalized DDL based on object type
        CASE p_object_type
            WHEN 'TABLE' THEN
                v_normalized_ddl := pggit.normalize_table_ddl(p_schema_name, p_object_name);
                
            WHEN 'VIEW' THEN
                v_normalized_ddl := pggit.normalize_view_ddl(p_schema_name, p_object_name);
                
            WHEN 'FUNCTION', 'PROCEDURE' THEN
                v_normalized_ddl := pggit.normalize_function_ddl(p_schema_name, p_object_name);
                
            WHEN 'INDEX' THEN
                -- For indexes, use the full definition with proper error handling
                BEGIN
                    SELECT regexp_replace(
                        lower(pg_get_indexdef(i.indexrelid, 0, true)),
                        '\s+', ' ', 'g'
                    ) INTO v_normalized_ddl
                    FROM pg_stat_user_indexes i
                    WHERE i.schemaname = p_schema_name
                    AND i.indexrelname = p_object_name;
                EXCEPTION WHEN OTHERS THEN
                    RAISE WARNING 'Error getting index definition for %.%: %', p_schema_name, p_object_name, SQLERRM;
                    v_normalized_ddl := NULL;
                END;
                
            ELSE
                -- For unsupported types, return NULL
                RETURN NULL;
        END CASE;
        
        -- Resource management: check input size
        IF v_normalized_ddl IS NOT NULL THEN
            v_hash_input_length := length(v_normalized_ddl);
            
            IF v_hash_input_length > v_max_hash_length THEN
                RAISE WARNING 'DDL too large for hashing (% bytes > % limit) for %.%', 
                    v_hash_input_length, v_max_hash_length, p_schema_name, p_object_name;
                RETURN NULL;
            END IF;
            
            -- Compute hash with error handling
            BEGIN
                RETURN encode(digest(v_normalized_ddl, 'sha256'), 'hex');
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Hash computation failed for %.%: %', p_schema_name, p_object_name, SQLERRM;
                RETURN NULL;
            END;
        ELSE
            RETURN NULL;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'DDL hash computation error for %.% (type %): %', 
            p_schema_name, p_object_name, p_object_type, SQLERRM;
        RETURN NULL;
    END;
    
    -- Performance warning for slow operations
    IF extract(epoch FROM (clock_timestamp() - v_start_time)) > 1.0 THEN
        RAISE WARNING 'Slow hash computation for %.% took % seconds', 
            p_schema_name, p_object_name, extract(epoch FROM (clock_timestamp() - v_start_time));
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Compute component hashes for tables
CREATE OR REPLACE FUNCTION pggit.compute_table_component_hashes(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TABLE (
    structure_hash TEXT,
    constraints_hash TEXT,
    indexes_hash TEXT
) AS $$
DECLARE
    v_structure TEXT;
    v_constraints TEXT;
    v_indexes TEXT;
BEGIN
    -- Get normalized components
    v_structure := pggit.normalize_table_ddl(p_schema_name, p_table_name);
    v_constraints := pggit.normalize_constraints(p_schema_name, p_table_name);
    v_indexes := pggit.normalize_indexes(p_schema_name, p_table_name);
    
    -- Return hashes
    RETURN QUERY SELECT
        encode(digest(v_structure, 'sha256'), 'hex'),
        encode(digest(v_constraints, 'sha256'), 'hex'),
        encode(digest(v_indexes, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- PART 4: Change Detection Functions
-- ============================================

-- Function to detect if object has changed based on hash
CREATE OR REPLACE FUNCTION pggit.has_object_changed_by_hash(
    p_object_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    v_object RECORD;
    v_current_hash TEXT;
BEGIN
    -- Get object details
    SELECT * INTO v_object
    FROM pggit.objects
    WHERE id = p_object_id;
    
    -- Compute current hash
    v_current_hash := pggit.compute_ddl_hash(
        v_object.object_type,
        v_object.schema_name,
        v_object.object_name
    );
    
    -- Compare with stored hash
    RETURN v_current_hash IS DISTINCT FROM v_object.ddl_hash;
END;
$$ LANGUAGE plpgsql STABLE;

-- Bulk change detection using hashes
CREATE OR REPLACE FUNCTION pggit.detect_changes_by_hash()
RETURNS TABLE (
    object_id INTEGER,
    full_name TEXT,
    object_type pggit.object_type,
    old_hash TEXT,
    new_hash TEXT,
    has_changed BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id,
        o.full_name,
        o.object_type,
        o.ddl_hash,
        pggit.compute_ddl_hash(o.object_type, o.schema_name, o.object_name),
        pggit.compute_ddl_hash(o.object_type, o.schema_name, o.object_name) 
            IS DISTINCT FROM o.ddl_hash
    FROM pggit.objects o
    WHERE o.is_active = true
    AND o.object_type IN ('TABLE', 'VIEW', 'FUNCTION', 'INDEX');
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Update Event Triggers
-- ============================================

-- Enhanced handle_ddl_command that uses hashing
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command_with_hash() 
RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
    v_object_id INTEGER;
    v_old_hash TEXT;
    v_new_hash TEXT;
    v_has_changed BOOLEAN;
    v_change_type pggit.change_type;
    v_change_severity pggit.change_severity;
BEGIN
    -- Process each affected object
    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        -- Skip if not a tracked object type
        CONTINUE WHEN v_object.object_type NOT IN 
            ('table', 'view', 'function', 'index', 'sequence');
        
        -- Get or create object record
        SELECT id, ddl_hash INTO v_object_id, v_old_hash
        FROM pggit.objects
        WHERE schema_name = v_object.schema_name
        AND object_name = regexp_replace(v_object.object_identity, '^[^.]+\.', '')
        AND is_active = true;
        
        -- If object doesn't exist, create it
        IF v_object_id IS NULL THEN
            -- This is a CREATE
            v_change_type := 'CREATE';
            v_change_severity := 'MINOR';
            v_has_changed := true;
            
            -- Insert new object
            INSERT INTO pggit.objects (
                object_type, schema_name, object_name, version,
                major_version, minor_version, patch_version
            ) VALUES (
                v_object.object_type::pggit.object_type,
                v_object.schema_name,
                regexp_replace(v_object.object_identity, '^[^.]+\.', ''),
                1, 1, 0, 0
            ) RETURNING id INTO v_object_id;
        ELSE
            -- This is an ALTER
            v_change_type := 'ALTER';
            
            -- Compute new hash
            v_new_hash := pggit.compute_ddl_hash(
                v_object.object_type::pggit.object_type,
                v_object.schema_name,
                regexp_replace(v_object.object_identity, '^[^.]+\.', '')
            );
            
            -- Check if actually changed
            v_has_changed := v_new_hash IS DISTINCT FROM v_old_hash;
            
            -- Determine severity based on the type of change
            -- (This is simplified - real logic would analyze the actual changes)
            v_change_severity := 'MINOR';
        END IF;
        
        -- Only record if there was an actual change
        IF v_has_changed THEN
            -- Update object with new hash
            UPDATE pggit.objects
            SET ddl_hash = v_new_hash,
                version = version + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = v_object_id;
            
            -- Record in history
            INSERT INTO pggit.history (
                object_id, change_type, change_severity,
                old_hash, new_hash,
                change_description, sql_executed,
                created_at, created_by
            ) VALUES (
                v_object_id, v_change_type, v_change_severity,
                v_old_hash, v_new_hash,
                v_object.command_tag || ' ' || v_object.object_type || ' ' || v_object.object_identity,
                current_query(),
                CURRENT_TIMESTAMP, CURRENT_USER
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Utility Functions
-- ============================================

-- Update all existing objects with hashes
CREATE OR REPLACE FUNCTION pggit.update_all_hashes()
RETURNS TABLE (
    updated_count INTEGER,
    error_count INTEGER
) AS $$
DECLARE
    v_updated INTEGER := 0;
    v_errors INTEGER := 0;
    v_object RECORD;
    v_hash TEXT;
BEGIN
    FOR v_object IN 
        SELECT id, object_type, schema_name, object_name
        FROM pggit.objects
        WHERE is_active = true
        AND ddl_hash IS NULL
    LOOP
        BEGIN
            -- Compute hash
            v_hash := pggit.compute_ddl_hash(
                v_object.object_type,
                v_object.schema_name,
                v_object.object_name
            );
            
            -- Update if hash computed successfully
            IF v_hash IS NOT NULL THEN
                UPDATE pggit.objects
                SET ddl_hash = v_hash
                WHERE id = v_object.id;
                
                v_updated := v_updated + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
        END;
    END LOOP;
    
    RETURN QUERY SELECT v_updated, v_errors;
END;
$$ LANGUAGE plpgsql;

-- Compare schemas using hashes (for cross-database comparison)
CREATE OR REPLACE FUNCTION pggit.export_schema_hashes(
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TABLE (
    object_type TEXT,
    object_name TEXT,
    ddl_hash TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.object_type::TEXT,
        o.full_name,
        COALESCE(
            o.ddl_hash, 
            pggit.compute_ddl_hash(o.object_type, o.schema_name, o.object_name)
        )
    FROM pggit.objects o
    WHERE o.schema_name = p_schema_name
    AND o.is_active = true
    AND o.object_type IN ('TABLE', 'VIEW', 'FUNCTION', 'INDEX')
    ORDER BY o.object_type, o.object_name;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 7: Views for Hash-Based Analysis
-- ============================================

-- View showing objects that have changed (by hash)
CREATE OR REPLACE VIEW pggit.changed_objects AS
SELECT 
    o.id,
    o.full_name,
    o.object_type,
    o.version,
    o.ddl_hash as stored_hash,
    pggit.compute_ddl_hash(o.object_type, o.schema_name, o.object_name) as current_hash,
    o.ddl_hash IS DISTINCT FROM 
        pggit.compute_ddl_hash(o.object_type, o.schema_name, o.object_name) as has_changed,
    o.updated_at
FROM pggit.objects o
WHERE o.is_active = true
AND o.object_type IN ('TABLE', 'VIEW', 'FUNCTION', 'INDEX');

-- View showing hash history
CREATE OR REPLACE VIEW pggit.hash_history AS
SELECT 
    o.full_name,
    o.object_type,
    h.change_type,
    h.old_hash,
    h.new_hash,
    h.old_hash = h.new_hash as false_positive,
    h.created_at,
    h.created_by
FROM pggit.history h
JOIN pggit.objects o ON o.id = h.object_id
WHERE h.old_hash IS NOT NULL OR h.new_hash IS NOT NULL
ORDER BY h.created_at DESC;