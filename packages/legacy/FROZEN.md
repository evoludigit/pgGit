# FROZEN

This package contains pgGit v0.2.1 source, preserved for reference only.

**No pull requests will be accepted against this package.**
**No issues filed against this package will be resolved.**

The architectural defects that motivated the rewrite are documented in:
  docs/architecture/00-overview.md

The primary defects were:
- `content_hash` was always NULL — hashing was never wired up
- Table-inheritance CoW scheme was wrong abstraction for DDL versioning
- GUC-based query routing was incompatible with connection poolers
- Scores of unrelated features (AI/ML, monitoring, CoW data branching)
  accumulated without completing the core functionality

To understand what was attempted before reading the new code:
  packages/legacy/sql/install.sql  — entry point
