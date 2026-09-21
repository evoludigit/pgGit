# ADR 0001: One database per branch

Status: Accepted, 2026-09-21

## Context
v1.0 tracked branches as rows while every branch shared one physical schema.
Altering a table on a feature branch altered it for main; tracking drifted
from reality on the first cross-branch DROP. v0.x tried schema-per-branch with
view routing and a session GUC, which broke on views, functions, poolers and
schema-qualified application code.

## Decision
A branch is a PostgreSQL database created with `CREATE DATABASE <base>__<branch>
TEMPLATE <base>` or `TEMPLATE template_<base>`. Applications connect to a
branch by database name. Nothing routes.

## Consequences
Real isolation on an unmodified server. Branch creation is a full copy, fast
from a template and acceptable for development databases. Data is copied,
never merged. Storage-level copy-on-write is out of scope; that is Neon's
business, not an extension's.
