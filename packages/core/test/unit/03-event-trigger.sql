-- pgTAP unit tests: event trigger (Phase 3)

BEGIN;
SELECT plan(19);

CREATE SCHEMA pggit_et_test;

-- ---------------------------------------------------------------------------
-- resolve_object_type
-- ---------------------------------------------------------------------------

SELECT is(
    pggit_internal.resolve_object_type('table', 'CREATE TABLE'),
    'table'::pggit.object_type,
    'resolve_object_type: table'
);

SELECT is(
    pggit_internal.resolve_object_type('view', 'CREATE VIEW'),
    'view'::pggit.object_type,
    'resolve_object_type: view'
);

SELECT is(
    pggit_internal.resolve_object_type('materialized view', 'CREATE MATERIALIZED VIEW'),
    'materialized_view'::pggit.object_type,
    'resolve_object_type: materialized view'
);

SELECT is(
    pggit_internal.resolve_object_type('function', 'CREATE FUNCTION'),
    'function'::pggit.object_type,
    'resolve_object_type: function'
);

SELECT is(
    pggit_internal.resolve_object_type('index', 'CREATE INDEX'),
    'index'::pggit.object_type,
    'resolve_object_type: index'
);

SELECT is(
    pggit_internal.resolve_object_type('unknown_type', 'CREATE UNKNOWN'),
    NULL::pggit.object_type,
    'resolve_object_type: unknown returns NULL'
);

-- ---------------------------------------------------------------------------
-- Pause/resume tracking
-- ---------------------------------------------------------------------------

SELECT ok(NOT pggit_internal.is_tracking_paused(), 'tracking not paused initially');

SELECT pggit.pause_tracking();
SELECT ok(pggit_internal.is_tracking_paused(), 'tracking paused after pause_tracking()');

SELECT pggit.resume_tracking();
SELECT ok(NOT pggit_internal.is_tracking_paused(), 'tracking resumed after resume_tracking()');

-- ---------------------------------------------------------------------------
-- CREATE event capture
-- ---------------------------------------------------------------------------

CREATE TABLE pggit_et_test.captured (id INT PRIMARY KEY, val TEXT);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'pggit_et_test'
          AND object_name LIKE '%captured%'
          AND object_type = 'table'
          AND is_deleted = FALSE
    ),
    'CREATE TABLE captured in pggit.objects'
);

SELECT ok(
    (
        SELECT content_hash IS NOT NULL
        FROM pggit.objects
        WHERE schema_name = 'pggit_et_test'
          AND object_name LIKE '%captured%'
          AND object_type = 'table'
    ),
    'content_hash is NOT NULL after CREATE'
);

SELECT ok(
    (
        SELECT content_hash ~ '^[0-9a-f]{64}$'
        FROM pggit.objects
        WHERE schema_name = 'pggit_et_test'
          AND object_name LIKE '%captured%'
          AND object_type = 'table'
    ),
    'content_hash is valid 64-char hex'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.history
        JOIN pggit.objects o ON o.id = history.object_id
        WHERE o.schema_name = 'pggit_et_test'
          AND o.object_name LIKE '%captured%'
          AND operation = 'CREATE'
    ),
    'CREATE logged in history'
);

-- ---------------------------------------------------------------------------
-- ALTER event capture
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE _et_hash_before AS
    SELECT content_hash AS h
    FROM pggit.objects
    WHERE schema_name = 'pggit_et_test'
      AND object_name LIKE '%captured%'
      AND object_type = 'table';

ALTER TABLE pggit_et_test.captured ADD COLUMN extra BOOLEAN;

SELECT ok(
    (SELECT h FROM _et_hash_before) <>
    (SELECT content_hash FROM pggit.objects
     WHERE schema_name = 'pggit_et_test'
       AND object_name LIKE '%captured%'
       AND object_type = 'table'),
    'content_hash changes after ALTER'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.history
        JOIN pggit.objects o ON o.id = history.object_id
        WHERE o.schema_name = 'pggit_et_test'
          AND o.object_name LIKE '%captured%'
          AND operation = 'ALTER'
    ),
    'ALTER logged in history'
);

-- ---------------------------------------------------------------------------
-- DROP event capture
-- ---------------------------------------------------------------------------

DROP TABLE pggit_et_test.captured;

SELECT ok(
    (
        SELECT is_deleted
        FROM pggit.objects
        WHERE schema_name = 'pggit_et_test'
          AND object_name LIKE '%captured%'
          AND object_type = 'table'
    ),
    'object soft-deleted after DROP'
);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.history
        JOIN pggit.objects o ON o.id = history.object_id
        WHERE o.schema_name = 'pggit_et_test'
          AND o.object_name LIKE '%captured%'
          AND operation = 'DROP'
    ),
    'DROP logged in history'
);

-- ---------------------------------------------------------------------------
-- Schema filtering — pggit schema not tracked
-- ---------------------------------------------------------------------------

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'pggit'
          AND object_name LIKE '%branches%'
    ),
    'pggit.branches not tracked (pggit schema excluded)'
);

-- ---------------------------------------------------------------------------
-- Pause: DDL while paused not tracked
-- ---------------------------------------------------------------------------

SELECT pggit.pause_tracking();

CREATE TABLE pggit_et_test.paused_table (id INT);

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'pggit_et_test'
          AND object_name LIKE '%paused_table%'
    ),
    'DDL while paused not tracked'
);

SELECT pggit.resume_tracking();

DROP TABLE pggit_et_test.paused_table;

DROP SCHEMA pggit_et_test CASCADE;

SELECT finish();
ROLLBACK;
