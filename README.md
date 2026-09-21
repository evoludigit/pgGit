# pgGit

Isolation, verification and attribution for PostgreSQL schemas in the
FraiseQL stack. v2 is in development; see [docs/product.md](docs/product.md)
for what it will do and `docs/adr/` for why.

## What exists today

`extension/` holds the v1.0 core: a pure-SQL PostgreSQL extension that records
every DDL statement through event triggers, stores a normalized copy of each
object with a SHA-256 content hash, and keeps an append-only history. It also
carries branch, commit and merge functions that operate on tracking rows only;
they do not isolate schemas and are being replaced by the v2 control plane.

Tested with pgTAP on PostgreSQL 16 in CI. Installs on PostgreSQL 14 to 18.

## Quickstart (extension)

Requires `psql`, a database you own, and the `pgcrypto` extension.

```sh
createdb pggit_try
psql -d pggit_try -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto'
make install PGDATABASE=pggit_try
```

```sql
CREATE TABLE public.tb_thing (id uuid PRIMARY KEY, name text NOT NULL);
ALTER TABLE public.tb_thing ADD COLUMN created_at timestamptz DEFAULT now();

SELECT object_name, object_type, left(content_hash, 12) AS hash
FROM pggit.objects WHERE is_deleted = false ORDER BY 1;
-- public.tb_thing      | table | <12 hex chars>
-- public.tb_thing_pkey | index | <12 hex chars>   (the primary key index is its own object)

SELECT operation, changed_at FROM pggit.status;
-- CREATE, CREATE, ALTER

SELECT pggit.commit('first commit');
SELECT id, message FROM pggit.log();
```

Remove with `make uninstall PGDATABASE=pggit_try`.

## Known limits of the extension

- All branches share one physical schema. `create_branch` copies tracking
  rows; DDL on one branch changes the database for every branch.
- DDL by a role other than the extension owner fails with a permission error
  while the extension is installed. Fixed in v2's `pggit_history`.
- Objects that exist before installation are not tracked until touched.
- `ALTER ... RENAME` leaves the old name as a live object.
- Foreign-key changes are not part of the content hash.

## Development

```sh
make test          # pgTAP unit and integration suites against $TEST_DB
make lint
tools/quickstart-check.sh   # runs the quickstart above against $PG* and checks its output
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Planning lives in `.phases/` locally
and is not committed.

## Part of the FraiseQL ecosystem

| Tool | Role |
|---|---|
| [fraiseql](https://github.com/fraiseql/fraiseql) | compiled GraphQL engine |
| [specql](https://github.com/evoludigit/specql) | spec to schema and project |
| [confiture](https://github.com/fraiseql/confiture) | migrations |
| [fraisier](https://github.com/fraiseql/fraisier) | deploys |
| pgGit | database per branch, attributed DDL history — v2 in development |

## License

MIT. See [LICENSE](LICENSE).
