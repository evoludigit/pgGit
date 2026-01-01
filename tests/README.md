# pggit Test Suite

Comprehensive test coverage for the pggit database versioning extension.

**Total Tests**: 400+ tests across 55+ files
**PostgreSQL Versions**: 15, 16, 17
**Coverage**: Unit, Integration, E2E, Chaos Engineering
**Test Environment**: 51 passing + 11 xfails (documented limitations)

## 🚀 Quick Start

```bash
# Run all SQL tests (recommended for quick verification)
./tests/test-full.sh

# Run Python E2E tests (comprehensive)
pytest tests/e2e/ -v

# Run integration tests
pytest tests/integration/ -v

# Run all tests with Podman (bulletproof)
./tests/test-full.sh --podman
```

## Test Environment & Limitations

### Xfail Strategy

pgGit uses `pytest.mark.xfail` for tests with known environment limitations:

- **Concurrent threading tests**: Limited by psycopg connection sharing
- **Complex backup chains**: Require commit/backup creation in test environment
- **Transaction isolation edge cases**: PostgreSQL transaction abortion scenarios

**Benefits:**
- ✅ Clean CI/CD pipelines (no false failures)
- ✅ Clear documentation of limitations
- ✅ Alerts when limitations are unexpectedly resolved

**Status:** 51 tests pass + 11 xfails = **62 total validated scenarios**

See: [Test Environment Status](../TEST_ENVIRONMENT_STATUS.md)

## Test Structure

```
tests/
├── test-core.sql                   # Core functionality (SQL)
├── test-enterprise.sql             # Enterprise features (SQL)
├── test-ai.sql                     # AI migration analysis (SQL)
├── test-full.sh                    # Main test runner
│
├── integration/                    # Integration tests (Python)
│   └── test_pg_version_compatibility.py  # Cross-version tests (16 tests)
│
├── e2e/                           # End-to-end tests (Python)
│   ├── test_ddl_comprehensive.py          # DDL tracking (26 tests)
│   ├── test_dependency_tracking.py        # Dependency analysis (12 tests)
│   ├── test_pg17_compression_integration.py  # PG17 features (13 tests)
│   └── [40+ other E2E test files]
│
├── chaos/                         # Chaos engineering tests
│   └── [25+ chaos test files]
│
└── fixtures/                      # Test fixtures and utilities
    ├── database.py                # Database connection management
    └── pggit.py                   # pgGit-specific fixtures
```

## Running Individual Tests

```bash
# Test core functionality
psql -d your_database -f tests/test-core.sql

# Test enterprise features  
psql -d your_database -f tests/test-enterprise.sql

# Test AI features
psql -d your_database -f tests/test-ai.sql

# Run everything
./tests/test-full.sh
```

## test-full.sh Options

```bash
# Run locally (default)
./tests/test-full.sh

# Run in Podman container (recommended for CI/CD)
./tests/test-full.sh --podman

# Specify database connection
./tests/test-full.sh --db mydb --user myuser --host localhost --port 5432

# Show help
./tests/test-full.sh --help
```

## Prerequisites

### For Local Testing
- PostgreSQL 17+
- pggit installed (via extension or from source)
- pgcrypto extension

### For Podman Testing
- Podman installed
- That's it! Everything else is automatic.

## Installation

If pggit is not installed, the test script will try to install it:

```bash
# Option 1: PostgreSQL extension
psql -d your_database -c "CREATE EXTENSION pggit CASCADE;"

# Option 2: From source
cd sql/
psql -d your_database -f install.sql
```

## Expected Results

### Success
```
🎉 ALL TESTS PASSED! 🎉
pggit is working correctly.
```

### Partial Success
```
⚠️  MOSTLY PASSED
Some tests failed, but core functionality works.
```

### Failure
```
❌ TEST SUITE FAILED
Too many failures. Please check the logs above.
```

## Test Categories

### SQL Tests (Legacy)

| Test | Purpose | Dependencies | Time |
|------|---------|--------------|------|
| test-core.sql | Basic versioning, triggers | None | ~5s |
| test-enterprise.sql | Branching, size management | Core | ~10s |
| test-ai.sql | AI analysis, risk assessment | AI module | ~15s |
| test-full.sh | All of the above | Varies | ~30s |

### Python Tests (Comprehensive)

| Test File | Purpose | Tests | Features |
|-----------|---------|-------|----------|
| **Integration Tests** |
| test_pg_version_compatibility.py | Cross-version compatibility | 16 | PG 15/16/17 support, version-specific features |
| **E2E Tests** |
| test_ddl_comprehensive.py | Complete DDL tracking | 26 | All DDL operations (tables, indexes, views, functions, types, triggers) |
| test_dependency_tracking.py | Dependency analysis | 12 | Foreign keys, views, functions, cascade behavior |
| test_pg17_compression_integration.py | PG17 compression | 13 | LZ4/ZSTD compression with pgGit tracking |
| **Chaos Tests** |
| chaos/* | Chaos engineering | 150+ | Concurrent access, crash recovery, resource limits |

### New Test Coverage Added (2026-01-01)

**67 new tests** added across 4 files:

1. **Cross-Version Compatibility** (16 tests)
   - Extension loading on PG 15, 16, 17
   - Core object tracking across versions
   - PG16+ partition support
   - PG17+ compression features
   - Performance benchmarks

2. **DDL Comprehensive** (26 tests)
   - Tables: CREATE, ALTER (add/drop/rename/change type), DROP
   - Indexes: CREATE, CREATE UNIQUE, multi-column, DROP
   - Views: CREATE, CREATE MATERIALIZED, REFRESH, DROP
   - Functions/Procedures: CREATE, DROP, with defaults
   - Types: CREATE (composite, enum, domain)
   - Triggers: CREATE, BEFORE/AFTER, DROP
   - Constraints: ADD/DROP

3. **Dependency Tracking** (12 tests)
   - View-table dependencies
   - Foreign key dependencies
   - Function-table dependencies
   - Multi-level dependency chains
   - DROP CASCADE behavior
   - Self-referential foreign keys

4. **PG17 Compression Integration** (13 tests)
   - Compressed table version tracking
   - Data integrity with compression
   - Schema evolution with compression
   - Mixed compression settings (none/LZ4/ZSTD)
   - Performance benchmarks
   - Edge cases and error handling

## Troubleshooting

### "psql: command not found"
Install PostgreSQL client tools.

### "FAIL: pggit schema does not exist"
Install pggit first (see Installation above).

### "FAIL: AI module not installed"
The AI module needs to be loaded:
```bash
psql -d your_database -f sql/030_ai_migration_analysis.sql
```

### Podman issues
```bash
# Check Podman
podman --version

# Test container
podman run --rm postgres:17-alpine echo "Works"
```

## Contributing

Keep tests simple:
1. Add test cases to appropriate file
2. Use clear PASS/FAIL messages
3. Clean up after tests
4. Run `test-full.sh` to verify

---

**Just run `./tests/test-full.sh` and you're good to go!** 🚀