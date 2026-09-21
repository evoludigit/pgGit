# pgGit — product definition

pgGit gives every branch, pull request and coding agent its own PostgreSQL
database on an unmodified server, records what happened to the schema there
with attribution, and hands the result to confiture as a migration. It is the
isolation, verification and attribution layer of the FraiseQL stack. It is not
a schema source of truth; specql specs and confiture migrations are.

## Persona and workflow

Primary persona: a developer on a FraiseQL project supervising coding agents
that change the schema. Secondary: any PostgreSQL team that wants a database
per branch on their own server.

1. `pggit template build --env dev --seed` builds `template_<db>` from
   `confiture build` and `fraiseql-data seed`.
2. `pggit branch create agent-task-123 --from-template --ttl 7d` gives the
   agent an isolated database in under a second.
3. The agent works against `pggit dsn agent-task-123`; every DDL statement is
   attributed to `PGGIT_ACTOR`.
4. `pggit intent claim agent-task-123 TABLE:public.tb_order` declares what the
   agent will touch; `pggit conflicts agent-task-123 other-branch` reports
   overlap before anyone promotes.
5. The human reviews `pggit diff main agent-task-123 --sql` and
   `pggit log --ddl agent-task-123`.
6. `pggit promote agent-task-123 --format confiture --out db/migrations/`
   writes the migration. confiture applies it, fraisier deploys it.
7. `pggit gc` drops expired branches.

Where pgGit is not useful: when every run starts from an empty container
built from migration files. Then git already is the version control.

## Non-goals

- Not a schema source of truth.
- Never applies DDL to `main` or to production.
- No row-level data merge. Branching copies data; promotion carries schema.
- No storage-level copy-on-write, no schema-per-branch routing, no session
  GUC branch selection.
- No multi-tenancy, AI analysis, compliance reporting or metrics.

## CLI surface v1

Every command accepts `--json` (alias `--format json`) and `--env <name>`.
Output objects carry `"contract": "v1"`.

| Command | Purpose | JSON result |
|---|---|---|
| `init [--env]` | register the env database as `main`; create `pggit_meta` | `{main: {name, database}}` |
| `doctor` | pg_dump, engine, meta schema version, extension presence | `{checks: [{name, ok, detail}]}` |
| `template build [--env] [--seed]` | confiture build + fraiseql-data seed → `template_<db>` | `{template, built_at, seeded}` |
| `branch create <name> [--from <b> \| --from-template] [--ttl <dur>]` | new database from a copy | `{branch: {name, database, head, expires_at}}` |
| `branch list` | all branches | `{branches: [...]}` |
| `branch delete <name> [--force]` | drop database, mark row | `{deleted: name}` |
| `branch close <name> --promotion <id>` | mark promoted | `{closed: name}` |
| `switch <name>` | write `.pggit/HEAD` | `{current: name}` |
| `dsn [branch]` | connection string, password masked unless `--reveal` | `{dsn}` |
| `status [branch]` | clean or dirty vs head | `{clean, added, removed, modified}` |
| `commit -m <msg>` | snapshot the branch | `{commit: {id, identifier, tree_hash, objects}}` |
| `log [branch] [--ddl]` | commits, or attributed DDL rows | `{commits: [...]}` or `{ddl: [...]}` |
| `diff <a> <b> [--sql] [--engine]` | object-level diff, or engine DDL | `{changes: [...]}` or `{sql, engine}` |
| `drift [branch] [--against-desired]` | live vs head; via confiture | `{drift: [...]}` |
| `checkout <commit> [--branch <b>]` | schema-only reset, non-main only | `{branch, head}` |
| `conflicts <a> <b>` | 13-case classification vs common base | `{base, objects: [{key, case, status}]}` |
| `intent claim\|release\|check\|list` | object-key claims per branch | `{intents: [...]}` or `{overlaps: [...]}` |
| `promote <branch> [--format confiture\|sql] [--out <dir>]` | migration or SQL plan; promotion recorded | `{promotion: {id, path, checksum}}` |
| `gc [--dry-run]` | drop expired branches | `{dropped: [...], skipped: [...]}` |
| `mcp` | stdio MCP server over the commands above | — |

Environment: `PGGIT_DATABASE_URL`, `DATABASE_URL`, `PGGIT_BRANCH`,
`PGGIT_ACTOR`, `PGGIT_PG_DUMP`, `PGGIT_ENGINE`. Exit codes follow confiture's
frozen classes; class 7 is reserved for pgGit errors.

## Decisions

See `.phases/README.md` for the full table and `docs/adr/` for the reasoning.
Rust workspace with `pggit-core` as a library; `pgschema` and confiture behind
one engine trait, confiture first; promote instead of merge; `pggit_meta` on
the same server with trinity-pattern tables; `pggit_history` as the extension.

## Kill criteria

Review date: ______ (three months after the Phase 07 launch). Continue only
if at least one FraiseQL project outside PrintOptim uses `pggit branch` in CI
and at least one stranger has filed an issue or pull request. Otherwise keep
`pggit-core` as the fraisier-core rehearsal backend and archive the CLI.
