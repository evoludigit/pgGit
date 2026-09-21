-- Integration test: chaos / stress scenarios
-- Tests edge cases, boundary conditions, and rapid DDL sequences.

BEGIN;
SELECT plan(14);

CREATE SCHEMA chaos_test;

-- ---------------------------------------------------------------------------
-- Scenario 1: Rapid DDL cycle (CREATE → multiple ALTERs → DROP)
-- ---------------------------------------------------------------------------

CREATE TABLE chaos_test.rapid (id INT PRIMARY KEY);
ALTER TABLE chaos_test.rapid ADD COLUMN a TEXT;
ALTER TABLE chaos_test.rapid ADD COLUMN b INT;
ALTER TABLE chaos_test.rapid ALTER COLUMN b SET NOT NULL;
ALTER TABLE chaos_test.rapid ADD COLUMN c BOOLEAN DEFAULT FALSE;
ALTER TABLE chaos_test.rapid DROP COLUMN a;
DROP TABLE chaos_test.rapid;

SELECT ok(
    (
        SELECT is_deleted
        FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND object_name LIKE '%rapid%'
          AND object_type = 'table'
        ORDER BY updated_at DESC
        LIMIT 1
    ) = TRUE,
    'Scenario 1: rapid DDL cycle ends with object soft-deleted'
);

SELECT ok(
    (
        SELECT COUNT(*) FROM pggit.history h
        JOIN pggit.objects o ON o.id = h.object_id
        WHERE o.schema_name = 'chaos_test'
          AND o.object_name LIKE '%rapid%'
    ) >= 6,
    'Scenario 1: all DDL operations logged in history'
);

-- ---------------------------------------------------------------------------
-- Scenario 2: 63-character table name (PostgreSQL identifier limit)
-- ---------------------------------------------------------------------------

CREATE TABLE chaos_test.abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxy (id INT);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND object_name LIKE '%abcdefghijklmnopqrstuvwxyz0123456789%'
    ),
    'Scenario 2: 63-char table name tracked correctly'
);

-- ---------------------------------------------------------------------------
-- Scenario 3: 50 branches created
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..50 LOOP
        PERFORM pggit.create_branch('chaos-branch-' || i);
    END LOOP;
END;
$$;

SELECT ok(
    (SELECT COUNT(*) FROM pggit.branches WHERE name LIKE 'chaos-branch-%') = 50,
    'Scenario 3: 50 branches created'
);

-- ---------------------------------------------------------------------------
-- Scenario 4: 10 commits in a row
-- ---------------------------------------------------------------------------

CREATE TABLE chaos_test.commit_target (id INT PRIMARY KEY);
SELECT pggit.commit('chaos commit 1');

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 2..10 LOOP
        EXECUTE format(
            'ALTER TABLE chaos_test.commit_target ADD COLUMN col_%s TEXT',
            i
        );
        PERFORM pggit.commit('chaos commit ' || i);
    END LOOP;
END;
$$;

SELECT ok(
    (SELECT COUNT(*) FROM pggit.log('main')) >= 10,
    'Scenario 4: 10 commits recorded on main'
);

-- ---------------------------------------------------------------------------
-- Scenario 5: Pause/resume during rapid DDL
-- ---------------------------------------------------------------------------

SELECT pggit.pause_tracking();

CREATE TABLE chaos_test.paused_rapid1 (id INT);
CREATE TABLE chaos_test.paused_rapid2 (x TEXT);
ALTER TABLE chaos_test.paused_rapid1 ADD COLUMN extra BOOLEAN;

SELECT pggit.resume_tracking();

SELECT ok(
    NOT EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND object_name LIKE '%paused_rapid%'
    ),
    'Scenario 5: DDL while paused not tracked'
);

DROP TABLE chaos_test.paused_rapid1;
DROP TABLE chaos_test.paused_rapid2;

-- ---------------------------------------------------------------------------
-- Scenario 6: Multiple object types in one transaction
-- ---------------------------------------------------------------------------

CREATE TYPE chaos_test.status_enum AS ENUM ('active', 'inactive', 'pending');
CREATE SEQUENCE chaos_test.chaos_seq START 1000 INCREMENT BY 10;
CREATE TABLE chaos_test.multi_type (
    id     SERIAL PRIMARY KEY,
    status chaos_test.status_enum NOT NULL DEFAULT 'active'
);
CREATE VIEW chaos_test.multi_view AS
    SELECT id, status FROM chaos_test.multi_type WHERE status = 'active';
CREATE INDEX chaos_idx ON chaos_test.multi_type (status);

SELECT ok(
    (
        SELECT COUNT(*) FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND is_deleted = FALSE
    ) >= 3,
    'Scenario 6: multiple object types tracked in same session'
);

-- ---------------------------------------------------------------------------
-- Scenario 7: Empty branch merge (no objects on source branch)
-- ---------------------------------------------------------------------------

SELECT pggit.create_branch('empty-chaos-src');
SELECT pggit.switch_branch('empty-chaos-src');
-- Make no DDL; just commit
CREATE TABLE chaos_test.empty_src_marker (id INT);
SELECT pggit.commit('empty-chaos-src only commit');
DROP TABLE chaos_test.empty_src_marker;
SELECT pggit.commit('dropped empty-src-marker');
SELECT pggit.switch_branch('main');

DO $$
DECLARE
    v_mid BIGINT;
BEGIN
    v_mid := pggit.merge('empty-chaos-src');
    PERFORM ok(
        (SELECT status FROM pggit.merge_history WHERE id = v_mid) IN ('completed', 'in_progress'),
        'Scenario 7: merge of empty-ish source does not crash'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- Scenario 8: Cascade DROP
-- ---------------------------------------------------------------------------

CREATE TABLE chaos_test.parent_table (id INT PRIMARY KEY);
CREATE TABLE chaos_test.child_table (
    id        INT PRIMARY KEY,
    parent_id INT REFERENCES chaos_test.parent_table(id)
);

DROP TABLE chaos_test.parent_table CASCADE;

SELECT ok(
    (
        SELECT is_deleted FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND object_name LIKE '%parent_table%'
          AND object_type = 'table'
    ) = TRUE,
    'Scenario 8: parent table soft-deleted after CASCADE DROP'
);

-- ---------------------------------------------------------------------------
-- Scenario 9: Re-create after drop (object should be re-tracked)
-- ---------------------------------------------------------------------------

CREATE TABLE chaos_test.recreated (id INT PRIMARY KEY, v TEXT);
SELECT pggit.commit('create recreated');

DO $$
DECLARE
    v_hash1 TEXT;
BEGIN
    SELECT content_hash INTO v_hash1
    FROM pggit.objects
    WHERE schema_name = 'chaos_test'
      AND object_name LIKE '%recreated%'
      AND is_deleted = FALSE;

    PERFORM ok(v_hash1 IS NOT NULL, 'Scenario 9: first creation hash non-null');
END;
$$;

DROP TABLE chaos_test.recreated;

CREATE TABLE chaos_test.recreated (id INT PRIMARY KEY, v TEXT, extra BOOLEAN);

SELECT ok(
    EXISTS(
        SELECT 1 FROM pggit.objects
        WHERE schema_name = 'chaos_test'
          AND object_name LIKE '%recreated%'
          AND is_deleted = FALSE
    ),
    'Scenario 9: re-created table tracked again'
);

-- ---------------------------------------------------------------------------
-- Scenario 10: Commit after large number of uncommitted changes
-- ---------------------------------------------------------------------------

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..20 LOOP
        EXECUTE format(
            'CREATE TABLE chaos_test.bulk_table_%s (id INT PRIMARY KEY, x TEXT)',
            i
        );
    END LOOP;
END;
$$;

SELECT ok(
    (SELECT COUNT(*) FROM pggit.status) >= 20,
    'Scenario 10: 20+ uncommitted changes visible in status'
);

DO $$
DECLARE
    v_cid BIGINT;
BEGIN
    v_cid := pggit.commit('bulk commit 20 tables');
    PERFORM ok(v_cid > 0, 'Scenario 10: bulk commit succeeds');
END;
$$;

SELECT ok(
    (SELECT COUNT(*) FROM pggit.status) = 0,
    'Scenario 10: status empty after bulk commit'
);

DROP SCHEMA chaos_test CASCADE;

SELECT finish();
ROLLBACK;
