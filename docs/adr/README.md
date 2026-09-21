# Architecture decision records

| ADR | Title |
|---|---|
| [0001](0001-database-per-branch.md) | One database per branch |
| [0002](0002-pg-dump-snapshots.md) | Commits are pg_dump snapshots split per object |
| [0003](0003-external-diff-engine.md) | DDL diff and apply are delegated to an external engine |
| [0004](0004-metadata-database.md) | Metadata lives in a pggit_meta database on the same server |
| [0005](0005-agent-first-interface.md) | The interface is designed for agents first |
| [0006](0006-no-direct-apply-to-main.md) | pgGit never applies DDL to main; it promotes |
| [0007](0007-house-conventions.md) | House conventions are adopted wholesale |
| [0008](0008-license.md) | MIT |
