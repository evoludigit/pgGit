-- pgGit v0.0.1 - Phase 1: Utility Functions
-- Helper functions used by other phases
-- Date: 2025-12-24

-- 1. generate_sha256() - Hash content for content-addressable storage
-- Usage: SELECT pggit.generate_sha256('some_content');
CREATE OR REPLACE FUNCTION pggit.generate_sha256(content TEXT)
RETURNS CHAR(64) AS $$
BEGIN
    RETURN encode(digest(content, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- 2. get_current_branch() - Get the currently checked-out branch
-- Usage: SELECT pggit.get_current_branch();
CREATE OR REPLACE FUNCTION pggit.get_current_branch()
RETURNS TEXT AS $$
DECLARE
    v_branch_name TEXT;
BEGIN
    -- Get current branch from session variable, default to 'main'
    v_branch_name := current_setting('pggit.current_branch', true);

    IF v_branch_name IS NULL THEN
        v_branch_name := 'main';
    END IF;

    RETURN v_branch_name;
EXCEPTION WHEN OTHERS THEN
    -- If session variable not set, return main
    RETURN 'main';
END;
$$ LANGUAGE plpgsql;

-- 3. validate_identifier() - Validate PostgreSQL identifier
-- Usage: SELECT pggit.validate_identifier('my_table'); -- true
-- Usage: SELECT pggit.validate_identifier('123_invalid'); -- false
CREATE OR REPLACE FUNCTION pggit.validate_identifier(identifier TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- PostgreSQL identifiers:
    -- - Must start with letter (a-z, A-Z, _) or non-ASCII
    -- - Can contain letters, digits (0-9), underscores, non-ASCII
    -- - Max 63 bytes
    -- - Case-insensitive (unless quoted)

    IF identifier IS NULL OR identifier = '' THEN
        RETURN false;
    END IF;

    IF length(identifier) > 63 THEN
        RETURN false;
    END IF;

    -- Check first character - must be letter or underscore
    IF NOT (substring(identifier, 1, 1) ~ '^[a-zA-Z_]$') THEN
        RETURN false;
    END IF;

    -- Check remaining characters - must be alphanumeric or underscore
    IF NOT (identifier ~ '^[a-zA-Z_][a-zA-Z0-9_]*$') THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- 4. raise_pggit_error() - Raise pgGit-specific error with code
-- Usage: SELECT pggit.raise_pggit_error('INVALID_BRANCH', 'Branch not found');
CREATE OR REPLACE FUNCTION pggit.raise_pggit_error(
    error_code TEXT,
    error_message TEXT
)
RETURNS VOID AS $$
DECLARE
    v_full_message TEXT;
BEGIN
    -- Format: [PGGIT-{code}] {message}
    v_full_message := format('[PGGIT-%s] %s', error_code, error_message);

    -- Raise exception
    RAISE EXCEPTION '%', v_full_message;
END;
$$ LANGUAGE plpgsql;

-- 5. set_current_branch() - Set the current branch in session
-- Usage: SELECT pggit.set_current_branch('feature/new-branch');
CREATE OR REPLACE FUNCTION pggit.set_current_branch(p_branch_name TEXT)
RETURNS VOID AS $$
BEGIN
    -- Validate branch exists
    IF NOT EXISTS (SELECT 1 FROM pggit.branches b WHERE b.branch_name = p_branch_name) THEN
        PERFORM pggit.raise_pggit_error('BRANCH_NOT_FOUND', format('Branch "%s" does not exist', p_branch_name));
    END IF;

    -- Set session variable
    EXECUTE format('SET pggit.current_branch = %L', p_branch_name);
END;
$$ LANGUAGE plpgsql;

-- 6. get_current_schema_hash() - Get hash of all current schema objects
-- Usage: SELECT pggit.get_current_schema_hash();
CREATE OR REPLACE FUNCTION pggit.get_current_schema_hash()
RETURNS CHAR(64) AS $$
DECLARE
    v_combined_hash TEXT;
    v_object_hashes TEXT;
BEGIN
    -- Combine all object hashes (sorted by object_id for consistency)
    SELECT string_agg(content_hash, '' ORDER BY object_id)
    INTO v_object_hashes
    FROM pggit.schema_objects
    WHERE is_active = true;

    -- If no objects, return hash of empty string
    IF v_object_hashes IS NULL THEN
        v_object_hashes := '';
    END IF;

    -- Return hash of combined hashes
    RETURN pggit.generate_sha256(v_object_hashes);
END;
$$ LANGUAGE plpgsql;

-- 7. normalize_sql() - Normalize SQL for consistent hashing
-- Usage: SELECT pggit.normalize_sql(ddl_text);
CREATE OR REPLACE FUNCTION pggit.normalize_sql(sql_text TEXT)
RETURNS TEXT AS $$
BEGIN
    -- Remove leading/trailing whitespace
    sql_text := trim(sql_text);

    -- Collapse multiple spaces to single space
    sql_text := regexp_replace(sql_text, '\s+', ' ', 'g');

    -- Remove trailing semicolon if present
    sql_text := rtrim(sql_text, ';');

    RETURN sql_text;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- 8. get_object_by_name() - Get object_id by type and name
-- Usage: SELECT pggit.get_object_by_name('TABLE', 'public', 'users');
CREATE OR REPLACE FUNCTION pggit.get_object_by_name(
    p_object_type TEXT,
    p_schema_name TEXT,
    p_object_name TEXT
)
RETURNS BIGINT AS $$
DECLARE
    v_object_id BIGINT;
BEGIN
    SELECT object_id
    INTO v_object_id
    FROM pggit.schema_objects
    WHERE object_type = p_object_type
      AND schema_name = p_schema_name
      AND object_name = p_object_name
      AND is_active = true
    LIMIT 1;

    RETURN v_object_id;
END;
$$ LANGUAGE plpgsql;

-- 9. get_commit_by_hash() - Get commit_id by commit hash
-- Usage: SELECT pggit.get_commit_by_hash('abc123...');
CREATE OR REPLACE FUNCTION pggit.get_commit_by_hash(p_commit_hash CHAR(64))
RETURNS BIGINT AS $$
DECLARE
    v_commit_id BIGINT;
BEGIN
    SELECT c.commit_id
    INTO v_commit_id
    FROM pggit.commits c
    WHERE c.commit_hash = p_commit_hash
    LIMIT 1;

    RETURN v_commit_id;
END;
$$ LANGUAGE plpgsql;

-- 10. get_branch_by_name() - Get branch_id by branch name
-- Usage: SELECT pggit.get_branch_by_name('main');
CREATE OR REPLACE FUNCTION pggit.get_branch_by_name(p_branch_name TEXT)
RETURNS INTEGER AS $$
DECLARE
    v_branch_id INTEGER;
BEGIN
    SELECT b.branch_id
    INTO v_branch_id
    FROM pggit.branches b
    WHERE b.branch_name = p_branch_name
    LIMIT 1;

    RETURN v_branch_id;
END;
$$ LANGUAGE plpgsql;
