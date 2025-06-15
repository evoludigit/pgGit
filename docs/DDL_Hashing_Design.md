# DDL Hashing Design for Change Detection

A design proposal for using DDL signature hashing to efficiently detect schema changes.

## Core Concept

Instead of comparing full DDL text or metadata, we compute deterministic hashes of database objects' DDL signatures. This enables:

- **Fast change detection**: Compare hashes instead of full definitions
- **Efficient storage**: Store compact hashes rather than full DDL
- **Network efficiency**: Transmit hashes for comparison before full DDL
- **Version independence**: Same logical structure = same hash

## Implementation Design

### 1. Normalized DDL Generation

First, we need to generate normalized DDL that produces consistent output:

```sql
CREATE OR REPLACE FUNCTION gitversion.get_normalized_ddl(
    p_object_type TEXT,
    p_object_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_ddl TEXT;
    v_normalized TEXT;
BEGIN
    CASE p_object_type
        WHEN 'TABLE' THEN
            -- Get table structure in normalized form
            SELECT string_agg(
                format(E'%s %s%s%s',
                    column_name,
                    data_type,
                    CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END,
                    CASE WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default ELSE '' END
                ),
                E',\n' ORDER BY ordinal_position
            ) INTO v_ddl
            FROM information_schema.columns
            WHERE table_schema || '.' || table_name = p_object_name;
            
        WHEN 'INDEX' THEN
            -- Get normalized index definition
            SELECT pg_get_indexdef(indexrelid, 0, true)
            INTO v_ddl
            FROM pg_index i
            JOIN pg_class c ON c.oid = i.indexrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname || '.' || c.relname = p_object_name;
            
        WHEN 'FUNCTION' THEN
            -- Get normalized function definition
            SELECT pg_get_functiondef(p.oid)
            INTO v_ddl
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname || '.' || p.proname = p_object_name;
    END CASE;
    
    -- Normalize the DDL:
    -- - Remove excess whitespace
    -- - Lowercase keywords
    -- - Sort constraints alphabetically
    -- - Remove schema qualifiers for portability
    v_normalized := regexp_replace(v_ddl, '\s+', ' ', 'g');
    v_normalized := lower(v_normalized);
    
    RETURN v_normalized;
END;
$$ LANGUAGE plpgsql;
```

### 2. Hash Computation

```sql
-- Add hash column to objects table
ALTER TABLE gitversion.objects ADD COLUMN ddl_hash TEXT;

-- Create hash computation function
CREATE OR REPLACE FUNCTION gitversion.compute_ddl_hash(
    p_object_type TEXT,
    p_object_name TEXT,
    p_metadata JSONB DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_normalized_ddl TEXT;
    v_hash_input TEXT;
BEGIN
    -- Get normalized DDL
    v_normalized_ddl := gitversion.get_normalized_ddl(p_object_type, p_object_name);
    
    -- For tables, include column order and constraints
    IF p_object_type = 'TABLE' AND p_metadata IS NOT NULL THEN
        v_hash_input := v_normalized_ddl || '|' || 
                       jsonb_pretty(p_metadata->'columns') || '|' ||
                       jsonb_pretty(p_metadata->'constraints');
    ELSE
        v_hash_input := v_normalized_ddl;
    END IF;
    
    -- Compute SHA-256 hash
    RETURN encode(digest(v_hash_input, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;
```

### 3. Change Detection Using Hashes

```sql
-- Fast change detection function
CREATE OR REPLACE FUNCTION gitversion.has_object_changed(
    p_object_name TEXT,
    p_stored_hash TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_current_hash TEXT;
    v_object_type gitversion.object_type;
BEGIN
    -- Get object type
    SELECT object_type INTO v_object_type
    FROM gitversion.objects
    WHERE full_name = p_object_name AND is_active = true;
    
    -- Compute current hash
    v_current_hash := gitversion.compute_ddl_hash(v_object_type::TEXT, p_object_name);
    
    -- Compare hashes
    RETURN v_current_hash != p_stored_hash;
END;
$$ LANGUAGE plpgsql;

-- Bulk change detection
CREATE OR REPLACE FUNCTION gitversion.detect_changed_objects()
RETURNS TABLE(
    object_name TEXT,
    object_type gitversion.object_type,
    old_hash TEXT,
    new_hash TEXT,
    changed BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.full_name,
        o.object_type,
        o.ddl_hash,
        gitversion.compute_ddl_hash(o.object_type::TEXT, o.full_name),
        gitversion.compute_ddl_hash(o.object_type::TEXT, o.full_name) != o.ddl_hash
    FROM gitversion.objects o
    WHERE o.is_active = true
    AND o.ddl_hash IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
```

### 4. Schema Comparison Using Hashes

For comparing schemas across databases:

```sql
-- Create type for hash comparison results
CREATE TYPE schema_hash_diff AS (
    object_name TEXT,
    object_type TEXT,
    source_hash TEXT,
    target_hash TEXT,
    status TEXT  -- 'identical', 'different', 'source_only', 'target_only'
);

-- Compare schemas using hashes
CREATE OR REPLACE FUNCTION gitversion.compare_schema_hashes(
    p_source_hashes JSONB,  -- {"table.users": "hash1", ...}
    p_target_hashes JSONB
) RETURNS SETOF schema_hash_diff AS $$
DECLARE
    v_key TEXT;
    v_result schema_hash_diff;
BEGIN
    -- Find objects in both, different, or only in source
    FOR v_key IN SELECT jsonb_object_keys(p_source_hashes) LOOP
        v_result.object_name := v_key;
        v_result.object_type := split_part(v_key, '.', 1);
        v_result.source_hash := p_source_hashes->>v_key;
        v_result.target_hash := p_target_hashes->>v_key;
        
        IF p_target_hashes ? v_key THEN
            IF p_source_hashes->>v_key = p_target_hashes->>v_key THEN
                v_result.status := 'identical';
            ELSE
                v_result.status := 'different';
            END IF;
        ELSE
            v_result.status := 'source_only';
        END IF;
        
        RETURN NEXT v_result;
    END LOOP;
    
    -- Find objects only in target
    FOR v_key IN SELECT jsonb_object_keys(p_target_hashes) LOOP
        IF NOT (p_source_hashes ? v_key) THEN
            v_result.object_name := v_key;
            v_result.object_type := split_part(v_key, '.', 1);
            v_result.source_hash := NULL;
            v_result.target_hash := p_target_hashes->>v_key;
            v_result.status := 'target_only';
            RETURN NEXT v_result;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 5. Integration with Event Triggers

Update the event triggers to maintain hashes:

```sql
-- Modified version tracking to include hash
CREATE OR REPLACE FUNCTION gitversion.track_change_with_hash(
    p_object_id INTEGER,
    p_change_type gitversion.change_type,
    p_change_severity gitversion.change_severity,
    p_description TEXT
) RETURNS VOID AS $$
DECLARE
    v_object RECORD;
    v_new_hash TEXT;
BEGIN
    -- Get object details
    SELECT * INTO v_object FROM gitversion.objects WHERE id = p_object_id;
    
    -- Compute new hash
    v_new_hash := gitversion.compute_ddl_hash(
        v_object.object_type::TEXT, 
        v_object.full_name,
        v_object.metadata
    );
    
    -- Only record change if hash actually changed
    IF v_object.ddl_hash IS NULL OR v_object.ddl_hash != v_new_hash THEN
        -- Update object with new hash
        UPDATE gitversion.objects 
        SET ddl_hash = v_new_hash,
            version = version + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_object_id;
        
        -- Record in history
        INSERT INTO gitversion.history (
            object_id, change_type, change_severity,
            old_version, new_version, change_description
        ) VALUES (
            p_object_id, p_change_type, p_change_severity,
            v_object.version, v_object.version + 1, p_description
        );
    END IF;
END;
$$ LANGUAGE plpgsql;
```

## Use Cases

### 1. Efficient Change Detection

```sql
-- Quick check if schema has changed
WITH current_hashes AS (
    SELECT 
        full_name,
        gitversion.compute_ddl_hash(object_type::TEXT, full_name) as current_hash
    FROM gitversion.objects
    WHERE is_active = true
)
SELECT 
    o.full_name,
    o.ddl_hash != ch.current_hash as has_changed
FROM gitversion.objects o
JOIN current_hashes ch ON ch.full_name = o.full_name
WHERE o.ddl_hash != ch.current_hash;
```

### 2. Cross-Database Sync

```sql
-- On source database: Export hashes
COPY (
    SELECT json_object_agg(
        full_name, 
        ddl_hash
    )
    FROM gitversion.objects
    WHERE is_active = true
) TO '/tmp/source_hashes.json';

-- On target database: Compare
WITH source_hashes AS (
    SELECT jsonb_object_agg(
        full_name,
        ddl_hash
    ) as hashes
    FROM gitversion.objects
    WHERE is_active = true
),
target_hashes AS (
    -- Load from file or foreign table
    SELECT pg_read_file('/tmp/source_hashes.json')::jsonb as hashes
)
SELECT * FROM gitversion.compare_schema_hashes(
    (SELECT hashes FROM source_hashes),
    (SELECT hashes FROM target_hashes)
)
WHERE status != 'identical';
```

### 3. Drift Monitoring

```sql
-- Create baseline snapshot
CREATE TABLE gitversion.hash_baselines (
    id SERIAL PRIMARY KEY,
    baseline_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    object_hashes JSONB NOT NULL
);

-- Save current state
INSERT INTO gitversion.hash_baselines (baseline_name, object_hashes)
SELECT 
    'production_' || to_char(CURRENT_DATE, 'YYYYMMDD'),
    jsonb_object_agg(full_name, ddl_hash)
FROM gitversion.objects
WHERE is_active = true;

-- Check for drift from baseline
WITH current_state AS (
    SELECT jsonb_object_agg(full_name, ddl_hash) as hashes
    FROM gitversion.objects
    WHERE is_active = true
),
baseline AS (
    SELECT object_hashes as hashes
    FROM gitversion.hash_baselines
    WHERE baseline_name = 'production_20240614'
)
SELECT * FROM gitversion.compare_schema_hashes(
    (SELECT hashes FROM baseline),
    (SELECT hashes FROM current_state)
)
WHERE status != 'identical';
```

## Benefits

1. **Performance**: O(1) comparison vs O(n) text comparison
2. **Network Efficient**: Send 64-char hash instead of full DDL
3. **Storage Efficient**: Store compact hashes for history
4. **Deterministic**: Same structure always produces same hash
5. **Version Agnostic**: Works across PostgreSQL versions

## Challenges and Solutions

### Challenge 1: Hash Stability
**Problem**: Different PostgreSQL versions might format DDL differently
**Solution**: Use information_schema and catalog queries instead of pg_get_*def functions

### Challenge 2: Insignificant Differences
**Problem**: Whitespace, comments, or order changes trigger hash changes
**Solution**: Aggressive normalization before hashing

### Challenge 3: Partial Comparisons
**Problem**: Sometimes only want to compare specific aspects
**Solution**: Separate hashes for structure, constraints, indexes, etc.

```sql
CREATE TABLE gitversion.object_hashes (
    object_id INTEGER REFERENCES gitversion.objects(id),
    hash_type TEXT NOT NULL, -- 'structure', 'constraints', 'indexes', 'permissions'
    hash_value TEXT NOT NULL,
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (object_id, hash_type)
);
```

## Future Enhancements

1. **Merkle Trees**: Build tree of hashes for hierarchical comparison
2. **Incremental Hashing**: Update hashes incrementally for large objects
3. **Semantic Hashing**: Hash logical structure, not physical representation
4. **Cross-DBMS Hashing**: Normalize across different database systems