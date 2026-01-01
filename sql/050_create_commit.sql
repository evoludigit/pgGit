-- Three-Way Merge Support: create_commit function
-- Minimal installation to support three-way merge tests

-- Create commit function for database versioning
CREATE OR REPLACE FUNCTION pggit.create_commit(
    p_branch_name TEXT,
    p_message TEXT,
    p_sql_content TEXT,
    p_parent_ids UUID[] DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_commit_id UUID;
    v_tree_hash TEXT;
    v_parent_hash TEXT;
    v_branch_id INTEGER;
    v_commit_hash TEXT;
BEGIN
    -- Validate inputs
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RAISE EXCEPTION 'Branch name cannot be NULL or empty';
    END IF;

    IF p_message IS NULL OR p_message = '' THEN
        RAISE EXCEPTION 'Commit message cannot be NULL or empty';
    END IF;

    -- Generate new commit ID and hash
    v_commit_id := gen_random_uuid();
    v_commit_hash := encode(sha256((p_message || COALESCE(p_sql_content, '') || CURRENT_TIMESTAMP::TEXT)::bytea), 'hex');

    -- Get branch ID
    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = p_branch_name;

    -- If branch doesn't exist, create it
    IF v_branch_id IS NULL THEN
        INSERT INTO pggit.branches (name, status, created_at)
        VALUES (p_branch_name, 'ACTIVE'::pggit.branch_status, CURRENT_TIMESTAMP)
        RETURNING id INTO v_branch_id;
    END IF;

    -- Create tree hash based on SQL content
    v_tree_hash := encode(sha256(p_sql_content::bytea), 'hex');

    -- Insert commit
    INSERT INTO pggit.commits (
        branch_id, message, author,
        authored_at, committer, committed_at, hash,
        tree_hash
    ) VALUES (
        v_branch_id, p_message, current_user,
        CURRENT_TIMESTAMP, current_user, CURRENT_TIMESTAMP, v_commit_hash,
        v_tree_hash
    );

    RETURN v_commit_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.create_commit(TEXT, TEXT, TEXT, UUID[]) IS
'Create a commit in a branch for three-way merge support';
