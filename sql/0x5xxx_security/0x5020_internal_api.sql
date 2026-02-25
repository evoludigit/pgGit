-- pgGit Internal Schema and API Organization
-- File: 026_internal_schema.sql
-- Purpose: Separate public API from internal implementation details

-- ============================================================================
-- Create Internal Schema
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pggit_internal;

COMMENT ON SCHEMA pggit_internal IS 
    'Internal implementation details for pgGit. 
     Functions and objects in this schema are not part of the public API
     and may change without notice. Do not use directly.';

-- ============================================================================
-- Move Internal Helper Functions to pggit_internal Schema
-- ============================================================================

-- Function: Extract table columns (internal)
CREATE OR REPLACE FUNCTION pggit_internal.extract_table_columns(
    p_schema_name TEXT,
    p_table_name TEXT
) RETURNS JSONB AS $$
DECLARE
    v_columns JSONB;
BEGIN
    SELECT jsonb_object_agg(
        column_name,
        jsonb_build_object(
            'type', udt_name || 
                CASE 
                    WHEN character_maximum_length IS NOT NULL 
                    THEN '(' || character_maximum_length || ')'
                    ELSE ''
                END,
            'nullable', is_nullable = 'YES',
            'default', column_default,
            'position', ordinal_position
        )
    ) INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = p_schema_name
    AND table_name = p_table_name;
    
    RETURN COALESCE(v_columns, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql
STABLE
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.extract_table_columns IS 
    'Internal: Extract column metadata from a table';

-- Function: Normalize DDL text (internal)
CREATE OR REPLACE FUNCTION pggit_internal.normalize_ddl(
    p_ddl_text TEXT
) RETURNS TEXT AS $$
BEGIN
    -- Remove extra whitespace
    RETURN regexp_replace(
        regexp_replace(p_ddl_text, '\s+', ' ', 'g'),
        '^\s+|\s+$', '', 'g'
    );
END;
$$ LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.normalize_ddl IS 
    'Internal: Normalize DDL text for consistent hashing';

-- Function: Compute hash (internal)
CREATE OR REPLACE FUNCTION pggit_internal.compute_hash(
    p_content TEXT
) RETURNS TEXT AS $$
BEGIN
    RETURN encode(sha256(p_content::bytea), 'hex');
END;
$$ LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.compute_hash IS 
    'Internal: Compute SHA-256 hash of content';

-- Function: Validate branch name (internal)
CREATE OR REPLACE FUNCTION pggit_internal.validate_branch_name(
    p_branch_name TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Check for NULL or empty
    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RETURN false;
    END IF;
    
    -- Check length (max 255)
    IF length(p_branch_name) > 255 THEN
        RETURN false;
    END IF;
    
    -- Check for valid characters (alphanumeric, underscore, hyphen, dot)
    IF p_branch_name !~ '^[a-zA-Z0-9_\-\.]+$' THEN
        RETURN false;
    END IF;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.validate_branch_name IS 
    'Internal: Validate branch name format';

-- Function: Get object dependencies (internal)
CREATE OR REPLACE FUNCTION pggit_internal.get_object_dependencies(
    p_object_id INTEGER
) RETURNS TABLE (
    dependency_type TEXT,
    dependent_object_id INTEGER,
    dependency_details JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.dependency_type::TEXT,
        d.dependent_id,
        jsonb_build_object(
            'object_type', o.object_type,
            'full_name', o.full_name
        )
    FROM pggit.dependencies d
    JOIN pggit.objects o ON d.dependent_id = o.id
    WHERE d.depends_on_id = p_object_id;
END;
$$ LANGUAGE plpgsql
STABLE
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.get_object_dependencies IS 
    'Internal: Get objects that depend on the specified object';

-- Function: Log audit event (internal)
CREATE OR REPLACE FUNCTION pggit_internal.log_audit_event(
    p_event_type TEXT,
    p_event_details JSONB,
    p_user_name TEXT DEFAULT current_user
) RETURNS BIGINT AS $$
DECLARE
    v_log_id BIGINT;
BEGIN
    -- Note: This assumes an audit_log table exists
    -- If not, this function can be a no-op or create the table
    
    -- For now, we'll log to a simple table if it exists
    BEGIN
        INSERT INTO pggit_internal.audit_log (event_type, event_details, user_name)
        VALUES (p_event_type, p_event_details, p_user_name)
        RETURNING log_id INTO v_log_id;
    EXCEPTION
        WHEN undefined_table THEN
            -- Audit log table doesn't exist, just return 0
            v_log_id := 0;
    END;
    
    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER;

COMMENT ON FUNCTION pggit_internal.log_audit_event IS 
    'Internal: Log audit events for security and compliance';

-- ============================================================================
-- Create Audit Log Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit_internal.audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    event_details JSONB,
    user_name TEXT DEFAULT current_user,
    client_addr INET DEFAULT inet_client_addr(),
    session_id TEXT DEFAULT pg_backend_pid()::TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_log_type 
ON pggit_internal.audit_log(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_user 
ON pggit_internal.audit_log(user_name, created_at DESC);

COMMENT ON TABLE pggit_internal.audit_log IS 
    'Internal audit trail for security and compliance tracking';

-- ============================================================================
-- Internal Configuration and State Management
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit_internal.config (
    config_key TEXT PRIMARY KEY,
    config_value TEXT,
    config_type TEXT DEFAULT 'string' CHECK (config_type IN ('string', 'integer', 'boolean', 'json')),
    is_sensitive BOOLEAN DEFAULT false,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by TEXT DEFAULT current_user
);

COMMENT ON TABLE pggit_internal.config IS 
    'Internal configuration storage for pgGit system settings';

-- Function: Get internal config (internal)
CREATE OR REPLACE FUNCTION pggit_internal.get_config(
    p_key TEXT,
    p_default_value TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_value TEXT;
BEGIN
    SELECT config_value INTO v_value
    FROM pggit_internal.config
    WHERE config_key = p_key;
    
    RETURN COALESCE(v_value, p_default_value);
END;
$$ LANGUAGE plpgsql
STABLE
SECURITY INVOKER;

-- Function: Set internal config (internal)
CREATE OR REPLACE FUNCTION pggit_internal.set_config(
    p_key TEXT,
    p_value TEXT,
    p_config_type TEXT DEFAULT 'string'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit_internal.config (config_key, config_value, config_type, updated_by)
    VALUES (p_key, p_value, p_config_type, current_user)
    ON CONFLICT (config_key) DO UPDATE
    SET config_value = EXCLUDED.config_value,
        config_type = EXCLUDED.config_type,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = current_user;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER;

-- ============================================================================
-- Internal Utility Functions
-- ============================================================================

-- Function: Generate unique ID (internal)
CREATE OR REPLACE FUNCTION pggit_internal.generate_uuid()
RETURNS UUID AS $$
BEGIN
    RETURN gen_random_uuid();
END;
$$ LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER;

-- Function: Get current tenant ID (for multi-tenancy support)
CREATE OR REPLACE FUNCTION pggit_internal.get_current_tenant_id()
RETURNS INTEGER AS $$
BEGIN
    -- This can be customized based on your multi-tenancy strategy
    -- For now, return a default or from session variable
    RETURN COALESCE(
        current_setting('pggit.tenant_id', true)::INTEGER,
        1  -- Default tenant
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN 1;
END;
$$ LANGUAGE plpgsql
STABLE
SECURITY INVOKER;

-- Function: Set current tenant ID
CREATE OR REPLACE FUNCTION pggit_internal.set_current_tenant_id(
    p_tenant_id INTEGER
) RETURNS VOID AS $$
BEGIN
    PERFORM set_config('pggit.tenant_id', p_tenant_id::TEXT, false);
END;
$$ LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER;

-- ============================================================================
-- Performance and Caching (Internal)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit_internal.cache (
    cache_key TEXT PRIMARY KEY,
    cache_value JSONB,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cache_expires 
ON pggit_internal.cache(expires_at);

-- Function: Get from cache (internal)
CREATE OR REPLACE FUNCTION pggit_internal.cache_get(
    p_key TEXT
) RETURNS JSONB AS $$
BEGIN
    RETURN (
        SELECT cache_value 
        FROM pggit_internal.cache 
        WHERE cache_key = p_key 
        AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
    );
END;
$$ LANGUAGE plpgsql
STABLE
SECURITY INVOKER;

-- Function: Set cache (internal)
CREATE OR REPLACE FUNCTION pggit_internal.cache_set(
    p_key TEXT,
    p_value JSONB,
    p_ttl_seconds INTEGER DEFAULT 3600
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit_internal.cache (cache_key, cache_value, expires_at)
    VALUES (p_key, p_value, CURRENT_TIMESTAMP + (p_ttl_seconds || ' seconds')::INTERVAL)
    ON CONFLICT (cache_key) DO UPDATE
    SET cache_value = EXCLUDED.cache_value,
        expires_at = EXCLUDED.expires_at;
END;
$$ LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER;

-- Function: Clear expired cache (internal)
CREATE OR REPLACE FUNCTION pggit_internal.cache_clear_expired()
RETURNS INTEGER AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM pggit_internal.cache WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER;

-- ============================================================================
-- Grant Permissions on Internal Schema
-- ============================================================================

-- Internal schema should not be directly accessed by users
-- Only functions in pggit schema should access pggit_internal

-- Grant usage to public (required for functions to work)
GRANT USAGE ON SCHEMA pggit_internal TO PUBLIC;

-- But restrict direct table access
REVOKE ALL ON ALL TABLES IN SCHEMA pggit_internal FROM PUBLIC;

-- Grant access to specific internal functions that might be needed
GRANT EXECUTE ON FUNCTION pggit_internal.get_current_tenant_id() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit_internal.validate_branch_name(TEXT) TO PUBLIC;
