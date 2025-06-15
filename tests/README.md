# pggit Test Suite

Clean, simple test structure for the pggit database versioning extension.

## 🚀 Quick Start

```bash
# Run all tests (recommended)
./tests/test-full.sh

# Run all tests with Podman (bulletproof)
./tests/test-full.sh --podman
```

## Test Files

Just 4 simple test files:

```
tests/
├── test-core.sql       # Core functionality (versioning, triggers, functions)
├── test-enterprise.sql # Enterprise features (branching, size management) 
├── test-ai.sql         # AI migration analysis
└── test-full.sh        # Run all tests (THIS IS THE MAIN RUNNER)
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

| Test | Purpose | Dependencies | Time |
|------|---------|--------------|------|
| test-core.sql | Basic versioning, triggers | None | ~5s |
| test-enterprise.sql | Branching, size management | Core | ~10s |
| test-ai.sql | AI analysis, risk assessment | AI module | ~15s |
| test-full.sh | All of the above | Varies | ~30s |

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