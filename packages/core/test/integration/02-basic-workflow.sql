-- Integration test: basic git-like workflow
-- Simulates: init → create table → commit → branch → modify → commit → merge

BEGIN;
SELECT plan(20);

CREATE SCHEMA workflow_test;

-- Step 1: initial state
SELECT is(pggit.current_branch(), 'main', 'starts on main');

-- Step 2: create a table and verify tracking
CREATE TABLE workflow_test.users (
    id    SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name  TEXT NOT NULL
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'workflow_test'
          AND object_name LIKE '%users%'
          AND content_hash ~ '^[0-9a-f]{64}$'
    ),
    'users table tracked with valid hash'
);

-- Step 3: commit
DO $$
DECLARE v_cid BIGINT;
BEGIN
    v_cid := pggit.commit('create users table');
    PERFORM ok(v_cid > 0, 'first commit succeeds');
END;
$$;

SELECT ok(
    (SELECT COUNT(*) FROM pggit.status) = 0,
    'no uncommitted changes after commit'
);

-- Step 4: create a feature branch
DO $$
DECLARE v_bid BIGINT;
BEGIN
    v_bid := pggit.create_branch('feature-add-posts');
    PERFORM ok(v_bid > 0, 'feature branch created');
END;
$$;

SELECT pggit.switch_branch('feature-add-posts');
SELECT is(pggit.current_branch(), 'feature-add-posts', 'switched to feature branch');

-- Step 5: add a table on the feature branch
CREATE TABLE workflow_test.posts (
    id      SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    title   TEXT NOT NULL,
    body    TEXT
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE branch_id  = pggit_internal.branch_id('feature-add-posts')
          AND schema_name = 'workflow_test'
          AND object_name LIKE '%posts%'
    ),
    'posts tracked on feature branch'
);

DO $$
DECLARE v_cid BIGINT;
BEGIN
    v_cid := pggit.commit('add posts table');
    PERFORM ok(v_cid > 0, 'commit on feature branch succeeds');
END;
$$;

-- Step 6: diff shows the difference
SELECT pggit.switch_branch('main');

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.diff('main', 'feature-add-posts')
        WHERE object_name LIKE '%posts%' AND change_type = 'added'
    ),
    'diff shows posts as added on feature branch'
);

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.diff('main', 'feature-add-posts')
        WHERE object_name LIKE '%users%'
    ),
    'diff does not show users (same on both branches)'
);

-- Step 7: merge (auto-complete, no conflicts)
DO $$
DECLARE v_mid BIGINT;
BEGIN
    v_mid := pggit.merge('feature-add-posts');
    PERFORM is(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid),
        'completed'::pggit.merge_status,
        'merge auto-completes'
    );
END;
$$;

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE branch_id  = pggit_internal.branch_id('main')
          AND schema_name = 'workflow_test'
          AND object_name LIKE '%posts%'
          AND is_deleted  = FALSE
    ),
    'posts tracked on main after merge'
);

SELECT ok(
    (SELECT status FROM pggit.branches WHERE name = 'feature-add-posts') = 'merged',
    'feature branch marked merged'
);

-- Step 8: log shows merge commit
SELECT ok(
    (SELECT COUNT(*) FROM pggit.log('main')) >= 2,
    'log shows at least 2 commits on main (initial + merge)'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.log('main')
        WHERE message LIKE '%feature-add-posts%'
    ),
    'merge commit message references source branch'
);

-- Step 9: make another change and verify history
ALTER TABLE workflow_test.users ADD COLUMN created_at TIMESTAMPTZ DEFAULT now();
SELECT pggit.commit('add created_at to users');

SELECT ok(
    (SELECT COUNT(*) FROM pggit.log('main')) >= 3,
    'log grows with subsequent commits'
);

-- Step 10: create and delete a branch
SELECT pggit.create_branch('temporary');
SELECT pggit.delete_branch('temporary');
SELECT ok(
    (SELECT status FROM pggit.branches WHERE name = 'temporary') = 'deleted',
    'temporary branch soft-deleted'
);

-- Step 11: verify history is append-only (no lost entries)
SELECT ok(
    (SELECT COUNT(*) FROM pggit.history WHERE branch_id = pggit_internal.branch_id('main')) > 0,
    'history table has entries for main branch'
);

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.history h
        JOIN pggit.branches b ON b.id = h.branch_id
        WHERE b.name = 'main' AND h.commit_id IS NULL
    ),
    'all history entries on main are committed'
);

-- Step 12: diff between identical states is empty
SELECT is(
    (SELECT COUNT(*) FROM pggit.diff('main', 'main')),
    0::BIGINT,
    'diff against self is empty'
);

DROP SCHEMA workflow_test CASCADE;

SELECT finish();
ROLLBACK;
