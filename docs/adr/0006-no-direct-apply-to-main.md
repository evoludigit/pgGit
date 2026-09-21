# ADR 0006: pgGit never applies DDL to main; it promotes

Status: Accepted, 2026-09-21

## Context
In the FraiseQL stack, changes reach main through confiture migrations under
fraisier's policy tiers and window-safety gates, and confiture ledgers every
applied change. A three-way merge that applies DDL to main directly would
bypass all of it. confiture already generates migration files from a branch
diff (`integrations/pggit/generator.py`).

## Decision
`pggit promote <branch>` emits a confiture migration (or an ordered SQL plan
with `--format sql`) from `diff(main@head, branch)` and records a
`tb_promotion` row with the migration checksum. `pggit conflicts` and the
intent registry detect overlap between branches before promotion. The 13-case
classifier from v1.0 survives as a read-only detector. `checkout` applies DDL
only to non-main branches.

## Consequences
No second path to production. The hardest part of v1.0, applying merged DDL,
is deleted rather than fixed. Projects outside the stack get a SQL plan and
apply it with their own tooling.
