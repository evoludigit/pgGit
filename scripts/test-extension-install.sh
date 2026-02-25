#!/usr/bin/env bash
# Test CREATE EXTENSION pggit CASCADE in a container
# Mirrors .github/workflows/extension-install-test.yml
set -euo pipefail

PG_VERSION="${1:-17}"
IMAGE="docker.io/postgres:${PG_VERSION}-alpine"
CONTAINER_NAME="pggit-extension-test-pg${PG_VERSION}"

echo "=== Extension Install Test (PostgreSQL ${PG_VERSION}) ==="

# Cleanup on exit
cleanup() {
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Remove any leftover container
cleanup

# Start PostgreSQL container
echo "Starting PostgreSQL ${PG_VERSION}..."
podman run -d \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=pggit_extension_test \
    "$IMAGE"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
for i in $(seq 1 30); do
    if podman exec "$CONTAINER_NAME" pg_isready -U postgres 2>/dev/null; then
        break
    fi
    sleep 1
done

# Copy project files into the container
echo "Copying project files..."
podman cp "$(pwd)/pggit.control" "$CONTAINER_NAME:/tmp/pggit.control"
podman cp "$(pwd)/pggit--0.1.3.sql" "$CONTAINER_NAME:/tmp/pggit--0.1.3.sql"
podman cp "$(pwd)/Makefile" "$CONTAINER_NAME:/tmp/Makefile"

# Install extension files into PostgreSQL's sharedir
echo "Installing extension files..."
podman exec "$CONTAINER_NAME" bash -c '
    SHAREDIR=$(pg_config --sharedir)
    cp /tmp/pggit.control "$SHAREDIR/extension/"
    cp /tmp/pggit--0.1.3.sql "$SHAREDIR/extension/"
    echo "Installed to $SHAREDIR/extension/"
    ls -la "$SHAREDIR/extension/pggit"*
'

# Test 1: Clean install
echo ""
echo "=== Test 1: CREATE EXTENSION pggit CASCADE ==="
podman exec "$CONTAINER_NAME" psql -U postgres -d pggit_extension_test \
    -v ON_ERROR_STOP=1 \
    -c "CREATE EXTENSION pggit CASCADE;"
echo "PASS: Clean install succeeded"

# Test 2: Schema validation
echo ""
echo "=== Test 2: Schema validation ==="
podman exec "$CONTAINER_NAME" psql -U postgres -d pggit_extension_test \
    -v ON_ERROR_STOP=1 <<'EOF'
DO $$
DECLARE
    missing text[];
    tbl text;
BEGIN
    FOR tbl IN SELECT unnest(ARRAY['commits', 'branches', 'merge_conflicts', 'merge_history'])
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'pggit' AND table_name = tbl
        ) THEN
            missing := array_append(missing, tbl);
        END IF;
    END LOOP;

    IF array_length(missing, 1) > 0 THEN
        RAISE EXCEPTION 'Missing tables: %', array_to_string(missing, ', ');
    END IF;

    RAISE NOTICE 'All expected tables exist';
END $$;

SELECT pggit.version() AS pggit_version;
EOF
echo "PASS: Schema validation succeeded"

# Test 3: Drop and recreate
echo ""
echo "=== Test 3: DROP + CREATE lifecycle ==="
podman exec "$CONTAINER_NAME" psql -U postgres -d pggit_extension_test \
    -v ON_ERROR_STOP=1 <<'EOF'
DROP EXTENSION pggit CASCADE;
CREATE EXTENSION pggit CASCADE;
SELECT pggit.version() AS pggit_version;
EOF
echo "PASS: Lifecycle test succeeded"

echo ""
echo "=== All tests passed (PostgreSQL ${PG_VERSION}) ==="
