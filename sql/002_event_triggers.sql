-- Event triggers to automatically track DDL changes
-- These triggers capture CREATE, ALTER, and DROP statements

-- Function to extract column information from a table
CREATE OR REPLACE FUNCTION pggit.extract_table_columns(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS JSONB AS $$
DECLARE
    v_columns JSONB;
BEGIN
    SELECT jsonb_object_agg(
        column_name,
        jsonb_build_object(
            'type', udt_name || 
                CASE 
                    WHEN character_maximum_length IS NOT NULL 
                    THEN '(' || character_maximum_length || ')'
                    ELSE ''
                END,
            'nullable', is_nullable = 'YES',
            'default', column_default,
            'position', ordinal_position
        )
    ) INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = p_schema_name
    AND table_name = p_table_name;
    
    RETURN COALESCE(v_columns, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql;

-- Function to handle DDL commands
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command() RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
    v_column RECORD;
    v_object_id INTEGER;
    v_parent_id INTEGER;
    v_change_type pggit.change_type;
    v_change_severity pggit.change_severity;
    v_metadata JSONB;
    v_schema_name TEXT;
    v_object_name TEXT;
    v_parent_name TEXT;
    v_old_metadata JSONB;
    v_description TEXT;
BEGIN
    -- Skip DDL tracking during schema installation if history table doesn't exist yet
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'pggit' AND table_name = 'history') THEN
        RETURN;
    END IF;
    -- Loop through all objects affected by the DDL command
    FOR v_object IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        -- FIRST: Check for temporary objects before ANY processing
        IF v_object.schema_name IS NOT NULL AND 
           (v_object.schema_name LIKE 'pg_temp%' OR 
            v_object.schema_name LIKE 'pg_toast_temp%') THEN
            CONTINUE;
        END IF;
        
        -- Also check command tag for TEMP/TEMPORARY keywords
        IF v_object.command_tag LIKE '%TEMP%TABLE%' OR 
           v_object.command_tag LIKE '%TEMPORARY%TABLE%' THEN
            CONTINUE;
        END IF;
        
        -- NOW safe to parse schema and object names
        IF v_object.schema_name IS NOT NULL THEN
            v_schema_name := v_object.schema_name;
            -- Use defensive approach for object name access
            BEGIN
                v_object_name := v_object.objid::regclass::text;
                -- Remove schema prefix if present
                v_object_name := regexp_replace(v_object_name, '^' || v_schema_name || '\.', '');
            EXCEPTION 
                WHEN insufficient_privilege THEN
                    -- Skip objects we can't access due to permissions
                    CONTINUE;
                WHEN OTHERS THEN
                    -- Use object_identity as fallback
                    v_object_name := v_object.object_identity;
            END;
        ELSE
            v_schema_name := 'public';
            v_object_name := v_object.object_identity;
        END IF;
        
        -- Determine change type
        CASE v_object.command_tag
            WHEN 'CREATE TABLE', 'CREATE VIEW', 'CREATE INDEX', 'CREATE FUNCTION' THEN
                v_change_type := 'CREATE';
                v_change_severity := 'MINOR';
            WHEN 'ALTER TABLE', 'ALTER VIEW', 'ALTER INDEX', 'ALTER FUNCTION' THEN
                v_change_type := 'ALTER';
                v_change_severity := 'MINOR'; -- May be overridden based on specific change
            WHEN 'DROP TABLE', 'DROP VIEW', 'DROP INDEX', 'DROP FUNCTION' THEN
                v_change_type := 'DROP';
                v_change_severity := 'MAJOR';
            ELSE
                CONTINUE; -- Skip unsupported commands
        END CASE;
        
        -- Handle different object types
        CASE v_object.object_type
            WHEN 'table' THEN
                -- Extract table metadata
                v_metadata := jsonb_build_object(
                    'columns', pggit.extract_table_columns(v_schema_name, v_object_name),
                    'oid', v_object.objid
                );
                
                -- Ensure table object exists
                v_object_id := pggit.ensure_object(
                    'TABLE'::pggit.object_type,
                    v_schema_name,
                    v_object_name,
                    NULL,
                    v_metadata
                );
                
                -- Track columns as separate objects
                FOR v_column IN 
                    SELECT column_name, 
                           udt_name || CASE 
                               WHEN character_maximum_length IS NOT NULL 
                               THEN '(' || character_maximum_length || ')'
                               ELSE ''
                           END AS data_type,
                           is_nullable = 'YES' AS nullable,
                           column_default
                    FROM information_schema.columns
                    WHERE table_schema = v_schema_name
                    AND table_name = v_object_name
                LOOP
                    PERFORM pggit.ensure_object(
                        'COLUMN'::pggit.object_type,
                        v_schema_name,
                        v_object_name || '.' || v_column.column_name,
                        v_schema_name || '.' || v_object_name,
                        jsonb_build_object(
                            'type', v_column.data_type,
                            'nullable', v_column.nullable,
                            'default', v_column.column_default
                        )
                    );
                END LOOP;
                
            WHEN 'index' THEN
                -- Get parent table for index
                SELECT
                    schemaname,
                    tablename
                INTO
                    v_schema_name,
                    v_parent_name
                FROM pg_indexes
                WHERE indexname = v_object_name
                AND schemaname = v_schema_name;

                -- Ensure schema_name is not NULL (fallback to 'public')
                IF v_schema_name IS NULL THEN
                    v_schema_name := 'public';
                END IF;

                v_metadata := jsonb_build_object(
                    'table', v_parent_name,
                    'oid', v_object.objid
                );

                v_object_id := pggit.ensure_object(
                    'INDEX'::pggit.object_type,
                    v_schema_name,
                    v_object_name,
                    v_schema_name || '.' || COALESCE(v_parent_name, 'unknown'),
                    v_metadata
                );
                
            WHEN 'view' THEN
                v_metadata := jsonb_build_object(
                    'oid', v_object.objid
                );
                
                v_object_id := pggit.ensure_object(
                    'VIEW'::pggit.object_type,
                    v_schema_name,
                    v_object_name,
                    NULL,
                    v_metadata
                );
                
            WHEN 'function' THEN
                v_metadata := jsonb_build_object(
                    'oid', v_object.objid
                );
                
                v_object_id := pggit.ensure_object(
                    'FUNCTION'::pggit.object_type,
                    v_schema_name,
                    v_object_name,
                    NULL,
                    v_metadata
                );
                
            ELSE
                CONTINUE; -- Skip unsupported object types
        END CASE;
        
        -- Get current metadata for comparison
        SELECT metadata INTO v_old_metadata
        FROM pggit.objects
        WHERE id = v_object_id;
        
        -- Determine if this is a breaking change
        IF v_change_type = 'ALTER' AND v_object.object_type = 'table' THEN
            -- Check for breaking column changes
            -- This is simplified - a full implementation would compare old and new metadata
            IF v_old_metadata IS DISTINCT FROM v_metadata THEN
                v_change_severity := 'MAJOR';
            END IF;
        END IF;
        
        -- Create description
        v_description := format('%s %s %s.%s',
            v_object.command_tag,
            v_object.object_type,
            v_schema_name,
            v_object_name
        );
        
        -- Increment version
        IF v_change_type != 'CREATE' OR v_old_metadata IS NOT NULL THEN
            PERFORM pggit.increment_version(
                v_object_id,
                v_change_type,
                v_change_severity,
                v_description,
                v_metadata,
                current_query()
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to handle dropped objects
CREATE OR REPLACE FUNCTION pggit.handle_sql_drop() RETURNS event_trigger AS $$
DECLARE
    v_object RECORD;
    v_object_id INTEGER;
BEGIN
    FOR v_object IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP
        -- Skip temporary objects (pg_temp* schemas)
        IF COALESCE(v_object.schema_name, '') LIKE 'pg_temp%' OR 
           COALESCE(v_object.schema_name, '') LIKE 'pg_toast_temp%' THEN
            CONTINUE;
        END IF;
        
        -- Find the object in our tracking system
        SELECT id INTO v_object_id
        FROM pggit.objects
        WHERE object_type = 
            CASE v_object.object_type
                WHEN 'table' THEN 'TABLE'::pggit.object_type
                WHEN 'view' THEN 'VIEW'::pggit.object_type
                WHEN 'index' THEN 'INDEX'::pggit.object_type
                WHEN 'function' THEN 'FUNCTION'::pggit.object_type
                ELSE NULL
            END
        AND schema_name = COALESCE(v_object.schema_name, '')
        AND object_name = v_object.object_name
        AND is_active = true;
        
        IF v_object_id IS NOT NULL THEN
            -- Mark as inactive
            UPDATE pggit.objects
            SET is_active = false,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = v_object_id;
            
            -- Record the drop in history
            INSERT INTO pggit.history (
                object_id,
                change_type,
                change_severity,
                old_version,
                new_version,
                change_description,
                sql_executed
            )
            SELECT
                id,
                'DROP'::pggit.change_type,
                'MAJOR'::pggit.change_severity,
                version,
                NULL,
                format('Dropped %s %s', object_type, full_name),
                current_query()
            FROM pggit.objects
            WHERE id = v_object_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create event triggers
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger;
CREATE EVENT TRIGGER pggit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION pggit.handle_ddl_command();

DROP EVENT TRIGGER IF EXISTS pggit_drop_trigger;
CREATE EVENT TRIGGER pggit_drop_trigger
    ON sql_drop
    EXECUTE FUNCTION pggit.handle_sql_drop();

-- Function to detect foreign key dependencies
CREATE OR REPLACE FUNCTION pggit.detect_foreign_keys() RETURNS VOID AS $$
DECLARE
    v_fk RECORD;
    v_dependent_name TEXT;
    v_referenced_name TEXT;
BEGIN
    FOR v_fk IN 
        SELECT
            con.conname AS constraint_name,
            con_ns.nspname AS constraint_schema,
            con_rel.relname AS table_name,
            ref_ns.nspname AS referenced_schema,
            ref_rel.relname AS referenced_table,
            array_agg(att.attname ORDER BY conkey_ord.ord) AS columns,
            array_agg(ref_att.attname ORDER BY confkey_ord.ord) AS referenced_columns
        FROM pg_constraint con
        JOIN pg_class con_rel ON con.conrelid = con_rel.oid
        JOIN pg_namespace con_ns ON con_rel.relnamespace = con_ns.oid
        JOIN pg_class ref_rel ON con.confrelid = ref_rel.oid
        JOIN pg_namespace ref_ns ON ref_rel.relnamespace = ref_ns.oid
        JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS conkey_ord(attnum, ord) ON true
        JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = conkey_ord.attnum
        JOIN LATERAL unnest(con.confkey) WITH ORDINALITY AS confkey_ord(attnum, ord) ON true
        JOIN pg_attribute ref_att ON ref_att.attrelid = con.confrelid AND ref_att.attnum = confkey_ord.attnum
        WHERE con.contype = 'f'
        GROUP BY con.conname, con_ns.nspname, con_rel.relname, ref_ns.nspname, ref_rel.relname
    LOOP
        -- Build full names
        v_dependent_name := v_fk.constraint_schema || '.' || v_fk.table_name;
        v_referenced_name := v_fk.referenced_schema || '.' || v_fk.referenced_table;
        
        -- Add table-level dependency
        BEGIN
            PERFORM pggit.add_dependency(
                v_dependent_name,
                v_referenced_name,
                'foreign_key'
            );
        EXCEPTION WHEN OTHERS THEN
            -- Ignore if objects don't exist in tracking
            NULL;
        END;
        
        -- Add column-level dependencies
        FOR i IN 1..array_length(v_fk.columns, 1) LOOP
            BEGIN
                PERFORM pggit.add_dependency(
                    v_dependent_name || '.' || v_fk.columns[i],
                    v_referenced_name || '.' || v_fk.referenced_columns[i],
                    'foreign_key'
                );
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Run initial detection of foreign keys
SELECT pggit.detect_foreign_keys();