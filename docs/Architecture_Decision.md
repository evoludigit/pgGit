# Architecture Decision: Single Extension with Modular Design

## Decision: Enhanced pg_gitversion with Optional Sync Module

After implementing DDL hashing, the synergies between versioning and schema synchronization are too significant to ignore. We recommend a **single extension with modular components**.

## Architecture Overview

```
pg_gitversion
├── Core Module (always loaded)
│   ├── Event triggers & tracking
│   ├── DDL hashing infrastructure  
│   ├── Version management
│   └── Local dependency tracking
├── Sync Module (optional)
│   ├── Remote database connections
│   ├── Cross-database comparison
│   ├── Conflict resolution
│   └── Bidirectional sync
└── Advanced Module (optional)
    ├── Multi-tenant support
    ├── Sharding utilities
    └── Blue-green deployment tools
```

## Implementation Strategy

### 1. Modular Loading

```sql
-- Core extension (required)
CREATE EXTENSION pg_gitversion;

-- Optional modules
SELECT gitversion.enable_module('sync');
SELECT gitversion.enable_module('advanced');

-- Check enabled modules
SELECT * FROM gitversion.enabled_modules;
```

### 2. Namespace Organization

```sql
-- Core functions (always available)
gitversion.get_version()
gitversion.get_history()
gitversion.compute_ddl_hash()

-- Sync functions (when module enabled)
gitversion.sync_connect_remote()
gitversion.sync_compare_schemas()
gitversion.sync_generate_migration()

-- Advanced functions (when module enabled)
gitversion.advanced_multi_tenant_sync()
gitversion.advanced_shard_consistency_check()
```

### 3. Progressive Feature Disclosure

```sql
-- Level 1: Basic tracking (core)
CREATE TABLE users (id SERIAL PRIMARY KEY);
SELECT * FROM gitversion.get_version('public.users');

-- Level 2: Hash-based efficiency (core)
SELECT * FROM gitversion.detect_changes_by_hash();

-- Level 3: Cross-database sync (sync module)
SELECT gitversion.sync_with_remote('prod_db');

-- Level 4: Advanced scenarios (advanced module)
SELECT gitversion.advanced_tenant_sync('tenant_123', 'template_schema');
```

## Benefits of This Approach

### 1. **Unified Data Model**
- Single source of truth for object tracking
- Shared hash infrastructure
- Consistent dependency modeling
- No data duplication between extensions

### 2. **Seamless Integration**
```sql
-- Version tracking feeds directly into sync
SELECT gitversion.sync_from_version(
    remote_db => 'staging',
    from_migration => 'v1.2.0',  -- From versioning system
    to_migration => 'v1.3.0'
);

-- Sync respects local version history
SELECT gitversion.sync_with_conflict_resolution(
    remote_db => 'prod',
    strategy => 'prefer_higher_version'  -- Uses version numbers
);
```

### 3. **Performance Optimization**
```sql
-- Shared hash computation
-- No need to recompute hashes for sync operations
SELECT 
    local.ddl_hash,
    remote.ddl_hash,
    local.ddl_hash = remote.ddl_hash as objects_match
FROM gitversion.objects local
JOIN gitversion.remote_objects('prod_db') remote 
    ON local.full_name = remote.full_name;
```

### 4. **Simplified Installation**
```bash
# Single extension handles everything
make install
psql -c "CREATE EXTENSION pg_gitversion"
psql -c "SELECT gitversion.enable_module('sync')"
```

## Module Design

### Core Module (Always Loaded)

**Files:**
- `pg_gitversion--1.1.0.sql` (enhanced with hashing)
- `sql/001_schema.sql`
- `sql/002_event_triggers.sql` 
- `sql/009_ddl_hashing.sql`

**Capabilities:**
- Event trigger-based tracking
- DDL hashing infrastructure
- Version management
- Local dependency tracking
- Migration generation

### Sync Module (Optional)

**Files:**
- `sql/010_sync_module.sql`

**Capabilities:**
```sql
-- Remote database management
CREATE TABLE gitversion.remote_databases (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    connection_string TEXT NOT NULL,
    enabled BOOLEAN DEFAULT true
);

-- Connection functions
CREATE FUNCTION gitversion.sync_add_remote(name TEXT, connection TEXT);
CREATE FUNCTION gitversion.sync_test_connection(remote_name TEXT);

-- Comparison functions  
CREATE FUNCTION gitversion.sync_compare_schemas(
    remote_name TEXT,
    local_schema TEXT DEFAULT 'public'
) RETURNS TABLE(...);

-- Sync functions
CREATE FUNCTION gitversion.sync_generate_migration(
    remote_name TEXT,
    direction TEXT -- 'to_remote', 'from_remote', 'bidirectional'
) RETURNS TEXT;

CREATE FUNCTION gitversion.sync_apply_migration(
    remote_name TEXT,
    migration_script TEXT,
    dry_run BOOLEAN DEFAULT true
) RETURNS TABLE(...);
```

### Advanced Module (Optional)

**Files:**
- `sql/011_advanced_module.sql`

**Capabilities:**
- Multi-tenant schema synchronization
- Sharding consistency checks
- Blue-green deployment support
- Schema template management

## Implementation Example

### Enhanced Control File

```ini
# pg_gitversion.control
comment = 'Git-like version control for PostgreSQL schemas'
default_version = '1.1.0'
module_pathname = '$libdir/pg_gitversion'
relocatable = false
requires = ''
superuser = false
schema = gitversion
```

### Module Management

```sql
-- Module tracking table
CREATE TABLE gitversion.modules (
    name TEXT PRIMARY KEY,
    enabled BOOLEAN DEFAULT false,
    enabled_at TIMESTAMP,
    enabled_by TEXT,
    version TEXT,
    dependencies TEXT[]
);

-- Module management functions
CREATE OR REPLACE FUNCTION gitversion.enable_module(module_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    module_file TEXT;
BEGIN
    -- Validate module exists
    IF module_name NOT IN ('sync', 'advanced') THEN
        RAISE EXCEPTION 'Unknown module: %', module_name;
    END IF;
    
    -- Check if already enabled
    IF EXISTS (SELECT 1 FROM gitversion.modules WHERE name = module_name AND enabled = true) THEN
        RETURN false; -- Already enabled
    END IF;
    
    -- Load module SQL
    module_file := format('sql/%s_%s_module.sql', 
        CASE module_name
            WHEN 'sync' THEN '010'
            WHEN 'advanced' THEN '011'
        END,
        module_name
    );
    
    -- Execute module installation
    EXECUTE format('SELECT gitversion.load_module_file(%L)', module_file);
    
    -- Record as enabled
    INSERT INTO gitversion.modules (name, enabled, enabled_at, enabled_by, version)
    VALUES (module_name, true, CURRENT_TIMESTAMP, CURRENT_USER, '1.1.0')
    ON CONFLICT (name) DO UPDATE SET
        enabled = true,
        enabled_at = CURRENT_TIMESTAMP,
        enabled_by = CURRENT_USER;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;
```

### Usage Examples

```sql
-- Start with core tracking
CREATE EXTENSION pg_gitversion;
CREATE TABLE users (id SERIAL PRIMARY KEY, email TEXT);
SELECT * FROM gitversion.get_version('public.users'); -- Works

-- Enable sync when needed
SELECT gitversion.enable_module('sync');
SELECT gitversion.sync_add_remote('production', 'postgresql://...');
SELECT * FROM gitversion.sync_compare_schemas('production'); -- Now works

-- Enable advanced features for complex scenarios
SELECT gitversion.enable_module('advanced');
SELECT gitversion.advanced_setup_tenant_template('saas_template');
```

## Alternative: Extension Family

If the single extension becomes too complex, we could create an extension family:

```sql
-- Base extension
CREATE EXTENSION pg_gitversion;

-- Optional extensions that depend on base
CREATE EXTENSION pg_gitversion_sync;    -- Requires pg_gitversion
CREATE EXTENSION pg_gitversion_advanced; -- Requires pg_gitversion
```

But given the deep integration enabled by DDL hashing, the modular single-extension approach seems optimal.

## Decision Rationale

1. **DDL Hashing Changes Everything**: The shared hashing infrastructure creates too many synergies to ignore
2. **User Experience**: Single extension with optional features is simpler than managing multiple extensions
3. **Maintenance**: Easier to maintain consistent data models and APIs
4. **Performance**: Shared infrastructure avoids duplication and improves efficiency
5. **Future Growth**: Modular design allows adding new capabilities without architectural changes

## Conclusion

**Recommended**: Single `pg_gitversion` extension with optional sync and advanced modules, enabled on-demand through `gitversion.enable_module()`.

This provides the benefits of both approaches: unified infrastructure with optional complexity.