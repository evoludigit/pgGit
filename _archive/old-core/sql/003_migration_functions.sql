-- Functions for generating and managing migrations

-- Function to compare two column definitions and determine change severity
CREATE OR REPLACE FUNCTION pggit.compare_columns(
    p_old_columns JSONB,
    p_new_columns JSONB
) RETURNS TABLE (
    column_name TEXT,
    change_type pggit.change_type,
    change_severity pggit.change_severity,
    old_definition JSONB,
    new_definition JSONB,
    change_description TEXT
) AS $$
DECLARE
    v_column_name TEXT;
    v_old_def JSONB;
    v_new_def JSONB;
BEGIN
    -- Check for removed columns (MAJOR change)
    FOR v_column_name IN
        SELECT key FROM jsonb_each(p_old_columns)
        EXCEPT
        SELECT key FROM jsonb_each(p_new_columns)
    LOOP
        RETURN QUERY
        SELECT
            v_column_name,
            'DROP'::pggit.change_type,
            'MAJOR'::pggit.change_severity,
            p_old_columns->v_column_name,
            NULL::JSONB,
            'Column dropped: ' || v_column_name;
    END LOOP;

    -- Check for new columns (MINOR change)
    FOR v_column_name IN
        SELECT key FROM jsonb_each(p_new_columns)
        EXCEPT
        SELECT key FROM jsonb_each(p_old_columns)
    LOOP
        v_new_def := p_new_columns->v_column_name;
        RETURN QUERY
        SELECT
            v_column_name,
            'CREATE'::pggit.change_type,
            'MINOR'::pggit.change_severity,
            NULL::JSONB,
            v_new_def,
            'Column added: ' || v_column_name;
    END LOOP;

    -- Check for modified columns
    FOR v_column_name IN
        SELECT key FROM jsonb_each(p_old_columns)
        INTERSECT
        SELECT key FROM jsonb_each(p_new_columns)
    LOOP
        v_old_def := p_old_columns->v_column_name;
        v_new_def := p_new_columns->v_column_name;

        IF v_old_def IS DISTINCT FROM v_new_def THEN
            -- Determine severity based on change type
            RETURN QUERY
            SELECT
                v_column_name,
                'ALTER'::pggit.change_type,
                CASE
                    -- Changing from nullable to not null is breaking
                    WHEN (v_old_def->>'nullable')::boolean = true
                     AND (v_new_def->>'nullable')::boolean = false THEN 'MAJOR'::pggit.change_severity
                    -- Changing data type is usually breaking
                    WHEN v_old_def->>'type' IS DISTINCT FROM v_new_def->>'type' THEN 'MAJOR'::pggit.change_severity
                    -- Other changes are minor
                    ELSE 'MINOR'::pggit.change_severity
                END,
                v_old_def,
                v_new_def,
                'Column modified: ' || v_column_name;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to generate CREATE TABLE statement
CREATE OR REPLACE FUNCTION pggit.generate_create_table(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_columns JSONB
) RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
    v_column_defs TEXT[];
    v_column_name TEXT;
    v_column_def JSONB;
BEGIN
    -- Build column definitions
    FOR v_column_name, v_column_def IN SELECT * FROM jsonb_each(p_columns) LOOP
        v_column_defs := array_append(v_column_defs,
            format('%I %s%s%s',
                v_column_name,
                v_column_def->>'type',
                CASE WHEN (v_column_def->>'nullable')::boolean = false THEN ' NOT NULL' ELSE '' END,
                CASE WHEN v_column_def->>'default' IS NOT NULL THEN ' DEFAULT ' || v_column_def->>'default' ELSE '' END
            )
        );
    END LOOP;

    -- Build CREATE TABLE statement
    v_sql := format('CREATE TABLE %I.%I (%s)',
        p_schema_name,
        p_table_name,
        array_to_string(v_column_defs, ', ')
    );

    RETURN v_sql;
END;
$$ LANGUAGE plpgsql;

-- Function to generate ALTER TABLE statements for column changes
CREATE OR REPLACE FUNCTION pggit.generate_alter_column(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_column_name TEXT,
    p_change_type pggit.change_type,
    p_old_def JSONB,
    p_new_def JSONB
) RETURNS TEXT AS $$
DECLARE
    v_sql TEXT;
BEGIN
    CASE p_change_type
        WHEN 'CREATE' THEN
            v_sql := format('ALTER TABLE %I.%I ADD COLUMN %I %s%s%s',
                p_schema_name,
                p_table_name,
                p_column_name,
                p_new_def->>'type',
                CASE WHEN (p_new_def->>'nullable')::boolean = false THEN ' NOT NULL' ELSE '' END,
                CASE WHEN p_new_def->>'default' IS NOT NULL THEN ' DEFAULT ' || p_new_def->>'default' ELSE '' END
            );

        WHEN 'DROP' THEN
            v_sql := format('ALTER TABLE %I.%I DROP COLUMN %I',
                p_schema_name,
                p_table_name,
                p_column_name
            );

        WHEN 'ALTER' THEN
            -- Generate appropriate ALTER based on what changed
            IF p_old_def->>'type' IS DISTINCT FROM p_new_def->>'type' THEN
                v_sql := format('ALTER TABLE %I.%I ALTER COLUMN %I TYPE %s',
                    p_schema_name,
                    p_table_name,
                    p_column_name,
                    p_new_def->>'type'
                );
            ELSIF (p_old_def->>'nullable')::boolean IS DISTINCT FROM (p_new_def->>'nullable')::boolean THEN
                IF (p_new_def->>'nullable')::boolean = false THEN
                    v_sql := format('ALTER TABLE %I.%I ALTER COLUMN %I SET NOT NULL',
                        p_schema_name,
                        p_table_name,
                        p_column_name
                    );
                ELSE
                    v_sql := format('ALTER TABLE %I.%I ALTER COLUMN %I DROP NOT NULL',
                        p_schema_name,
                        p_table_name,
                        p_column_name
                    );
                END IF;
            END IF;
    END CASE;

    RETURN v_sql;
END;
$$ LANGUAGE plpgsql;

-- Function to detect schema changes between two states
CREATE OR REPLACE FUNCTION pggit.detect_schema_changes(
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TABLE (
    object_type pggit.object_type,
    object_name TEXT,
    change_type pggit.change_type,
    change_severity pggit.change_severity,
    current_version INTEGER,
    sql_statement TEXT
) AS $$
DECLARE
    v_table RECORD;
    v_current_columns JSONB;
    v_tracked_columns JSONB;
    v_column_change RECORD;
    v_object_id INTEGER;
BEGIN
    -- Check each table in the schema
    FOR v_table IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = p_schema_name
        AND table_type = 'BASE TABLE'
    LOOP
        -- Get current columns from database
        v_current_columns := pggit.extract_table_columns(p_schema_name, v_table.table_name::text);

        -- Get tracked columns
        SELECT metadata->'columns', id
        INTO v_tracked_columns, v_object_id
        FROM pggit.objects o
        WHERE o.object_type = 'TABLE'::pggit.object_type
        AND o.schema_name = p_schema_name
        AND o.object_name = v_table.table_name::text
        AND o.is_active = true;

        IF v_tracked_columns IS NULL THEN
            -- New table
            RETURN QUERY
            SELECT
                'TABLE'::pggit.object_type,
                v_table.table_name::text,
                'CREATE'::pggit.change_type,
                'MINOR'::pggit.change_severity,
                0,
                pggit.generate_create_table(p_schema_name, v_table.table_name::text, v_current_columns);
        ELSE
            -- Compare columns
            FOR v_column_change IN
                SELECT * FROM pggit.compare_columns(v_tracked_columns, v_current_columns)
            LOOP
                RETURN QUERY
                SELECT
                    'COLUMN'::pggit.object_type,
                    v_table.table_name::text || '.' || v_column_change.column_name,
                    v_column_change.change_type,
                    v_column_change.change_severity,
                    (SELECT version FROM pggit.objects WHERE id = v_object_id),
                    pggit.generate_alter_column(
                        p_schema_name,
                        v_table.table_name::text,
                        v_column_change.column_name,
                        v_column_change.change_type,
                        v_column_change.old_definition,
                        v_column_change.new_definition
                    );
            END LOOP;
        END IF;
    END LOOP;

    -- Check for dropped tables
    FOR v_table IN
        SELECT object_name, version
        FROM pggit.objects
        WHERE object_type = 'TABLE'
        AND schema_name = p_schema_name
        AND is_active = true
        AND NOT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = p_schema_name
            AND table_name = object_name
        )
    LOOP
        RETURN QUERY
        SELECT
            'TABLE'::pggit.object_type,
            v_table.object_name,
            'DROP'::pggit.change_type,
            'MAJOR'::pggit.change_severity,
            v_table.version,
            format('DROP TABLE %I.%I', p_schema_name, v_table.object_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to generate a migration script
CREATE OR REPLACE FUNCTION pggit.generate_migration(
    p_version TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TEXT AS $$
DECLARE
    v_version TEXT;
    v_changes RECORD;
    v_up_statements TEXT[];
    v_down_statements TEXT[];
    v_migration_id INTEGER;
    v_checksum TEXT;
BEGIN
    -- Generate version if not provided
    v_version := COALESCE(p_version, to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MISS'));

    -- Collect all changes
    FOR v_changes IN
        SELECT * FROM pggit.detect_schema_changes(p_schema_name)
        ORDER BY
            CASE change_type
                WHEN 'CREATE' THEN 1
                WHEN 'ALTER' THEN 2
                WHEN 'DROP' THEN 3
            END
    LOOP
        v_up_statements := array_append(v_up_statements, v_changes.sql_statement || ';');

        -- Generate reverse operations for down migration
        -- This is simplified - a full implementation would be more sophisticated
        CASE v_changes.change_type
            WHEN 'CREATE' THEN
                v_down_statements := array_prepend(
                    format('DROP %s %s;', v_changes.object_type, v_changes.object_name),
                    v_down_statements
                );
            WHEN 'DROP' THEN
                v_down_statements := array_prepend(
                    format('-- ROLLBACK: Recreate %s %s (original DDL stored in history)', v_changes.object_type, v_changes.object_name),
                    v_down_statements
                );
        END CASE;
    END LOOP;

    -- Create migration record
    IF array_length(v_up_statements, 1) > 0 THEN
        v_checksum := md5(array_to_string(v_up_statements, ''));

        INSERT INTO pggit.migrations (
            version,
            description,
            up_script,
            down_script,
            checksum
        ) VALUES (
            v_version,
            COALESCE(p_description, 'Auto-generated migration'),
            array_to_string(v_up_statements, E'\n'),
            array_to_string(v_down_statements, E'\n'),
            v_checksum
        ) RETURNING id INTO v_migration_id;

        RETURN format(E'-- Migration: %s\n-- Description: %s\n-- Generated: %s\n\n-- UP\n%s\n\n-- DOWN\n%s',
            v_version,
            COALESCE(p_description, 'Auto-generated migration'),
            CURRENT_TIMESTAMP,
            array_to_string(v_up_statements, E'\n'),
            array_to_string(v_down_statements, E'\n')
        );
    ELSE
        RETURN '-- No changes detected';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to apply a migration
CREATE OR REPLACE FUNCTION pggit.apply_migration(
    p_version TEXT
) RETURNS VOID AS $$
DECLARE
    v_migration RECORD;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
BEGIN
    -- Get migration
    SELECT * INTO v_migration
    FROM pggit.migrations
    WHERE version = p_version
    AND applied_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Migration % not found or already applied', p_version;
    END IF;

    v_start_time := clock_timestamp();

    -- Execute migration
    EXECUTE v_migration.up_script;

    v_end_time := clock_timestamp();

    -- Mark as applied
    UPDATE pggit.migrations
    SET applied_at = CURRENT_TIMESTAMP,
        applied_by = CURRENT_USER,
        execution_time_ms = EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER
    WHERE id = v_migration.id;

    RAISE NOTICE 'Migration % applied successfully in % ms',
        p_version,
        EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- View to show pending migrations
CREATE OR REPLACE VIEW pggit.pending_migrations AS
SELECT
    version,
    description,
    created_at,
    length(up_script) AS script_size
FROM pggit.migrations
WHERE applied_at IS NULL
ORDER BY version;