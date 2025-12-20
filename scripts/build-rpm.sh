#!/bin/bash
# pgGit RPM Package Builder
# Builds .rpm packages for RHEL/Rocky Linux
# Run with: bash scripts/build-rpm.sh [version]

set -e

VERSION=${1:-0.1.0}
echo "Building RPM package for pgGit $VERSION"

# Check if rpmbuild is available
if ! command -v rpmbuild &> /dev/null; then
    echo "Error: rpmbuild not found. Install with: dnf install rpm-build"
    exit 1
fi

# Setup RPM build environment
RPMBUILD_DIR="$HOME/rpmbuild"
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create source tarball
git archive --format=tar.gz --prefix=pggit-$VERSION/ HEAD > "$RPMBUILD_DIR/SOURCES/pggit-$VERSION.tar.gz"

# Copy spec file
cp packaging/rpm/pggit.spec "$RPMBUILD_DIR/SPECS/"

# Build RPM
rpmbuild -ba "$RPMBUILD_DIR/SPECS/pggit.spec"

# Move package to dist directory
mkdir -p dist
cp "$RPMBUILD_DIR/RPMS/x86_64/pggit-$VERSION-"*.rpm dist/

echo "✅ RPM package built successfully!"
echo "Package available in dist/:"
ls -la dist/pggit-*.rpm