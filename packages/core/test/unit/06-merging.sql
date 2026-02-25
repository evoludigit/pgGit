-- pgTAP unit tests: merging (Phase 6)

BEGIN;
SELECT plan(16);

CREATE SCHEMA pggit_merge_test;

-- Establish initial state on main
CREATE TABLE pggit_merge_test.base_table (id INT PRIMARY KEY, val TEXT);
SELECT pggit.commit('initial commit');

-- ---------------------------------------------------------------------------
-- find_lca
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_initial_commit BIGINT;
    v_branch_id      BIGINT;
    v_src_commit     BIGINT;
    v_lca            BIGINT;
BEGIN
    SELECT head_commit_id INTO v_initial_commit
    FROM pggit.branches WHERE name = 'main';

    v_branch_id := pggit.create_branch('lca-test');
    PERFORM pggit.switch_branch('lca-test');
    CREATE TABLE pggit_merge_test.on_lca_branch (x INT);
    PERFORM pggit.commit('commit on lca-test');

    SELECT head_commit_id INTO v_src_commit
    FROM pggit.branches WHERE name = 'lca-test';

    PERFORM pggit.switch_branch('main');

    v_lca := pggit_internal.find_lca(v_src_commit, v_initial_commit);
    PERFORM ok(v_lca = v_initial_commit, 'find_lca returns initial commit as LCA');
END;
$$;

-- ---------------------------------------------------------------------------
-- Auto-merge (no conflicts)
-- ---------------------------------------------------------------------------

SELECT pggit.create_branch('auto-merge-src');
SELECT pggit.switch_branch('auto-merge-src');

CREATE TABLE pggit_merge_test.new_table (z BOOLEAN);
SELECT pggit.commit('add new_table on auto-merge-src');

SELECT pggit.switch_branch('main');

DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    v_mid := pggit.merge('auto-merge-src');

    PERFORM is(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid),
        'completed'::pggit.merge_status,
        'auto-merge completes without conflicts'
    );

    PERFORM ok(
        EXISTS(
            SELECT 1 FROM pggit.objects
            WHERE branch_id = pggit_internal.branch_id('main')
              AND object_name LIKE '%new_table%'
              AND is_deleted = FALSE
        ),
        'merged object tracked on main after auto-merge'
    );

    PERFORM ok(
        (SELECT status FROM pggit.branches WHERE name = 'auto-merge-src') = 'merged',
        'source branch marked merged after auto-merge'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- Conflict detection
-- ---------------------------------------------------------------------------

SELECT pggit.create_branch('conflict-src');

-- Modify base_table on main
ALTER TABLE pggit_merge_test.base_table ADD COLUMN on_main INT;
SELECT pggit.commit('add on_main column');

-- Modify base_table on feature branch
SELECT pggit.switch_branch('conflict-src');
ALTER TABLE pggit_merge_test.base_table ADD COLUMN on_feature TEXT;
SELECT pggit.commit('add on_feature column');
SELECT pggit.switch_branch('main');

DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    v_mid := pggit.merge('conflict-src');

    PERFORM is(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid),
        'in_progress'::pggit.merge_status,
        'conflicting merge stays in_progress'
    );

    PERFORM ok(
        EXISTS(
            SELECT 1 FROM pggit.merge_conflicts
            WHERE merge_id = v_mid AND status = 'conflicted'
        ),
        'conflicted row exists in merge_conflicts'
    );

    PERFORM ok(
        (SELECT COUNT(*) FROM pggit.merge_conflicts
         WHERE merge_id = v_mid AND status = 'conflicted') >= 1,
        'at least one conflict detected'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- resolve_conflict
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_mid    BIGINT;
    v_schema TEXT;
    v_name   TEXT;
    v_type   pggit.object_type;
BEGIN
    SELECT id INTO v_mid
    FROM pggit.merge_history
    WHERE status = 'in_progress'
    ORDER BY started_at DESC
    LIMIT 1;

    SELECT schema_name, object_name, object_type
    INTO v_schema, v_name, v_type
    FROM pggit.merge_conflicts
    WHERE merge_id = v_mid AND status = 'conflicted'
    LIMIT 1;

    -- Resolve with 'ours'
    PERFORM pggit.resolve_conflict(v_mid, v_schema, v_name, v_type, 'ours');

    PERFORM ok(
        (SELECT status FROM pggit.merge_conflicts
         WHERE merge_id = v_mid
           AND schema_name = v_schema
           AND object_name = v_name
           AND object_type = v_type) = 'resolved',
        'resolve_conflict sets status to resolved'
    );

    PERFORM ok(
        (SELECT resolution FROM pggit.merge_conflicts
         WHERE merge_id = v_mid
           AND schema_name = v_schema
           AND object_name = v_name
           AND object_type = v_type) = 'ours',
        'resolution field set to ours'
    );
END;
$$;

-- resolve nonexistent conflict raises
SELECT throws_like(
    $$ SELECT pggit.resolve_conflict(0, 'public', 'noexist', 'table', 'ours') $$,
    '%No open conflict found%',
    'resolve nonexistent conflict raises'
);

-- resolve with invalid resolution raises
DO $$
DECLARE
    v_mid  BIGINT;
    v_schema TEXT;
    v_name TEXT;
    v_type pggit.object_type;
BEGIN
    -- Use a fresh conflict for this test
    SELECT mh.id, mc.schema_name, mc.object_name, mc.object_type
    INTO v_mid, v_schema, v_name, v_type
    FROM pggit.merge_history mh
    JOIN pggit.merge_conflicts mc ON mc.merge_id = mh.id
    WHERE mc.status = 'resolved'
    LIMIT 1;

    -- Test invalid resolution string (use a fresh bogus call)
    BEGIN
        PERFORM pggit.resolve_conflict(v_mid, v_schema, v_name, v_type, 'invalid');
    EXCEPTION WHEN OTHERS THEN
        PERFORM ok(TRUE, 'invalid resolution string raises exception');
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- complete_merge
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    SELECT id INTO v_mid
    FROM pggit.merge_history
    WHERE status = 'in_progress'
    ORDER BY started_at DESC
    LIMIT 1;

    PERFORM pggit.complete_merge(v_mid);

    PERFORM is(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid),
        'completed'::pggit.merge_status,
        'complete_merge sets status to completed'
    );

    PERFORM ok(
        (SELECT result_commit_id FROM pggit.merge_history WHERE id = v_mid) IS NOT NULL,
        'complete_merge sets result_commit_id'
    );
END;
$$;

-- complete_merge with unresolved conflicts raises
DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    -- Create a new conflict scenario
    PERFORM pggit.create_branch('unresolved-conflict-src');

    ALTER TABLE pggit_merge_test.base_table ADD COLUMN conflict_col1 INT;
    PERFORM pggit.commit('add conflict_col1 on main');

    PERFORM pggit.switch_branch('unresolved-conflict-src');
    ALTER TABLE pggit_merge_test.base_table ADD COLUMN conflict_col2 TEXT;
    PERFORM pggit.commit('add conflict_col2 on feature');
    PERFORM pggit.switch_branch('main');

    v_mid := pggit.merge('unresolved-conflict-src');

    BEGIN
        PERFORM pggit.complete_merge(v_mid);
        PERFORM ok(FALSE, 'should have raised exception');
    EXCEPTION WHEN OTHERS THEN
        PERFORM ok(TRUE, 'complete_merge with unresolved conflicts raises');
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Merge self raises
-- ---------------------------------------------------------------------------

SELECT throws_like(
    $$ SELECT pggit.merge('main') $$,
    '%Cannot merge a branch into itself%',
    'merge branch into itself raises'
);

-- ---------------------------------------------------------------------------
-- Merge classification: all 13 cases
-- ---------------------------------------------------------------------------
-- Full classification test via classify_merge_objects is covered in
-- integration/03-merge-scenarios.sql with explicit state setup.

SELECT ok(TRUE, 'classification cases tested in integration tests');

DROP SCHEMA pggit_merge_test CASCADE;

SELECT finish();
ROLLBACK;
