-- pgTAP unit tests: branching (Phase 4)

BEGIN;
SELECT plan(23);

CREATE SCHEMA pggit_branch_test;
CREATE TABLE pggit_branch_test.seed (id INT PRIMARY KEY);
SELECT pggit.commit('seed commit for branching tests');

-- ---------------------------------------------------------------------------
-- create_branch
-- ---------------------------------------------------------------------------

SELECT ok(pggit.create_branch('test-branch-1') > 0, 'create_branch returns positive id');

SELECT ok(
    EXISTS(SELECT 1 FROM pggit.branches WHERE name = 'test-branch-1' AND status = 'active'),
    'created branch appears in branches table with active status'
);

SELECT is(
    (SELECT parent_name FROM pggit.list_branches() WHERE name = 'test-branch-1'),
    'main',
    'new branch parent is main'
);

-- Objects copied from parent
SELECT ok(
    (SELECT COUNT(*) FROM pggit.objects WHERE branch_id = pggit_internal.branch_id('test-branch-1'))
    =
    (SELECT COUNT(*) FROM pggit.objects WHERE branch_id = pggit_internal.branch_id('main') AND is_deleted = FALSE),
    'new branch has same object count as parent'
);

-- Invalid name rejected
SELECT throws_like(
    $$ SELECT pggit.create_branch('bad/name') $$,
    '%Invalid branch name%',
    'slash in branch name rejected'
);

SELECT throws_like(
    $$ SELECT pggit.create_branch('bad name') $$,
    '%Invalid branch name%',
    'space in branch name rejected'
);

-- Duplicate name rejected
SELECT throws_like(
    $$ SELECT pggit.create_branch('test-branch-1') $$,
    '%already exists%',
    'duplicate branch name rejected'
);

-- Explicit parent
SELECT ok(pggit.create_branch('child-branch', 'test-branch-1') > 0, 'create_branch with explicit parent succeeds');

SELECT is(
    (SELECT parent_name FROM pggit.list_branches() WHERE name = 'child-branch'),
    'test-branch-1',
    'child branch parent is test-branch-1'
);

-- ---------------------------------------------------------------------------
-- switch_branch / current_branch
-- ---------------------------------------------------------------------------

SELECT is(pggit.current_branch(), 'main', 'current branch is main initially');

SELECT pggit.switch_branch('test-branch-1');
SELECT is(pggit.current_branch(), 'test-branch-1', 'current branch updated after switch');

-- DDL tracked on new branch
CREATE TABLE pggit_branch_test.on_feature (x INT);
SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE branch_id  = pggit_internal.branch_id('test-branch-1')
          AND schema_name = 'pggit_branch_test'
          AND object_name LIKE '%on_feature%'
    ),
    'DDL tracked on feature branch after switch'
);

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE branch_id  = pggit_internal.branch_id('main')
          AND schema_name = 'pggit_branch_test'
          AND object_name LIKE '%on_feature%'
          AND is_deleted = FALSE
    ),
    'feature DDL not tracked on main'
);

SELECT pggit.switch_branch('main');

-- Switch to non-existent branch raises
SELECT throws_like(
    $$ SELECT pggit.switch_branch('nonexistent') $$,
    '%not found%',
    'switch to nonexistent branch raises'
);

-- ---------------------------------------------------------------------------
-- list_branches
-- ---------------------------------------------------------------------------

SELECT ok(
    (SELECT COUNT(*) FROM pggit.list_branches()) >= 3,
    'list_branches returns at least 3 rows (main, test-branch-1, child-branch)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pggit.list_branches() WHERE name = 'main' AND parent_name IS NULL),
    'main branch has no parent in list_branches'
);

-- ---------------------------------------------------------------------------
-- delete_branch
-- ---------------------------------------------------------------------------

-- Delete main raises
SELECT throws_like(
    $$ SELECT pggit.delete_branch('main') $$,
    '%Cannot delete the main branch%',
    'delete main raises'
);

-- Delete nonexistent raises
SELECT throws_like(
    $$ SELECT pggit.delete_branch('does-not-exist') $$,
    '%not found%',
    'delete nonexistent branch raises'
);

-- Create a branch with no commits and delete it
SELECT pggit.create_branch('deletable');
SELECT pggit.delete_branch('deletable');
SELECT is(
    (SELECT status FROM pggit.branches WHERE name = 'deletable'),
    'deleted'::pggit.branch_status,
    'deleted branch has status deleted'
);

-- Branch with commits but no merge: delete_branch raises
SELECT pggit.switch_branch('child-branch');
CREATE TABLE pggit_branch_test.on_child (y INT);
SELECT pggit.commit('add on_child');
SELECT pggit.switch_branch('main');

SELECT throws_like(
    $$ SELECT pggit.delete_branch('child-branch') $$,
    '%unmerged commits%',
    'delete branch with unmerged commits raises'
);

-- force_delete bypasses merge check
SELECT pggit.force_delete_branch('child-branch');
SELECT is(
    (SELECT status FROM pggit.branches WHERE name = 'child-branch'),
    'deleted'::pggit.branch_status,
    'force_delete_branch marks branch deleted'
);

-- force_delete main raises
SELECT throws_like(
    $$ SELECT pggit.force_delete_branch('main') $$,
    '%Cannot delete the main branch%',
    'force_delete main raises'
);

-- Deleted branches visible in list_branches
SELECT ok(
    EXISTS(SELECT 1 FROM pggit.list_branches() WHERE name = 'deletable' AND status = 'deleted'),
    'deleted branch still visible in list_branches'
);

DROP SCHEMA pggit_branch_test CASCADE;

SELECT finish();
ROLLBACK;
