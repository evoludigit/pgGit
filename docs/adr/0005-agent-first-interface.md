# ADR 0005: The interface is designed for agents first

Status: Accepted, 2026-09-21

## Context
Coding agents author most DDL now. They create far more branches than people,
run unattended, and need machine-readable results. Humans need to know which
agent did what.

## Decision
Every command supports `--json` with a `contract` version. Every commit and
every DDL history row records an actor from `--actor`, `PGGIT_ACTOR`, or the
DSN user, and every connection sets `application_name = pggit:<actor>`.
Branches carry a TTL and `pggit gc` reaps them. `pggit intent` lets agents
declare what they will touch. `pggit mcp` exposes the surface over stdio,
matching confiture and fraisier.

## Consequences
The CLI is a contract, tested against `docs/contract/v1.json`. Human-facing
table output is secondary. The MCP server is a requirement, not a nice-to-have.
