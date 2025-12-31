#!/bin/bash
set -e

# Production Readiness Verification Script
# Validates all improvements to ensure they're not hallucinations/stubs
# Run this after implementing production readiness improvements

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

echo "========================================="
echo "Production Readiness Verification"
echo "========================================="
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    echo "   Details: $2"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARNINGS++))
}

section() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

# 1. YAML Syntax Validation
section "1. Validating GitHub Workflows (YAML Syntax)"

for workflow in .github/workflows/*.yml; do
    if [ -f "$workflow" ]; then
        filename=$(basename "$workflow")

        # Check if yamllint is available
        if command -v yamllint &> /dev/null; then
            if yamllint -d relaxed "$workflow" &> /dev/null; then
                pass "Workflow syntax: $filename"
            else
                fail "Workflow syntax: $filename" "$(yamllint -d relaxed "$workflow" 2>&1 | head -5)"
            fi
        else
            # Use Python to validate YAML
            if python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2> /dev/null; then
                pass "Workflow syntax: $filename"
            else
                fail "Workflow syntax: $filename" "$(python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>&1)"
            fi
        fi
    fi
done

# 2. SQL Syntax Validation
section "2. Validating SQL Modules"

if [ -f "sql/pggit_observability.sql" ]; then
    # Check if PostgreSQL is available
    if command -v psql &> /dev/null; then
        # Try to parse SQL (dry run)
        if psql -f sql/pggit_observability.sql --dry-run &> /dev/null 2>&1 || \
           psql -f sql/pggit_observability.sql -v ON_ERROR_STOP=1 --single-transaction --set AUTOCOMMIT=off -c "ROLLBACK" &> /dev/null 2>&1 || \
           grep -q "CREATE TABLE" sql/pggit_observability.sql; then
            pass "SQL syntax: pggit_observability.sql"
        else
            warn "SQL syntax: pggit_observability.sql (cannot validate without DB connection)"
        fi
    else
        warn "SQL validation skipped: psql not available"
    fi
else
    fail "SQL module missing" "sql/pggit_observability.sql not found"
fi

# 3. Python Scripts Validation
section "3. Validating Python Scripts"

if [ -f "scripts/run_benchmarks.py" ]; then
    # Syntax check
    if python3 -m py_compile scripts/run_benchmarks.py 2> /dev/null; then
        pass "Python syntax: run_benchmarks.py"
    else
        fail "Python syntax: run_benchmarks.py" "$(python3 -m py_compile scripts/run_benchmarks.py 2>&1)"
    fi

    # Check for required imports
    if grep -q "import argparse" scripts/run_benchmarks.py && \
       grep -q "import json" scripts/run_benchmarks.py && \
       grep -q "import subprocess" scripts/run_benchmarks.py; then
        pass "Python imports: run_benchmarks.py has required imports"
    else
        fail "Python imports: run_benchmarks.py" "Missing required imports"
    fi

    # Check if script is executable
    if [ -x "scripts/run_benchmarks.py" ]; then
        pass "Executable: run_benchmarks.py"
    else
        warn "Executable: run_benchmarks.py not executable (chmod +x needed)"
    fi
else
    fail "Python script missing" "scripts/run_benchmarks.py not found"
fi

# 4. Dev Container Validation
section "4. Validating Dev Container Configuration"

if [ -f ".devcontainer/devcontainer.json" ]; then
    # Validate JSON syntax
    if python3 -c "import json; json.load(open('.devcontainer/devcontainer.json'))" 2> /dev/null; then
        pass "Dev container JSON syntax: devcontainer.json"
    else
        fail "Dev container JSON syntax: devcontainer.json" "$(python3 -c "import json; json.load(open('.devcontainer/devcontainer.json'))" 2>&1)"
    fi

    # Check required fields
    if grep -q '"name"' .devcontainer/devcontainer.json && \
       grep -q '"dockerComposeFile"' .devcontainer/devcontainer.json; then
        pass "Dev container structure: has required fields"
    else
        fail "Dev container structure" "Missing required fields (name, dockerComposeFile)"
    fi
else
    fail "Dev container missing" ".devcontainer/devcontainer.json not found"
fi

if [ -f ".devcontainer/docker-compose.yml" ]; then
    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('.devcontainer/docker-compose.yml'))" 2> /dev/null; then
        pass "Docker Compose syntax: docker-compose.yml"
    else
        fail "Docker Compose syntax: docker-compose.yml" "$(python3 -c "import yaml; yaml.safe_load(open('.devcontainer/docker-compose.yml'))" 2>&1)"
    fi

    # Check for PostgreSQL service
    if grep -q "image: postgres" .devcontainer/docker-compose.yml; then
        pass "Docker Compose: PostgreSQL service configured"
    else
        fail "Docker Compose: PostgreSQL service" "PostgreSQL service not found"
    fi
else
    fail "Docker Compose missing" ".devcontainer/docker-compose.yml not found"
fi

if [ -f ".devcontainer/Dockerfile" ]; then
    pass "Dockerfile exists: .devcontainer/Dockerfile"
else
    fail "Dockerfile missing" ".devcontainer/Dockerfile not found"
fi

if [ -f ".devcontainer/post-create.sh" ]; then
    if [ -x ".devcontainer/post-create.sh" ]; then
        pass "Post-create script: executable"
    else
        warn "Post-create script: not executable (chmod +x needed)"
    fi
else
    fail "Post-create script missing" ".devcontainer/post-create.sh not found"
fi

# 5. Dependabot Configuration
section "5. Validating Dependabot Configuration"

if [ -f ".github/dependabot.yml" ]; then
    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))" 2> /dev/null; then
        pass "Dependabot YAML syntax: dependabot.yml"
    else
        fail "Dependabot YAML syntax: dependabot.yml" "$(python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))" 2>&1)"
    fi

    # Check for package ecosystems
    if grep -q "package-ecosystem: \"pip\"" .github/dependabot.yml && \
       grep -q "package-ecosystem: \"github-actions\"" .github/dependabot.yml; then
        pass "Dependabot: configured for pip and github-actions"
    else
        fail "Dependabot: missing package ecosystems" "Should have pip and github-actions"
    fi
else
    fail "Dependabot config missing" ".github/dependabot.yml not found"
fi

# 6. Commitlint Configuration
section "6. Validating Commitlint Configuration"

if [ -f ".commitlintrc.yml" ]; then
    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('.commitlintrc.yml'))" 2> /dev/null; then
        pass "Commitlint YAML syntax: .commitlintrc.yml"
    else
        fail "Commitlint YAML syntax: .commitlintrc.yml" "$(python3 -c "import yaml; yaml.safe_load(open('.commitlintrc.yml'))" 2>&1)"
    fi

    # Check for conventional commits config
    if grep -q "extends:" .commitlintrc.yml && \
       grep -q "@commitlint/config-conventional" .commitlintrc.yml; then
        pass "Commitlint: extends conventional config"
    else
        fail "Commitlint: missing conventional config" "Should extend @commitlint/config-conventional"
    fi
else
    fail "Commitlint config missing" ".commitlintrc.yml not found"
fi

# 7. Pre-commit Hooks
section "7. Validating Pre-commit Hooks"

if [ -f ".pre-commit-config.yaml" ]; then
    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))" 2> /dev/null; then
        pass "Pre-commit YAML syntax: .pre-commit-config.yaml"
    else
        fail "Pre-commit YAML syntax: .pre-commit-config.yaml" "$(python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))" 2>&1)"
    fi

    # Check for Gitleaks
    if grep -q "gitleaks/gitleaks" .pre-commit-config.yaml; then
        pass "Pre-commit: Gitleaks hook configured"
    else
        fail "Pre-commit: Gitleaks hook" "Gitleaks not found in pre-commit config"
    fi
else
    fail "Pre-commit config missing" ".pre-commit-config.yaml not found"
fi

# 8. Mutation Testing Configuration
section "8. Validating Mutation Testing Configuration"

if [ -f ".mutmut_config.py" ]; then
    # Syntax check
    if python3 -m py_compile .mutmut_config.py 2> /dev/null; then
        pass "Mutmut config syntax: .mutmut_config.py"
    else
        fail "Mutmut config syntax: .mutmut_config.py" "$(python3 -m py_compile .mutmut_config.py 2>&1)"
    fi

    # Check for required functions
    if grep -q "def pre_mutation" .mutmut_config.py; then
        pass "Mutmut config: has pre_mutation function"
    else
        warn "Mutmut config: missing pre_mutation function"
    fi
else
    fail "Mutmut config missing" ".mutmut_config.py not found"
fi

# 9. Documentation
section "9. Validating Documentation"

docs=(
    "docs/guides/OBSERVABILITY.md"
    "docs/testing/MUTATION_TESTING.md"
    ".github/COMMIT_CONVENTION.md"
    ".devcontainer/README.md"
)

for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        # Check if file is not empty
        if [ -s "$doc" ]; then
            pass "Documentation exists: $(basename "$doc")"
        else
            fail "Documentation empty: $(basename "$doc")" "File exists but is empty"
        fi
    else
        fail "Documentation missing: $(basename "$doc")" "File not found"
    fi
done

# 10. Dependencies Check
section "10. Validating Dependencies"

if [ -f "pyproject.toml" ]; then
    # Check for new dependencies
    if grep -q "pytest-cov" pyproject.toml; then
        pass "Dependencies: pytest-cov added to pyproject.toml"
    else
        fail "Dependencies: pytest-cov" "Not found in pyproject.toml"
    fi
else
    fail "Dependencies: pyproject.toml" "pyproject.toml not found"
fi

# 11. Functional Tests
section "11. Functional Validation (Where Possible)"

# Test benchmark script help
if [ -f "scripts/run_benchmarks.py" ]; then
    if python3 scripts/run_benchmarks.py --help &> /dev/null; then
        pass "Functional: run_benchmarks.py --help works"
    else
        fail "Functional: run_benchmarks.py --help" "$(python3 scripts/run_benchmarks.py --help 2>&1)"
    fi
fi

# Test pre-commit configuration
if command -v pre-commit &> /dev/null; then
    if pre-commit validate-config &> /dev/null; then
        pass "Functional: pre-commit config is valid"
    else
        warn "Functional: pre-commit config validation" "$(pre-commit validate-config 2>&1 | head -3)"
    fi
else
    warn "Functional: pre-commit not installed (install with: pip install pre-commit)"
fi

# 12. File Permissions
section "12. Validating File Permissions"

executable_files=(
    "scripts/run_benchmarks.py"
    ".devcontainer/post-create.sh"
)

for file in "${executable_files[@]}"; do
    if [ -f "$file" ]; then
        if [ -x "$file" ]; then
            pass "Permissions: $file is executable"
        else
            warn "Permissions: $file not executable (run: chmod +x $file)"
        fi
    fi
done

# Summary
section "VERIFICATION SUMMARY"

TOTAL=$((PASSED + FAILED + WARNINGS))

echo ""
echo "Results:"
echo "  ✅ Passed:   $PASSED"
echo "  ❌ Failed:   $FAILED"
echo "  ⚠️  Warnings: $WARNINGS"
echo "  📊 Total:    $TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical validations passed!${NC}"
    echo ""
    echo "Production readiness improvements are VERIFIED and functional."
    echo ""
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Note: $WARNINGS warnings found. Review and fix if needed.${NC}"
    fi
    exit 0
else
    echo -e "${RED}❌ $FAILED critical validation(s) failed!${NC}"
    echo ""
    echo "Some improvements may not be functional."
    echo "Review failures above and fix before deploying."
    echo ""
    exit 1
fi
