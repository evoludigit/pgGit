-- Git-Style Schema Branching Proof of Concept
-- This demonstrates the core concepts from the architecture document

-- Prerequisites: pg_gitversion extension must be installed
-- CREATE EXTENSION pg_gitversion;

-- ============================================
-- PART 1: Core Branch Management Tables
-- ============================================

-- Drop existing POC objects if they exist
DROP TABLE IF EXISTS gitversion.merge_conflicts CASCADE;
DROP TABLE IF EXISTS gitversion.object_references CASCADE;
DROP TABLE IF EXISTS gitversion.object_storage CASCADE;
DROP TABLE IF EXISTS gitversion.merkle_nodes CASCADE;
DROP TABLE IF EXISTS gitversion.object_snapshots CASCADE;
DROP TABLE IF EXISTS gitversion.commits CASCADE;
DROP TABLE IF EXISTS gitversion.branches CASCADE;
DROP TYPE IF EXISTS gitversion.conflict_type CASCADE;

-- Branch tracking
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

-- Git-style commits
CREATE TABLE gitversion.commits (
    id SERIAL PRIMARY KEY,
    commit_hash TEXT UNIQUE NOT NULL,
    branch_id INTEGER REFERENCES gitversion.branches(id),
    parent_commit_id INTEGER REFERENCES gitversion.commits(id),
    message TEXT NOT NULL,
    author TEXT NOT NULL,
    committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tree_hash TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'
);

-- Object snapshots at each commit
CREATE TABLE gitversion.object_snapshots (
    id BIGSERIAL PRIMARY KEY,
    commit_id INTEGER REFERENCES gitversion.commits(id),
    object_type gitversion.object_type NOT NULL,
    object_name TEXT NOT NULL,
    object_hash TEXT NOT NULL,
    ddl_content TEXT NOT NULL,
    dependencies JSONB DEFAULT '[]',
    metadata JSONB DEFAULT '{}',
    UNIQUE(commit_id, object_type, object_name)
);

-- Create indexes
CREATE INDEX idx_snapshots_commit_hash ON gitversion.object_snapshots(commit_id, object_hash);
CREATE INDEX idx_branches_active ON gitversion.branches(is_active) WHERE is_active = true;
CREATE INDEX idx_commits_branch ON gitversion.commits(branch_id, committed_at DESC);

-- ============================================
-- PART 2: Branch Creation and Management
-- ============================================

-- Function to create a new branch
CREATE OR REPLACE FUNCTION gitversion.create_branch(
    p_branch_name TEXT,
    p_from_branch TEXT DEFAULT 'main'
) RETURNS INTEGER AS $$
DECLARE
    v_from_schema TEXT;
    v_new_schema TEXT;
    v_from_branch_id INTEGER;
    v_from_commit_id INTEGER;
    v_new_branch_id INTEGER;
    v_new_commit_id INTEGER;
    v_object RECORD;
BEGIN
    -- Validate branch doesn't exist
    IF EXISTS (SELECT 1 FROM gitversion.branches WHERE branch_name = p_branch_name) THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;
    
    -- Get source branch info
    SELECT b.id, b.schema_name, 
           (SELECT MAX(c.id) FROM gitversion.commits c WHERE c.branch_id = b.id)
    INTO v_from_branch_id, v_from_schema, v_from_commit_id
    FROM gitversion.branches b
    WHERE b.branch_name = p_from_branch;
    
    IF v_from_branch_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', p_from_branch;
    END IF;
    
    -- Create new schema name
    v_new_schema := 'branch_' || regexp_replace(lower(p_branch_name), '[^a-z0-9_]', '_', 'g');
    
    -- Create new schema
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_new_schema);
    
    -- Create branch record
    INSERT INTO gitversion.branches (
        branch_name, schema_name, parent_branch_id, created_from_commit_id
    ) VALUES (
        p_branch_name, v_new_schema, v_from_branch_id, v_from_commit_id
    ) RETURNING id INTO v_new_branch_id;
    
    -- Clone schema objects
    PERFORM gitversion.clone_schema_objects(v_from_schema, v_new_schema);
    
    -- Create initial commit
    INSERT INTO gitversion.commits (
        commit_hash, branch_id, parent_commit_id, message, author, tree_hash
    ) VALUES (
        encode(digest(p_branch_name || v_from_commit_id::text || now()::text, 'sha256'), 'hex'),
        v_new_branch_id,
        v_from_commit_id,
        format('Created branch %s from %s', p_branch_name, p_from_branch),
        current_user,
        encode(digest(v_new_schema || now()::text, 'sha256'), 'hex')
    ) RETURNING id INTO v_new_commit_id;
    
    -- Copy object snapshots from parent
    INSERT INTO gitversion.object_snapshots (
        commit_id, object_type, object_name, object_hash, ddl_content, dependencies, metadata
    )
    SELECT 
        v_new_commit_id, object_type, object_name, object_hash, ddl_content, dependencies, metadata
    FROM gitversion.object_snapshots
    WHERE commit_id = v_from_commit_id;
    
    RAISE NOTICE 'Created branch % with schema %', p_branch_name, v_new_schema;
    RETURN v_new_branch_id;
END;
$$ LANGUAGE plpgsql;

-- Function to switch to a branch
CREATE OR REPLACE FUNCTION gitversion.checkout_branch(p_branch_name TEXT) 
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
        RAISE EXCEPTION 'Branch % not found or inactive', p_branch_name;
    END IF;
    
    -- Set search path to branch schema
    v_search_path := format('%I, gitversion, public', v_schema_name);
    EXECUTE format('SET search_path TO %s', v_search_path);
    
    -- Store current branch in session
    PERFORM set_config('gitversion.current_branch', p_branch_name, false);
    PERFORM set_config('gitversion.current_schema', v_schema_name, false);
    
    RAISE NOTICE 'Switched to branch % (schema: %)', p_branch_name, v_schema_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get current branch
CREATE OR REPLACE FUNCTION gitversion.current_branch() 
RETURNS TEXT AS $$
BEGIN
    RETURN current_setting('gitversion.current_branch', true);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Schema Cloning
-- ============================================

-- Simplified schema cloning function
CREATE OR REPLACE FUNCTION gitversion.clone_schema_objects(
    p_from_schema TEXT,
    p_to_schema TEXT
) RETURNS void AS $$
DECLARE
    v_table RECORD;
    v_ddl TEXT;
    v_constraint RECORD;
    v_index RECORD;
BEGIN
    -- Clone tables first (without constraints)
    FOR v_table IN 
        SELECT tablename, 
               pg_get_tabledef(schemaname||'.'||tablename) as tabledef
        FROM pg_tables 
        WHERE schemaname = p_from_schema
        ORDER BY tablename
    LOOP
        -- Get table definition and replace schema
        v_ddl := replace(v_table.tabledef, p_from_schema||'.', p_to_schema||'.');
        v_ddl := replace(v_ddl, 'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS');
        
        -- Remove foreign key constraints for now (will add later)
        v_ddl := regexp_replace(v_ddl, 'FOREIGN KEY.*?REFERENCES.*?(?=,|\))', '', 'g');
        
        BEGIN
            EXECUTE v_ddl;
            RAISE NOTICE 'Cloned table %.%', p_to_schema, v_table.tablename;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to clone table %.%: %', p_to_schema, v_table.tablename, SQLERRM;
        END;
    END LOOP;
    
    -- Clone indexes
    FOR v_index IN
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE schemaname = p_from_schema
        AND indexname NOT LIKE 'pg_%'
    LOOP
        v_ddl := replace(v_index.indexdef, p_from_schema||'.', p_to_schema||'.');
        v_ddl := replace(v_ddl, 'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS');
        v_ddl := replace(v_ddl, 'CREATE UNIQUE INDEX', 'CREATE UNIQUE INDEX IF NOT EXISTS');
        
        BEGIN
            EXECUTE v_ddl;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to clone index %: %', v_index.indexname, SQLERRM;
        END;
    END LOOP;
    
    -- Add foreign key constraints
    FOR v_constraint IN
        SELECT
            tc.constraint_name,
            tc.table_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name
        FROM 
            information_schema.table_constraints AS tc 
            JOIN information_schema.key_column_usage AS kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name
              AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY' 
          AND tc.table_schema = p_from_schema
    LOOP
        v_ddl := format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I (%I)',
            p_to_schema, v_constraint.table_name, v_constraint.constraint_name,
            v_constraint.column_name, p_to_schema, v_constraint.foreign_table_name,
            v_constraint.foreign_column_name);
        
        BEGIN
            EXECUTE v_ddl;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to clone constraint %: %', v_constraint.constraint_name, SQLERRM;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Helper function to get table definition (simplified)
CREATE OR REPLACE FUNCTION pg_get_tabledef(p_table TEXT)
RETURNS TEXT AS $$
DECLARE
    v_def TEXT;
BEGIN
    -- This is a simplified version - real implementation would be more complex
    SELECT 'CREATE TABLE ' || p_table || ' (' || 
           string_agg(
               column_name || ' ' || 
               CASE 
                   WHEN data_type = 'character varying' THEN 'varchar(' || character_maximum_length || ')'
                   WHEN data_type = 'numeric' AND numeric_precision IS NOT NULL THEN 
                        'numeric(' || numeric_precision || ',' || numeric_scale || ')'
                   ELSE data_type
               END ||
               CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END ||
               CASE WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default ELSE '' END,
               ', '
               ORDER BY ordinal_position
           ) || ')'
    INTO v_def
    FROM information_schema.columns
    WHERE table_schema || '.' || table_name = p_table;
    
    RETURN v_def;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Commit Tracking
-- ============================================

-- Function to create a commit (snapshot current state)
CREATE OR REPLACE FUNCTION gitversion.commit_changes(p_message TEXT)
RETURNS INTEGER AS $$
DECLARE
    v_branch_name TEXT;
    v_branch_id INTEGER;
    v_schema_name TEXT;
    v_parent_commit_id INTEGER;
    v_new_commit_id INTEGER;
    v_object RECORD;
    v_object_count INTEGER := 0;
BEGIN
    -- Get current branch
    v_branch_name := gitversion.current_branch();
    IF v_branch_name IS NULL THEN
        RAISE EXCEPTION 'No branch checked out. Use gitversion.checkout_branch() first';
    END IF;
    
    -- Get branch info
    SELECT id, schema_name,
           (SELECT MAX(id) FROM gitversion.commits WHERE branch_id = b.id)
    INTO v_branch_id, v_schema_name, v_parent_commit_id
    FROM gitversion.branches b
    WHERE branch_name = v_branch_name;
    
    -- Create commit record
    INSERT INTO gitversion.commits (
        commit_hash, branch_id, parent_commit_id, message, author, tree_hash
    ) VALUES (
        encode(digest(v_branch_name || p_message || now()::text, 'sha256'), 'hex'),
        v_branch_id,
        v_parent_commit_id,
        p_message,
        current_user,
        encode(digest(v_schema_name || now()::text, 'sha256'), 'hex')
    ) RETURNING id INTO v_new_commit_id;
    
    -- Snapshot all tables in the schema
    FOR v_object IN
        SELECT 
            'TABLE'::gitversion.object_type as object_type,
            tablename as object_name,
            pg_get_tabledef(schemaname||'.'||tablename) as ddl_content
        FROM pg_tables
        WHERE schemaname = v_schema_name
    LOOP
        INSERT INTO gitversion.object_snapshots (
            commit_id, object_type, object_name, object_hash, ddl_content
        ) VALUES (
            v_new_commit_id,
            v_object.object_type,
            v_object.object_name,
            encode(digest(v_object.ddl_content, 'sha256'), 'hex'),
            v_object.ddl_content
        );
        v_object_count := v_object_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Created commit % with % objects', v_new_commit_id, v_object_count;
    RETURN v_new_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Function to show commit history
CREATE OR REPLACE FUNCTION gitversion.log(p_limit INTEGER DEFAULT 10)
RETURNS TABLE (
    commit_id INTEGER,
    commit_hash TEXT,
    branch_name TEXT,
    message TEXT,
    author TEXT,
    committed_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        substring(c.commit_hash, 1, 8) as commit_hash,
        b.branch_name,
        c.message,
        c.author,
        c.committed_at
    FROM gitversion.commits c
    JOIN gitversion.branches b ON c.branch_id = b.id
    WHERE b.branch_name = gitversion.current_branch()
        OR gitversion.current_branch() IS NULL
    ORDER BY c.committed_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Diff and Comparison
-- ============================================

-- Function to compare two commits
CREATE OR REPLACE FUNCTION gitversion.diff_commits(
    p_from_commit_id INTEGER,
    p_to_commit_id INTEGER
) RETURNS TABLE (
    operation TEXT,
    object_type gitversion.object_type,
    object_name TEXT,
    details TEXT
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
        WHEN f.id IS NULL THEN 'ADDED'
        WHEN t.id IS NULL THEN 'REMOVED'
        WHEN f.object_hash != t.object_hash THEN 'MODIFIED'
        ELSE 'UNCHANGED'
    END as operation,
    COALESCE(f.object_type, t.object_type) as object_type,
    COALESCE(f.object_name, t.object_name) as object_name,
    CASE 
        WHEN f.id IS NULL THEN 'New object created'
        WHEN t.id IS NULL THEN 'Object removed'
        WHEN f.object_hash != t.object_hash THEN 
            'Hash changed from ' || substring(f.object_hash, 1, 8) || 
            ' to ' || substring(t.object_hash, 1, 8)
        ELSE 'No changes'
    END as details
FROM from_objects f
FULL OUTER JOIN to_objects t 
    ON f.object_type = t.object_type 
    AND f.object_name = t.object_name
WHERE f.object_hash IS DISTINCT FROM t.object_hash
ORDER BY 
    CASE operation 
        WHEN 'ADDED' THEN 1 
        WHEN 'MODIFIED' THEN 2 
        WHEN 'REMOVED' THEN 3 
    END,
    object_type, object_name;
$$ LANGUAGE sql;

-- ============================================
-- PART 6: Branch Status and Info
-- ============================================

-- Function to show branch status
CREATE OR REPLACE FUNCTION gitversion.status()
RETURNS TABLE (
    info_type TEXT,
    info_value TEXT
) AS $$
DECLARE
    v_branch TEXT;
    v_schema TEXT;
    v_last_commit RECORD;
BEGIN
    v_branch := gitversion.current_branch();
    v_schema := current_setting('gitversion.current_schema', true);
    
    -- Current branch
    RETURN QUERY SELECT 'Current Branch', COALESCE(v_branch, 'none');
    RETURN QUERY SELECT 'Schema', COALESCE(v_schema, 'none');
    
    -- Last commit info
    IF v_branch IS NOT NULL THEN
        SELECT c.id, substring(c.commit_hash, 1, 8), c.message, c.committed_at
        INTO v_last_commit
        FROM gitversion.commits c
        JOIN gitversion.branches b ON c.branch_id = b.id
        WHERE b.branch_name = v_branch
        ORDER BY c.committed_at DESC
        LIMIT 1;
        
        IF v_last_commit.id IS NOT NULL THEN
            RETURN QUERY SELECT 'Last Commit', v_last_commit.commit_hash || ' - ' || v_last_commit.message;
            RETURN QUERY SELECT 'Committed At', v_last_commit.committed_at::text;
        END IF;
    END IF;
    
    -- Branch list
    RETURN QUERY 
    SELECT 'Available Branches', string_agg(branch_name, ', ' ORDER BY branch_name)
    FROM gitversion.branches
    WHERE is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Function to list all branches
CREATE OR REPLACE FUNCTION gitversion.branch_list()
RETURNS TABLE (
    branch_name TEXT,
    schema_name TEXT,
    parent_branch TEXT,
    created_at TIMESTAMP,
    created_by TEXT,
    commit_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.branch_name,
        b.schema_name,
        pb.branch_name as parent_branch,
        b.created_at,
        b.created_by,
        COUNT(c.id) as commit_count
    FROM gitversion.branches b
    LEFT JOIN gitversion.branches pb ON b.parent_branch_id = pb.id
    LEFT JOIN gitversion.commits c ON c.branch_id = b.id
    WHERE b.is_active = true
    GROUP BY b.id, b.branch_name, b.schema_name, pb.branch_name, b.created_at, b.created_by
    ORDER BY b.created_at;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 7: Initialize with main branch
-- ============================================

-- Initialize the main branch if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM gitversion.branches WHERE branch_name = 'main') THEN
        -- Create main branch
        INSERT INTO gitversion.branches (
            branch_name, schema_name, created_by
        ) VALUES (
            'main', 'public', current_user
        );
        
        -- Create initial commit
        INSERT INTO gitversion.commits (
            commit_hash,
            branch_id,
            message,
            author,
            tree_hash
        ) VALUES (
            encode(digest('initial commit', 'sha256'), 'hex'),
            (SELECT id FROM gitversion.branches WHERE branch_name = 'main'),
            'Initial commit',
            current_user,
            encode(digest('public', 'sha256'), 'hex')
        );
        
        RAISE NOTICE 'Initialized main branch';
    END IF;
END $$;

-- ============================================
-- PART 8: Demo Usage
-- ============================================

/*
-- Example usage:

-- 1. Check current status
SELECT * FROM gitversion.status();

-- 2. Create a feature branch
SELECT gitversion.create_branch('feature/user-auth', 'main');

-- 3. Switch to the new branch
SELECT gitversion.checkout_branch('feature/user-auth');

-- 4. Make some schema changes in the branch
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Commit the changes
SELECT gitversion.commit_changes('Add users table for authentication');

-- 6. View commit history
SELECT * FROM gitversion.log();

-- 7. Create another branch
SELECT gitversion.create_branch('feature/products', 'main');
SELECT gitversion.checkout_branch('feature/products');

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

SELECT gitversion.commit_changes('Add products table');

-- 8. List all branches
SELECT * FROM gitversion.branch_list();

-- 9. Compare branches (diff commits)
SELECT * FROM gitversion.diff_commits(
    (SELECT MAX(id) FROM gitversion.commits WHERE branch_id = 
        (SELECT id FROM gitversion.branches WHERE branch_name = 'main')),
    (SELECT MAX(id) FROM gitversion.commits WHERE branch_id = 
        (SELECT id FROM gitversion.branches WHERE branch_name = 'feature/user-auth'))
);

*/

-- Show available commands
SELECT 'Git-style branching POC loaded. Available functions:' as message
UNION ALL
SELECT '  - gitversion.create_branch(name, from_branch)  : Create a new branch'
UNION ALL
SELECT '  - gitversion.checkout_branch(name)             : Switch to a branch'
UNION ALL  
SELECT '  - gitversion.commit_changes(message)           : Commit current schema state'
UNION ALL
SELECT '  - gitversion.log()                             : Show commit history'
UNION ALL
SELECT '  - gitversion.status()                          : Show current branch status'
UNION ALL
SELECT '  - gitversion.branch_list()                     : List all branches'
UNION ALL
SELECT '  - gitversion.diff_commits(from_id, to_id)      : Compare two commits';