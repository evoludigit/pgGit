-- pgTAP unit tests: public API surface (Phase 7 readiness check)

BEGIN;
SELECT plan(28);

-- ---------------------------------------------------------------------------
-- Function existence checks — all 14 public functions + status view
-- ---------------------------------------------------------------------------

-- has_function takes name[] for argument type list (not text[])
SELECT has_function('pggit', 'create_branch',      ARRAY['text','text']::name[],   'create_branch exists');
SELECT has_function('pggit', 'switch_branch',       ARRAY['text']::name[],          'switch_branch exists');
SELECT has_function('pggit', 'delete_branch',       ARRAY['text']::name[],          'delete_branch exists');
SELECT has_function('pggit', 'force_delete_branch', ARRAY['text']::name[],          'force_delete_branch exists');
SELECT has_function('pggit', 'list_branches',       ARRAY[]::name[],                'list_branches exists');
SELECT has_function('pggit', 'current_branch',      ARRAY[]::name[],                'current_branch exists');
SELECT has_function('pggit', 'commit',              ARRAY['text']::name[],          'commit exists');
SELECT has_function('pggit', 'log',                 ARRAY['text']::name[],          'log exists');
SELECT has_function('pggit', 'diff',                ARRAY['text','text']::name[],   'diff exists');
SELECT has_function('pggit', 'merge',               ARRAY['text']::name[],          'merge exists');
SELECT has_function('pggit', 'resolve_conflict',
    ARRAY['bigint','text','text','pggit.object_type','text','text']::name[],
    'resolve_conflict exists'
);
SELECT has_function('pggit', 'complete_merge',      ARRAY['bigint']::name[],        'complete_merge exists');
SELECT has_function('pggit', 'pause_tracking',      ARRAY[]::name[],                'pause_tracking exists');
SELECT has_function('pggit', 'resume_tracking',     ARRAY[]::name[],                'resume_tracking exists');

SELECT has_view('pggit', 'status', 'status view exists');

-- ---------------------------------------------------------------------------
-- pggit_internal inaccessible to PUBLIC
-- ---------------------------------------------------------------------------

-- The schema has REVOKE ALL ... FROM PUBLIC. Test that an unprivileged role
-- cannot look up objects directly. We verify the REVOKE was applied.
SELECT ok(
    NOT EXISTS(
        SELECT 1
        FROM information_schema.role_usage_grants
        WHERE object_schema = 'pggit_internal'
          AND grantee = 'PUBLIC'
          AND privilege_type = 'USAGE'
    ),
    'PUBLIC has no USAGE on pggit_internal'
);

-- ---------------------------------------------------------------------------
-- Error contract: consistent error messages
-- ---------------------------------------------------------------------------

SELECT throws_like(
    $$ SELECT pggit.create_branch('') $$,
    '%Invalid branch name%',
    'empty branch name gives descriptive error'
);

SELECT throws_like(
    $$ SELECT pggit.switch_branch('no-such') $$,
    '%not found%',
    'switch to nonexistent branch gives descriptive error'
);

SELECT throws_like(
    $$ SELECT pggit.delete_branch('main') $$,
    '%Cannot delete the main branch%',
    'delete main gives descriptive error'
);

SELECT throws_like(
    $$ SELECT pggit.commit(NULL) $$,
    '%Commit message must not be empty%',
    'null commit message gives descriptive error'
);

SELECT throws_like(
    $$ SELECT * FROM pggit.diff('main', 'nonexistent') $$,
    '%not found%',
    'diff with bad branch gives descriptive error'
);

SELECT throws_like(
    $$ SELECT pggit.merge('main') $$,
    '%Cannot merge a branch into itself%',
    'self-merge gives descriptive error'
);

-- ---------------------------------------------------------------------------
-- Workflow smoke test
-- ---------------------------------------------------------------------------

CREATE SCHEMA pggit_api_test;

CREATE TABLE pggit_api_test.smoke (id INT PRIMARY KEY);
SELECT ok(pggit.commit('smoke commit') > 0, 'commit() returns positive id');

SELECT ok(pggit.create_branch('smoke-branch') > 0, 'create_branch() returns positive id');

SELECT pggit.switch_branch('smoke-branch');
SELECT is(pggit.current_branch(), 'smoke-branch', 'current_branch() returns switched branch');

CREATE TABLE pggit_api_test.smoke2 (x TEXT);
SELECT pggit.commit('add smoke2 on feature');

SELECT pggit.switch_branch('main');
SELECT ok(
    (SELECT COUNT(*) FROM pggit.log('smoke-branch')) >= 2,
    'log() returns at least 2 entries for smoke-branch'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pggit.diff('main', 'smoke-branch') WHERE change_type = 'added'),
    'diff() shows added object on smoke-branch'
);

DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    v_mid := pggit.merge('smoke-branch');
    PERFORM ok(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid) = 'completed',
        'merge() auto-completes smoke-branch into main'
    );
END;
$$;

DROP SCHEMA pggit_api_test CASCADE;

SELECT finish();
ROLLBACK;
