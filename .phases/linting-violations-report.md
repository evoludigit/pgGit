# pgGit Greenfield Phase 4: Linting Violations Report

## Executive Summary

Comprehensive linting analysis reveals 1,066 violations across 735 Python files. Violations are categorized by severity and fixability, with clear prioritization for systematic resolution.

## Violations by Category

### Critical Security Issues (Fix Immediately)

| Code | Description | Count | Severity | Fixable |
|------|-------------|-------|----------|---------|
| **S608** | hardcoded-sql-expression | 52 | 🔴 Critical | No |
| **S106** | hardcoded-password-func-arg | 1 | 🔴 Critical | No |

**Security Impact:** 53 violations requiring immediate attention
- S608: Hardcoded SQL expressions pose SQL injection risks
- S106: Hardcoded passwords in function arguments

### High Priority Fixes (Automated Fixes Available)

| Code | Description | Count | Severity | Fixable |
|------|-------------|-------|----------|---------|
| **COM812** | missing-trailing-comma | 220 | 🟡 High | Yes (safe) |
| **I001** | unsorted-imports | 27 | 🟡 High | Yes (safe) |
| **RET505** | superfluous-else-return | 24 | 🟡 High | Yes (safe) |
| **Q000** | bad-quotes-inline-string | 20 | 🟡 High | Yes (safe) |
| **F541** | f-string-missing-placeholders | 11 | 🟡 High | Yes (safe) |
| **PIE790** | unnecessary-placeholder | 1 | 🟡 High | Yes (safe) |
| **PLR5501** | collapsible-else-if | 1 | 🟡 High | Yes (safe) |
| **SIM114** | if-with-same-arms | 1 | 🟡 High | Yes (safe) |

**Automated Fixes Available:** 305 violations (28.6% of total)
- Safe fixes: 305 violations can be auto-fixed without code review

### Medium Priority Issues (Manual Review Required)

| Code | Description | Count | Severity | Fixable |
|------|-------------|-------|----------|---------|
| **E501** | line-too-long | 160 | 🟡 Medium | Manual |
| **T201** | print | 155 | 🟡 Medium | Manual |
| **BLE001** | blind-except | 52 | 🟡 Medium | Manual |
| **PLR2004** | magic-value-comparison | 48 | 🟡 Medium | Manual |
| **TRY300** | try-consider-else | 38 | 🟡 Medium | Manual |
| **S110** | try-except-pass | 28 | 🟡 Medium | Manual |
| **PT017** | pytest-assert-in-except | 27 | 🟡 Medium | Manual |
| **PERF203** | try-except-in-loop | 24 | 🟡 Medium | Manual |
| **E722** | bare-except | 19 | 🟡 Medium | Manual |
| **PLC0415** | import-outside-top-level | 19 | 🟡 Medium | Manual |

**Manual Review Required:** 620 violations (58.2% of total)
- Code style: Line length, print statements, magic values
- Error handling: Blind except, bare except, try-except-pass
- Performance: Try-except in loops
- Testing: Pytest-specific issues

### Low Priority Issues (Code Quality)

| Code | Description | Count | Severity | Fixable |
|------|-------------|-------|----------|---------|
| **F841** | unused-variable | 27 | 🟢 Low | Manual |
| **F401** | unused-import | 10 | 🟢 Low | Yes (safe) |
| **ARG002** | unused-method-argument | 14 | 🟢 Low | Manual |
| **SIM105** | suppressible-exception | 15 | 🟢 Low | Manual |
| **PLR0915** | too-many-statements | 7 | 🟢 Low | Manual |
| **B011** | assert-false | 6 | 🟢 Low | Manual |
| **PT015** | pytest-assert-always-false | 6 | 🟢 Low | Manual |
| **B007** | unused-loop-control-variable | 5 | 🟢 Low | Manual |
| **PT018** | pytest-composite-assertion | 5 | 🟢 Low | Manual |
| **RUF015** | unnecessary-iterable-allocation-for-first-element | 5 | 🟢 Low | Manual |

**Code Quality Issues:** 96 violations (9.0% of total)
- Cleanup: Unused variables, imports, arguments
- Complexity: Too many statements, complex structures
- Testing: Pytest assertion issues

### Minor Issues (Nitpicks)

| Code | Description | Count | Severity | Fixable |
|------|-------------|-------|----------|---------|
| **UP035** | deprecated-import | 3 | 🔵 Minor | Manual |
| **EM101** | raw-string-in-exception | 4 | 🔵 Minor | Manual |
| **S311** | suspicious-non-cryptographic-random-usage | 4 | 🔵 Minor | Manual |
| **TRY003** | raise-vanilla-args | 4 | 🔵 Minor | Manual |
| **FBT003** | boolean-positional-value-in-call | 2 | 🔵 Minor | Manual |
| **C401** | unnecessary-generator-set | 1 | 🔵 Minor | Manual |
| **C901** | complex-structure | 3 | 🔵 Minor | Manual |
| **INP001** | implicit-namespace-package | 3 | 🔵 Minor | Manual |
| **RET503** | implicit-return | 2 | 🔵 Minor | Manual |
| **A004** | builtin-import-shadowing | 1 | 🔵 Minor | Manual |
| **ARG001** | unused-function-argument | 1 | 🔵 Minor | Manual |
| **F821** | undefined-name | 1 | 🔵 Minor | Manual |
| **F823** | undefined-local | 1 | 🔵 Minor | Manual |
| **PERF401** | manual-list-comprehension | 1 | 🔵 Minor | Manual |
| **PT003** | pytest-extraneous-scope-function | 1 | 🔵 Minor | Manual |
| **SIM103** | needless-bool | 1 | 🔵 Minor | Manual |
| **W291** | trailing-whitespace | 1 | 🔵 Minor | Manual |
| **B033** | duplicate-value | 4 | 🔵 Minor | Yes (safe) |

**Minor Issues:** 43 violations (4.0% of total)

## Fix Implementation Plan

### Phase 1: Automated Safe Fixes (Immediate - 305 violations)

```bash
# Apply all safe automated fixes
ruff check . --fix

# Expected result: 305 violations resolved
```

### Phase 2: Security Fixes (High Priority - 53 violations)

**S608 (52 violations):** Replace hardcoded SQL with parameterized queries
- **Files affected:** Test files with SQL assertions
- **Risk:** SQL injection if not properly handled
- **Fix:** Use psycopg3 parameterized queries

**S106 (1 violation):** Remove hardcoded password arguments
- **Location:** Test fixture or configuration
- **Fix:** Use environment variables or secure credential management

### Phase 3: Code Style Fixes (Medium Priority - 620 violations)

**E501 (160 violations):** Break long lines
- **Tools:** ruff format or manual line breaks
- **Standards:** 88 character line length (Black/ruff default)

**T201 (155 violations):** Replace print with logging
- **Pattern:** `print(` → `logger.info(` or appropriate level
- **Impact:** Production-ready logging instead of debug prints

**BLE001 (52 violations):** Add specific exception handling
- **Pattern:** `except:` → `except Exception:` or specific exception types
- **Impact:** Better error handling and debugging

### Phase 4: Code Quality Improvements (Low Priority - 96 violations)

**F841 (27 violations):** Remove unused variables
- **Pattern:** `_variable` or remove if truly unused
- **Impact:** Cleaner code, reduced confusion

**F401 (10 violations):** Remove unused imports
- **Already auto-fixable** with `ruff check --fix`

## Success Metrics

- **Target Violations:** 0 (except intentional ignores)
- **Acceptable Ignores:** S101 (assert in tests), S104 (hardcoded binds in tests)
- **Security Violations:** 0 (S608, S106 must be fixed)
- **Automated Fixes:** 305+ violations resolved immediately

## Verification Commands

```bash
# After fixes, verify results
ruff check . --statistics

# Should show significant reduction
# Target: <200 violations (from 1,066)
# Critical: 0 security violations
```

---

*Linting Analysis: 1,066 violations across 735 Python files*
*Automated fixes available: 305 violations (28.6%)*
*Security issues requiring attention: 53 violations*
*Created: 2025-12-21*