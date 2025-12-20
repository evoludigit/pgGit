# Release Checklist

## Pre-Release (1 week before)

- [ ] All tests passing on main branch
- [ ] No open P0/P1 bugs
- [ ] Security audit complete (if major version)
- [ ] Performance benchmarks run
- [ ] Documentation up to date
- [ ] CHANGELOG.md updated
- [ ] Migration scripts created (if needed)
- [ ] Upgrade tested from previous version

## Release Day

- [ ] Create release branch: `git checkout -b release/vX.Y.Z`
- [ ] Update version in:
  - [ ] pggit.control
  - [ ] pggit--X.Y.Z.sql
  - [ ] README.md
  - [ ] package files
- [ ] Tag release: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Wait for CI to build packages
- [ ] Test installation from packages
- [ ] Publish release notes
- [ ] Update website/docs
- [ ] Announce on Twitter, Reddit, HN

## Post-Release

- [ ] Monitor issue tracker for bug reports
- [ ] Update Docker images
- [ ] Update package repositories
- [ ] Merge release branch back to main
- [ ] Create milestone for next version