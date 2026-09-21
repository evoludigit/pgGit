-- pggit v1.0 — Internal functions
-- All objects in pggit_internal schema. Not part of the public API.

-- ---------------------------------------------------------------------------
-- Schema filtering
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.is_tracked_schema(p_schema TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_schema NOT IN (
        'pg_catalog',
        'information_schema',
        'pg_toast',
        'pggit',
        'pggit_internal'
    )
    AND p_schema NOT LIKE 'pg_temp%'
    AND p_schema NOT LIKE 'pg_toast_temp%';
$$;

COMMENT ON FUNCTION pggit_internal.is_tracked_schema(TEXT) IS
    'Returns TRUE if the schema should be tracked by pggit. Excludes system '
    'schemas, temp schemas, and pggit own schemas.';

-- ---------------------------------------------------------------------------
-- GUC helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.current_branch_name()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        current_setting('pggit.current_branch', TRUE),
        'main'
    );
$$;

CREATE OR REPLACE FUNCTION pggit_internal.branch_id(p_name TEXT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT id FROM pggit.branches WHERE name = p_name;
$$;

COMMENT ON FUNCTION pggit_internal.branch_id(TEXT) IS
    'Convenience: resolve branch name to id. Returns NULL if not found.';

-- ---------------------------------------------------------------------------
-- Tenant management helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('pggit.tenant_id', TRUE), '')::UUID;
$$;

COMMENT ON FUNCTION pggit_internal.current_tenant_id() IS
    'Get the current tenant UUID from session configuration. '
    'Returns NULL if no tenant set (admin/shared mode).';

CREATE OR REPLACE FUNCTION pggit_internal.set_tenant_id(p_tenant_id UUID)
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT set_config('pggit.tenant_id', COALESCE(p_tenant_id::TEXT, ''), FALSE);
$$;

COMMENT ON FUNCTION pggit_internal.set_tenant_id(UUID) IS
    'Set the tenant ID for the current session. NULL clears the tenant.';

CREATE OR REPLACE FUNCTION pggit_internal.is_tenant_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT pg_has_role(current_user, 'pggit_admin', 'MEMBER')
        OR current_setting('pggit.tenant_id', TRUE) IS NULL;
$$;

COMMENT ON FUNCTION pggit_internal.is_tenant_admin() IS
    'Check if current user is a tenant admin or in admin mode (no tenant set).';

-- ---------------------------------------------------------------------------
-- Tracking pause/resume (used by merge completion)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.is_tracking_paused()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        current_setting('pggit.tracking_paused', TRUE),
        'false'
    )::BOOLEAN;
$$;

-- ---------------------------------------------------------------------------
-- DDL normalization — one function per object type
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.normalize_table(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    WITH
    cols AS (
        SELECT
            a.attnum,
            a.attname                                        AS col_name,
            format_type(a.atttypid, a.atttypmod)            AS col_type,
            CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END AS not_null,
            CASE WHEN a.atthasdef
                 THEN ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid)
                 ELSE ''
            END                                              AS col_default
        FROM pg_attribute a
        LEFT JOIN pg_attrdef d
               ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = p_oid
          AND a.attnum > 0
          AND NOT a.attisdropped
        ORDER BY a.attnum
    ),
    col_list AS (
        SELECT string_agg(
            col_name || ' ' || col_type || not_null || col_default,
            E',\n' ORDER BY attnum
        ) AS text
        FROM cols
    ),
    constraints AS (
        SELECT
            conname,
            pg_get_constraintdef(oid, TRUE) AS def
        FROM pg_constraint
        WHERE conrelid = p_oid
          AND contype <> 'f'
        ORDER BY conname
    ),
    con_list AS (
        SELECT string_agg(
            'CONSTRAINT ' || conname || ' ' || def,
            E',\n' ORDER BY conname
        ) AS text
        FROM constraints
    ),
    indexes AS (
        SELECT
            indexrelid,
            pg_get_indexdef(indexrelid, 0, TRUE) AS def
        FROM pg_index
        WHERE indrelid = p_oid
          AND NOT indisprimary
        ORDER BY indexrelid
    ),
    idx_list AS (
        SELECT string_agg(def, E';\n' ORDER BY indexrelid) AS text
        FROM indexes
    )
    SELECT
        'CREATE TABLE ' || p_oid::regclass::TEXT || E' (\n'
        || COALESCE(col_list.text, '')
        || CASE WHEN con_list.text IS NOT NULL
                THEN E',\n' || con_list.text
                ELSE ''
           END
        || E'\n)'
        || CASE WHEN idx_list.text IS NOT NULL
                THEN E';\n' || idx_list.text
                ELSE ''
           END
    FROM col_list
    CROSS JOIN con_list
    CROSS JOIN idx_list;
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_view(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT 'CREATE OR REPLACE VIEW ' || p_oid::regclass::TEXT
        || E' AS\n'
        || pg_get_viewdef(p_oid, TRUE);
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_matview(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT 'CREATE MATERIALIZED VIEW ' || p_oid::regclass::TEXT
        || E' AS\n'
        || pg_get_viewdef(p_oid, TRUE);
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_function(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT pg_get_functiondef(p_oid);
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_trigger(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT pg_get_triggerdef(p_oid, TRUE);
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_type(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT CASE c.relkind
        WHEN 'c' THEN
            'CREATE TYPE ' || p_oid::regtype::TEXT
            || E' AS (\n'
            || (
                SELECT string_agg(
                    a.attname || ' ' || format_type(a.atttypid, a.atttypmod),
                    E',\n' ORDER BY a.attnum
                )
                FROM pg_attribute a
                WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
            )
            || E'\n)'
        ELSE
            'CREATE TYPE ' || p_oid::regtype::TEXT
            || E' AS ENUM (\n'
            || (
                SELECT string_agg(
                    quote_literal(enumlabel),
                    E',\n' ORDER BY enumsortorder
                )
                FROM pg_enum
                WHERE enumtypid = p_oid
            )
            || E'\n)'
    END
    FROM pg_class c
    JOIN pg_type t ON t.typrelid = c.oid
    WHERE t.oid = p_oid;
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_domain(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT
        'CREATE DOMAIN ' || p_oid::regtype::TEXT
        || ' AS ' || format_type(t.typbasetype, t.typtypmod)
        || CASE WHEN t.typnotnull THEN ' NOT NULL' ELSE '' END
        || CASE WHEN t.typdefault IS NOT NULL
                THEN ' DEFAULT ' || t.typdefault
                ELSE ''
           END
        || COALESCE(
            (
                SELECT string_agg(
                    ' CONSTRAINT ' || conname || ' ' || pg_get_constraintdef(oid, TRUE),
                    ' '
                )
                FROM pg_constraint
                WHERE contypid = p_oid
            ),
            ''
        )
    FROM pg_type t
    WHERE t.oid = p_oid;
$$;

CREATE OR REPLACE FUNCTION pggit_internal.normalize_sequence(p_oid OID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT
        'CREATE SEQUENCE ' || p_oid::regclass::TEXT
        || ' AS ' || seqtypid::regtype::TEXT
        || ' INCREMENT BY ' || seqincrement
        || ' MINVALUE ' || seqmin
        || ' MAXVALUE ' || seqmax
        || ' CACHE ' || seqcache
        || CASE WHEN seqcycle THEN ' CYCLE' ELSE ' NO CYCLE' END
    FROM pg_sequence
    WHERE seqrelid = p_oid;
$$;

-- ---------------------------------------------------------------------------
-- Dispatcher and hash entry point
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.normalize_object(
    p_oid         OID,
    p_object_type pggit.object_type
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN CASE p_object_type
        WHEN 'table'             THEN pggit_internal.normalize_table(p_oid)
        WHEN 'view'              THEN pggit_internal.normalize_view(p_oid)
        WHEN 'materialized_view' THEN pggit_internal.normalize_matview(p_oid)
        WHEN 'function'          THEN pggit_internal.normalize_function(p_oid)
        WHEN 'procedure'         THEN pggit_internal.normalize_function(p_oid)
        WHEN 'trigger'           THEN pggit_internal.normalize_trigger(p_oid)
        WHEN 'type'              THEN pggit_internal.normalize_type(p_oid)
        WHEN 'domain'            THEN pggit_internal.normalize_domain(p_oid)
        WHEN 'sequence'          THEN pggit_internal.normalize_sequence(p_oid)
        WHEN 'index'             THEN pg_get_indexdef(p_oid, 0, TRUE)
        ELSE
            NULL
    END;
END;
$$;

CREATE OR REPLACE FUNCTION pggit_internal.compute_hash(
    p_oid         OID,
    p_object_type pggit.object_type
)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT encode(
        sha256(pggit_internal.normalize_object(p_oid, p_object_type)::bytea),
        'hex'
    );
$$;

-- ---------------------------------------------------------------------------
-- Object type resolver (event trigger → pggit.object_type)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.resolve_object_type(
    p_object_type TEXT,
    p_command_tag TEXT
)
RETURNS pggit.object_type
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE lower(p_object_type)
        WHEN 'table'             THEN 'table'::pggit.object_type
        WHEN 'view'              THEN 'view'::pggit.object_type
        WHEN 'materialized view' THEN 'materialized_view'::pggit.object_type
        WHEN 'function'          THEN 'function'::pggit.object_type
        WHEN 'procedure'         THEN 'procedure'::pggit.object_type
        WHEN 'trigger'           THEN 'trigger'::pggit.object_type
        WHEN 'index'             THEN 'index'::pggit.object_type
        WHEN 'sequence'          THEN 'sequence'::pggit.object_type
        WHEN 'type'              THEN 'type'::pggit.object_type
        WHEN 'domain'            THEN 'domain'::pggit.object_type
        ELSE NULL
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Tree hash computation
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.compute_tree_hash(p_branch_id BIGINT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT encode(
        sha256(
            COALESCE(
                string_agg(
                    content_hash,
                    E'\n' ORDER BY schema_name, object_name, object_type::TEXT
                ),
                ''
            )::bytea
        ),
        'hex'
    )
    FROM pggit.objects
    WHERE branch_id = p_branch_id
      AND is_deleted = FALSE;
$$;

-- ---------------------------------------------------------------------------
-- Merge: LCA finder
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.find_lca(
    p_source_commit_id BIGINT,
    p_target_commit_id BIGINT
)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE
    source_ancestors AS (
        SELECT id, parent_id, 0 AS depth
        FROM pggit.commits
        WHERE id = p_source_commit_id

        UNION ALL

        SELECT c.id, c.parent_id, sa.depth + 1
        FROM pggit.commits c
        JOIN source_ancestors sa ON sa.parent_id = c.id
    ),
    target_ancestors AS (
        SELECT id, parent_id, 0 AS depth
        FROM pggit.commits
        WHERE id = p_target_commit_id

        UNION ALL

        SELECT c.id, c.parent_id, ta.depth + 1
        FROM pggit.commits c
        JOIN target_ancestors ta ON ta.parent_id = c.id
    )
    SELECT sa.id
    FROM source_ancestors sa
    JOIN target_ancestors ta ON ta.id = sa.id
    ORDER BY sa.depth ASC
    LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Merge: object classification
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.classify_merge_objects(
    p_merge_id         BIGINT,
    p_lca_commit_id    BIGINT,
    p_source_branch_id BIGINT,
    p_target_branch_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_obj            RECORD;
    v_conflict_status pggit.conflict_status;
BEGIN
    FOR v_obj IN
        WITH
        -- Objects at LCA: most recent state of each object in history up to LCA
        lca_objects AS (
            SELECT DISTINCT ON (o.schema_name, o.object_name, o.object_type)
                o.schema_name, o.object_name, o.object_type,
                h.content_hash, h.ddl_text,
                (h.operation = 'DROP') AS is_deleted
            FROM pggit.history h
            JOIN pggit.objects o ON o.id = h.object_id
            WHERE h.commit_id IN (
                WITH RECURSIVE ancestors AS (
                    SELECT id, parent_id FROM pggit.commits WHERE id = p_lca_commit_id
                    UNION ALL
                    SELECT c.id, c.parent_id FROM pggit.commits c
                    JOIN ancestors a ON a.parent_id = c.id
                )
                SELECT id FROM ancestors
            )
            ORDER BY o.schema_name, o.object_name, o.object_type, h.changed_at DESC
        ),
        lca AS (
            SELECT schema_name, object_name, object_type, content_hash, ddl_text
            FROM lca_objects
            WHERE NOT is_deleted
        ),
        src AS (
            SELECT schema_name, object_name, object_type, content_hash, ddl_text
            FROM pggit.objects
            WHERE branch_id = p_source_branch_id AND is_deleted = FALSE
        ),
        tgt AS (
            SELECT schema_name, object_name, object_type, content_hash, ddl_text
            FROM pggit.objects
            WHERE branch_id = p_target_branch_id AND is_deleted = FALSE
        ),
        all_objects AS (
            SELECT schema_name, object_name, object_type FROM src
            UNION
            SELECT schema_name, object_name, object_type FROM tgt
            UNION
            SELECT schema_name, object_name, object_type FROM lca
        )
        SELECT
            ao.schema_name, ao.object_name, ao.object_type,
            lca.content_hash AS lca_hash, lca.ddl_text AS lca_ddl,
            src.content_hash AS src_hash, src.ddl_text AS src_ddl,
            tgt.content_hash AS tgt_hash, tgt.ddl_text AS tgt_ddl
        FROM all_objects ao
        LEFT JOIN lca ON lca.schema_name = ao.schema_name
                     AND lca.object_name = ao.object_name
                     AND lca.object_type = ao.object_type
        LEFT JOIN src ON src.schema_name = ao.schema_name
                     AND src.object_name = ao.object_name
                     AND src.object_type = ao.object_type
        LEFT JOIN tgt ON tgt.schema_name = ao.schema_name
                     AND tgt.object_name = ao.object_name
                     AND tgt.object_type = ao.object_type
        -- Skip case 1: all three identical (nothing to merge)
        WHERE NOT (
            lca.content_hash IS NOT DISTINCT FROM src.content_hash
            AND lca.content_hash IS NOT DISTINCT FROM tgt.content_hash
        )
    LOOP
        v_conflict_status := CASE
            -- Case 5: both changed differently
            WHEN v_obj.lca_hash IS NOT NULL
                 AND v_obj.src_hash IS NOT NULL
                 AND v_obj.tgt_hash IS NOT NULL
                 AND v_obj.src_hash <> v_obj.lca_hash
                 AND v_obj.tgt_hash <> v_obj.lca_hash
                 AND v_obj.src_hash <> v_obj.tgt_hash
                THEN 'conflicted'::pggit.conflict_status
            -- Case 11: both added differently
            WHEN v_obj.lca_hash IS NULL
                 AND v_obj.src_hash IS NOT NULL
                 AND v_obj.tgt_hash IS NOT NULL
                 AND v_obj.src_hash <> v_obj.tgt_hash
                THEN 'conflicted'::pggit.conflict_status
            -- Case 12: source deleted, target changed
            WHEN v_obj.lca_hash IS NOT NULL
                 AND v_obj.src_hash IS NULL
                 AND v_obj.tgt_hash IS NOT NULL
                 AND v_obj.tgt_hash <> v_obj.lca_hash
                THEN 'conflicted'::pggit.conflict_status
            -- Case 13: source changed, target deleted
            WHEN v_obj.lca_hash IS NOT NULL
                 AND v_obj.src_hash IS NOT NULL
                 AND v_obj.tgt_hash IS NULL
                 AND v_obj.src_hash <> v_obj.lca_hash
                THEN 'conflicted'::pggit.conflict_status
            ELSE 'auto_merged'::pggit.conflict_status
        END;

        INSERT INTO pggit.merge_conflicts (
            merge_id, schema_name, object_name, object_type,
            lca_hash, source_hash, target_hash,
            source_ddl, target_ddl, status
        )
        VALUES (
            p_merge_id,
            v_obj.schema_name, v_obj.object_name, v_obj.object_type,
            v_obj.lca_hash, v_obj.src_hash, v_obj.tgt_hash,
            v_obj.src_ddl, v_obj.tgt_ddl,
            v_conflict_status
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Merge: completion (internal)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit_internal.complete_merge(p_merge_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_merge     RECORD;
    v_mc        RECORD;
    v_commit_id BIGINT;
    v_remaining INT;
    v_target_id BIGINT;
    v_tree_hash TEXT;
BEGIN
    SELECT * INTO v_merge
    FROM pggit.merge_history WHERE id = p_merge_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Merge % not found', p_merge_id;
    END IF;

    v_target_id := v_merge.target_branch_id;

    SELECT COUNT(*) INTO v_remaining
    FROM pggit.merge_conflicts
    WHERE merge_id = p_merge_id AND status = 'conflicted';

    IF v_remaining > 0 THEN
        RAISE EXCEPTION
            'Merge % has % unresolved conflict(s)', p_merge_id, v_remaining;
    END IF;

    -- Sync pggit.objects for the target branch to reflect the merged state.
    -- pggit tracks DDL state per branch; branches share the same physical schema.
    FOR v_mc IN
        SELECT *
        FROM pggit.merge_conflicts
        WHERE merge_id = p_merge_id
          AND status IN ('auto_merged', 'resolved')
    LOOP
        IF v_mc.lca_hash IS NULL AND v_mc.source_hash IS NOT NULL THEN
            -- Object added on source: add it to target branch tracking.
            INSERT INTO pggit.objects (
                branch_id, schema_name, object_name, object_type,
                content_hash, ddl_text, pg_oid, is_deleted
            )
            SELECT
                v_target_id,
                o.schema_name, o.object_name, o.object_type,
                o.content_hash, o.ddl_text, o.pg_oid, FALSE
            FROM pggit.objects o
            WHERE o.branch_id  = v_merge.source_branch_id
              AND o.schema_name = v_mc.schema_name
              AND o.object_name = v_mc.object_name
              AND o.object_type = v_mc.object_type
              AND o.is_deleted  = FALSE
            ON CONFLICT (branch_id, schema_name, object_name, object_type) DO UPDATE
            SET content_hash = EXCLUDED.content_hash,
                ddl_text     = EXCLUDED.ddl_text,
                pg_oid       = EXCLUDED.pg_oid,
                is_deleted   = FALSE,
                updated_at   = now();

        ELSIF v_mc.lca_hash IS NOT NULL AND v_mc.source_hash IS NULL THEN
            -- Object deleted on source: mark as deleted in target branch tracking.
            UPDATE pggit.objects
            SET is_deleted = TRUE,
                pg_oid     = NULL,
                updated_at = now()
            WHERE branch_id   = v_target_id
              AND schema_name = v_mc.schema_name
              AND object_name = v_mc.object_name
              AND object_type = v_mc.object_type;

        ELSIF v_mc.status = 'resolved' AND v_mc.resolution = 'theirs' THEN
            -- Conflict resolved with theirs: update target to source state.
            UPDATE pggit.objects
            SET content_hash = v_mc.source_hash,
                ddl_text     = v_mc.source_ddl,
                is_deleted   = FALSE,
                updated_at   = now()
            WHERE branch_id   = v_target_id
              AND schema_name = v_mc.schema_name
              AND object_name = v_mc.object_name
              AND object_type = v_mc.object_type;

        ELSIF v_mc.status = 'resolved' AND v_mc.resolution = 'manual' THEN
            -- Manual resolution: update target to the manually supplied DDL hash.
            UPDATE pggit.objects
            SET content_hash = encode(sha256(v_mc.resolved_ddl::bytea), 'hex'),
                ddl_text     = v_mc.resolved_ddl,
                is_deleted   = FALSE,
                updated_at   = now()
            WHERE branch_id   = v_target_id
              AND schema_name = v_mc.schema_name
              AND object_name = v_mc.object_name
              AND object_type = v_mc.object_type;

        ELSIF v_mc.status = 'auto_merged'
              AND v_mc.source_hash IS NOT NULL
              AND v_mc.lca_hash IS NOT NULL
              AND v_mc.source_hash IS DISTINCT FROM v_mc.lca_hash THEN
            -- Source modified (target unchanged from LCA): apply source state to target.
            UPDATE pggit.objects
            SET content_hash = v_mc.source_hash,
                ddl_text     = v_mc.source_ddl,
                is_deleted   = FALSE,
                updated_at   = now()
            WHERE branch_id   = v_target_id
              AND schema_name = v_mc.schema_name
              AND object_name = v_mc.object_name
              AND object_type = v_mc.object_type;

        -- For 'ours' resolution: target pggit.objects already has the right state.
        END IF;
    END LOOP;

    -- Create the merge commit directly, bypassing the "nothing to commit" guard
    -- in pggit.commit(). Merge commits record the merge event even when the
    -- resulting tree is identical to the prior commit (e.g. all resolved with ours).
    v_tree_hash := pggit_internal.compute_tree_hash(v_target_id);

    INSERT INTO pggit.commits (branch_id, parent_id, message, tree_hash)
    VALUES (
        v_target_id,
        (SELECT head_commit_id FROM pggit.branches WHERE id = v_target_id),
        'Merge branch ' || quote_ident(
            (SELECT name FROM pggit.branches WHERE id = v_merge.source_branch_id)
        ),
        v_tree_hash
    )
    RETURNING id INTO v_commit_id;

    UPDATE pggit.branches
    SET head_commit_id = v_commit_id,
        updated_at     = now()
    WHERE id = v_target_id;

    UPDATE pggit.history
    SET commit_id = v_commit_id
    WHERE branch_id = v_target_id
      AND commit_id IS NULL;

    UPDATE pggit.merge_history
    SET status           = 'completed',
        result_commit_id = v_commit_id,
        completed_at     = now()
    WHERE id = p_merge_id;

    UPDATE pggit.branches
    SET status     = 'merged',
        updated_at = now()
    WHERE id = v_merge.source_branch_id;
END;
$$;
