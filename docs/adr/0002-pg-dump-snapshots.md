# ADR 0002: Commits are pg_dump snapshots split per object

Status: Accepted, 2026-09-21

## Context
v1.0 hand-wrote a catalog normalizer per object type. It excluded foreign
keys, missed RENAME, and had to be extended for every object kind.

## Decision
A commit snapshot is `pg_dump --schema-only --no-owner` of the branch
database, split on `-- Name: ...; Type: ...; Schema: ...` headers into
per-object blocks keyed `<type>:<schema>.<name>`. Blocks are normalized (drop
`SET`, `set_config`, `\restrict`, `\unrestrict`, `Dumped from`, `Dumped by`;
trim trailing whitespace; one trailing newline) and hashed with SHA-256. The
tree hash is the SHA-256 of sorted `key\thash` lines. Schemas `pggit_history`,
confiture's and specql's tracking tables are excluded.

## Consequences
pg_dump is authoritative for every object type. Hashes are stable across
pg_dump 14–18 (fixture test). The normalization rules are a compatibility
contract and change only with a major version. pg_dump must be at least the
server's major version; `pggit doctor` checks.
