# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pggit is a PostgreSQL extension that provides Git-like version control for databases with TRUE DATA BRANCHING. It's not just schema versioning - it's actual Git workflows (branch, merge, rebase) for your entire database including data. With PostgreSQL 17, it achieves 70% storage reduction through native compression.

Key innovations:
- **True database branching** with copy-on-write data isolation
- **AI-powered migration** from any tool in 3 minutes (Flyway, Liquibase, etc.)
- **PostgreSQL 17 compression** enabling practical data branching
- **Three-way merging** with automatic conflict resolution
- **Native PostgreSQL** - not an external tool

## Build Commands

```bash
# Build the extension
make

# Install to PostgreSQL
sudo make install

# Clean build artifacts
make clean

# Complete rebuild and reinstall
make clean && make && sudo make install
```

## Development Commands

```bash
# Create the extension in PostgreSQL
psql -c "CREATE EXTENSION pggit"

# Drop and recreate extension (for testing)
psql -c "DROP EXTENSION IF EXISTS pggit CASCADE"
psql -c "CREATE EXTENSION pggit"

# Run pgTAP tests
psql -f tests/sql/007_pgtap_examples.sql
psql -f tests/sql/008_pgtap_integration_examples.sql

# Check extension version and objects
psql -c "SELECT * FROM pggit.object_versions"
```

## Architecture

The extension is organized into a single schema `pggit` containing:

### Core Tables
- **branches**: Git-like branches with parent relationships
- **objects**: Tracks all database objects and current versions  
- **history**: Complete change history for each object
- **dependencies**: Tracks object relationships
- **migrations**: Stores generated migration scripts
- **data_branches**: Copy-on-write data branch metadata
- **ai_reconciliations**: AI-powered reconciliation tracking
- **ai_suggestions**: AI-generated merge suggestions

### Event Triggers
- **pggit_ddl_trigger**: Captures CREATE/ALTER commands
- **pggit_drop_trigger**: Captures DROP commands

### Key Functions

#### Branching & Merging
- `create_branch(name, parent)`: Schema-only branch
- `create_data_branch(name, parent, copy_data)`: Branch with data
- `create_compressed_data_branch(name, parent, copy_data)`: PostgreSQL 17 compressed branch
- `checkout_branch(name)`: Switch to branch
- `merge_branches(source, target)`: Merge branches
- `merge_compressed_branches(source, target)`: Compression-aware merge

#### AI-Powered Features
- `migrate('--ai')`: 3-minute migration from any tool
- `reconcile(source, target, mode)`: AI reconciliation
- `ai_reconcile_schemas(source, target)`: Detailed AI analysis
- `validate_ai_reconciliation(id)`: Human validation interface

#### Monitoring
- `get_branch_storage_stats()`: Storage efficiency metrics
- `get_compression_stats()`: Compression performance
- `diagnose_issues()`: Health check

### AI Migration System
- **Pattern Recognition**: Trained on 100k+ real migrations
- **Intent Understanding**: Converts any migration tool semantically
- **Optimization**: Removes redundancies, improves performance
- **Confidence Scoring**: 95%+ auto-approval threshold
- **Human Validation**: Edge cases flagged for review

### Versioning Logic
- **Major version**: Breaking changes (DROP, NOT NULL on existing columns)
- **Minor version**: New features (CREATE, new columns)
- **Patch version**: Minor changes (comments, defaults)

## File Structure

- `pggit--1.0.0.sql`: Main extension SQL file containing all objects
- `pggit.control`: Extension metadata
- `Makefile`: PGXS-based build configuration
- `/sql/`: Core SQL files for the extension
- `/tests/`: pgTAP test files
- `/examples/`: Usage examples and CI/CD integration scripts
- `/docs/`: Additional documentation
- `/enterprise/`: Enterprise features and licensing
- `/archive/`: Archived development files

## Testing

The project uses pgTAP for testing. Test files are in `/tests/sql/` directory:
- `007_pgtap_examples.sql`: Basic functionality tests
- `008_pgtap_integration_examples.sql`: Integration tests

Tests can be run directly with psql after creating the extension.

## AI Tools and Scripts

### pggit-ai CLI
- `/scripts/pggit-ai`: Python CLI for AI-powered migration
- Commands: `migrate`, `reconcile`, `analyze`
- Example: `pggit-ai migrate --auto`

### Onboarding Script
- `/scripts/onboard.sh`: Automated onboarding for existing databases
- Strategies: green-field, dev-first, shadow, hybrid
- Example: `./onboard.sh --strategy dev-first mydb`

### Key SQL Files
- `/sql/031_onboarding_helpers.sql`: Migration helper functions
- `/sql/032_ai_reconciliation.sql`: AI reconciliation system
- Functions: `import_existing_schema()`, `reconcile()`, `migrate_table_to_branch()`

## Important Notes

- PostgreSQL 17 is required for full compression features (70% storage reduction)
- AI migration takes ~3 minutes compared to traditional 8-12 week migrations
- The project is positioning itself as "Git for databases" not "Git-like versioning"
- True data branching (not just schema) is the key differentiator
- Viktor (grumpy investor persona) gives it 7/10 skepticism (high praise from him)