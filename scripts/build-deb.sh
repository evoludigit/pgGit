#!/bin/bash
# pgGit Debian Package Builder
# Builds .deb packages for multiple PostgreSQL versions
# Run with: bash scripts/build-deb.sh [version]

set -e

VERSION=${1:-0.1.0}
echo "Building Debian packages for pgGit $VERSION"

# Check if we're in the right directory
if [ ! -d "packaging/debian" ]; then
    echo "Error: packaging/debian directory not found"
    echo "Run this script from the pgGit root directory"
    exit 1
fi

# Create build directory
BUILD_DIR="build-deb"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy source for building
cp -r . "$BUILD_DIR/pggit-$VERSION"

cd "$BUILD_DIR/pggit-$VERSION"

# For each PostgreSQL version
for PG_VERSION in 15 16 17; do
    echo "Building for PostgreSQL $PG_VERSION..."

    # Update control file with correct version
    sed -i "s/postgresql-PGVERSION/postgresql-$PG_VERSION/g" packaging/debian/control

    # Build package
    dpkg-buildpackage -us -uc -b

    echo "✅ Built package for PostgreSQL $PG_VERSION"
done

# Move packages to dist directory
cd ..
mkdir -p ../../dist
mv *.deb ../../dist/

echo "✅ All Debian packages built successfully!"
echo "Packages available in dist/:"
ls -la ../../dist/ | grep "\.deb$"