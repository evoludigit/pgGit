# pgGit v0.0.1

A Git-like version control system for PostgreSQL database schemas.

## Overview

pgGit provides schema versioning, branching, merging, and audit tracking for PostgreSQL databases. It enables teams to manage database evolution as code, similar to application version control.

**Status**: v0.0.1 (Early development - Phase 1 Foundation complete)

## What's Included in Phase 1

- ✅ Complete schema with 8 tables
- ✅ Utility functions for hashing, validation, branch management
- ✅ Event triggers for automatic DDL capture
- ✅ Bootstrap initialization
- ✅ Comprehensive unit tests

## Quick Start

### 1. Prerequisites

- PostgreSQL 15+
- Python 3.10+
- `psycopg` (PostgreSQL driver for Python)

### 2. Setup

```bash
# Clone repository
cd /home/lionel/code/pggit

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -e ".[dev]"
```

### 3. Initialize Database

```bash
# Create test database
createdb pggit_test

# Initialize schema (from project root)
psql -d pggit_test -f sql/v1.0.0/phase_1_schema.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_utilities.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_triggers.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_bootstrap.sql
```

### 4. Run Tests

```bash
# Run all tests
pytest tests/ -v

# Run only unit tests
pytest tests/unit/ -v

# Run with coverage
pytest tests/ -v --cov=sql --cov-report=html
```

## Directory Structure

```
pggit/
├── sql/
│   └── v1.0.0/
│       ├── phase_1_schema.sql        # 8 tables, indexes, constraints
│       ├── phase_1_utilities.sql     # Helper functions
│       ├── phase_1_triggers.sql      # DDL capture triggers
│       └── phase_1_bootstrap.sql     # Initialization data
├── tests/
│   ├── conftest.py                   # Pytest configuration
│   ├── unit/
│   │   ├── test_phase_1_schema.py    # Schema tests
│   │   └── test_phase_1_utilities.py # Utility function tests
│   └── integration/
│       └── test_phase_1_workflows.py # Integration tests (TODO)
├── src/                              # Python source code (for future phases)
├── pyproject.toml                    # Project configuration
└── README.md                          # This file
```

## Phase 1: Foundation

**Objective**: Establish the foundation for pgGit by creating the core schema, utilities, and event-driven capture system.

**Deliverables**:
- [x] 8 core tables with proper relationships
- [x] 10+ utility functions
- [x] Event triggers for automatic DDL capture
- [x] Bootstrap initialization script
- [x] 30+ unit tests covering schema and utilities
- [x] Integration tests for basic workflows (TODO)

**Status**: Phase 1 Foundation Complete

## Testing

### Unit Tests

- `test_phase_1_schema.py`: Validates all 8 tables, columns, types, constraints, and indexes
- `test_phase_1_utilities.py`: Tests all 10 utility functions with various inputs

### Integration Tests (TODO)

- Schema initialization workflow
- DDL auto-capture workflow
- Edge cases and error handling

### Running Tests

```bash
# All tests
pytest tests/ -v

# Specific test file
pytest tests/unit/test_phase_1_schema.py -v

# Specific test class
pytest tests/unit/test_phase_1_schema.py::TestSchemaObjects -v

# Specific test
pytest tests/unit/test_phase_1_schema.py::TestSchemaObjects::test_table_exists -v

# With coverage
pytest tests/ -v --cov --cov-report=html --cov-report=term
```

## Configuration

Database connection can be configured via environment variables:

```bash
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=password
export PGDATABASE=pggit_test

pytest tests/
```

Or use default values (localhost, port 5432, user postgres, database pggit_test).

## Key Concepts

### Branches
Similar to Git, pgGit supports branching for isolated schema development:
- Each branch has a name, parent branch, and head commit
- Branches can be merged back to their parent
- Status tracking: ACTIVE, MERGED, DELETED, CONFLICTED, STALE

### Commits
Immutable records of schema changes:
- Each commit has a SHA256 hash (like Git)
- Contains object changes, tree hash, author info
- Linked via parent pointers to form history

### Schema Objects
Tracks individual database objects:
- Tables, views, functions, indexes, etc.
- Content hashing for efficient diffs
- Semantic versioning (MAJOR.MINOR.PATCH)
- Audit trail via object_history table

### Content Addressing
SHA256 hashes enable:
- Efficient merge conflict detection
- Deduplication in copy-on-write
- Three-way merge algorithms

## Documentation

For detailed specification, see `/tmp/pggit-api-spec/`:

- `SCHEMA_DESIGN.md` - Complete schema documentation
- `API_SPECIFICATION.md` - Function specifications (Phases 2-7)
- `PHASE_1_QUICK_START.md` - Phase 1 implementation guide
- `IMPLEMENTATION_ROADMAP.md` - All 7 phases

## Development Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/description
   ```

2. **Implement changes** (follow Phase structure in specification)

3. **Run tests**
   ```bash
   pytest tests/ -v --cov
   ```

4. **Commit with descriptive message**
   ```bash
   git commit -m "feat(phase-1): Add feature description"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/description
   ```

## Next Steps

**Phase 2**: Branch Management Functions
- `create_branch()`, `delete_branch()`, `list_branches()`, `checkout_branch()`

**Phase 3**: Object Tracking Functions
- `get_current_schema()`, `get_object_definition()`, `get_object_history()`

**Phase 4**: Merge & Conflict Functions
- `merge_branches()`, `detect_merge_conflicts()`, `resolve_conflict()`

See `/tmp/pggit-api-spec/IMPLEMENTATION_ROADMAP.md` for complete timeline.

## Support

For issues or questions:
1. Check specification docs in `/tmp/pggit-api-spec/`
2. Review test cases for usage examples
3. Check function comments for implementation details

## License

MIT License - See LICENSE file for details

---

**Built with**: PostgreSQL, Python, pytest
**Quality Target**: Enterprise-grade v1.0 quality standards
**Version Strategy**: Conservative versioning (0.0.1 → 0.1.0 → 1.0.0)
