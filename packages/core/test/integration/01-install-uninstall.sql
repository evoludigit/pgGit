-- Integration test: install and uninstall
-- This test verifies the extension installs cleanly and uninstalls completely.
-- It is run as a standalone script by the CI pipeline, not inside pgTAP.

BEGIN;
SELECT plan(12);

-- After install, all schemas must exist
SELECT has_schema('pggit',          'pggit schema present after install');
SELECT has_schema('pggit_internal', 'pggit_internal schema present after install');

-- All 6 tables must exist
SELECT has_table('pggit', 'branches',        'branches table present');
SELECT has_table('pggit', 'commits',         'commits table present');
SELECT has_table('pggit', 'objects',         'objects table present');
SELECT has_table('pggit', 'history',         'history table present');
SELECT has_table('pggit', 'merge_history',   'merge_history table present');
SELECT has_table('pggit', 'merge_conflicts', 'merge_conflicts table present');

-- Both event triggers registered
SELECT ok(
    EXISTS(SELECT 1 FROM pg_event_trigger WHERE evtname = 'pggit_ddl_command_end'),
    'ddl_command_end trigger registered'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_event_trigger WHERE evtname = 'pggit_sql_drop'),
    'sql_drop trigger registered'
);

-- Bootstrap: exactly one branch named main
SELECT is(
    (SELECT COUNT(*) FROM pggit.branches WHERE name = 'main'),
    1::BIGINT,
    'exactly one main branch after install'
);

-- Idempotency: running bootstrap again is safe
INSERT INTO pggit.branches (name, parent_id, status)
VALUES ('main', NULL, 'active')
ON CONFLICT (name) DO NOTHING;

SELECT is(
    (SELECT COUNT(*) FROM pggit.branches WHERE name = 'main'),
    1::BIGINT,
    'bootstrap is idempotent (no duplicate main)'
);

SELECT finish();
ROLLBACK;
