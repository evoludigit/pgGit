-- pgGit v0.0.1 - Phase 1: Event Triggers for DDL Capture
-- Automatically captures DDL commands and records in schema tracking
-- Date: 2025-12-24

-- 1. Main DDL event trigger function
-- Captures CREATE/ALTER/DROP TABLE, CREATE/ALTER FUNCTION, etc.
CREATE OR REPLACE FUNCTION pggit.on_ddl_command()
RETURNS event_trigger AS $$
DECLARE
    v_ddl_command TEXT;
    v_event_type TEXT;
    v_object_type TEXT;
    v_schema_name TEXT;
    v_object_name TEXT;
    v_current_definition TEXT;
    v_content_hash CHAR(64);
    v_object_id BIGINT;
    v_change_type TEXT;
    v_change_severity TEXT;
    v_before_hash CHAR(64);
    v_before_definition TEXT;
    v_before_version TEXT;
    v_after_version TEXT;
    v_commit_hash CHAR(64);
    v_branch_id INTEGER;
    v_current_branch TEXT;
    v_author_name TEXT;
    v_author_time TIMESTAMP;
    r_object record;
BEGIN
    -- Get event details
    v_event_type := tg_event;

    -- Get DDL command text
    SELECT command_type, command_text
    INTO v_object_type, v_ddl_command
    FROM pg_event_trigger_ddl_commands()
    LIMIT 1;

    IF v_ddl_command IS NULL THEN
        RETURN;
    END IF;

    -- Extract schema and object name from object identity
    FOR r_object IN
        SELECT classid, objid, objsubid, object_type, schema_name, object_name, object_identity
        FROM pg_event_trigger_ddl_commands()
    LOOP
        v_object_type := r_object.object_type;
        v_schema_name := r_object.schema_name;
        v_object_name := r_object.object_name;

        -- Skip system schemas
        IF v_schema_name IN ('pg_catalog', 'information_schema', 'pg_toast') THEN
            CONTINUE;
        END IF;

        -- Skip pggit schema itself
        IF v_schema_name = 'pggit' THEN
            CONTINUE;
        END IF;

        -- Get current definition from catalog
        v_current_definition := r_object.object_identity;

        -- Calculate content hash
        v_content_hash := pggit.generate_sha256(pggit.normalize_sql(v_current_definition));

        -- Determine change type
        CASE v_event_type
            WHEN 'ddl_command_start' THEN
                -- On start, we won't have full object info yet
                CONTINUE;
            WHEN 'ddl_command_end' THEN
                v_change_type := CASE r_object.object_type
                    WHEN 'TABLE' THEN
                        CASE
                            WHEN EXISTS (SELECT 1 FROM pggit.schema_objects
                                        WHERE object_type = 'TABLE'
                                          AND schema_name = v_schema_name
                                          AND object_name = v_object_name
                                          AND is_active = true) THEN 'ALTER'
                            ELSE 'CREATE'
                        END
                    WHEN 'FUNCTION' THEN
                        CASE
                            WHEN EXISTS (SELECT 1 FROM pggit.schema_objects
                                        WHERE object_type = 'FUNCTION'
                                          AND schema_name = v_schema_name
                                          AND object_name = v_object_name
                                          AND is_active = true) THEN 'ALTER'
                            ELSE 'CREATE'
                        END
                    ELSE 'ALTER'
                END;
        END CASE;

        -- Get current branch
        v_current_branch := pggit.get_current_branch();
        v_branch_id := pggit.get_branch_by_name(v_current_branch);

        -- If branch doesn't exist, skip
        IF v_branch_id IS NULL THEN
            CONTINUE;
        END IF;

        -- Get or create object record
        SELECT object_id, content_hash, version_major, version_minor, version_patch, current_definition
        INTO v_object_id, v_before_hash, v_before_version, v_after_version, v_object_name, v_before_definition
        FROM pggit.schema_objects
        WHERE object_type = r_object.object_type
          AND schema_name = v_schema_name
          AND object_name = r_object.object_name
          AND is_active = true;

        IF v_change_type = 'CREATE' THEN
            -- Insert new object record
            INSERT INTO pggit.schema_objects (
                object_type, schema_name, object_name,
                current_definition, content_hash,
                version_major, version_minor, version_patch,
                is_active, first_seen_commit_hash,
                created_at, last_modified_at
            ) VALUES (
                r_object.object_type, v_schema_name, r_object.object_name,
                v_current_definition, v_content_hash,
                1, 0, 0,
                true, NULL,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
            RETURNING object_id INTO v_object_id;

            v_before_hash := NULL;
            v_before_definition := NULL;
            v_change_severity := 'MAJOR';
            v_after_version := '1.0.0';

        ELSIF v_change_type = 'ALTER' THEN
            -- Update existing object
            v_before_hash := (SELECT content_hash FROM pggit.schema_objects WHERE object_id = v_object_id);
            v_before_definition := (SELECT current_definition FROM pggit.schema_objects WHERE object_id = v_object_id);

            -- Determine severity based on hash change
            IF v_before_hash = v_content_hash THEN
                -- No actual change
                CONTINUE;
            ELSE
                -- For now, mark as MINOR - could be enhanced with semantic analysis
                v_change_severity := 'MINOR';
            END IF;

            UPDATE pggit.schema_objects
            SET current_definition = v_current_definition,
                content_hash = v_content_hash,
                version_minor = version_minor + 1,
                last_modified_at = CURRENT_TIMESTAMP
            WHERE object_id = v_object_id;

            v_after_version := (SELECT format('%s.%s.%s', version_major, version_minor, version_patch)
                               FROM pggit.schema_objects WHERE object_id = v_object_id);
        END IF;

        -- Generate commit hash for this change
        v_author_name := CURRENT_USER;
        v_author_time := CURRENT_TIMESTAMP;
        v_commit_hash := pggit.generate_sha256(
            format('%s_%s_%s_%s_%s_%s',
                v_object_type,
                v_schema_name,
                r_object.object_name,
                v_change_type,
                v_content_hash,
                v_author_time
            )
        );

        -- Create commit record
        INSERT INTO pggit.commits (
            commit_hash,
            parent_commit_hash,
            branch_id,
            object_changes,
            tree_hash,
            author_name,
            author_time,
            commit_message,
            created_at
        ) VALUES (
            v_commit_hash,
            (SELECT head_commit_hash FROM pggit.branches WHERE branch_id = v_branch_id),
            v_branch_id,
            jsonb_build_object(
                v_object_id::text, jsonb_build_object(
                    'action', v_change_type,
                    'before_hash', v_before_hash,
                    'after_hash', v_content_hash
                )
            ),
            pggit.get_current_schema_hash(),
            v_author_name,
            v_author_time,
            format('%s %s.%s.%s',
                v_change_type,
                v_schema_name,
                r_object.object_name,
                r_object.object_type
            ),
            CURRENT_TIMESTAMP
        );

        -- Update branch head commit
        UPDATE pggit.branches
        SET head_commit_hash = v_commit_hash
        WHERE branch_id = v_branch_id;

        -- Record in object history
        INSERT INTO pggit.object_history (
            object_id,
            change_type,
            change_severity,
            before_hash,
            after_hash,
            before_version,
            after_version,
            before_definition,
            after_definition,
            commit_hash,
            branch_id,
            author_name,
            author_time,
            created_at
        ) VALUES (
            v_object_id,
            v_change_type,
            v_change_severity,
            v_before_hash,
            v_content_hash,
            v_before_version,
            v_after_version,
            v_before_definition,
            v_current_definition,
            v_commit_hash,
            v_branch_id,
            v_author_name,
            v_author_time,
            CURRENT_TIMESTAMP
        );

    END LOOP;

END;
$$ LANGUAGE plpgsql;

-- 2. Create event trigger
CREATE EVENT TRIGGER pggit_ddl_capture
    ON ddl_command_end
    EXECUTE FUNCTION pggit.on_ddl_command();

-- 3. Alternative simpler trigger for testing (can be disabled)
CREATE OR REPLACE FUNCTION pggit.on_ddl_command_simple()
RETURNS event_trigger AS $$
BEGIN
    -- Simple version: just log that DDL was executed
    -- More advanced version would parse the command
    RAISE NOTICE 'pgGit: DDL command executed - %', tg_event;
END;
$$ LANGUAGE plpgsql;
