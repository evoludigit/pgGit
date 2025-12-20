-- Chaos Engineering: Core pggit functions implementation
-- Phase 2-GREEN: Implement missing functions identified in RED phase

-- Function: pggit.commit_changes
-- Creates a commit record with the given Trinity ID
-- Parameters:
--   p_trinity_id: Unique commit identifier (hash)
--   p_branch_name: Branch name to commit to
--   p_message: Commit message
-- Returns: The Trinity ID that was committed

CREATE OR REPLACE FUNCTION pggit.commit_changes(
    p_trinity_id TEXT,
    p_branch_name TEXT,
    p_message TEXT DEFAULT ''
) RETURNS TEXT AS $$
DECLARE
    v_branch_id INTEGER;
BEGIN
    -- Look up branch ID by name
    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = p_branch_name AND status = 'ACTIVE';

    -- If branch doesn't exist, create it
    IF v_branch_id IS NULL THEN
        INSERT INTO pggit.branches (name, parent_branch_id, head_commit_hash)
        VALUES (p_branch_name, (SELECT id FROM pggit.branches WHERE name = 'main'), NULL)
        RETURNING id INTO v_branch_id;
    END IF;

    -- Insert commit record
    INSERT INTO pggit.commits (
        hash,
        branch_id,
        message,
        committed_at
    ) VALUES (
        p_trinity_id,
        v_branch_id,
        p_message,
        CURRENT_TIMESTAMP
    );

    -- Return the Trinity ID
    RETURN p_trinity_id;

EXCEPTION
    WHEN unique_violation THEN
        -- Commit with this Trinity ID already exists
        RETURN p_trinity_id;
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to create commit: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: pggit.create_data_branch
-- Creates a data branch (copy-on-write) of a table
-- Parameters:
--   p_table_name: Name of the table to branch
--   p_from_branch: Source branch (currently ignored, assumes 'main')
--   p_to_branch: Target branch name
-- Returns: Branch table name created

CREATE OR REPLACE FUNCTION pggit.create_data_branch(
    p_table_name TEXT,
    p_from_branch TEXT,
    p_to_branch TEXT
) RETURNS TEXT AS $$
DECLARE
    v_branch_table_name TEXT;
BEGIN
    -- Create branch table name: table__branch
    v_branch_table_name := p_table_name || '__' || p_to_branch;

    -- Create branch table as a copy of the original table
    -- Use inheritance for copy-on-write semantics
    EXECUTE format(
        'CREATE TABLE %I (LIKE %I INCLUDING ALL) INHERITS (%I)',
        v_branch_table_name,
        p_table_name,
        p_table_name
    );

    -- Return the branch table name
    RETURN v_branch_table_name;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to create data branch: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;