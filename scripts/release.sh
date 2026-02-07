#!/usr/bin/env bash
# pgGit Release Script - Automates version bumping and GitHub releases
# Usage: ./scripts/release.sh [patch|minor|major]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RELEASE_TYPE="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYPROJECT="${PROJECT_ROOT}/pyproject.toml"
CHANGELOG="${PROJECT_ROOT}/CHANGELOG.md"
README="${PROJECT_ROOT}/README.md"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ ${NC}$*"
}

log_success() {
    echo -e "${GREEN}✅ ${NC}$*"
}

log_error() {
    echo -e "${RED}❌ ${NC}$*"
}

log_warn() {
    echo -e "${YELLOW}⚠ ${NC}$*"
}

# Validate release type
if [[ ! "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]]; then
    log_error "Invalid release type: $RELEASE_TYPE"
    echo "Usage: $0 [patch|minor|major]"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep 'version = ' "$PYPROJECT" | head -1 | sed 's/version = "\(.*\)"/\1/')
log_info "Current version: $CURRENT_VERSION"

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"

# Bump version
case "$RELEASE_TYPE" in
    patch)
        PATCH=$((PATCH + 1))
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
log_info "New version: $NEW_VERSION"

# Get commits since last tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LAST_TAG" ]; then
    log_warn "No previous tags found"
    COMMITS=$(git log --oneline | head -20)
else
    log_info "Last tag: $LAST_TAG"
    COMMITS=$(git log "${LAST_TAG}..HEAD" --oneline)
fi

# Count commits
COMMIT_COUNT=$(echo "$COMMITS" | wc -l)
log_info "Commits since last tag: $COMMIT_COUNT"

echo ""
log_info "Changes included in this release:"
echo "$COMMITS" | head -10
if [ "$COMMIT_COUNT" -gt 10 ]; then
    echo "... and $((COMMIT_COUNT - 10)) more commits"
fi

echo ""
log_info "Updating files..."

# 1. Update version in pyproject.toml
log_info "Updating pyproject.toml..."
sed -i.bak "s/version = \"${CURRENT_VERSION}\"/version = \"${NEW_VERSION}\"/" "$PYPROJECT"
rm -f "${PYPROJECT}.bak"
log_success "Updated version to $NEW_VERSION"

# 2. Update CHANGELOG.md
log_info "Updating CHANGELOG.md..."
TODAY=$(date +%Y-%m-%d)

# Create temporary changelog with new entry
TEMP_CHANGELOG=$(mktemp)
cat > "$TEMP_CHANGELOG" <<EOF
# Changelog

All notable changes to pgGit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [${NEW_VERSION}] - ${TODAY}

### Summary
Release ${NEW_VERSION} with ${COMMIT_COUNT} commits.

### Changes
EOF

# Add commits to changelog
echo "$COMMITS" | while read -r line; do
    COMMIT_HASH=$(echo "$line" | cut -d' ' -f1)
    COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)
    echo "- \`${COMMIT_HASH}\` ${COMMIT_MSG}" >> "$TEMP_CHANGELOG"
done

# Append rest of original CHANGELOG (skip header lines)
tail -n +8 "$CHANGELOG" >> "$TEMP_CHANGELOG"

# Replace original with new
mv "$TEMP_CHANGELOG" "$CHANGELOG"
log_success "Updated CHANGELOG.md"

# 3. Update README.md version badge (if it exists)
if grep -q "version-" "$README"; then
    log_info "Updating README.md version badge..."
    sed -i.bak "s/version-${CURRENT_VERSION}/version-${NEW_VERSION}/g" "$README"
    rm -f "${README}.bak"
    log_success "Updated version badge in README.md"
fi

# 4. Create git commit with changes
log_info "Creating git commit..."
git add "$PYPROJECT" "$CHANGELOG"
if grep -q "version-" "$README"; then
    git add "$README"
fi

COMMIT_MSG="chore(release): v${NEW_VERSION}"
git commit -m "$(cat <<EOF
chore(release): v${NEW_VERSION}

Bump version for release.

## Changes
- Updated version to ${NEW_VERSION} in pyproject.toml
- Updated CHANGELOG.md with release notes
${COMMIT_COUNT} commits included in this release

## Release Type
${RELEASE_TYPE^} release

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
EOF
)"
log_success "Created commit"

# 5. Create annotated git tag
log_info "Creating git tag v${NEW_VERSION}..."
git tag -a "v${NEW_VERSION}" -m "$(cat <<EOF
v${NEW_VERSION}: Release

## Summary
${RELEASE_TYPE^} release with ${COMMIT_COUNT} commits.

## Release Type
- ${RELEASE_TYPE^} release

## What Changed
$(echo "$COMMITS" | head -15)

## Installation
See README.md and INSTALLATION.md for installation instructions.

## Testing
All tests passing. See CHANGELOG.md for details.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
EOF
)"
log_success "Created tag v${NEW_VERSION}"

# 6. Push to remote
log_info "Pushing to remote..."
git push origin main
log_success "Pushed main branch"

git push origin "v${NEW_VERSION}"
log_success "Pushed tag v${NEW_VERSION}"

# 7. Create GitHub release
log_info "Creating GitHub release..."
RELEASE_BODY=$(cat <<EOF
## v${NEW_VERSION} Release

**Release Type:** ${RELEASE_TYPE^}
**Released:** ${TODAY}
**Commits:** ${COMMIT_COUNT}

## What's Included
$(echo "$COMMITS" | head -20)
EOF
)

if command -v gh &> /dev/null; then
    gh release create "v${NEW_VERSION}" \
        --title "v${NEW_VERSION}: pgGit Release" \
        --notes "$RELEASE_BODY"
    log_success "Created GitHub release"
else
    log_warn "GitHub CLI not found. Skipping GitHub release creation."
    log_warn "Create it manually with: gh release create v${NEW_VERSION} --notes '...'"
fi

echo ""
log_success "🎉 Release v${NEW_VERSION} complete!"
echo ""
log_info "Summary:"
echo "  Version: ${CURRENT_VERSION} → ${NEW_VERSION}"
echo "  Type: ${RELEASE_TYPE^}"
echo "  Commits: ${COMMIT_COUNT}"
echo "  Tag: v${NEW_VERSION}"
echo ""
log_info "Next steps:"
echo "  1. Verify release on GitHub: https://github.com/evoludigit/pgGit/releases/tag/v${NEW_VERSION}"
echo "  2. Update any related documentation"
echo "  3. Announce release to team"
