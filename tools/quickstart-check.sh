#!/usr/bin/env bash
# Runs the README quickstart against a database and asserts its documented
# output. Usage: tools/quickstart-check.sh [dbname]
# Connection comes from the libpq PG* environment variables.
set -euo pipefail

DB="${1:-pggit_quickstart}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dropdb --if-exists "$DB"
createdb "$DB"
psql -q -d "$DB" -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto'
make -s -C "$ROOT" install PGDATABASE="$DB" >/dev/null

out=$(psql -qtA -d "$DB" <<'SQL'
CREATE TABLE public.tb_thing (id uuid PRIMARY KEY, name text NOT NULL);
ALTER TABLE public.tb_thing ADD COLUMN created_at timestamptz DEFAULT now();
SELECT string_agg(object_name || '|' || object_type || '|' || length(content_hash), E'\n' ORDER BY object_name)
FROM pggit.objects WHERE is_deleted = false;
SELECT string_agg(operation, ',' ORDER BY changed_at) FROM pggit.status;
SELECT pggit.commit('first commit');
SELECT count(*) FROM pggit.log();
SQL
)

expected=$'public.tb_thing|table|64\npublic.tb_thing_pkey|index|64\nCREATE,CREATE,ALTER\n1\n1'
if [[ "$out" != "$expected" ]]; then
    echo "quickstart output differs from README" >&2
    diff <(echo "$expected") <(echo "$out") >&2 || true
    exit 1
fi

make -s -C "$ROOT" uninstall PGDATABASE="$DB" >/dev/null
dropdb "$DB"
echo "quickstart OK"
