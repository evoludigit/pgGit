-- Git Core Implementation for pggit
-- ACTUAL branching, commits, and checkout functionality

-- ============================================
-- PART 1: Core Git Tables
-- ============================================

-- Git references (branches, tags)
CREATE TABLE IF NOT EXISTS pggit.refs (
    ref_name TEXT PRIMARY KEY,
    ref_type TEXT NOT NULL CHECK (ref_type IN ('branch', 'tag')),
    target_commit_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT current_user
);

-- Git commits
CREATE TABLE IF NOT EXISTS pggit.commits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID REFERENCES pggit.commits(id),
    tree_hash TEXT NOT NULL, -- SHA256 of schema state
    author TEXT NOT NULL DEFAULT current_user,
    message TEXT NOT NULL,
    committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    branch_name TEXT,
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_commits_parent ON pggit.commits(parent_id);
CREATE INDEX idx_commits_branch ON pggit.commits(branch_name);

-- Git trees (schema snapshots)
CREATE TABLE IF NOT EXISTS pggit.trees (
    tree_hash TEXT PRIMARY KEY,
    schema_snapshot JSONB NOT NULL, -- Complete schema state
    object_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Git blobs (individual object definitions)
CREATE TABLE IF NOT EXISTS pggit.blobs (
    blob_hash TEXT PRIMARY KEY,
    object_type pggit.object_type NOT NULL,
    object_name TEXT NOT NULL,
    object_schema TEXT NOT NULL,
    object_definition TEXT NOT NULL,
    dependencies JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Current branch tracking
CREATE TABLE IF NOT EXISTS pggit.HEAD (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Singleton
    current_branch TEXT NOT NULL DEFAULT 'main',
    current_commit_id UUID,
    working_schema TEXT NOT NULL DEFAULT 'public'
);

-- Initialize HEAD if not exists
INSERT INTO pggit.HEAD (current_branch) 
VALUES ('main') 
ON CONFLICT (id) DO NOTHING;

-- Initialize main branch
INSERT INTO pggit.refs (ref_name, ref_type, target_commit_id)
VALUES ('main', 'branch', '00000000-0000-0000-0000-000000000000')
ON CONFLICT (ref_name) DO NOTHING;

-- ============================================
-- PART 2: Branch Management
-- ============================================

-- Create a new branch
CREATE OR REPLACE FUNCTION pggit.create_branch(
    p_branch_name TEXT,
    p_from_branch TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_source_commit_id UUID;
    v_source_branch TEXT;
BEGIN
    -- Validate branch name
    IF p_branch_name !~ '^[a-zA-Z0-9/_-]+$' THEN
        RAISE EXCEPTION 'Invalid branch name: %', p_branch_name;
    END IF;
    
    -- Check if branch already exists
    IF EXISTS (SELECT 1 FROM pggit.refs WHERE ref_name = p_branch_name) THEN
        RAISE EXCEPTION 'Branch % already exists', p_branch_name;
    END IF;
    
    -- Get source branch
    v_source_branch := COALESCE(p_from_branch, 
        (SELECT current_branch FROM pggit.HEAD LIMIT 1));
    
    -- Get commit to branch from
    SELECT target_commit_id INTO v_source_commit_id
    FROM pggit.refs
    WHERE ref_name = v_source_branch
    AND ref_type = 'branch';
    
    IF v_source_commit_id IS NULL THEN
        RAISE EXCEPTION 'Source branch % not found', v_source_branch;
    END IF;
    
    -- Create new branch
    INSERT INTO pggit.refs (ref_name, ref_type, target_commit_id)
    VALUES (p_branch_name, 'branch', v_source_commit_id);
    
    RETURN format('Created branch %s from %s at commit %s', 
        p_branch_name, v_source_branch, v_source_commit_id);
END;
$$ LANGUAGE plpgsql;

-- Checkout a branch
CREATE OR REPLACE FUNCTION pggit.checkout(
    p_branch_name TEXT,
    p_create_new BOOLEAN DEFAULT FALSE
) RETURNS TEXT AS $$
DECLARE
    v_commit_id UUID;
    v_old_branch TEXT;
    v_tree_hash TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_old_branch FROM pggit.HEAD;
    
    -- Create branch if requested
    IF p_create_new THEN
        PERFORM pggit.create_branch(p_branch_name);
    END IF;
    
    -- Verify branch exists
    SELECT target_commit_id INTO v_commit_id
    FROM pggit.refs
    WHERE ref_name = p_branch_name
    AND ref_type = 'branch';
    
    IF v_commit_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Get tree hash for this commit
    SELECT tree_hash INTO v_tree_hash
    FROM pggit.commits
    WHERE id = v_commit_id;
    
    -- Update HEAD
    UPDATE pggit.HEAD
    SET current_branch = p_branch_name,
        current_commit_id = v_commit_id;
    
    -- Apply schema state (in real implementation, would modify actual schema)
    PERFORM pggit.apply_tree_state(v_tree_hash);
    
    RETURN format('Switched to branch ''%s''', p_branch_name);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Commit System
-- ============================================

-- Stage changes (detect what's different from last commit)
CREATE OR REPLACE FUNCTION pggit.stage_changes()
RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    old_hash TEXT,
    new_hash TEXT
) AS $$
DECLARE
    v_last_commit_id UUID;
    v_last_tree_hash TEXT;
BEGIN
    -- Get last commit on current branch
    SELECT c.id, c.tree_hash INTO v_last_commit_id, v_last_tree_hash
    FROM pggit.HEAD h
    JOIN pggit.refs r ON r.ref_name = h.current_branch
    JOIN pggit.commits c ON c.id = r.target_commit_id
    LIMIT 1;
    
    -- Compare current schema state with last commit
    RETURN QUERY
    WITH current_state AS (
        SELECT 
            n.nspname || '.' || c.relname as object_name,
            'TABLE' as object_type,
            pggit.compute_ddl_hash('TABLE', n.nspname, c.relname) as object_hash
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pggit')
    ),
    last_state AS (
        SELECT 
            b.object_schema || '.' || b.object_name as object_name,
            b.blob_hash as object_hash
        FROM pggit.trees t
        JOIN pggit.blobs b ON b.blob_hash = ANY(t.schema_snapshot->>'blobs'::text[])
        WHERE t.tree_hash = v_last_tree_hash
    )
    SELECT 
        COALESCE(c.object_name, l.object_name),
        CASE 
            WHEN l.object_hash IS NULL THEN 'ADD'
            WHEN c.object_hash IS NULL THEN 'DELETE'
            WHEN c.object_hash != l.object_hash THEN 'MODIFY'
        END as change_type,
        l.object_hash,
        c.object_hash
    FROM current_state c
    FULL OUTER JOIN last_state l ON c.object_name = l.object_name
    WHERE c.object_hash IS DISTINCT FROM l.object_hash;
END;
$$ LANGUAGE plpgsql;

-- Create a commit
CREATE OR REPLACE FUNCTION pggit.commit(
    p_message TEXT
) RETURNS UUID AS $$
DECLARE
    v_commit_id UUID;
    v_parent_id UUID;
    v_tree_hash TEXT;
    v_branch_name TEXT;
    v_changes_count INTEGER;
BEGIN
    -- Check for changes
    SELECT COUNT(*) INTO v_changes_count FROM pggit.stage_changes();
    
    IF v_changes_count = 0 THEN
        RAISE NOTICE 'No changes to commit';
        RETURN NULL;
    END IF;
    
    -- Get current branch and parent commit
    SELECT h.current_branch, r.target_commit_id 
    INTO v_branch_name, v_parent_id
    FROM pggit.HEAD h
    JOIN pggit.refs r ON r.ref_name = h.current_branch;
    
    -- Create tree snapshot
    v_tree_hash := pggit.create_tree_snapshot();
    
    -- Create commit
    INSERT INTO pggit.commits (
        parent_id,
        tree_hash,
        message,
        branch_name
    ) VALUES (
        NULLIF(v_parent_id, '00000000-0000-0000-0000-000000000000'),
        v_tree_hash,
        p_message,
        v_branch_name
    ) RETURNING id INTO v_commit_id;
    
    -- Update branch pointer
    UPDATE pggit.refs
    SET target_commit_id = v_commit_id
    WHERE ref_name = v_branch_name;
    
    -- Update HEAD
    UPDATE pggit.HEAD
    SET current_commit_id = v_commit_id;
    
    RETURN v_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Create tree snapshot of current schema
CREATE OR REPLACE FUNCTION pggit.create_tree_snapshot()
RETURNS TEXT AS $$
DECLARE
    v_tree_data JSONB;
    v_tree_hash TEXT;
    v_blob_hashes TEXT[];
BEGIN
    -- Snapshot all objects
    WITH object_snapshots AS (
        SELECT 
            pggit.create_blob_for_object(
                c.relkind::text,
                n.nspname,
                c.relname
            ) as blob_hash
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pggit')
        AND c.relkind IN ('r', 'v', 'f', 'p')
    )
    SELECT array_agg(blob_hash) INTO v_blob_hashes
    FROM object_snapshots;
    
    -- Create tree structure
    v_tree_data := jsonb_build_object(
        'blobs', v_blob_hashes,
        'timestamp', CURRENT_TIMESTAMP,
        'object_count', array_length(v_blob_hashes, 1)
    );
    
    -- Generate tree hash
    v_tree_hash := encode(
        digest(v_tree_data::text, 'sha256'),
        'hex'
    );
    
    -- Store tree
    INSERT INTO pggit.trees (tree_hash, schema_snapshot, object_count)
    VALUES (v_tree_hash, v_tree_data, array_length(v_blob_hashes, 1))
    ON CONFLICT (tree_hash) DO NOTHING;
    
    RETURN v_tree_hash;
END;
$$ LANGUAGE plpgsql;

-- Create blob for individual object
CREATE OR REPLACE FUNCTION pggit.create_blob_for_object(
    p_object_kind TEXT,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_object_def TEXT;
    v_blob_hash TEXT;
    v_object_type pggit.object_type;
BEGIN
    -- Get object definition
    CASE p_object_kind
        WHEN 'r' THEN -- table
            v_object_type := 'TABLE';
            SELECT pggit.get_table_ddl(p_schema_name, p_object_name) 
            INTO v_object_def;
        WHEN 'v' THEN -- view
            v_object_type := 'VIEW';
            SELECT pg_get_viewdef(
                (p_schema_name || '.' || p_object_name)::regclass, true
            ) INTO v_object_def;
        WHEN 'f' THEN -- function
            v_object_type := 'FUNCTION';
            SELECT pg_get_functiondef(
                (p_schema_name || '.' || p_object_name)::regproc::oid
            ) INTO v_object_def;
        ELSE
            v_object_type := 'TABLE'; -- default
            v_object_def := '';
    END CASE;
    
    -- Generate blob hash
    v_blob_hash := encode(
        digest(
            p_schema_name || '.' || p_object_name || E'\n' || v_object_def,
            'sha256'
        ),
        'hex'
    );
    
    -- Store blob
    INSERT INTO pggit.blobs (
        blob_hash,
        object_type,
        object_schema,
        object_name,
        object_definition
    ) VALUES (
        v_blob_hash,
        v_object_type,
        p_schema_name,
        p_object_name,
        v_object_def
    ) ON CONFLICT (blob_hash) DO NOTHING;
    
    RETURN v_blob_hash;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Git Commands
-- ============================================

-- Git status
CREATE OR REPLACE FUNCTION pggit.status()
RETURNS TABLE (
    branch TEXT,
    changes_staged INTEGER,
    current_commit UUID,
    commit_message TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        h.current_branch,
        (SELECT COUNT(*)::INTEGER FROM pggit.stage_changes()),
        h.current_commit_id,
        c.message
    FROM pggit.HEAD h
    LEFT JOIN pggit.commits c ON c.id = h.current_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Git log
CREATE OR REPLACE FUNCTION pggit.log(
    p_limit INTEGER DEFAULT 10
) RETURNS TABLE (
    commit_id UUID,
    message TEXT,
    author TEXT,
    committed_at TIMESTAMP,
    parent_id UUID
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE commit_history AS (
        -- Start with current branch's HEAD
        SELECT c.*
        FROM pggit.commits c
        JOIN pggit.refs r ON r.target_commit_id = c.id
        JOIN pggit.HEAD h ON h.current_branch = r.ref_name
        
        UNION ALL
        
        -- Recursively get parents
        SELECT c.*
        FROM pggit.commits c
        JOIN commit_history ch ON c.id = ch.parent_id
    )
    SELECT 
        id,
        message,
        author,
        committed_at,
        parent_id
    FROM commit_history
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Git diff
CREATE OR REPLACE FUNCTION pggit.diff(
    p_from_commit UUID DEFAULT NULL,
    p_to_commit UUID DEFAULT NULL
) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    diff_text TEXT
) AS $$
BEGIN
    -- If no commits specified, diff working directory against HEAD
    IF p_from_commit IS NULL THEN
        SELECT current_commit_id INTO p_from_commit FROM pggit.HEAD;
    END IF;
    
    -- Implementation would generate actual diffs
    RETURN QUERY
    SELECT 
        s.object_name,
        s.change_type,
        format('Object %s was %s', s.object_name, s.change_type) as diff_text
    FROM pggit.stage_changes() s;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Helper Functions
-- ============================================

-- Get complete table DDL
CREATE OR REPLACE FUNCTION pggit.get_table_ddl(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_ddl TEXT;
BEGIN
    -- Get CREATE TABLE statement
    SELECT 'CREATE TABLE ' || p_schema_name || '.' || p_table_name || ' (' || E'\n' ||
           string_agg(
               '    ' || column_name || ' ' || 
               data_type || 
               CASE 
                   WHEN character_maximum_length IS NOT NULL 
                   THEN '(' || character_maximum_length || ')'
                   ELSE ''
               END ||
               CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END ||
               CASE WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default ELSE '' END,
               E',\n' ORDER BY ordinal_position
           ) || E'\n);'
    INTO v_ddl
    FROM information_schema.columns
    WHERE table_schema = p_schema_name
    AND table_name = p_table_name;
    
    RETURN v_ddl;
END;
$$ LANGUAGE plpgsql;

-- Apply tree state (ACTUAL implementation - transforms schema)
CREATE OR REPLACE FUNCTION pggit.apply_tree_state(
    p_tree_hash TEXT
) RETURNS TEXT AS $$
DECLARE
    v_tree_record RECORD;
    v_blob_record RECORD;
    v_current_schema TEXT;
    v_ddl_commands TEXT[];
    v_command TEXT;
    v_objects_processed INTEGER := 0;
BEGIN
    -- Get current working schema
    SELECT working_schema INTO v_current_schema FROM pggit.HEAD;
    
    -- Get tree data
    SELECT * INTO v_tree_record 
    FROM pggit.trees 
    WHERE tree_hash = p_tree_hash;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tree hash % not found', p_tree_hash;
    END IF;
    
    -- Collect DDL commands to execute
    v_ddl_commands := ARRAY[];
    
    -- Process each blob in the tree
    FOR v_blob_record IN 
        SELECT * FROM pggit.blobs 
        WHERE blob_hash = ANY(
            SELECT jsonb_array_elements_text(v_tree_record.schema_snapshot->'blobs')
        )
        ORDER BY 
            CASE object_type 
                WHEN 'TABLE' THEN 1
                WHEN 'INDEX' THEN 2
                WHEN 'VIEW' THEN 3
                WHEN 'FUNCTION' THEN 4
                ELSE 5
            END
    LOOP
        -- Check if object exists in current schema
        IF pggit.object_exists_in_schema(
            v_blob_record.object_type,
            v_current_schema, 
            v_blob_record.object_name
        ) THEN
            -- Object exists - check if it needs updating
            IF pggit.compute_ddl_hash(
                v_blob_record.object_type::text,
                v_current_schema,
                v_blob_record.object_name
            ) != v_blob_record.blob_hash THEN
                -- Object changed - generate ALTER or DROP/CREATE
                v_command := pggit.generate_update_ddl(
                    v_blob_record.object_type,
                    v_current_schema,
                    v_blob_record.object_name,
                    v_blob_record.object_definition
                );
                v_ddl_commands := v_ddl_commands || v_command;
            END IF;
        ELSE
            -- Object doesn't exist - create it
            v_command := replace(
                v_blob_record.object_definition,
                v_blob_record.object_schema || '.',
                v_current_schema || '.'
            );
            v_ddl_commands := v_ddl_commands || v_command;
        END IF;
        
        v_objects_processed := v_objects_processed + 1;
    END LOOP;
    
    -- Execute DDL commands
    FOREACH v_command IN ARRAY v_ddl_commands LOOP
        BEGIN
            EXECUTE v_command;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to execute DDL: %\nError: %', v_command, SQLERRM;
        END;
    END LOOP;
    
    RETURN format('Applied tree state %s: processed %s objects, executed %s DDL commands',
        p_tree_hash, v_objects_processed, array_length(v_ddl_commands, 1));
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Merge Implementation
-- ============================================

-- Find common ancestor (merge base) between two branches
CREATE OR REPLACE FUNCTION pggit.find_merge_base(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS UUID AS $$
DECLARE
    v_commit1 UUID;
    v_commit2 UUID;
    v_ancestors1 UUID[];
    v_ancestors2 UUID[];
    v_common UUID;
BEGIN
    -- Get current commits for both branches
    SELECT target_commit_id INTO v_commit1
    FROM pggit.refs WHERE ref_name = p_branch1;
    
    SELECT target_commit_id INTO v_commit2
    FROM pggit.refs WHERE ref_name = p_branch2;
    
    -- Find all ancestors of first branch
    WITH RECURSIVE ancestors AS (
        SELECT id, parent_id FROM pggit.commits WHERE id = v_commit1
        UNION ALL
        SELECT c.id, c.parent_id 
        FROM pggit.commits c
        JOIN ancestors a ON c.id = a.parent_id
    )
    SELECT array_agg(id) INTO v_ancestors1 FROM ancestors;
    
    -- Find all ancestors of second branch
    WITH RECURSIVE ancestors AS (
        SELECT id, parent_id FROM pggit.commits WHERE id = v_commit2
        UNION ALL
        SELECT c.id, c.parent_id 
        FROM pggit.commits c
        JOIN ancestors a ON c.id = a.parent_id
    )
    SELECT array_agg(id) INTO v_ancestors2 FROM ancestors;
    
    -- Find first common ancestor
    SELECT id INTO v_common
    FROM unnest(v_ancestors1) id
    WHERE id = ANY(v_ancestors2)
    LIMIT 1;
    
    RETURN v_common;
END;
$$ LANGUAGE plpgsql;

-- Three-way merge for schema objects
CREATE OR REPLACE FUNCTION pggit.three_way_merge(
    p_base_commit UUID,
    p_source_commit UUID,
    p_target_commit UUID
) RETURNS TABLE (
    object_name TEXT,
    action_type TEXT,
    conflict BOOLEAN,
    base_definition TEXT,
    source_definition TEXT,
    target_definition TEXT,
    merged_definition TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH base_objects AS (
        SELECT 
            b.object_schema || '.' || b.object_name as full_name,
            b.object_definition,
            b.blob_hash
        FROM pggit.commits c
        JOIN pggit.trees t ON t.tree_hash = c.tree_hash
        JOIN pggit.blobs b ON b.blob_hash = ANY(t.schema_snapshot->>'blobs'::text[])
        WHERE c.id = p_base_commit
    ),
    source_objects AS (
        SELECT 
            b.object_schema || '.' || b.object_name as full_name,
            b.object_definition,
            b.blob_hash
        FROM pggit.commits c
        JOIN pggit.trees t ON t.tree_hash = c.tree_hash
        JOIN pggit.blobs b ON b.blob_hash = ANY(t.schema_snapshot->>'blobs'::text[])
        WHERE c.id = p_source_commit
    ),
    target_objects AS (
        SELECT 
            b.object_schema || '.' || b.object_name as full_name,
            b.object_definition,
            b.blob_hash
        FROM pggit.commits c
        JOIN pggit.trees t ON t.tree_hash = c.tree_hash
        JOIN pggit.blobs b ON b.blob_hash = ANY(t.schema_snapshot->>'blobs'::text[])
        WHERE c.id = p_target_commit
    )
    SELECT 
        COALESCE(s.full_name, t.full_name, b.full_name),
        CASE
            -- No changes
            WHEN s.blob_hash = b.blob_hash AND t.blob_hash = b.blob_hash THEN 'no_change'
            -- Only changed in source
            WHEN s.blob_hash != b.blob_hash AND t.blob_hash = b.blob_hash THEN 'take_source'
            -- Only changed in target
            WHEN s.blob_hash = b.blob_hash AND t.blob_hash != b.blob_hash THEN 'take_target'
            -- Both changed same way
            WHEN s.blob_hash = t.blob_hash AND s.blob_hash != b.blob_hash THEN 'both_same'
            -- Conflict: both changed differently
            WHEN s.blob_hash != b.blob_hash AND t.blob_hash != b.blob_hash AND s.blob_hash != t.blob_hash THEN 'conflict'
            -- Added in source only
            WHEN b.full_name IS NULL AND t.full_name IS NULL THEN 'add_source'
            -- Added in target only
            WHEN b.full_name IS NULL AND s.full_name IS NULL THEN 'add_target'
            -- Deleted in source, modified in target
            WHEN s.full_name IS NULL AND t.blob_hash != b.blob_hash THEN 'delete_modify_conflict'
            -- Modified in source, deleted in target
            WHEN s.blob_hash != b.blob_hash AND t.full_name IS NULL THEN 'modify_delete_conflict'
            -- Deleted in both
            WHEN s.full_name IS NULL AND t.full_name IS NULL THEN 'both_deleted'
            ELSE 'unknown'
        END as action_type,
        CASE
            WHEN s.blob_hash != b.blob_hash AND t.blob_hash != b.blob_hash AND s.blob_hash != t.blob_hash THEN true
            WHEN s.full_name IS NULL AND t.blob_hash != b.blob_hash THEN true
            WHEN s.blob_hash != b.blob_hash AND t.full_name IS NULL THEN true
            ELSE false
        END as conflict,
        b.object_definition,
        s.object_definition,
        t.object_definition,
        -- Merged definition (null if conflict)
        CASE
            WHEN s.blob_hash != b.blob_hash AND t.blob_hash = b.blob_hash THEN s.object_definition
            WHEN s.blob_hash = b.blob_hash AND t.blob_hash != b.blob_hash THEN t.object_definition
            WHEN s.blob_hash = t.blob_hash THEN s.object_definition
            ELSE NULL
        END as merged_definition
    FROM base_objects b
    FULL OUTER JOIN source_objects s ON b.full_name = s.full_name
    FULL OUTER JOIN target_objects t ON COALESCE(b.full_name, s.full_name) = t.full_name
    WHERE 
        -- Exclude unchanged objects
        NOT (s.blob_hash = b.blob_hash AND t.blob_hash = b.blob_hash);
END;
$$ LANGUAGE plpgsql;

-- Merge two branches
CREATE OR REPLACE FUNCTION pggit.merge(
    p_source_branch TEXT,
    p_merge_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_target_branch TEXT;
    v_base_commit UUID;
    v_source_commit UUID;
    v_target_commit UUID;
    v_conflict_count INTEGER;
    v_merge_commit UUID;
    v_tree_hash TEXT;
    v_merge_msg TEXT;
BEGIN
    -- Get current branch as target
    v_target_branch := pggit.current_branch();
    IF v_target_branch IS NULL THEN
        RAISE EXCEPTION 'No branch checked out';
    END IF;
    
    IF v_target_branch = p_source_branch THEN
        RAISE EXCEPTION 'Cannot merge branch into itself';
    END IF;
    
    -- Get commits
    SELECT target_commit_id INTO v_source_commit
    FROM pggit.refs WHERE ref_name = p_source_branch;
    
    SELECT target_commit_id INTO v_target_commit
    FROM pggit.refs WHERE ref_name = v_target_branch;
    
    -- Find merge base
    v_base_commit := pggit.find_merge_base(p_source_branch, v_target_branch);
    
    IF v_base_commit IS NULL THEN
        RAISE EXCEPTION 'No common ancestor found between branches';
    END IF;
    
    -- Check if already up to date
    IF v_source_commit = v_target_commit THEN
        RAISE NOTICE 'Already up to date';
        RETURN v_target_commit;
    END IF;
    
    -- Check if fast-forward possible
    IF v_base_commit = v_target_commit THEN
        -- Fast-forward merge
        UPDATE pggit.refs
        SET target_commit_id = v_source_commit
        WHERE ref_name = v_target_branch;
        
        UPDATE pggit.HEAD
        SET current_commit_id = v_source_commit;
        
        RETURN v_source_commit;
    END IF;
    
    -- Perform three-way merge
    SELECT COUNT(*) INTO v_conflict_count
    FROM pggit.three_way_merge(v_base_commit, v_source_commit, v_target_commit)
    WHERE conflict = true;
    
    IF v_conflict_count > 0 THEN
        RAISE EXCEPTION 'Merge conflicts detected: % conflicts', v_conflict_count;
    END IF;
    
    -- Apply merged changes
    PERFORM pggit.apply_merge_result(
        v_base_commit, v_source_commit, v_target_commit
    );
    
    -- Create merge commit
    v_tree_hash := pggit.create_tree_snapshot();
    
    v_merge_msg := COALESCE(
        p_merge_message,
        format('Merge branch ''%s'' into ''%s''', p_source_branch, v_target_branch)
    );
    
    INSERT INTO pggit.commits (
        parent_id,
        tree_hash,
        message,
        branch_name,
        metadata
    ) VALUES (
        v_target_commit,
        v_tree_hash,
        v_merge_msg,
        v_target_branch,
        jsonb_build_object(
            'merge', true,
            'source_branch', p_source_branch,
            'source_commit', v_source_commit,
            'merge_base', v_base_commit
        )
    ) RETURNING id INTO v_merge_commit;
    
    -- Update branch pointer
    UPDATE pggit.refs
    SET target_commit_id = v_merge_commit
    WHERE ref_name = v_target_branch;
    
    UPDATE pggit.HEAD
    SET current_commit_id = v_merge_commit;
    
    RETURN v_merge_commit;
END;
$$ LANGUAGE plpgsql;

-- Apply merge results to current schema (ACTUAL implementation)
CREATE OR REPLACE FUNCTION pggit.apply_merge_result(
    p_base_commit UUID,
    p_source_commit UUID,
    p_target_commit UUID
) RETURNS TEXT AS $$
DECLARE
    v_action_type RECORD;
    v_current_schema TEXT;
    v_commands_executed INTEGER := 0;
    v_ddl_command TEXT;
BEGIN
    -- Get current working schema
    SELECT working_schema INTO v_current_schema FROM pggit.HEAD;
    
    -- Apply each merge action
    FOR v_action_type IN 
        SELECT * FROM pggit.three_way_merge(
            p_base_commit, p_source_commit, p_target_commit
        )
        WHERE conflict = false
        ORDER BY 
            CASE action_type
                WHEN 'add_source' THEN 1
                WHEN 'add_target' THEN 2
                WHEN 'take_source' THEN 3
                WHEN 'take_target' THEN 4
                WHEN 'both_deleted' THEN 5
                ELSE 6
            END
    LOOP
        CASE v_action_type.action_type
            WHEN 'take_source', 'add_source' THEN
                -- Apply source definition
                IF v_action_type.source_definition IS NOT NULL THEN
                    v_ddl_command := replace(
                        v_action_type.source_definition,
                        split_part(v_action_type.object_name, '.', 1) || '.',
                        v_current_schema || '.'
                    );
                    
                    BEGIN
                        EXECUTE v_ddl_command;
                        v_commands_executed := v_commands_executed + 1;
                        RAISE NOTICE 'Applied: % for %', 
                            v_action_type.action_type, v_action_type.object_name;
                    EXCEPTION WHEN OTHERS THEN
                        RAISE WARNING 'Failed to apply %: %\nError: %', 
                            v_action_type.object_name, v_ddl_command, SQLERRM;
                    END;
                END IF;
                
            WHEN 'take_target', 'add_target' THEN
                -- Apply target definition
                IF v_action_type.target_definition IS NOT NULL THEN
                    v_ddl_command := replace(
                        v_action_type.target_definition,
                        split_part(v_action_type.object_name, '.', 1) || '.',
                        v_current_schema || '.'
                    );
                    
                    BEGIN
                        EXECUTE v_ddl_command;
                        v_commands_executed := v_commands_executed + 1;
                        RAISE NOTICE 'Applied: % for %', 
                            v_action_type.action_type, v_action_type.object_name;
                    EXCEPTION WHEN OTHERS THEN
                        RAISE WARNING 'Failed to apply %: %\nError: %', 
                            v_action_type.object_name, v_ddl_command, SQLERRM;
                    END;
                END IF;
                
            WHEN 'both_deleted' THEN
                -- Drop the object if it exists
                v_ddl_command := format('DROP TABLE IF EXISTS %I.%I CASCADE',
                    v_current_schema, 
                    split_part(v_action_type.object_name, '.', 2)
                );
                
                BEGIN
                    EXECUTE v_ddl_command;
                    v_commands_executed := v_commands_executed + 1;
                    RAISE NOTICE 'Dropped: %', v_action_type.object_name;
                EXCEPTION WHEN OTHERS THEN
                    RAISE WARNING 'Failed to drop %: %', 
                        v_action_type.object_name, SQLERRM;
                END;
                
            ELSE
                RAISE NOTICE 'Skipping %: %', 
                    v_action_type.action_type, v_action_type.object_name;
        END CASE;
    END LOOP;
    
    RETURN format('Applied merge result: %s DDL commands executed', v_commands_executed);
END;
$$ LANGUAGE plpgsql;

-- Resolve merge conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    p_object_name TEXT,
    p_resolution TEXT -- 'ours', 'theirs', or actual DDL
) RETURNS void AS $$
BEGIN
    -- Store conflict resolution
    INSERT INTO pggit.conflict_resolutions (
        object_name,
        resolution_type,
        resolved_definition,
        resolved_by,
        resolved_at
    ) VALUES (
        p_object_name,
        CASE 
            WHEN p_resolution IN ('ours', 'theirs') THEN p_resolution
            ELSE 'manual'
        END,
        p_resolution,
        current_user,
        CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql;

-- Table for tracking conflict resolutions
CREATE TABLE IF NOT EXISTS pggit.conflict_resolutions (
    id SERIAL PRIMARY KEY,
    object_name TEXT NOT NULL,
    resolution_type TEXT CHECK (resolution_type IN ('ours', 'theirs', 'manual')),
    resolved_definition TEXT,
    resolved_by TEXT,
    resolved_at TIMESTAMP
);

-- ============================================
-- PART 7: Helper Functions for Real Implementation
-- ============================================

-- Check if object exists in schema
CREATE OR REPLACE FUNCTION pggit.object_exists_in_schema(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    CASE p_object_type
        WHEN 'TABLE' THEN
            RETURN EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = p_schema_name
                AND table_name = p_object_name
            );
        WHEN 'VIEW' THEN
            RETURN EXISTS (
                SELECT 1 FROM information_schema.views
                WHERE table_schema = p_schema_name
                AND table_name = p_object_name
            );
        WHEN 'FUNCTION' THEN
            RETURN EXISTS (
                SELECT 1 FROM information_schema.routines
                WHERE routine_schema = p_schema_name
                AND routine_name = p_object_name
            );
        WHEN 'INDEX' THEN
            RETURN EXISTS (
                SELECT 1 FROM pg_indexes
                WHERE schemaname = p_schema_name
                AND indexname = p_object_name
            );
        ELSE
            RETURN false;
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Generate UPDATE DDL for existing objects
CREATE OR REPLACE FUNCTION pggit.generate_update_ddl(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_target_definition TEXT
) RETURNS TEXT AS $$
DECLARE
    v_drop_ddl TEXT;
    v_create_ddl TEXT;
BEGIN
    -- For most objects, we drop and recreate
    -- (More sophisticated implementations would generate ALTER statements)
    
    CASE p_object_type
        WHEN 'TABLE' THEN
            v_drop_ddl := format('DROP TABLE IF EXISTS %I.%I CASCADE', 
                p_schema_name, p_object_name);
        WHEN 'VIEW' THEN
            v_drop_ddl := format('DROP VIEW IF EXISTS %I.%I CASCADE', 
                p_schema_name, p_object_name);
        WHEN 'FUNCTION' THEN
            v_drop_ddl := format('DROP FUNCTION IF EXISTS %I.%I CASCADE', 
                p_schema_name, p_object_name);
        WHEN 'INDEX' THEN
            v_drop_ddl := format('DROP INDEX IF EXISTS %I.%I', 
                p_schema_name, p_object_name);
        ELSE
            v_drop_ddl := format('-- Cannot handle object type %s', p_object_type);
    END CASE;
    
    -- Update schema references in target definition
    v_create_ddl := replace(
        p_target_definition,
        regexp_replace(p_target_definition, '^[^.]+\.', ''),
        p_schema_name || '.'
    );
    
    RETURN v_drop_ddl || '; ' || v_create_ddl;
END;
$$ LANGUAGE plpgsql;

-- Get current object definition for comparison
CREATE OR REPLACE FUNCTION pggit.get_current_object_definition(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_definition TEXT;
BEGIN
    CASE p_object_type
        WHEN 'TABLE' THEN
            v_definition := pggit.get_table_ddl(p_schema_name, p_object_name);
        WHEN 'VIEW' THEN
            SELECT pg_get_viewdef(
                (p_schema_name || '.' || p_object_name)::regclass, true
            ) INTO v_definition;
        WHEN 'FUNCTION' THEN
            SELECT pg_get_functiondef(
                (p_schema_name || '.' || p_object_name)::regproc::oid
            ) INTO v_definition;
        ELSE
            v_definition := '';
    END CASE;
    
    RETURN COALESCE(v_definition, '');
END;
$$ LANGUAGE plpgsql;

-- Enhanced checkout that actually applies schema changes
CREATE OR REPLACE FUNCTION pggit.checkout_with_apply(
    p_branch_name TEXT,
    p_create_new BOOLEAN DEFAULT FALSE
) RETURNS TEXT AS $$
DECLARE
    v_commit_id UUID;
    v_old_branch TEXT;
    v_tree_hash TEXT;
    v_apply_result TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_old_branch FROM pggit.HEAD;
    
    -- Create branch if requested
    IF p_create_new THEN
        PERFORM pggit.create_branch(p_branch_name);
    END IF;
    
    -- Verify branch exists
    SELECT target_commit_id INTO v_commit_id
    FROM pggit.refs
    WHERE ref_name = p_branch_name
    AND ref_type = 'branch';
    
    IF v_commit_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Get tree hash for this commit
    SELECT tree_hash INTO v_tree_hash
    FROM pggit.commits
    WHERE id = v_commit_id;
    
    -- Update HEAD first
    UPDATE pggit.HEAD
    SET current_branch = p_branch_name,
        current_commit_id = v_commit_id;
    
    -- Actually apply the schema state
    v_apply_result := pggit.apply_tree_state(v_tree_hash);
    
    RETURN format('Switched to branch ''%s''\n%s', p_branch_name, v_apply_result);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 8: Rollback and Reset Functionality
-- ============================================

-- Reset current branch to a specific commit (like git reset --hard)
CREATE OR REPLACE FUNCTION pggit.reset_hard(
    p_commit_id UUID
) RETURNS TEXT AS $$
DECLARE
    v_current_branch TEXT;
    v_tree_hash TEXT;
    v_apply_result TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_current_branch FROM pggit.HEAD;
    
    IF v_current_branch IS NULL THEN
        RAISE EXCEPTION 'No branch checked out';
    END IF;
    
    -- Verify commit exists
    SELECT tree_hash INTO v_tree_hash
    FROM pggit.commits
    WHERE id = p_commit_id;
    
    IF v_tree_hash IS NULL THEN
        RAISE EXCEPTION 'Commit % not found', p_commit_id;
    END IF;
    
    -- Update branch pointer
    UPDATE pggit.refs
    SET target_commit_id = p_commit_id
    WHERE ref_name = v_current_branch AND ref_type = 'branch';
    
    -- Update HEAD
    UPDATE pggit.HEAD
    SET current_commit_id = p_commit_id;
    
    -- Apply the schema state
    v_apply_result := pggit.apply_tree_state(v_tree_hash);
    
    RETURN format('Reset branch ''%s'' to commit %s\n%s', 
        v_current_branch, 
        substring(p_commit_id::text, 1, 8),
        v_apply_result
    );
END;
$$ LANGUAGE plpgsql;

-- Revert a specific commit (like git revert)
CREATE OR REPLACE FUNCTION pggit.revert_commit(
    p_commit_id UUID,
    p_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_parent_commit UUID;
    v_parent_tree_hash TEXT;
    v_revert_commit UUID;
    v_current_branch TEXT;
    v_message TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_current_branch FROM pggit.HEAD;
    
    -- Get parent commit to revert to
    SELECT parent_id INTO v_parent_commit
    FROM pggit.commits
    WHERE id = p_commit_id;
    
    IF v_parent_commit IS NULL THEN
        RAISE EXCEPTION 'Cannot revert initial commit or commit not found';
    END IF;
    
    -- Get parent tree
    SELECT tree_hash INTO v_parent_tree_hash
    FROM pggit.commits
    WHERE id = v_parent_commit;
    
    -- Apply parent state
    PERFORM pggit.apply_tree_state(v_parent_tree_hash);
    
    -- Create new tree snapshot of reverted state
    v_parent_tree_hash := pggit.create_tree_snapshot();
    
    -- Create revert commit
    v_message := COALESCE(
        p_message,
        format('Revert commit %s', substring(p_commit_id::text, 1, 8))
    );
    
    INSERT INTO pggit.commits (
        parent_id,
        tree_hash,
        message,
        branch_name,
        metadata
    ) VALUES (
        (SELECT current_commit_id FROM pggit.HEAD),
        v_parent_tree_hash,
        v_message,
        v_current_branch,
        jsonb_build_object(
            'revert', true,
            'reverted_commit', p_commit_id
        )
    ) RETURNING id INTO v_revert_commit;
    
    -- Update branch and HEAD
    UPDATE pggit.refs
    SET target_commit_id = v_revert_commit
    WHERE ref_name = v_current_branch AND ref_type = 'branch';
    
    UPDATE pggit.HEAD
    SET current_commit_id = v_revert_commit;
    
    RETURN v_revert_commit;
END;
$$ LANGUAGE plpgsql;

-- Show what would be reverted (dry run)
CREATE OR REPLACE FUNCTION pggit.show_revert_preview(
    p_commit_id UUID
) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    current_state TEXT,
    reverted_state TEXT
) AS $$
DECLARE
    v_parent_commit UUID;
BEGIN
    -- Get parent commit
    SELECT parent_id INTO v_parent_commit
    FROM pggit.commits
    WHERE id = p_commit_id;
    
    RETURN QUERY
    SELECT 
        COALESCE(current_obj.object_name, parent_obj.object_name),
        CASE 
            WHEN current_obj.object_name IS NULL THEN 'ADD'
            WHEN parent_obj.object_name IS NULL THEN 'REMOVE'
            ELSE 'MODIFY'
        END,
        current_obj.object_definition,
        parent_obj.object_definition
    FROM (
        SELECT 
            b.object_schema || '.' || b.object_name as object_name,
            b.object_definition
        FROM pggit.commits c
        JOIN pggit.trees t ON t.tree_hash = c.tree_hash
        JOIN pggit.blobs b ON b.blob_hash = ANY(
            SELECT jsonb_array_elements_text(t.schema_snapshot->'blobs')
        )
        WHERE c.id = p_commit_id
    ) current_obj
    FULL OUTER JOIN (
        SELECT 
            b.object_schema || '.' || b.object_name as object_name,
            b.object_definition
        FROM pggit.commits c
        JOIN pggit.trees t ON t.tree_hash = c.tree_hash
        JOIN pggit.blobs b ON b.blob_hash = ANY(
            SELECT jsonb_array_elements_text(t.schema_snapshot->'blobs')
        )
        WHERE c.id = v_parent_commit
    ) parent_obj ON current_obj.object_name = parent_obj.object_name
    WHERE current_obj.object_definition IS DISTINCT FROM parent_obj.object_definition;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 9: Git Aliases
-- ============================================

-- Convenience function: checkout -b
CREATE OR REPLACE FUNCTION pggit.checkout_b(
    p_branch_name TEXT
) RETURNS TEXT AS $$
BEGIN
    RETURN pggit.checkout(p_branch_name, true);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.create_branch IS 'Create a new Git branch';
COMMENT ON FUNCTION pggit.checkout IS 'Switch to a different branch';
COMMENT ON FUNCTION pggit.commit IS 'Create a new commit with current changes';
COMMENT ON FUNCTION pggit.status IS 'Show current branch and pending changes';
COMMENT ON FUNCTION pggit.log IS 'Show commit history';
COMMENT ON FUNCTION pggit.find_merge_base IS 'Find common ancestor between two branches';
COMMENT ON FUNCTION pggit.three_way_merge IS 'Perform three-way merge analysis';
COMMENT ON FUNCTION pggit.merge IS 'Merge a branch into current branch';
COMMENT ON FUNCTION pggit.apply_tree_state IS 'Apply schema state from tree hash (ACTUALLY modifies schema)';
COMMENT ON FUNCTION pggit.apply_merge_result IS 'Apply merge results to current schema (ACTUALLY executes DDL)';
COMMENT ON FUNCTION pggit.checkout_with_apply IS 'Checkout branch and apply schema changes';
COMMENT ON FUNCTION pggit.reset_hard IS 'Reset branch to commit and apply schema state';
COMMENT ON FUNCTION pggit.revert_commit IS 'Revert a commit and create new commit with reverted state';