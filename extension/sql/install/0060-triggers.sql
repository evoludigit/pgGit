-- pggit v1.0 — Event trigger functions and registration
-- Must be loaded after 0040-functions-internal.sql

-- ---------------------------------------------------------------------------
-- ddl_command_end — fires after CREATE/ALTER
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.on_ddl_command_end()
RETURNS EVENT_TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cmd          RECORD;
    v_obj_type     pggit.object_type;
    v_branch_id    BIGINT;
    v_branch_name  TEXT;
    v_norm_ddl     TEXT;
    v_content_hash TEXT;
    v_operation    TEXT;
    v_obj_id       BIGINT;
BEGIN
    IF pggit_internal.is_tracking_paused() THEN
        RETURN;
    END IF;

    v_branch_name := pggit_internal.current_branch_name();

    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = v_branch_name AND status = 'active';

    IF v_branch_id IS NULL THEN
        RETURN;
    END IF;

    FOR v_cmd IN
        SELECT *
        FROM pg_event_trigger_ddl_commands()
        WHERE schema_name IS NOT NULL
    LOOP
        IF NOT pggit_internal.is_tracked_schema(v_cmd.schema_name) THEN
            CONTINUE;
        END IF;

        v_obj_type := pggit_internal.resolve_object_type(
            v_cmd.object_type, v_cmd.command_tag
        );
        IF v_obj_type IS NULL THEN
            CONTINUE;
        END IF;

        BEGIN
            v_norm_ddl     := pggit_internal.normalize_object(v_cmd.objid, v_obj_type);
            v_content_hash := encode(sha256(v_norm_ddl::bytea), 'hex');
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;

        IF v_norm_ddl IS NULL OR v_content_hash IS NULL THEN
            CONTINUE;
        END IF;

        v_operation := CASE
            WHEN v_cmd.command_tag LIKE 'CREATE%' THEN 'CREATE'
            ELSE 'ALTER'
        END;

        INSERT INTO pggit.objects (
            branch_id, schema_name, object_name, object_type,
            content_hash, ddl_text, pg_oid, is_deleted
        )
        VALUES (
            v_branch_id,
            v_cmd.schema_name,
            v_cmd.object_identity,
            v_obj_type,
            v_content_hash,
            v_norm_ddl,
            v_cmd.objid,
            FALSE
        )
        ON CONFLICT (branch_id, schema_name, object_name, object_type)
        DO UPDATE SET
            content_hash = EXCLUDED.content_hash,
            ddl_text     = EXCLUDED.ddl_text,
            pg_oid       = EXCLUDED.pg_oid,
            is_deleted   = FALSE,
            updated_at   = now()
        RETURNING id INTO v_obj_id;

        INSERT INTO pggit.history (
            branch_id, object_id, commit_id, operation, content_hash, ddl_text
        )
        VALUES (
            v_branch_id,
            v_obj_id,
            NULL,
            v_operation,
            v_content_hash,
            v_norm_ddl
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- sql_drop — fires before DROP
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.on_sql_drop()
RETURNS EVENT_TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_drop        RECORD;
    v_obj_type    pggit.object_type;
    v_branch_id   BIGINT;
    v_branch_name TEXT;
    v_obj_id      BIGINT;
    v_last_hash   TEXT;
    v_last_ddl    TEXT;
BEGIN
    IF pggit_internal.is_tracking_paused() THEN
        RETURN;
    END IF;

    v_branch_name := pggit_internal.current_branch_name();

    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = v_branch_name AND status = 'active';

    IF v_branch_id IS NULL THEN
        RETURN;
    END IF;

    FOR v_drop IN
        SELECT *
        FROM pg_event_trigger_dropped_objects()
        WHERE schema_name IS NOT NULL
    LOOP
        IF NOT pggit_internal.is_tracked_schema(v_drop.schema_name) THEN
            CONTINUE;
        END IF;

        v_obj_type := pggit_internal.resolve_object_type(
            v_drop.object_type, v_drop.object_type
        );
        IF v_obj_type IS NULL THEN
            CONTINUE;
        END IF;

        SELECT id, content_hash, ddl_text
        INTO v_obj_id, v_last_hash, v_last_ddl
        FROM pggit.objects
        WHERE branch_id  = v_branch_id
          AND schema_name = v_drop.schema_name
          AND object_name = v_drop.object_identity
          AND object_type = v_obj_type
          AND is_deleted  = FALSE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        UPDATE pggit.objects
        SET is_deleted = TRUE,
            pg_oid     = NULL,
            updated_at = now()
        WHERE id = v_obj_id;

        INSERT INTO pggit.history (
            branch_id, object_id, commit_id, operation, content_hash, ddl_text
        )
        VALUES (
            v_branch_id,
            v_obj_id,
            NULL,
            'DROP',
            v_last_hash,
            v_last_ddl
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Register event triggers
-- ---------------------------------------------------------------------------

CREATE EVENT TRIGGER pggit_ddl_command_end
    ON ddl_command_end
    EXECUTE FUNCTION pggit_internal.on_ddl_command_end();

CREATE EVENT TRIGGER pggit_sql_drop
    ON sql_drop
    EXECUTE FUNCTION pggit_internal.on_sql_drop();
