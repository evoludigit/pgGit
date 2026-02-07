#!/usr/bin/env bash
# Validate CHANGELOG.md follows Keep a Changelog format
# Usage: ./scripts/validate-changelog.sh

set -euo pipefail

CHANGELOG="CHANGELOG.md"
ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() {
    echo -e "${RED}❌ ${NC}$*"
    ((ERRORS++))
}

log_success() {
    echo -e "${GREEN}✅ ${NC}$*"
}

log_warn() {
    echo -e "${YELLOW}⚠ ${NC}$*"
}

log_info() {
    echo -e "${YELLOW}ℹ ${NC}$*"
}

# Check file exists
if [ ! -f "$CHANGELOG" ]; then
    log_error "CHANGELOG.md not found"
    exit 1
fi

echo "Validating CHANGELOG.md..."
echo ""

# 1. Check for Unreleased section
if ! grep -q "^## \[Unreleased\]" "$CHANGELOG"; then
    log_error "Missing '## [Unreleased]' section"
else
    log_success "Has [Unreleased] section"
fi

# 2. Check for latest version
LATEST_VERSION=$(grep "^## \[" "$CHANGELOG" | head -2 | tail -1 | sed 's/.*\[\(.*\)\].*/\1/')
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "Unreleased" ]; then
    log_error "Could not find latest version in changelog"
else
    log_success "Latest version: $LATEST_VERSION"
fi

# 3. Check date format for latest release
LATEST_DATE=$(grep "^## \[" "$CHANGELOG" | head -2 | tail -1 | sed 's/.*- \([0-9-]*\)$/\1/')
if ! [[ $LATEST_DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    log_error "Latest release has invalid date format: $LATEST_DATE (expected YYYY-MM-DD)"
else
    log_success "Latest release date format valid: $LATEST_DATE"
fi

# 4. Check for standard sections in latest release
if grep -A 50 "^## \[$LATEST_VERSION\]" "$CHANGELOG" | grep -q "^### Summary"; then
    log_success "Has '### Summary' section"
else
    log_error "Latest release missing '### Summary' section"
fi

if grep -A 50 "^## \[$LATEST_VERSION\]" "$CHANGELOG" | grep -q "^### Changes"; then
    log_success "Has '### Changes' section"
else
    log_error "Latest release missing '### Changes' section"
fi

# 5. Check for basic structure
if ! grep -q "^# Changelog" "$CHANGELOG"; then
    log_error "Missing '# Changelog' header"
else
    log_success "Has Changelog header"
fi

if ! grep -q "Keep a Changelog" "$CHANGELOG"; then
    log_error "Missing 'Keep a Changelog' reference"
else
    log_success "References Keep a Changelog format"
fi

if ! grep -q "Semantic Versioning" "$CHANGELOG"; then
    log_error "Missing 'Semantic Versioning' reference"
else
    log_success "References Semantic Versioning"
fi

# 6. Check version format (should be X.Y.Z)
VERSIONS=$(grep "^## \[" "$CHANGELOG" | grep -v Unreleased | sed 's/.*\[\(.*\)\].*/\1/' | head -5)
if [ -n "$VERSIONS" ]; then
    while IFS= read -r version; do
        if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid version format: $version (expected X.Y.Z)"
        fi
    done <<< "$VERSIONS"
    log_success "Version format valid (X.Y.Z)"
fi

# 7. Check for duplicate versions (warn but don't fail - may be historical)
DUPLICATE=$(grep "^## \[" "$CHANGELOG" | grep -v Unreleased | sed 's/.*\[\(.*\)\].*/\1/' | sort | uniq -d)
if [ -n "$DUPLICATE" ]; then
    log_warn "Duplicate version found: $DUPLICATE (may be historical debt)"
fi

# 8. Check for broken links (basic check)
LINKS=$(grep -o '\[.*\](.*\.md' "$CHANGELOG" 2>/dev/null | cut -d']' -f2 | tr -d '()' || true)
if [ -n "$LINKS" ]; then
    while IFS= read -r link; do
        if [ -n "$link" ] && [ ! -f "$link" ]; then
            log_error "Broken link in changelog: $link"
        fi
    done <<< "$LINKS"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    log_success "CHANGELOG.md is valid ✨"
    exit 0
else
    echo -e "${RED}Found $ERRORS validation error(s)${NC}"
    exit 1
fi
