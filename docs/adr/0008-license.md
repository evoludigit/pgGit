# ADR 0008: MIT

Status: Accepted, 2026-09-21

## Context
Every engine in the stack is MIT (jsonb_delta is PostgreSQL License). The
business is hosting; engines are the open moat and the control plane is the
product.

## Decision
pgGit stays MIT. The hosted control plane that embeds `pggit-core` is not part
of this repository and is not covered by this decision.

## Consequences
Anyone may run pgGit anywhere, including competitors. Revenue comes from the
service, never from this code. Revisit only before accepting outside
contributors, never after.
