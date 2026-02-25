-- pgTAP unit tests: DDL normalization (Phase 2)

BEGIN;
SELECT plan(19);

-- ---------------------------------------------------------------------------
-- Schema filtering
-- ---------------------------------------------------------------------------

SELECT ok(
    NOT pggit_internal.is_tracked_schema('pg_catalog'),
    'pg_catalog is not tracked'
);
SELECT ok(
    NOT pggit_internal.is_tracked_schema('information_schema'),
    'information_schema is not tracked'
);
SELECT ok(
    NOT pggit_internal.is_tracked_schema('pggit'),
    'pggit schema is not tracked'
);
SELECT ok(
    NOT pggit_internal.is_tracked_schema('pggit_internal'),
    'pggit_internal schema is not tracked'
);
SELECT ok(
    NOT pggit_internal.is_tracked_schema('pg_temp_1'),
    'pg_temp_1 is not tracked'
);
SELECT ok(
    pggit_internal.is_tracked_schema('public'),
    'public schema is tracked'
);
SELECT ok(
    pggit_internal.is_tracked_schema('myapp'),
    'custom schema is tracked'
);

-- ---------------------------------------------------------------------------
-- Table normalization
-- ---------------------------------------------------------------------------

CREATE SCHEMA pggit_norm_test;

CREATE TABLE pggit_norm_test.test_table (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

SELECT ok(
    pggit_internal.normalize_table('pggit_norm_test.test_table'::regclass) IS NOT NULL,
    'normalize_table returns non-NULL'
);

SELECT ok(
    pggit_internal.normalize_table('pggit_norm_test.test_table'::regclass) LIKE '%name%',
    'normalize_table contains column name'
);

SELECT ok(
    length(pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass,
        'table'::pggit.object_type
    )) = 64,
    'compute_hash returns 64-char string for table'
);

SELECT ok(
    pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass,
        'table'::pggit.object_type
    ) ~ '^[0-9a-f]{64}$',
    'compute_hash is lowercase hex'
);

-- ---------------------------------------------------------------------------
-- View normalization
-- ---------------------------------------------------------------------------

CREATE VIEW pggit_norm_test.test_view AS
    SELECT id, name FROM pggit_norm_test.test_table WHERE id > 0;

SELECT ok(
    pggit_internal.normalize_view('pggit_norm_test.test_view'::regclass) IS NOT NULL,
    'normalize_view returns non-NULL'
);

SELECT ok(
    length(pggit_internal.compute_hash(
        'pggit_norm_test.test_view'::regclass,
        'view'::pggit.object_type
    )) = 64,
    'compute_hash returns 64-char string for view'
);

-- ---------------------------------------------------------------------------
-- Function normalization
-- ---------------------------------------------------------------------------

CREATE FUNCTION pggit_norm_test.test_func(x INT) RETURNS INT
LANGUAGE sql AS $$ SELECT x + 1 $$;

SELECT ok(
    pggit_internal.normalize_function('pggit_norm_test.test_func(int)'::regprocedure) IS NOT NULL,
    'normalize_function returns non-NULL'
);

SELECT ok(
    pggit_internal.normalize_function('pggit_norm_test.test_func(int)'::regprocedure)
        LIKE '%test_func%',
    'normalize_function contains function name'
);

-- ---------------------------------------------------------------------------
-- Sequence normalization
-- ---------------------------------------------------------------------------

CREATE SEQUENCE pggit_norm_test.test_seq START 100 INCREMENT BY 5;

SELECT ok(
    pggit_internal.normalize_sequence('pggit_norm_test.test_seq'::regclass) IS NOT NULL,
    'normalize_sequence returns non-NULL'
);

SELECT ok(
    pggit_internal.normalize_sequence('pggit_norm_test.test_seq'::regclass)
        LIKE '%INCREMENT BY 5%',
    'normalize_sequence contains increment value'
);

-- ---------------------------------------------------------------------------
-- Hash stability: same object → same hash
-- ---------------------------------------------------------------------------

SELECT ok(
    pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass, 'table'::pggit.object_type
    ) = pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass, 'table'::pggit.object_type
    ),
    'same object produces same hash twice'
);

-- Hash changes after semantic change
CREATE TEMP TABLE _norm_hash_before AS
    SELECT pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass, 'table'::pggit.object_type
    ) AS h;

ALTER TABLE pggit_norm_test.test_table ADD COLUMN extra BOOLEAN;

SELECT ok(
    (SELECT h FROM _norm_hash_before) <>
    pggit_internal.compute_hash(
        'pggit_norm_test.test_table'::regclass, 'table'::pggit.object_type
    ),
    'hash changes after ALTER TABLE ADD COLUMN'
);

DROP SCHEMA pggit_norm_test CASCADE;

SELECT finish();
ROLLBACK;
