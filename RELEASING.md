# pgGit Release Procedures

**Complete guide for creating and publishing pgGit releases**

---

## Overview

This document provides step-by-step procedures for releasing pgGit versions. All releases follow semantic versioning (v0.x.y for v0 series, v1.0.0+ for future major versions).

**Key Principles**:
- ✅ Releases are immutable (tags are signed and permanent)
- ✅ All tests must pass before release
- ✅ Changelog must be updated
- ✅ Documentation must be synchronized with code
- ✅ Release notes must be generated

---

## Pre-Release Checklist

### 1. Code Readiness

Before starting the release process:

```bash
# Ensure main branch is clean
git status
# Expected: "On branch main. Your branch is up to date with 'origin/main'."
# Expected: "nothing to commit, working tree clean"

# Run full test suite
pytest tests/ -v

# Run linting and type checking
ruff check . --select=E,W,F
mypy src/ --strict

# Verify documentation builds
cd docs/
make html
cd ..

# Check for any TODO/FIXME/HACK comments
grep -r "TODO\|FIXME\|HACK" src/ tests/ --include="*.py" || echo "✅ No TODOs found"
```

### 2. Version Number Decision

Determine the new version using semantic versioning:

- **PATCH** (v0.1.0 → v0.1.1): Bug fixes, security patches, no new features
- **MINOR** (v0.1.1 → v0.2.0): New features, backward-compatible
- **MAJOR** (v0.x.x → v1.0.0): Breaking changes, major architectural changes

**Current Version**: Run this to check:
```bash
grep "version" pyproject.toml | head -1
grep "__version__" src/pggit/__init__.py
```

### 3. Update Version Numbers

Update version in three locations:

```bash
# 1. Update pyproject.toml
# Change: version = "0.1.0"
# To:     version = "0.2.0"
sed -i 's/version = "0\.1\.0"/version = "0.2.0"/' pyproject.toml

# 2. Update src/pggit/__init__.py
# Change: __version__ = "0.1.0"
# To:     __version__ = "0.2.0"
sed -i 's/__version__ = "0\.1\.0"/__version__ = "0.2.0"/' src/pggit/__init__.py

# 3. Update setup.py if it exists
# Change: version="0.1.0"
# To:     version="0.2.0"
sed -i 's/version="0\.1\.0"/version="0.2.0"/' setup.py

# Verify all updates
grep "0.2.0" pyproject.toml setup.py src/pggit/__init__.py
```

---

## Release Process

### Step 1: Update CHANGELOG.md

Add entry at the top of CHANGELOG.md:

```markdown
## [0.2.0] - 2025-12-21

### Added
- New feature 1
- New feature 2
- New API endpoints

### Fixed
- Bug fix 1
- Bug fix 2

### Changed
- Behavior change 1
- Deprecated: feature_name (use new_feature instead)

### Security
- Security patch 1 (describe what was fixed)

### Documentation
- Improved documentation section
- Added new tutorial

---

## [0.1.1] - 2025-12-15
...
```

### Step 2: Create Release Branch (for major/minor releases)

For MINOR and MAJOR releases, use a release branch:

```bash
# Create release branch from main
git checkout main
git pull origin main
git checkout -b release/v0.2.0

# Make any final version updates
git add pyproject.toml src/pggit/__init__.py CHANGELOG.md

# Commit
git commit -m "chore: Prepare v0.2.0 release"

# Push release branch
git push origin release/v0.2.0
```

For PATCH releases, you can commit directly to main (optional).

### Step 3: Create Release Tag

Tag the release commit:

```bash
# Create annotated tag with release notes
git tag -a v0.2.0 -m "Release version 0.2.0

## Release Highlights
- Feature 1
- Feature 2
- Bug fixes

See CHANGELOG.md for full details."

# For security releases, sign the tag with GPG
git tag -s -a v0.2.0 -m "Release version 0.2.0"
```

### Step 4: Merge to Main

For release branches, merge back to main:

```bash
# Switch to main
git checkout main

# Merge release branch
git merge --no-ff release/v0.2.0 -m "Merge release/v0.2.0 into main"

# Delete release branch
git branch -d release/v0.2.0
```

### Step 5: Push Release

```bash
# Push main branch with tags
git push origin main --follow-tags

# Verify tag was pushed
git tag -l v0.2.0
git show v0.2.0
```

### Step 6: Build Release Artifacts

```bash
# Build Python distribution
python -m build
# Creates: dist/pggit-0.2.0-py3-none-any.whl
# Creates: dist/pggit-0.2.0.tar.gz

# Build Docker image
docker build -t pggit:0.2.0 .
docker tag pggit:0.2.0 pggit:latest

# Verify artifacts exist
ls -lh dist/
docker image ls | grep pggit
```

### Step 7: Publish Release Artifacts

```bash
# Option A: PyPI (Python Package Index)
python -m twine upload dist/pggit-0.2.0*

# Option B: GitHub Releases (create manually via GitHub UI)
# 1. Go to GitHub repository
# 2. Click "Releases" → "Draft a new release"
# 3. Select tag "v0.2.0"
# 4. Title: "pgGit v0.2.0"
# 5. Description: Copy from CHANGELOG.md
# 6. Upload wheel and tarball
# 7. Click "Publish release"

# Option C: Docker Hub
docker push pggit:0.2.0
docker push pggit:latest
```

---

## Post-Release Tasks

### 1. Update Documentation

```bash
# Update docs/INDEX.md with new version
sed -i 's/pgGit v0\.1\.1/pgGit v0.2.0/' docs/INDEX.md
sed -i 's/December 21, 2025/[current date]/' docs/INDEX.md

# Update README.md with latest version
sed -i 's/v0\.1\.1/v0.2.0/' README.md
```

### 2. Create GitHub Release Page

Create a summary for users:

```markdown
# pgGit v0.2.0

**Release Date**: December 21, 2025

## What's New?

- **Feature 1**: Detailed description
- **Feature 2**: Detailed description
- **Bug Fixes**: 5 bugs fixed

## Installation

```bash
pip install pggit==0.2.0
```

## Docker

```bash
docker pull pggit:0.2.0
```

## Migration Guide

If upgrading from v0.1.x:
1. Step 1
2. Step 2
3. Step 3

See [CHANGELOG.md](CHANGELOG.md) for full details.
```

### 3. Update Version in Development

After release, bump to next development version:

```bash
# Update to v0.2.1-dev for next patch
sed -i 's/version = "0\.2\.0"/version = "0.2.1-dev"/' pyproject.toml
sed -i 's/__version__ = "0\.2\.0"/__version__ = "0.2.1-dev"/' src/pggit/__init__.py

# Commit
git add pyproject.toml src/pggit/__init__.py
git commit -m "chore: Bump version to v0.2.1-dev"
git push origin main
```

### 4. Notify Community

- [ ] Send announcement to users
- [ ] Post to community channels (Slack, Discord, etc.)
- [ ] Update website with new version
- [ ] Link release notes in community posts

---

## Rollback Procedure

If a release has critical issues:

### For Untagged Commits
```bash
# Revert the release commit
git revert COMMIT_HASH
git push origin main
```

### For Already-Tagged Releases
```bash
# Create a new patch release with the fix
# Example: v0.2.1 fixes v0.2.0

# Create a new tag pointing to previous version
git tag v0.2.0-rollback COMMIT_BEFORE_BAD_RELEASE

# Revert the bad release
git revert v0.2.0..main
git push origin main --follow-tags

# Document in CHANGELOG.md
```

### For Published Artifacts

```bash
# Remove from PyPI (if critical security issue)
python -m twine remove pggit==0.2.0

# Docker: Unpublish image (not recommended, mark as deprecated instead)
# Mark as deprecated in README

# GitHub: Delete release and tag (last resort)
git tag -d v0.2.0
git push origin --delete v0.2.0
```

---

## Release Types Reference

### Hotfix Release (v0.1.1 → v0.1.2)
- **Duration**: 30 minutes
- **Process**: Direct to main, quick tag
- **Use**: Critical bug fixes, security patches
- **Testing**: Minimal (issue-specific tests only)

### Patch Release (v0.1.0 → v0.1.1)
- **Duration**: 2-4 hours
- **Process**: Optional release branch, full testing
- **Use**: Bug fixes, minor improvements
- **Testing**: Run full test suite

### Minor Release (v0.1.x → v0.2.0)
- **Duration**: 4-8 hours
- **Process**: Release branch, staging environment testing
- **Use**: New features, backward-compatible changes
- **Testing**: Full test suite + integration tests + UAT

### Major Release (v0.x.x → v1.0.0)
- **Duration**: 1-2 days
- **Process**: Release planning, extended testing, release notes
- **Use**: Breaking changes, major architectural updates
- **Testing**: Full suite + extended integration + user acceptance testing

---

## Automated Release Checklist

For CI/CD automated releases, ensure:

- [ ] All commits are signed
- [ ] All tests pass
- [ ] All linting checks pass
- [ ] Documentation builds without errors
- [ ] No breaking changes (minor/patch releases)
- [ ] Changelog is updated
- [ ] Version numbers are consistent
- [ ] Release notes are generated
- [ ] Artifacts are built successfully
- [ ] Artifacts are uploaded to all repositories (PyPI, Docker Hub, GitHub)

---

## Troubleshooting

### Tag Already Exists
```bash
# Delete local tag
git tag -d v0.2.0

# Delete remote tag
git push origin --delete v0.2.0

# Re-create tag
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0
```

### Wrong Commit Tagged
```bash
# Create new tag on correct commit
git tag v0.2.0-correct CORRECT_COMMIT_HASH

# Delete old tag
git tag -d v0.2.0
git push origin --delete v0.2.0

# Rename new tag
git tag -d v0.2.0-correct
git tag -a v0.2.0 CORRECT_COMMIT_HASH
git push origin v0.2.0
```

### Version Mismatch
```bash
# Check all version references
grep -r "0\.2\.0" . --include="*.py" --include="*.toml" --include="*.md"

# Update any missed files
sed -i 's/0\.1\.0/0.2.0/' missed_file.py
```

---

## Contact & Support

- **GitHub Issues**: https://github.com/evoludigit/pgGit/issues
- **Security Issues**: See SECURITY.md for responsible disclosure
- **Release Questions**: Open a GitHub discussion

---

**Last Updated**: December 21, 2025
**Version**: pgGit v0.1.1
**Maintainer**: pgGit Team
