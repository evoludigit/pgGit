-- pgGit Three-Way Merge Implementation
-- Git-like merge functionality with conflict detection
-- Making the story real

-- =====================================================
-- Core Merge Tables
-- =====================================================

CREATE TABLE IF NOT EXISTS pggit.commits (
    commit_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    branch_name TEXT NOT NULL,
    parent_commit_id UUID,
    commit_message TEXT NOT NULL,
    commit_sql TEXT NOT NULL,
    author TEXT DEFAULT current_user,
    committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    merge_parent_id UUID, -- For merge commits
    FOREIGN KEY (parent_commit_id) REFERENCES pggit.commits(commit_id),
    FOREIGN KEY (merge_parent_id) REFERENCES pggit.commits(commit_id)
);

CREATE TABLE IF NOT EXISTS pggit.merge_conflicts (
    conflict_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source_branch TEXT NOT NULL,
    target_branch TEXT NOT NULL,
    base_commit_id UUID NOT NULL,
    conflict_type TEXT NOT NULL, -- 'schema', 'data', 'index', 'constraint'
    object_name TEXT NOT NULL,
    source_change TEXT,
    target_change TEXT,
    detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolution_status TEXT DEFAULT 'unresolved', -- 'unresolved', 'auto_resolved', 'manual_resolved'
    resolution_sql TEXT,
    resolved_by TEXT,
    resolved_at TIMESTAMP
);

-- =====================================================
-- Three-Way Merge Functions
-- =====================================================

-- Create a commit
CREATE OR REPLACE FUNCTION pggit.create_commit(
    p_branch_name TEXT,
    p_commit_message TEXT,
    p_commit_sql TEXT,
    p_parent_commit_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_commit_id UUID;
    v_parent_id UUID;
BEGIN
    -- Get parent commit if not specified
    IF p_parent_commit_id IS NULL THEN
        SELECT commit_id INTO v_parent_id
        FROM pggit.commits
        WHERE branch_name = p_branch_name
        ORDER BY committed_at DESC
        LIMIT 1;
    ELSE
        v_parent_id := p_parent_commit_id;
    END IF;
    
    -- Create commit
    INSERT INTO pggit.commits (branch_name, parent_commit_id, commit_message, commit_sql)
    VALUES (p_branch_name, v_parent_id, p_commit_message, p_commit_sql)
    RETURNING commit_id INTO v_commit_id;
    
    RETURN v_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Detect merge conflicts between branches
CREATE OR REPLACE FUNCTION pggit.detect_merge_conflicts(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_base_commit_id UUID
) RETURNS TABLE (
    has_conflicts BOOLEAN,
    conflict_count INT,
    conflict_details JSONB
) AS $$
DECLARE
    v_source_changes TEXT[];
    v_target_changes TEXT[];
    v_conflicts JSONB := '[]'::JSONB;
    v_has_conflicts BOOLEAN := false;
BEGIN
    -- Get all changes from base to source
    WITH source_commits AS (
        SELECT commit_sql
        FROM pggit.commits
        WHERE branch_name = p_source_branch
        AND committed_at > (SELECT committed_at FROM pggit.commits WHERE commit_id = p_base_commit_id)
        ORDER BY committed_at
    )
    SELECT array_agg(commit_sql) INTO v_source_changes FROM source_commits;
    
    -- Get all changes from base to target
    WITH target_commits AS (
        SELECT commit_sql
        FROM pggit.commits
        WHERE branch_name = p_target_branch
        AND committed_at > (SELECT committed_at FROM pggit.commits WHERE commit_id = p_base_commit_id)
        ORDER BY committed_at
    )
    SELECT array_agg(commit_sql) INTO v_target_changes FROM target_commits;
    
    -- Analyze changes for conflicts
    v_conflicts := pggit.analyze_sql_conflicts(v_source_changes, v_target_changes);
    v_has_conflicts := jsonb_array_length(v_conflicts) > 0;
    
    RETURN QUERY
    SELECT 
        v_has_conflicts,
        jsonb_array_length(v_conflicts)::INT,
        v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- Analyze SQL statements for conflicts
CREATE OR REPLACE FUNCTION pggit.analyze_sql_conflicts(
    p_source_changes TEXT[],
    p_target_changes TEXT[]
) RETURNS JSONB AS $$
DECLARE
    v_conflicts JSONB := '[]'::JSONB;
    v_source_sql TEXT;
    v_target_sql TEXT;
    v_source_parsed JSONB;
    v_target_parsed JSONB;
BEGIN
    -- Simple conflict detection based on SQL patterns
    FOREACH v_source_sql IN ARRAY p_source_changes LOOP
        v_source_parsed := pggit.parse_sql_statement(v_source_sql);
        
        FOREACH v_target_sql IN ARRAY p_target_changes LOOP
            v_target_parsed := pggit.parse_sql_statement(v_target_sql);
            
            -- Check if both modify same object
            IF v_source_parsed->>'object_name' = v_target_parsed->>'object_name' 
               AND v_source_parsed->>'operation' = v_target_parsed->>'operation' THEN
                
                -- Same object, same operation = conflict
                v_conflicts := v_conflicts || jsonb_build_object(
                    'type', 'schema_conflict',
                    'object', v_source_parsed->>'object_name',
                    'operation', v_source_parsed->>'operation',
                    'source_change', v_source_sql,
                    'target_change', v_target_sql
                );
                
            ELSIF v_source_parsed->>'object_name' = v_target_parsed->>'object_name'
                  AND v_source_parsed->>'operation' = 'DROP' THEN
                
                -- One branch drops, other modifies = conflict
                v_conflicts := v_conflicts || jsonb_build_object(
                    'type', 'drop_modify_conflict',
                    'object', v_source_parsed->>'object_name',
                    'source_change', v_source_sql,
                    'target_change', v_target_sql
                );
            END IF;
        END LOOP;
    END LOOP;
    
    RETURN v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- Parse SQL statement for conflict analysis
CREATE OR REPLACE FUNCTION pggit.parse_sql_statement(
    p_sql TEXT
) RETURNS JSONB AS $$
DECLARE
    v_sql_upper TEXT := UPPER(p_sql);
    v_result JSONB := '{}'::JSONB;
    v_object_name TEXT;
    v_operation TEXT;
BEGIN
    -- Determine operation type
    CASE
        WHEN v_sql_upper LIKE 'CREATE TABLE%' THEN
            v_operation := 'CREATE_TABLE';
            v_object_name := regexp_replace(p_sql, 'CREATE TABLE\s+(\S+).*', '\1', 'i');
            
        WHEN v_sql_upper LIKE 'ALTER TABLE%' THEN
            v_operation := 'ALTER_TABLE';
            v_object_name := regexp_replace(p_sql, 'ALTER TABLE\s+(\S+).*', '\1', 'i');
            
        WHEN v_sql_upper LIKE 'DROP TABLE%' THEN
            v_operation := 'DROP';
            v_object_name := regexp_replace(p_sql, 'DROP TABLE\s+(\S+).*', '\1', 'i');
            
        WHEN v_sql_upper LIKE 'CREATE INDEX%' THEN
            v_operation := 'CREATE_INDEX';
            v_object_name := regexp_replace(p_sql, 'CREATE INDEX\s+(\S+).*', '\1', 'i');
            
        WHEN v_sql_upper LIKE 'DROP INDEX%' THEN
            v_operation := 'DROP';
            v_object_name := regexp_replace(p_sql, 'DROP INDEX\s+(\S+).*', '\1', 'i');
            
        WHEN v_sql_upper LIKE 'UPDATE%' THEN
            v_operation := 'UPDATE';
            v_object_name := regexp_replace(p_sql, 'UPDATE\s+(\S+).*', '\1', 'i');
            
        ELSE
            v_operation := 'OTHER';
            v_object_name := 'unknown';
    END CASE;
    
    -- Extract additional details based on operation
    v_result := jsonb_build_object(
        'operation', v_operation,
        'object_name', lower(trim(v_object_name)),
        'sql', p_sql
    );
    
    -- Add column info for ALTER TABLE
    IF v_operation = 'ALTER_TABLE' THEN
        IF v_sql_upper LIKE '%ADD COLUMN%' THEN
            v_result := v_result || jsonb_build_object(
                'alter_type', 'ADD_COLUMN',
                'column_name', regexp_replace(p_sql, '.*ADD COLUMN\s+(\S+).*', '\1', 'i')
            );
        ELSIF v_sql_upper LIKE '%DROP COLUMN%' THEN
            v_result := v_result || jsonb_build_object(
                'alter_type', 'DROP_COLUMN',
                'column_name', regexp_replace(p_sql, '.*DROP COLUMN\s+(\S+).*', '\1', 'i')
            );
        ELSIF v_sql_upper LIKE '%ALTER COLUMN%' THEN
            v_result := v_result || jsonb_build_object(
                'alter_type', 'ALTER_COLUMN',
                'column_name', regexp_replace(p_sql, '.*ALTER COLUMN\s+(\S+).*', '\1', 'i')
            );
        END IF;
    END IF;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Merge branches with automatic resolution
CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_strategy TEXT DEFAULT 'auto', -- 'auto', 'manual', 'theirs', 'ours'
    p_commit_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_base_commit_id UUID;
    v_conflicts RECORD;
    v_merge_sql TEXT := '';
    v_merge_commit_id UUID;
    v_source_commits TEXT[];
    v_target_commits TEXT[];
BEGIN
    -- Find merge base (common ancestor)
    v_base_commit_id := pggit.find_merge_base(p_source_branch, p_target_branch);
    
    IF v_base_commit_id IS NULL THEN
        RAISE EXCEPTION 'No common ancestor found between branches % and %', 
            p_source_branch, p_target_branch;
    END IF;
    
    -- Detect conflicts
    SELECT * INTO v_conflicts 
    FROM pggit.detect_merge_conflicts(p_source_branch, p_target_branch, v_base_commit_id);
    
    IF v_conflicts.has_conflicts AND p_merge_strategy = 'auto' THEN
        RAISE EXCEPTION 'Cannot auto-merge: % conflicts detected', v_conflicts.conflict_count;
    END IF;
    
    -- Get all changes to merge
    SELECT array_agg(commit_sql ORDER BY committed_at) INTO v_source_commits
    FROM pggit.commits
    WHERE branch_name = p_source_branch
    AND committed_at > (SELECT committed_at FROM pggit.commits WHERE commit_id = v_base_commit_id);
    
    SELECT array_agg(commit_sql ORDER BY committed_at) INTO v_target_commits
    FROM pggit.commits
    WHERE branch_name = p_target_branch
    AND committed_at > (SELECT committed_at FROM pggit.commits WHERE commit_id = v_base_commit_id);
    
    -- Build merged SQL based on strategy
    CASE p_merge_strategy
        WHEN 'theirs' THEN
            v_merge_sql := array_to_string(v_source_commits, E';\n');
        WHEN 'ours' THEN
            v_merge_sql := array_to_string(v_target_commits, E';\n');
        ELSE -- 'auto' or 'manual'
            v_merge_sql := pggit.build_merged_sql(v_source_commits, v_target_commits, v_conflicts.conflict_details);
    END CASE;
    
    -- Create merge commit
    INSERT INTO pggit.commits (
        branch_name, 
        parent_commit_id,
        merge_parent_id,
        commit_message, 
        commit_sql
    )
    SELECT 
        p_target_branch,
        (SELECT commit_id FROM pggit.commits WHERE branch_name = p_target_branch ORDER BY committed_at DESC LIMIT 1),
        (SELECT commit_id FROM pggit.commits WHERE branch_name = p_source_branch ORDER BY committed_at DESC LIMIT 1),
        COALESCE(p_commit_message, format('Merge %s into %s', p_source_branch, p_target_branch)),
        v_merge_sql
    RETURNING commit_id INTO v_merge_commit_id;
    
    RETURN v_merge_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Find common ancestor commit
CREATE OR REPLACE FUNCTION pggit.find_merge_base(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS UUID AS $$
DECLARE
    v_base_commit_id UUID;
BEGIN
    -- Simple implementation: find latest common commit
    -- In real Git, this would use graph traversal
    WITH branch1_history AS (
        SELECT commit_id, parent_commit_id, committed_at
        FROM pggit.commits
        WHERE branch_name = p_branch1
    ),
    branch2_history AS (
        SELECT commit_id, parent_commit_id, committed_at
        FROM pggit.commits
        WHERE branch_name = p_branch2
    )
    SELECT b1.commit_id INTO v_base_commit_id
    FROM branch1_history b1
    JOIN branch2_history b2 ON b1.commit_id = b2.commit_id
    ORDER BY b1.committed_at DESC
    LIMIT 1;
    
    -- If no direct common commit, look for common parent
    IF v_base_commit_id IS NULL THEN
        -- This is simplified - real implementation would traverse full history
        SELECT commit_id INTO v_base_commit_id
        FROM pggit.commits
        WHERE branch_name IN (p_branch1, p_branch2)
        GROUP BY commit_id
        HAVING COUNT(DISTINCT branch_name) = 2
        ORDER BY MAX(committed_at) DESC
        LIMIT 1;
    END IF;
    
    RETURN v_base_commit_id;
END;
$$ LANGUAGE plpgsql;

-- Build merged SQL from changes
CREATE OR REPLACE FUNCTION pggit.build_merged_sql(
    p_source_changes TEXT[],
    p_target_changes TEXT[],
    p_conflicts JSONB
) RETURNS TEXT AS $$
DECLARE
    v_merged_sql TEXT := '';
    v_processed_objects TEXT[] := '{}';
    v_sql TEXT;
    v_parsed JSONB;
BEGIN
    -- Add all non-conflicting changes from both branches
    -- First, add target changes (base branch)
    FOREACH v_sql IN ARRAY p_target_changes LOOP
        v_parsed := pggit.parse_sql_statement(v_sql);
        IF NOT pggit.is_conflicted_change(v_parsed, p_conflicts) THEN
            v_merged_sql := v_merged_sql || v_sql || E';\n';
            v_processed_objects := array_append(v_processed_objects, v_parsed->>'object_name');
        END IF;
    END LOOP;
    
    -- Then add source changes that don't conflict
    FOREACH v_sql IN ARRAY p_source_changes LOOP
        v_parsed := pggit.parse_sql_statement(v_sql);
        IF NOT pggit.is_conflicted_change(v_parsed, p_conflicts) 
           AND NOT (v_parsed->>'object_name' = ANY(v_processed_objects)) THEN
            v_merged_sql := v_merged_sql || v_sql || E';\n';
        END IF;
    END LOOP;
    
    RETURN v_merged_sql;
END;
$$ LANGUAGE plpgsql;

-- Check if a change is part of a conflict
CREATE OR REPLACE FUNCTION pggit.is_conflicted_change(
    p_parsed_sql JSONB,
    p_conflicts JSONB
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM jsonb_array_elements(p_conflicts) c
        WHERE c->>'object' = p_parsed_sql->>'object_name'
    );
END;
$$ LANGUAGE plpgsql;

-- Analyze data conflicts in merge
CREATE OR REPLACE FUNCTION pggit.analyze_merge_data_conflicts(
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS TABLE (
    data_conflicts JSONB,
    affected_tables TEXT[]
) AS $$
DECLARE
    v_conflicts JSONB := '[]'::JSONB;
    v_tables TEXT[] := '{}';
BEGIN
    -- This is a placeholder for data conflict detection
    -- Real implementation would analyze UPDATE/DELETE statements
    -- and check for overlapping row modifications
    
    -- For now, return empty result
    RETURN QUERY
    SELECT v_conflicts, v_tables;
END;
$$ LANGUAGE plpgsql;

-- Generate merge plan for complex scenarios
CREATE OR REPLACE FUNCTION pggit.generate_merge_plan(
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS TABLE (
    merge_plan JSONB
) AS $$
DECLARE
    v_base_commit_id UUID;
    v_conflicts RECORD;
    v_plan JSONB;
BEGIN
    -- Find merge base
    v_base_commit_id := pggit.find_merge_base(p_source_branch, p_target_branch);
    
    -- Detect conflicts
    SELECT * INTO v_conflicts
    FROM pggit.detect_merge_conflicts(p_source_branch, p_target_branch, v_base_commit_id);
    
    -- Build merge plan
    v_plan := jsonb_build_object(
        'source_branch', p_source_branch,
        'target_branch', p_target_branch,
        'base_commit', v_base_commit_id,
        'has_conflicts', v_conflicts.has_conflicts,
        'conflict_count', v_conflicts.conflict_count,
        'conflicts', v_conflicts.conflict_details,
        'merge_strategy', CASE 
            WHEN v_conflicts.has_conflicts THEN 'manual'
            ELSE 'auto'
        END
    );
    
    RETURN QUERY SELECT v_plan;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for performance
-- Note: These indexes require columns that may not exist in base schema
-- CREATE INDEX IF NOT EXISTS idx_commits_branch_time 
-- ON pggit.commits(branch_name, committed_at DESC);

-- CREATE INDEX IF NOT EXISTS idx_commits_parent 
-- ON pggit.commits(parent_commit_id);

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_branches 
ON pggit.merge_conflicts(source_branch, target_branch);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;