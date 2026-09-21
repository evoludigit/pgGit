# ADR 0007: House conventions are adopted wholesale

Status: Accepted, 2026-09-21

## Context
The stack already has conventions for DSNs, exit codes, config, lints, naming
and releases. Evidence with paths is in
`.phases/ecosystem-study-2026-09-21.md` §5.

## Decision
- Rust: `unsafe_code = "forbid"`; clippy all, pedantic, cargo deny; nursery
  warn; MSRV 1.95; rustfmt width 100, `StdExternalCrate`; `.clippy.toml` from
  fraiseql; `cargo xtask ci`; nextest, insta, proptest, testcontainers;
  release-plz; SBOM and cosign on tags.
- Output: global `--json`, `--format json` accepted as an alias.
- DSN: never on argv. `--env <name>` reads `db/environments/<name>.yaml`;
  else `PGGIT_DATABASE_URL`; else `DATABASE_URL`; both set and different is an
  error, as in confiture. Subprocesses receive libpq `PG*` variables.
- Exit codes: confiture's frozen classes, vendored with a fixture test;
  class 7 for pgGit errors.
- Config: `pggit.toml`, TOML, `${ENV}` interpolation, `deny_unknown_fields`;
  env prefix `PGGIT_`.
- Naming: trinity columns and `tb_` singular names in pgGit's own SQL.
- Repository under `github.com/fraiseql`; `.phases/` for planning; ADRs here.

## Consequences
A FraiseQL user learns nothing new to use pgGit. Deviations require an ADR.
