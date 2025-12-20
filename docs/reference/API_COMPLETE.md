# pgGit API Reference

## Overview

pgGit provides a comprehensive SQL API for database version control. All functions are available in the `pggit` schema and work directly within PostgreSQL.

## Core Functions

### Schema Management
- `pggit.ensure_object()` - Register or get existing object ID
- `pggit.get_version()` - Get semantic version for an object
- `pggit.get_history()` - View change history for an object

### Migration & DDL
- `pggit.generate_migration()` - Create migration scripts from changes
- `pggit.apply_migration()` - Execute migration scripts safely

### Branching (Planned)
- `pggit.create_branch()` - Create new branch
- `pggit.checkout_branch()` - Switch branches
- `pggit.merge_branches()` - Merge branches

### Utility Functions
- `pggit.determine_severity()` - Classify change impact
- `pggit.handle_ddl_command()` - Process DDL events

## Function Categories

### 🔧 Core Infrastructure
Functions that form the foundation of pgGit's operation.

### 📊 Version Control
Functions for tracking and managing database versions.

### 🔄 Migration Tools
Functions for generating and applying database migrations.

### 🌿 Branching (Planned)
Functions for Git-like branching operations.

### 🛡️ Security & Safety
Functions for transaction safety and conflict resolution.

## Complete API Reference

For the complete auto-generated API reference, run:
```bash
psql -f scripts/generate-api-docs.sql
cat /tmp/api-reference.md
```

This generates detailed documentation for all 10+ pgGit functions with signatures, parameters, and examples.