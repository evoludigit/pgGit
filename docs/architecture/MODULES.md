# pgGit Module Architecture

## Overview

pgGit is organized into **core modules** (required) and **extension modules** (optional).

```
pggit/
├── core/sql/              # Required - Always loaded
│   ├── 001_schema.sql     # Base types, tables, enums
│   ├── 002_event_triggers.sql  # DDL capture
│   ├── 003_migration_functions.sql # Migration generation
│   ├── 004_utility_views.sql # Helper views
│   └── install.sql        # Load all core
│
├── sql/                   # Extensions - Optional features
│   ├── pggit_configuration.sql      # Selective tracking
│   ├── pggit_cqrs_support.sql       # CQRS patterns
│   ├── pggit_function_versioning.sql # Function overloads
│   ├── 020-054_*.sql                # Advanced features
│   └── install.sql                  # Load all extensions
│
└── pggit--0.1.0.sql       # Combined installation file
```

## Module Dependency Graph

```
001_schema.sql (base types, tables, enums)
    ↓
002_event_triggers.sql (DDL capture)
    ↓
003_migration_functions.sql
    ↓
004_utility_views.sql
    ↓
[Extensions - no dependencies between them]
    ├── pggit_configuration.sql
    ├── pggit_cqrs_support.sql
    ├── pggit_function_versioning.sql
    └── ...
```

## Installation Options

### Option 1: Full Installation (Recommended)
```sql
CREATE EXTENSION pggit;
-- OR
\i pggit--0.1.0.sql
```

### Option 2: Core Only
```sql
\i core/sql/install.sql
```

### Option 3: Core + Selected Extensions
```sql
\i core/sql/install.sql
\i sql/pggit_configuration.sql
\i sql/pggit_cqrs_support.sql
```

## Module Loading Order

**Critical**: Modules must be loaded in numerical order.

| Order | File | Purpose | Required |
|-------|------|---------|----------|
| 1 | 001_schema.sql | Types, tables, enums | ✅ |
| 2 | 002_event_triggers.sql | DDL capture | ✅ |
| 3 | 003_migration_functions.sql | Migration generation | ✅ |
| 4 | 004_utility_views.sql | Helper views | ✅ |
| 5+ | Extensions | Optional features | ❌ |

## Feature Matrix

| Feature | Module | Status |
|---------|--------|--------|
| DDL Tracking | core/002 | ✅ Stable |
| Git Branching | core/006 | ✅ Stable |
| CQRS Support | sql/pggit_cqrs | 🧪 Experimental |
| Function Versioning | sql/pggit_function | 🧪 Experimental |
| AI Analysis | sql/030_ai | 🚧 Planned |

## How to Add New Modules

1. Determine if core (required) or extension (optional)
2. Choose next available number (e.g., 055_)
3. Add dependency declarations in file header
4. Update install.sql to include new module
5. Add to this documentation
6. Add tests to tests/test-[module-name].sql