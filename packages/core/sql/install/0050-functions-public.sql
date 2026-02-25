-- pggit v1.0 — Public API functions (exactly 14)
-- All objects in the pggit schema.

-- ---------------------------------------------------------------------------
-- Tracking control (functions 13, 14)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit.pause_tracking()
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT set_config('pggit.tracking_paused', 'true', FALSE);
$$;

COMMENT ON FUNCTION pggit.pause_tracking() IS
    'Disable DDL capture for this session. Use before bulk operations.';

CREATE OR REPLACE FUNCTION pggit.resume_tracking()
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT set_config('pggit.tracking_paused', 'false', FALSE);
$$;

COMMENT ON FUNCTION pggit.resume_tracking() IS
    'Re-enable DDL capture after pause_tracking().';

-- ---------------------------------------------------------------------------
-- Branch management (functions 1–6)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit.create_branch(
    p_name        TEXT,
    p_parent_name TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_parent_id   BIGINT;
    v_parent_name TEXT;
    v_new_id      BIGINT;
BEGIN
    v_parent_name := COALESCE(p_parent_name, pggit_internal.current_branch_name());

    SELECT id INTO v_parent_id
    FROM pggit.branches
    WHERE name = v_parent_name AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parent branch "%" not found or not active', v_parent_name;
    END IF;

    IF p_name !~ '^[a-zA-Z0-9._-]+$' THEN
        RAISE EXCEPTION
            'Invalid branch name "%". Use alphanumeric, dots, hyphens only.', p_name;
    END IF;

    IF EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_name) THEN
        RAISE EXCEPTION 'Branch "%" already exists', p_name;
    END IF;

    -- Copy parent's head_commit_id so the first commit on the new branch
    -- has the correct parent_id, enabling LCA computation for merges.
    INSERT INTO pggit.branches (name, parent_id, status, head_commit_id)
    SELECT p_name, v_parent_id, 'active', head_commit_id
    FROM pggit.branches
    WHERE id = v_parent_id
    RETURNING id INTO v_new_id;

    INSERT INTO pggit.objects (
        branch_id, schema_name, object_name, object_type,
        content_hash, ddl_text, pg_oid, is_deleted, created_at, updated_at
    )
    SELECT
        v_new_id,
        schema_name, object_name, object_type,
        content_hash, ddl_text, pg_oid,
        FALSE, now(), now()
    FROM pggit.objects
    WHERE branch_id = v_parent_id
      AND is_deleted = FALSE;

    RETURN v_new_id;
END;
$$;

COMMENT ON FUNCTION pggit.create_branch(TEXT, TEXT) IS
    'Create a new branch from parent_name (default: current branch). '
    'Copies all live objects from parent. Returns new branch id.';

CREATE OR REPLACE FUNCTION pggit.switch_branch(p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pggit.branches
        WHERE name = p_name AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Branch "%" not found or not active', p_name;
    END IF;

    PERFORM set_config('pggit.current_branch', p_name, FALSE);
END;
$$;

COMMENT ON FUNCTION pggit.switch_branch(TEXT) IS
    'Set the active branch for this session. Subsequent DDL is tracked here.';

CREATE OR REPLACE FUNCTION pggit.delete_branch(p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_branch_id BIGINT;
BEGIN
    IF p_name = 'main' THEN
        RAISE EXCEPTION 'Cannot delete the main branch';
    END IF;

    SELECT id INTO v_branch_id
    FROM pggit.branches WHERE name = p_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch "%" not found', p_name;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pggit.commits c
        WHERE c.branch_id = v_branch_id
          AND NOT EXISTS (
              SELECT 1
              FROM pggit.merge_history mh
              WHERE mh.source_branch_id = v_branch_id
                AND mh.status = 'completed'
          )
    ) THEN
        RAISE EXCEPTION
            'Branch "%" has unmerged commits. Merge first or use force_delete_branch.',
            p_name;
    END IF;

    UPDATE pggit.branches
    SET status     = 'deleted',
        updated_at = now()
    WHERE id = v_branch_id;
END;
$$;

COMMENT ON FUNCTION pggit.delete_branch(TEXT) IS
    'Soft-delete a branch. Rejects main. Rejects branches with unmerged commits.';

CREATE OR REPLACE FUNCTION pggit.force_delete_branch(p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_branch_id BIGINT;
BEGIN
    IF p_name = 'main' THEN
        RAISE EXCEPTION 'Cannot delete the main branch';
    END IF;

    SELECT id INTO v_branch_id
    FROM pggit.branches WHERE name = p_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch "%" not found', p_name;
    END IF;

    UPDATE pggit.branches
    SET status     = 'deleted',
        updated_at = now()
    WHERE id = v_branch_id;
END;
$$;

COMMENT ON FUNCTION pggit.force_delete_branch(TEXT) IS
    'Soft-delete a branch unconditionally (no merge check). Rejects main.';

CREATE OR REPLACE FUNCTION pggit.list_branches()
RETURNS TABLE (
    name           TEXT,
    status         pggit.branch_status,
    parent_name    TEXT,
    head_commit_id BIGINT,
    created_at     TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        b.name,
        b.status,
        p.name AS parent_name,
        b.head_commit_id,
        b.created_at
    FROM pggit.branches b
    LEFT JOIN pggit.branches p ON p.id = b.parent_id
    ORDER BY b.created_at;
$$;

COMMENT ON FUNCTION pggit.list_branches() IS
    'List all branches (including merged and deleted) with parent name and head commit.';

CREATE OR REPLACE FUNCTION pggit.current_branch()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT pggit_internal.current_branch_name();
$$;

COMMENT ON FUNCTION pggit.current_branch() IS
    'Returns the name of the currently active branch for this session.';

-- ---------------------------------------------------------------------------
-- Commit graph (functions 7–9)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit.commit(p_message TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_branch_name TEXT;
    v_branch_id   BIGINT;
    v_parent_id   BIGINT;
    v_tree_hash   TEXT;
    v_commit_id   BIGINT;
BEGIN
    IF p_message IS NULL OR trim(p_message) = '' THEN
        RAISE EXCEPTION 'Commit message must not be empty';
    END IF;

    v_branch_name := pggit_internal.current_branch_name();

    SELECT id, head_commit_id
    INTO v_branch_id, v_parent_id
    FROM pggit.branches
    WHERE name = v_branch_name AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Current branch "%" not found or not active', v_branch_name;
    END IF;

    v_tree_hash := pggit_internal.compute_tree_hash(v_branch_id);

    IF v_parent_id IS NOT NULL THEN
        IF (SELECT tree_hash FROM pggit.commits WHERE id = v_parent_id) = v_tree_hash THEN
            RAISE EXCEPTION
                'Nothing to commit on branch "%": tree unchanged since last commit',
                v_branch_name;
        END IF;
    END IF;

    INSERT INTO pggit.commits (branch_id, parent_id, message, tree_hash)
    VALUES (v_branch_id, v_parent_id, p_message, v_tree_hash)
    RETURNING id INTO v_commit_id;

    UPDATE pggit.branches
    SET head_commit_id = v_commit_id,
        updated_at     = now()
    WHERE id = v_branch_id;

    UPDATE pggit.history
    SET commit_id = v_commit_id
    WHERE branch_id = v_branch_id
      AND commit_id IS NULL;

    RETURN v_commit_id;
END;
$$;

COMMENT ON FUNCTION pggit.commit(TEXT) IS
    'Snapshot the current branch tree. Rejects empty messages and empty commits. '
    'Returns the new commit id.';

CREATE OR REPLACE FUNCTION pggit.log(p_branch_name TEXT DEFAULT NULL)
RETURNS TABLE (
    id           BIGINT,
    parent_id    BIGINT,
    message      TEXT,
    tree_hash    TEXT,
    author       TEXT,
    committed_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE commit_chain AS (
        SELECT c.*
        FROM pggit.commits c
        JOIN pggit.branches b ON b.id = c.branch_id
        WHERE b.name = COALESCE(p_branch_name, pggit_internal.current_branch_name())
          AND c.id = b.head_commit_id

        UNION ALL

        SELECT c.*
        FROM pggit.commits c
        JOIN commit_chain cc ON cc.parent_id = c.id
    )
    SELECT id, parent_id, message, tree_hash, author, committed_at
    FROM commit_chain
    ORDER BY committed_at DESC;
$$;

COMMENT ON FUNCTION pggit.log(TEXT) IS
    'Return commit history for the given branch (default: current branch), '
    'most recent first.';

CREATE OR REPLACE FUNCTION pggit.diff(p_from TEXT, p_to TEXT)
RETURNS TABLE (
    schema_name TEXT,
    object_name TEXT,
    object_type pggit.object_type,
    change_type TEXT,
    from_hash   TEXT,
    to_hash     TEXT,
    from_ddl    TEXT,
    to_ddl      TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_from_branch_id BIGINT;
    v_to_branch_id   BIGINT;
BEGIN
    SELECT id INTO v_from_branch_id
    FROM pggit.branches WHERE name = p_from;

    SELECT id INTO v_to_branch_id
    FROM pggit.branches WHERE name = p_to;

    IF v_from_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch "%" not found', p_from;
    END IF;
    IF v_to_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch "%" not found', p_to;
    END IF;

    RETURN QUERY
    WITH
    from_objects AS (
        SELECT o.schema_name, o.object_name, o.object_type, o.content_hash, o.ddl_text
        FROM pggit.objects o
        WHERE o.branch_id = v_from_branch_id AND o.is_deleted = FALSE
    ),
    to_objects AS (
        SELECT o.schema_name, o.object_name, o.object_type, o.content_hash, o.ddl_text
        FROM pggit.objects o
        WHERE o.branch_id = v_to_branch_id AND o.is_deleted = FALSE
    )
    SELECT
        COALESCE(f.schema_name, t.schema_name),
        COALESCE(f.object_name, t.object_name),
        COALESCE(f.object_type, t.object_type),
        CASE
            WHEN f.object_name IS NULL THEN 'added'
            WHEN t.object_name IS NULL THEN 'removed'
            ELSE 'modified'
        END AS change_type,
        f.content_hash AS from_hash,
        t.content_hash AS to_hash,
        f.ddl_text     AS from_ddl,
        t.ddl_text     AS to_ddl
    FROM from_objects f
    FULL OUTER JOIN to_objects t
        ON  f.schema_name = t.schema_name
        AND f.object_name = t.object_name
        AND f.object_type = t.object_type
    WHERE f.content_hash IS DISTINCT FROM t.content_hash
    ORDER BY
        COALESCE(f.schema_name, t.schema_name),
        COALESCE(f.object_name, t.object_name);
END;
$$;

COMMENT ON FUNCTION pggit.diff(TEXT, TEXT) IS
    'Compare object state between two branches. Returns added/removed/modified objects.';

-- Working tree status view
CREATE VIEW pggit.status AS
SELECT
    o.schema_name,
    o.object_name,
    o.object_type,
    h.operation,
    h.changed_at
FROM pggit.history h
JOIN pggit.objects o  ON o.id = h.object_id
JOIN pggit.branches b ON b.id = h.branch_id
WHERE b.name = pggit_internal.current_branch_name()
  AND h.commit_id IS NULL
ORDER BY h.changed_at;

COMMENT ON VIEW pggit.status IS
    'Uncommitted changes on the current branch (history rows with commit_id IS NULL).';

-- ---------------------------------------------------------------------------
-- Merging (functions 10–12)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pggit.merge(p_source_branch TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_id     BIGINT;
    v_target_id     BIGINT;
    v_target_name   TEXT;
    v_src_head      BIGINT;
    v_tgt_head      BIGINT;
    v_lca_id        BIGINT;
    v_merge_id      BIGINT;
    v_conflict_count INT;
BEGIN
    v_target_name := pggit_internal.current_branch_name();

    SELECT id, head_commit_id INTO v_source_id, v_src_head
    FROM pggit.branches WHERE name = p_source_branch AND status = 'active';

    SELECT id, head_commit_id INTO v_target_id, v_tgt_head
    FROM pggit.branches WHERE name = v_target_name AND status = 'active';

    IF v_source_id IS NULL THEN
        RAISE EXCEPTION 'Source branch "%" not found or not active', p_source_branch;
    END IF;
    IF v_source_id = v_target_id THEN
        RAISE EXCEPTION 'Cannot merge a branch into itself';
    END IF;
    IF v_src_head IS NULL THEN
        RAISE EXCEPTION 'Source branch "%" has no commits', p_source_branch;
    END IF;

    v_lca_id := pggit_internal.find_lca(
        v_src_head,
        COALESCE(v_tgt_head, v_src_head)
    );

    IF v_lca_id IS NULL THEN
        RAISE EXCEPTION 'No common ancestor found between "%" and "%"',
            p_source_branch, v_target_name;
    END IF;

    INSERT INTO pggit.merge_history (
        source_branch_id, target_branch_id,
        lca_commit_id, source_commit_id, target_commit_id,
        status
    )
    VALUES (
        v_source_id, v_target_id,
        v_lca_id, v_src_head, COALESCE(v_tgt_head, v_src_head),
        'pending'
    )
    RETURNING id INTO v_merge_id;

    PERFORM pggit_internal.classify_merge_objects(
        v_merge_id, v_lca_id, v_source_id, v_target_id
    );

    SELECT COUNT(*) INTO v_conflict_count
    FROM pggit.merge_conflicts
    WHERE merge_id = v_merge_id AND status = 'conflicted';

    IF v_conflict_count = 0 THEN
        PERFORM pggit_internal.complete_merge(v_merge_id);
    ELSE
        UPDATE pggit.merge_history
        SET status = 'in_progress'
        WHERE id = v_merge_id;
    END IF;

    RETURN v_merge_id;
END;
$$;

COMMENT ON FUNCTION pggit.merge(TEXT) IS
    'Start a three-way merge from source_branch into the current branch. '
    'Auto-completes if no conflicts. Returns merge_id.';

CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    p_merge_id    BIGINT,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_object_type pggit.object_type,
    p_resolution  TEXT,
    p_manual_ddl  TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_conflict    RECORD;
    v_resolved_ddl TEXT;
BEGIN
    SELECT * INTO v_conflict
    FROM pggit.merge_conflicts
    WHERE merge_id    = p_merge_id
      AND schema_name = p_schema_name
      AND object_name = p_object_name
      AND object_type = p_object_type
      AND status      = 'conflicted';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No open conflict found for object %.% (%) in merge %',
            p_schema_name, p_object_name, p_object_type, p_merge_id;
    END IF;

    IF p_resolution NOT IN ('ours', 'theirs', 'manual') THEN
        RAISE EXCEPTION 'resolution must be "ours", "theirs", or "manual"';
    END IF;

    IF p_resolution = 'manual' AND p_manual_ddl IS NULL THEN
        RAISE EXCEPTION 'manual resolution requires p_manual_ddl to be provided';
    END IF;

    v_resolved_ddl := CASE p_resolution
        WHEN 'ours'   THEN v_conflict.target_ddl
        WHEN 'theirs' THEN v_conflict.source_ddl
        WHEN 'manual' THEN p_manual_ddl
    END;

    UPDATE pggit.merge_conflicts
    SET resolution   = p_resolution,
        resolved_ddl = v_resolved_ddl,
        status       = 'resolved',
        resolved_at  = now()
    WHERE id = v_conflict.id;
END;
$$;

COMMENT ON FUNCTION pggit.resolve_conflict(BIGINT, TEXT, TEXT, pggit.object_type, TEXT, TEXT) IS
    '"ours" = keep target DDL, "theirs" = apply source DDL, "manual" = apply p_manual_ddl.';

CREATE OR REPLACE FUNCTION pggit.complete_merge(p_merge_id BIGINT)
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT pggit_internal.complete_merge(p_merge_id);
$$;

COMMENT ON FUNCTION pggit.complete_merge(BIGINT) IS
    'Apply all resolved merge changes and create the merge commit. '
    'Fails if any conflicts are still unresolved.';
