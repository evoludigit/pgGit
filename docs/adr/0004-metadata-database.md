# ADR 0004: Metadata lives in a pggit_meta database on the same server

Status: Accepted, 2026-09-21

## Context
Branches, commits, snapshots, intents and promotions need durable, queryable,
shared state. v1.0 kept it inside the tracked database, which does not work
once each branch is its own database.

## Decision
`pggit init` creates `pggit_meta` on the target server and applies embedded
SQL guarded by `tb_schema_version`. Tables follow the trinity pattern and
`tb_` naming: `tb_branch`, `tb_commit` (with `parent_pks BIGINT[]` for merge
ancestry), `tb_commit_object`, `tb_intent`, `tb_promotion`. v1.0's `find_lca`
and tree-hash functions are ported; plpgsql locals follow `v_<entity>_<role>`.

## Consequences
One server holds branches and their metadata; backups cover both. The SQL is
pgTAP-tested and passes naming-police. A file or SQLite store was rejected
because two developers on one server must see the same branches.
