-- pgTAP unit tests: commit graph (Phase 5)

BEGIN;
SELECT plan(18);

CREATE SCHEMA pggit_commit_test;

-- ---------------------------------------------------------------------------
-- compute_tree_hash on empty branch
-- ---------------------------------------------------------------------------

SELECT pggit.create_branch('empty-branch');
SELECT pggit.switch_branch('empty-branch');

SELECT is(
    pggit_internal.compute_tree_hash(pggit_internal.branch_id('empty-branch')),
    encode(sha256(''::bytea), 'hex'),
    'compute_tree_hash on empty branch returns empty-string SHA-256'
);

SELECT pggit.switch_branch('main');

-- ---------------------------------------------------------------------------
-- pggit.commit
-- ---------------------------------------------------------------------------

-- Empty message rejected
SELECT throws_like(
    $$ SELECT pggit.commit('') $$,
    '%Commit message must not be empty%',
    'empty commit message rejected'
);

SELECT throws_like(
    $$ SELECT pggit.commit(NULL) $$,
    '%Commit message must not be empty%',
    'NULL commit message rejected'
);

-- Successful commit
CREATE TABLE pggit_commit_test.alpha (id INT PRIMARY KEY);

SELECT ok(pggit.commit('add alpha') > 0, 'commit returns positive id');

SELECT ok(
    EXISTS(SELECT 1 FROM pggit.commits WHERE message = 'add alpha'),
    'commit row exists after commit()'
);

SELECT ok(
    (SELECT head_commit_id FROM pggit.branches WHERE name = 'main') IS NOT NULL,
    'head_commit_id updated after commit'
);

-- Empty commit (tree unchanged) rejected
SELECT throws_like(
    $$ SELECT pggit.commit('nothing changed') $$,
    '%Nothing to commit%',
    'empty commit (no tree change) rejected'
);

-- History rows backfilled with commit_id
SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.history h
        JOIN pggit.branches b ON b.id = h.branch_id
        WHERE b.name = 'main'
          AND h.commit_id IS NULL
          AND h.changed_at <= now()
    ),
    'all history rows backfilled with commit_id after commit'
);

-- ---------------------------------------------------------------------------
-- pggit.log
-- ---------------------------------------------------------------------------

CREATE TABLE pggit_commit_test.beta (x TEXT);
SELECT pggit.commit('add beta');

CREATE TABLE pggit_commit_test.gamma (y BOOLEAN);
SELECT pggit.commit('add gamma');

SELECT ok(
    (SELECT COUNT(*) FROM pggit.log()) >= 3,
    'log() returns at least 3 rows after 3 commits'
);

SELECT ok(
    (SELECT message FROM pggit.log() LIMIT 1) = 'add gamma',
    'log() returns most recent commit first'
);

-- Explicit branch name
SELECT ok(
    (SELECT COUNT(*) FROM pggit.log('main')) >= 3,
    'log(branch_name) works'
);

-- ---------------------------------------------------------------------------
-- pggit.diff
-- ---------------------------------------------------------------------------

SELECT pggit.create_branch('diff-branch');
SELECT pggit.switch_branch('diff-branch');
CREATE TABLE pggit_commit_test.delta (z INT);
SELECT pggit.commit('add delta on diff-branch');
SELECT pggit.switch_branch('main');

-- diff main → diff-branch: delta is added
SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.diff('main', 'diff-branch')
        WHERE object_name LIKE '%delta%' AND change_type = 'added'
    ),
    'diff shows delta as added on diff-branch'
);

-- diff diff-branch → main: delta is removed
SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.diff('diff-branch', 'main')
        WHERE object_name LIKE '%delta%' AND change_type = 'removed'
    ),
    'diff shows delta as removed from main perspective'
);

-- diff against self is empty
SELECT is(
    (SELECT COUNT(*) FROM pggit.diff('main', 'main')),
    0::BIGINT,
    'diff against self returns zero rows'
);

-- Modified object
ALTER TABLE pggit_commit_test.alpha ADD COLUMN extra TEXT;
SELECT pggit.commit('alter alpha on main');

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.diff('diff-branch', 'main')
        WHERE object_name LIKE '%alpha%' AND change_type = 'modified'
    ),
    'diff shows modified object'
);

-- diff with nonexistent branch raises
SELECT throws_like(
    $$ SELECT * FROM pggit.diff('main', 'no-such-branch') $$,
    '%not found%',
    'diff with nonexistent branch raises'
);

-- ---------------------------------------------------------------------------
-- pggit.status view
-- ---------------------------------------------------------------------------

CREATE TABLE pggit_commit_test.uncommitted (id INT);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.status
        WHERE schema_name = 'pggit_commit_test'
          AND object_name LIKE '%uncommitted%'
    ),
    'status view shows uncommitted change'
);

SELECT pggit.commit('add uncommitted');

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.status
        WHERE schema_name = 'pggit_commit_test'
          AND object_name LIKE '%uncommitted%'
    ),
    'status view empty after commit'
);

DROP SCHEMA pggit_commit_test CASCADE;

SELECT finish();
ROLLBACK;
