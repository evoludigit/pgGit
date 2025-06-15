# Git-Style Schema Branching Architecture for PostgreSQL

## Executive Summary

This document presents a technically sound architecture for implementing actual Git semantics in PostgreSQL, enabling true schema branching, merging, and version control at the database level. Unlike the current pg_gitversion which is primarily an audit log, this design enables multiple concurrent schema versions to coexist and be manipulated independently.

## Core Architecture Components

### 1. Schema State Management

#### 1.1 Branch Isolation Strategy

**Approach: Schema-Based Branch Isolation**

Each branch lives in its own PostgreSQL schema, providing complete isolation while sharing the same database instance:

```sql
-- Branch naming convention: branch_<branch_name>
CREATE SCHEMA branch_main;
CREATE SCHEMA branch_feature_user_auth;
CREATE SCHEMA branch_hotfix_v2_1;

-- Branch metadata tracking
CREATE TABLE gitversion.branches (
    id SERIAL PRIMARY KEY,
    branch_name TEXT UNIQUE NOT NULL,
    schema_name TEXT UNIQUE NOT NULL,
    parent_branch_id INTEGER REFERENCES gitversion.branches(id),
    created_from_commit_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}'
);

-- Commit tracking (similar to Git commits)
CREATE TABLE gitversion.commits (
    id SERIAL PRIMARY KEY,
    commit_hash TEXT UNIQUE NOT NULL, -- SHA256 of commit content
    branch_id INTEGER REFERENCES gitversion.branches(id),
    parent_commit_id INTEGER REFERENCES gitversion.commits(id),
    message TEXT NOT NULL,
    author TEXT NOT NULL,
    committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tree_hash TEXT NOT NULL, -- Hash of entire schema state
    metadata JSONB DEFAULT '{}'
);
```

#### 1.2 Schema State Snapshots

**Object Storage Model**

```sql
-- Complete DDL storage for each object at each commit
CREATE TABLE gitversion.object_snapshots (
    id BIGSERIAL PRIMARY KEY,
    commit_id INTEGER REFERENCES gitversion.commits(id),
    object_type gitversion.object_type NOT NULL,
    object_name TEXT NOT NULL,
    object_hash TEXT NOT NULL, -- SHA256 of normalized DDL
    ddl_content TEXT NOT NULL, -- Full DDL to recreate object
    dependencies JSONB, -- Array of dependent object hashes
    metadata JSONB DEFAULT '{}',
    UNIQUE(commit_id, object_type, object_name)
);

-- Index for efficient lookups
CREATE INDEX idx_snapshots_commit_hash ON gitversion.object_snapshots(commit_id, object_hash);
CREATE INDEX idx_snapshots_object ON gitversion.object_snapshots(object_type, object_name);
```

### 2. Efficient Diff Algorithms

#### 2.1 DDL Normalization Engine

```sql
-- Enhanced DDL normalization for consistent hashing
CREATE OR REPLACE FUNCTION gitversion.normalize_ddl_advanced(
    p_ddl TEXT,
    p_object_type gitversion.object_type
) RETURNS TEXT AS $$
DECLARE
    v_normalized TEXT;
    v_ast JSONB;
BEGIN
    -- Parse DDL into abstract syntax tree (AST)
    v_ast := gitversion.parse_ddl_to_ast(p_ddl, p_object_type);
    
    -- Normalize AST (sort properties, standardize types, etc.)
    v_ast := gitversion.normalize_ast(v_ast);
    
    -- Convert back to canonical DDL
    v_normalized := gitversion.ast_to_ddl(v_ast);
    
    RETURN v_normalized;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Merkle tree for efficient schema comparison
CREATE TABLE gitversion.merkle_nodes (
    id BIGSERIAL PRIMARY KEY,
    commit_id INTEGER REFERENCES gitversion.commits(id),
    node_path TEXT NOT NULL, -- e.g., 'tables/users/columns/email'
    node_hash TEXT NOT NULL,
    node_type TEXT NOT NULL, -- 'leaf' or 'branch'
    children_hashes TEXT[], -- For branch nodes
    content_hash TEXT, -- For leaf nodes
    UNIQUE(commit_id, node_path)
);
```

#### 2.2 Three-Way Diff Algorithm

```sql
-- Compute diff between two schema states
CREATE OR REPLACE FUNCTION gitversion.compute_schema_diff(
    p_from_commit_id INTEGER,
    p_to_commit_id INTEGER
) RETURNS TABLE (
    operation gitversion.change_type,
    object_type gitversion.object_type,
    object_name TEXT,
    from_ddl TEXT,
    to_ddl TEXT,
    conflict_potential BOOLEAN
) AS $$
WITH 
from_objects AS (
    SELECT * FROM gitversion.object_snapshots WHERE commit_id = p_from_commit_id
),
to_objects AS (
    SELECT * FROM gitversion.object_snapshots WHERE commit_id = p_to_commit_id
)
SELECT 
    CASE 
        WHEN f.id IS NULL THEN 'CREATE'::gitversion.change_type
        WHEN t.id IS NULL THEN 'DROP'::gitversion.change_type
        ELSE 'ALTER'::gitversion.change_type
    END,
    COALESCE(f.object_type, t.object_type),
    COALESCE(f.object_name, t.object_name),
    f.ddl_content,
    t.ddl_content,
    -- Detect potential conflicts
    CASE 
        WHEN f.id IS NOT NULL AND t.id IS NOT NULL 
             AND f.object_hash != t.object_hash THEN true
        ELSE false
    END
FROM from_objects f
FULL OUTER JOIN to_objects t 
    ON f.object_type = t.object_type 
    AND f.object_name = t.object_name
WHERE f.object_hash IS DISTINCT FROM t.object_hash;
$$ LANGUAGE sql;
```

### 3. Transaction Isolation for Branches

#### 3.1 Branch-Aware Connection Routing

```sql
-- Session configuration for branch isolation
CREATE OR REPLACE FUNCTION gitversion.use_branch(p_branch_name TEXT) 
RETURNS void AS $$
DECLARE
    v_schema_name TEXT;
    v_search_path TEXT;
BEGIN
    -- Get schema for branch
    SELECT schema_name INTO v_schema_name
    FROM gitversion.branches
    WHERE branch_name = p_branch_name AND is_active = true;
    
    IF v_schema_name IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Set search path to branch schema
    v_search_path := format('%I, gitversion, public', v_schema_name);
    EXECUTE format('SET search_path TO %s', v_search_path);
    
    -- Store current branch in session
    PERFORM set_config('gitversion.current_branch', p_branch_name, false);
    PERFORM set_config('gitversion.current_schema', v_schema_name, false);
END;
$$ LANGUAGE plpgsql;

-- Automatic branch isolation for new connections
CREATE OR REPLACE FUNCTION gitversion.setup_branch_isolation()
RETURNS event_trigger AS $$
DECLARE
    v_branch TEXT;
    v_schema TEXT;
BEGIN
    -- Check if branch specified in connection
    v_branch := current_setting('gitversion.use_branch', true);
    
    IF v_branch IS NOT NULL THEN
        PERFORM gitversion.use_branch(v_branch);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER gitversion_connection_setup
ON login
EXECUTE FUNCTION gitversion.setup_branch_isolation();
```

#### 3.2 Cross-Branch Queries

```sql
-- Query objects across branches
CREATE OR REPLACE FUNCTION gitversion.query_cross_branch(
    p_query TEXT,
    p_branches TEXT[]
) RETURNS TABLE (
    branch_name TEXT,
    result JSONB
) AS $$
DECLARE
    v_branch TEXT;
    v_schema TEXT;
    v_result JSONB;
BEGIN
    FOREACH v_branch IN ARRAY p_branches LOOP
        -- Get schema for branch
        SELECT schema_name INTO v_schema
        FROM gitversion.branches
        WHERE branch_name = v_branch;
        
        -- Execute query in branch context
        EXECUTE format(
            'SELECT to_jsonb(array_agg(row_to_json(t.*))) 
             FROM (%s) t',
            regexp_replace(p_query, '\bpublic\.', v_schema || '.', 'g')
        ) INTO v_result;
        
        RETURN QUERY SELECT v_branch, v_result;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 4. Schema Branching Operations

#### 4.1 Create Branch

```sql
CREATE OR REPLACE FUNCTION gitversion.create_branch(
    p_branch_name TEXT,
    p_from_branch TEXT DEFAULT 'main'
) RETURNS INTEGER AS $$
DECLARE
    v_from_schema TEXT;
    v_new_schema TEXT;
    v_from_commit_id INTEGER;
    v_new_branch_id INTEGER;
    v_new_commit_id INTEGER;
BEGIN
    -- Validate branch doesn't exist
    IF EXISTS (SELECT 1 FROM gitversion.branches WHERE branch_name = p_branch_name) THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;
    
    -- Get source branch info
    SELECT schema_name, 
           (SELECT MAX(id) FROM gitversion.commits WHERE branch_id = b.id)
    INTO v_from_schema, v_from_commit_id
    FROM gitversion.branches b
    WHERE branch_name = p_from_branch;
    
    -- Create new schema
    v_new_schema := 'branch_' || regexp_replace(p_branch_name, '[^a-zA-Z0-9_]', '_', 'g');
    EXECUTE format('CREATE SCHEMA %I', v_new_schema);
    
    -- Clone schema objects
    PERFORM gitversion.clone_schema_objects(v_from_schema, v_new_schema);
    
    -- Create branch record
    INSERT INTO gitversion.branches (
        branch_name, schema_name, parent_branch_id, created_from_commit_id
    ) VALUES (
        p_branch_name, v_new_schema, 
        (SELECT id FROM gitversion.branches WHERE branch_name = p_from_branch),
        v_from_commit_id
    ) RETURNING id INTO v_new_branch_id;
    
    -- Create initial commit
    INSERT INTO gitversion.commits (
        commit_hash, branch_id, parent_commit_id, message, author, tree_hash
    ) VALUES (
        gitversion.compute_commit_hash(v_new_branch_id, v_from_commit_id),
        v_new_branch_id,
        v_from_commit_id,
        format('Created branch %s from %s', p_branch_name, p_from_branch),
        current_user,
        gitversion.compute_tree_hash(v_new_schema)
    ) RETURNING id INTO v_new_commit_id;
    
    -- Copy object snapshots
    INSERT INTO gitversion.object_snapshots (
        commit_id, object_type, object_name, object_hash, ddl_content, dependencies
    )
    SELECT 
        v_new_commit_id, object_type, object_name, object_hash, ddl_content, dependencies
    FROM gitversion.object_snapshots
    WHERE commit_id = v_from_commit_id;
    
    RETURN v_new_branch_id;
END;
$$ LANGUAGE plpgsql;
```

#### 4.2 Schema Cloning with Object Rewriting

```sql
CREATE OR REPLACE FUNCTION gitversion.clone_schema_objects(
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS void AS $$
DECLARE
    v_object RECORD;
    v_ddl TEXT;
    v_dependencies TEXT[];
BEGIN
    -- Clone in dependency order
    FOR v_object IN 
        WITH RECURSIVE dep_tree AS (
            -- Start with objects that have no dependencies
            SELECT 
                c.oid,
                c.relname,
                c.relkind,
                n.nspname,
                0 as level
            FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = p_from_schema
            AND NOT EXISTS (
                SELECT 1 FROM pg_depend d 
                WHERE d.objid = c.oid 
                AND d.deptype = 'n'
                AND d.refobjid IN (
                    SELECT oid FROM pg_class 
                    WHERE relnamespace = n.oid
                )
            )
            
            UNION ALL
            
            -- Add dependent objects
            SELECT 
                c.oid,
                c.relname,
                c.relkind,
                n.nspname,
                dt.level + 1
            FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_depend d ON d.objid = c.oid
            JOIN dep_tree dt ON d.refobjid = dt.oid
            WHERE n.nspname = p_from_schema
            AND d.deptype = 'n'
        )
        SELECT DISTINCT ON (oid) * FROM dep_tree
        ORDER BY oid, level DESC
    LOOP
        -- Generate DDL with schema replacement
        v_ddl := gitversion.get_object_ddl(
            v_object.nspname, 
            v_object.relname, 
            v_object.relkind
        );
        
        -- Replace schema references
        v_ddl := regexp_replace(v_ddl, '\b' || p_from_schema || '\.', p_to_schema || '.', 'g');
        
        -- Execute DDL in new schema
        EXECUTE v_ddl;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 5. Performance Optimizations

#### 5.1 Incremental Hash Computation

```sql
-- Incremental Merkle tree updates
CREATE OR REPLACE FUNCTION gitversion.update_merkle_tree_incremental(
    p_commit_id INTEGER,
    p_changed_objects TEXT[]
) RETURNS void AS $$
DECLARE
    v_object TEXT;
    v_path_parts TEXT[];
    v_current_path TEXT;
    v_new_hash TEXT;
BEGIN
    -- Update only affected paths
    FOREACH v_object IN ARRAY p_changed_objects LOOP
        v_path_parts := string_to_array(v_object, '/');
        
        -- Update from leaf to root
        FOR i IN REVERSE array_length(v_path_parts, 1)..1 LOOP
            v_current_path := array_to_string(v_path_parts[1:i], '/');
            
            -- Compute new hash for this node
            v_new_hash := gitversion.compute_node_hash(p_commit_id, v_current_path);
            
            -- Update or insert node
            INSERT INTO gitversion.merkle_nodes (
                commit_id, node_path, node_hash, node_type
            ) VALUES (
                p_commit_id, v_current_path, v_new_hash,
                CASE WHEN i = array_length(v_path_parts, 1) THEN 'leaf' ELSE 'branch' END
            ) ON CONFLICT (commit_id, node_path) 
            DO UPDATE SET node_hash = EXCLUDED.node_hash;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

#### 5.2 Copy-on-Write for Large Objects

```sql
-- Efficient storage using copy-on-write
CREATE TABLE gitversion.object_storage (
    content_hash TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    compression_type TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Reference counting for garbage collection
CREATE TABLE gitversion.object_references (
    content_hash TEXT REFERENCES gitversion.object_storage(content_hash),
    commit_id INTEGER REFERENCES gitversion.commits(id),
    reference_count INTEGER DEFAULT 1,
    PRIMARY KEY (content_hash, commit_id)
);

-- Store object with deduplication
CREATE OR REPLACE FUNCTION gitversion.store_object_cow(
    p_content TEXT,
    p_commit_id INTEGER
) RETURNS TEXT AS $$
DECLARE
    v_hash TEXT;
    v_compressed TEXT;
BEGIN
    -- Compute content hash
    v_hash := encode(digest(p_content, 'sha256'), 'hex');
    
    -- Try to insert (will fail if exists)
    BEGIN
        -- Compress if large
        IF length(p_content) > 1000 THEN
            v_compressed := gitversion.compress_content(p_content);
            INSERT INTO gitversion.object_storage (
                content_hash, content, size_bytes, compression_type
            ) VALUES (
                v_hash, v_compressed, length(p_content), 'gzip'
            );
        ELSE
            INSERT INTO gitversion.object_storage (
                content_hash, content, size_bytes
            ) VALUES (
                v_hash, p_content, length(p_content)
            );
        END IF;
    EXCEPTION WHEN unique_violation THEN
        -- Object already exists, just add reference
        NULL;
    END;
    
    -- Update reference count
    INSERT INTO gitversion.object_references (content_hash, commit_id)
    VALUES (v_hash, p_commit_id)
    ON CONFLICT (content_hash, commit_id) 
    DO UPDATE SET reference_count = object_references.reference_count + 1;
    
    RETURN v_hash;
END;
$$ LANGUAGE plpgsql;
```

### 6. Merge Operations

#### 6.1 Three-Way Merge Algorithm

```sql
CREATE OR REPLACE FUNCTION gitversion.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_strategy TEXT DEFAULT 'recursive'
) RETURNS INTEGER AS $$
DECLARE
    v_merge_base_commit_id INTEGER;
    v_source_commit_id INTEGER;
    v_target_commit_id INTEGER;
    v_conflicts JSONB[];
    v_merge_commit_id INTEGER;
BEGIN
    -- Find merge base (common ancestor)
    v_merge_base_commit_id := gitversion.find_merge_base(p_source_branch, p_target_branch);
    
    -- Get latest commits
    SELECT MAX(c.id) INTO v_source_commit_id
    FROM gitversion.commits c
    JOIN gitversion.branches b ON c.branch_id = b.id
    WHERE b.branch_name = p_source_branch;
    
    SELECT MAX(c.id) INTO v_target_commit_id
    FROM gitversion.commits c
    JOIN gitversion.branches b ON c.branch_id = b.id
    WHERE b.branch_name = p_target_branch;
    
    -- Perform three-way merge
    v_conflicts := gitversion.three_way_merge(
        v_merge_base_commit_id,
        v_source_commit_id,
        v_target_commit_id,
        p_strategy
    );
    
    IF array_length(v_conflicts, 1) > 0 THEN
        -- Handle conflicts
        RAISE EXCEPTION 'Merge conflicts detected: %', to_json(v_conflicts);
    END IF;
    
    -- Create merge commit
    INSERT INTO gitversion.commits (
        commit_hash, 
        branch_id,
        parent_commit_id,
        message,
        author,
        tree_hash,
        metadata
    ) VALUES (
        gitversion.compute_commit_hash(
            (SELECT id FROM gitversion.branches WHERE branch_name = p_target_branch),
            v_target_commit_id
        ),
        (SELECT id FROM gitversion.branches WHERE branch_name = p_target_branch),
        v_target_commit_id,
        format('Merge branch ''%s'' into ''%s''', p_source_branch, p_target_branch),
        current_user,
        gitversion.compute_tree_hash(
            (SELECT schema_name FROM gitversion.branches WHERE branch_name = p_target_branch)
        ),
        jsonb_build_object(
            'merge', true,
            'source_branch', p_source_branch,
            'source_commit', v_source_commit_id,
            'merge_base', v_merge_base_commit_id
        )
    ) RETURNING id INTO v_merge_commit_id;
    
    RETURN v_merge_commit_id;
END;
$$ LANGUAGE plpgsql;
```

### 7. Conflict Resolution

```sql
-- Conflict detection and resolution strategies
CREATE TYPE gitversion.conflict_type AS ENUM (
    'schema_schema',    -- Same object modified in both branches
    'schema_data',      -- Schema change conflicts with data
    'delete_modify',    -- Deleted in one, modified in other
    'type_mismatch',    -- Type changes that are incompatible
    'constraint_violation' -- New constraints that existing data violates
);

CREATE TABLE gitversion.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_attempt_id INTEGER,
    conflict_type gitversion.conflict_type,
    object_type gitversion.object_type,
    object_name TEXT,
    base_version TEXT,
    source_version TEXT,
    target_version TEXT,
    resolution_strategy TEXT,
    resolved_version TEXT,
    resolved_by TEXT,
    resolved_at TIMESTAMP
);

CREATE OR REPLACE FUNCTION gitversion.auto_resolve_conflict(
    p_conflict JSONB,
    p_strategy TEXT
) RETURNS TEXT AS $$
BEGIN
    CASE p_strategy
        WHEN 'theirs' THEN
            RETURN p_conflict->>'source_version';
        WHEN 'ours' THEN
            RETURN p_conflict->>'target_version';
        WHEN 'union' THEN
            -- For compatible changes, combine both
            RETURN gitversion.merge_ddl_union(
                p_conflict->>'source_version',
                p_conflict->>'target_version'
            );
        ELSE
            RETURN NULL; -- Manual resolution required
    END CASE;
END;
$$ LANGUAGE plpgsql;
```

## Implementation Considerations

### Performance Impact

1. **Branch Creation**: O(n) where n is number of objects in schema
2. **Commit Operation**: O(m) where m is number of changed objects  
3. **Merge Operation**: O(n log n) for diff computation
4. **Storage Overhead**: ~2-3x base schema size for active branches

### Limitations

1. **Data Synchronization**: This design handles schema only, not data
2. **Cross-Branch FK**: Foreign keys cannot reference across branches
3. **System Catalog**: Some PostgreSQL internals cannot be branched
4. **Performance**: Each branch requires full schema copy

### Migration Path

1. Start with single-schema prototype
2. Add branch isolation incrementally  
3. Implement merge algorithms iteratively
4. Optimize storage with COW as needed

## Conclusion

This architecture provides a technically feasible path to implementing Git-like semantics in PostgreSQL. While complex, it leverages PostgreSQL's native features (schemas, event triggers, JSONB) to create a powerful schema versioning system that goes beyond simple audit logging to enable true concurrent development workflows at the database level.