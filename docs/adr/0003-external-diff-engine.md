# ADR 0003: DDL diff and apply are delegated to an external engine

Status: Accepted, 2026-09-21

## Context
Catalog-to-catalog diff with dependency-ordered DDL is where Atlas, migra,
pg-schema-diff and confiture spent years. Writing another one is the fastest
way to lose two.

## Decision
`pggit-engine` defines `SchemaEngine::plan(from_dsn, target) -> Plan` and
`apply(dsn, &Plan)`. Adapters are subprocesses. The first adapter is
confiture (`confiture diff --format json`, `confiture migrate generate`),
chosen when `db/environments/` exists; the second is `pgschema` for projects
outside the FraiseQL stack. Selection: `--engine`, `PGGIT_ENGINE`,
`pggit.toml`, then the default above.

## Consequences
pgGit stays small and inherits confiture's coverage and its one-model seam.
Object-level diff, status, drift and conflict classification remain native
because they need no engine. A roundtrip harness records what each engine
cannot reproduce in `docs/limits.md`.
