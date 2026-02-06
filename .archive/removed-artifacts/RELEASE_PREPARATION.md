# Release Preparation Guide

This document provides a checklist and procedure for preparing pgGit releases.

## Current Release Status

| Release | Status | Date | Tag |
|---------|--------|------|-----|
| v0.4.1 | ✅ Released | 2026-02-04 | `v0.4.1` |
| v0.4.0 | ✅ Released | 2026-02-04 | `v0.4.0` |
| v0.3.0 | ✅ Released | Earlier | `v0.3.0` |

## Next Release (v0.5.0)

### Versioning Strategy

pgGit follows [Semantic Versioning](https://semver.org/):
- **v0.4.x** - Current stability release line (patch updates)
- **v0.5.0** - Next minor release (new features)
- **v1.0.0** - First stable major release (when feature-complete)

### Release Checklist

#### Phase 1: Development (In Progress)
- [ ] Implement planned features
- [ ] Write unit/integration tests
- [ ] Update function implementations
- [ ] Test all changes locally

#### Phase 2: Code Review & Testing (Pre-Release)
- [ ] Run full test suite: `pytest tests/e2e tests/chaos tests/unit -v`
- [ ] Code review of all changes
- [ ] Performance validation
- [ ] Security audit of new features
- [ ] Documentation updates completed

#### Phase 3: Release Preparation (Final Steps)
- [ ] Update CHANGELOG.md with all changes
- [ ] Update version number in:
  - `pyproject.toml` (if applicable)
  - `sql/VERSION` or metadata files
  - Documentation headers
- [ ] Create comprehensive release notes
- [ ] Test installation and basic operations
- [ ] Verify all tests still pass
- [ ] Run linting: `ruff check --fix && ruff format`

#### Phase 4: Release (Git & GitHub)
- [ ] Create commit: `git commit -m "chore: Prepare vX.Y.Z release"`
- [ ] Create annotated tag: `git tag -a vX.Y.Z -m "Release notes"`
- [ ] Push to main: `git push origin main --tags`
- [ ] Create GitHub release with changelog
- [ ] Verify release appears on GitHub releases page

#### Phase 5: Post-Release
- [ ] Document any known issues
- [ ] Monitor for bug reports
- [ ] Plan next release cycle

## Test Suite Requirements Before Release

```bash
# All tests must pass
pytest tests/e2e -v                    # E2E tests
pytest tests/chaos -v --timeout=30     # Chaos tests
pytest tests/unit -v                   # Unit tests

# Code quality
ruff check .
ruff format --check .

# Type checking (if applicable)
py check .
```

## Creating a Release

### Step 1: Update Changelog

1. Open `CHANGELOG.md`
2. Add new section at top:
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Summary
One-line description of the release

### Added
- Feature 1
- Feature 2

### Fixed
- Bug fix 1
- Bug fix 2

### Changed
- Change 1

### Breaking Changes
None (or list if any)
```

### Step 2: Prepare Release Commit

```bash
# Stage changelog
git add CHANGELOG.md

# Commit
git commit -m "chore: Prepare vX.Y.Z release

## Changes
- Summary of key changes

## Test Results
✅ All tests passing"
```

### Step 3: Create Tag

```bash
git tag -a vX.Y.Z -m "vX.Y.Z: Release Title

One-line summary of release

## Key Features
- Feature 1
- Feature 2

## Bug Fixes
- Fix 1
- Fix 2

## Test Results
✅ All XX tests passing
✅ Code quality: clean
✅ No breaking changes

Released: YYYY-MM-DD"
```

### Step 4: Push Release

```bash
# Push main branch and tags
git push origin main --tags
```

### Step 5: Create GitHub Release

Visit: `https://github.com/evoludigit/pgGit/releases/new`

1. Select tag: `vX.Y.Z`
2. Title: "Release vX.Y.Z: [Short Description]"
3. Description: Copy from CHANGELOG.md section
4. Publish release

## Release Notes Template

```markdown
# vX.Y.Z: Release Title

**Released**: YYYY-MM-DD

## Summary
One-paragraph description of the release focus.

## ✨ New Features
- Feature 1: Description
- Feature 2: Description

## 🐛 Bug Fixes
- Bug 1: Description
- Bug 2: Description

## 🔧 Improvements
- Improvement 1
- Improvement 2

## 📊 Test Results
✅ All XX tests passing
  - XX E2E tests
  - XX Chaos tests
  - XX Unit tests
✅ Code quality: clean
✅ No regressions

## 📝 Breaking Changes
None

## 📦 Installation
```bash
# Update pgGit extension
psql -d your_db -f sql/install.sql
```

## 🙏 Credits
Built with pgGit team collaboration.
```

## Version Numbering Guide

### Patch Releases (v0.4.x → v0.4.2)
- Bug fixes only
- No new features
- No breaking changes
- Example: SQL bug fixes, test improvements

### Minor Releases (v0.4.0 → v0.5.0)
- New features
- Backward compatible
- May add new functions/capabilities
- Example: New backup strategies, new API functions

### Major Releases (v0.x → v1.0)
- May have breaking changes
- Significant feature additions
- Recommended when: feature-complete, stable, ready for production

## Helpful Commands

```bash
# View all tags
git tag -l --sort=-version:refname

# View commits since last release
git log v0.4.1..HEAD --oneline

# View specific tag details
git show v0.4.1

# Create signed tag (optional for production)
git tag -s -a vX.Y.Z -m "Release message"

# Push tags to remote
git push origin --tags

# Delete local tag (if needed)
git tag -d vX.Y.Z

# Delete remote tag (if needed)
git push origin :refs/tags/vX.Y.Z
```

## Release Schedule

Recommend releases:
- **Patch releases** (v0.4.x): As-needed for critical bugs
- **Minor releases** (v0.5.0): Every 4-6 weeks with new features
- **Major release** (v1.0.0): When feature-complete and production-ready

## Quick Start: Next Release

1. **Check status**: `git log v0.4.1..HEAD --oneline`
2. **Update changelog**: Add changes to `CHANGELOG.md`
3. **Run tests**: `pytest tests/e2e tests/chaos tests/unit -v`
4. **Commit**: `git commit -m "chore: Prepare vX.Y.Z release"`
5. **Tag**: `git tag -a vX.Y.Z -m "Release notes"`
6. **Push**: `git push origin main --tags`

## Support

For release questions or issues, refer to:
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [README.md](README.md) - Project documentation
- GitHub Issues - Bug reports and feature requests
