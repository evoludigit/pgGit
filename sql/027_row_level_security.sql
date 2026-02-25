-- pgGit Row-Level Security for Multi-Tenancy
-- File: 027_row_level_security.sql
-- Purpose: Enable row-level security for multi-tenant deployments

-- ============================================================================
-- Add Tenant ID Columns to Core Tables
-- ============================================================================

-- Add tenant_id to branches table
ALTER TABLE pggit.branches 
ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_branches_tenant 
ON pggit.branches(tenant_id);

-- Add tenant_id to objects table
ALTER TABLE pggit.objects 
ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_objects_tenant 
ON pggit.objects(tenant_id);

-- Add tenant_id to history table
ALTER TABLE pggit.history 
ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_history_tenant 
ON pggit.history(tenant_id);

-- Add tenant_id to merge_history table
ALTER TABLE pggit.merge_history 
ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_merge_history_tenant 
ON pggit.merge_history(tenant_id);

-- ============================================================================
-- Enable Row-Level Security on Tables
-- ============================================================================

ALTER TABLE pggit.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.merge_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.commits ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Create RLS Policies
-- ============================================================================

-- Policy: Branch Isolation
CREATE POLICY branch_isolation ON pggit.branches
    FOR ALL
    USING (tenant_id = pggit_internal.get_current_tenant_id())
    WITH CHECK (tenant_id = pggit_internal.get_current_tenant_id());

COMMENT ON POLICY branch_isolation ON pggit.branches IS 
    'Users can only see and modify branches in their tenant';

-- Policy: Object Isolation
CREATE POLICY object_isolation ON pggit.objects
    FOR ALL
    USING (tenant_id = pggit_internal.get_current_tenant_id())
    WITH CHECK (tenant_id = pggit_internal.get_current_tenant_id());

COMMENT ON POLICY object_isolation ON pggit.objects IS 
    'Users can only see and modify objects in their tenant';

-- Policy: History Isolation
CREATE POLICY history_isolation ON pggit.history
    FOR ALL
    USING (
        tenant_id = pggit_internal.get_current_tenant_id()
        OR tenant_id IS NULL  -- Allow NULL tenant for system operations
    );

COMMENT ON POLICY history_isolation ON pggit.history IS 
    'Users can only see history for their tenant (or system history)';

-- Policy: Merge History Isolation
CREATE POLICY merge_history_isolation ON pggit.merge_history
    FOR ALL
    USING (tenant_id = pggit_internal.get_current_tenant_id())
    WITH CHECK (tenant_id = pggit_internal.get_current_tenant_id());

COMMENT ON POLICY merge_history_isolation ON pggit.merge_history IS 
    'Users can only see and modify merge history for their tenant';

-- Policy: Commit Isolation
CREATE POLICY commit_isolation ON pggit.commits
    FOR ALL
    USING (
        branch_id IN (
            SELECT id FROM pggit.branches 
            WHERE tenant_id = pggit_internal.get_current_tenant_id()
        )
    );

COMMENT ON POLICY commit_isolation ON pggit.commits IS 
    'Users can only see commits from branches in their tenant';

-- ============================================================================
-- Admin Bypass Policy (for administrative operations)
-- ============================================================================

-- Create a policy that allows admins to see all data
CREATE POLICY branch_admin_bypass ON pggit.branches
    FOR ALL
    TO PUBLIC
    USING (pg_has_role(current_user, 'pggit_admin', 'MEMBER'));

CREATE POLICY object_admin_bypass ON pggit.objects
    FOR ALL
    TO PUBLIC
    USING (pg_has_role(current_user, 'pggit_admin', 'MEMBER'));

CREATE POLICY history_admin_bypass ON pggit.history
    FOR ALL
    TO PUBLIC
    USING (pg_has_role(current_user, 'pggit_admin', 'MEMBER'));

-- ============================================================================
-- Functions for Tenant Management
-- ============================================================================

-- Function: Create tenant
CREATE OR REPLACE FUNCTION pggit.create_tenant(
    p_tenant_name TEXT,
    p_tenant_config JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
DECLARE
    v_tenant_id INTEGER;
BEGIN
    -- Generate new tenant ID (max existing + 1)
    SELECT COALESCE(max(tenant_id), 0) + 1 INTO v_tenant_id
    FROM (
        SELECT tenant_id FROM pggit.branches
        UNION
        SELECT tenant_id FROM pggit.objects
    ) all_tenants;
    
    -- Store tenant configuration
    INSERT INTO pggit_internal.config (config_key, config_value, config_type)
    VALUES (
        'tenant_' || v_tenant_id || '_config',
        p_tenant_config::TEXT,
        'json'
    )
    ON CONFLICT (config_key) DO UPDATE
    SET config_value = EXCLUDED.config_value;
    
    RAISE NOTICE 'Created tenant % with name "%"', v_tenant_id, p_tenant_name;
    
    RETURN v_tenant_id;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER;

COMMENT ON FUNCTION pggit.create_tenant IS 
    'Create a new tenant and return the tenant ID';

-- Function: Get tenant info
CREATE OR REPLACE FUNCTION pggit.get_tenant_info(
    p_tenant_id INTEGER
) RETURNS TABLE (
    tenant_id INTEGER,
    branch_count BIGINT,
    object_count BIGINT,
    config JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p_tenant_id,
        (SELECT count(*) FROM pggit.branches WHERE tenant_id = p_tenant_id),
        (SELECT count(*) FROM pggit.objects WHERE tenant_id = p_tenant_id),
        (
            SELECT config_value::JSONB 
            FROM pggit_internal.config 
            WHERE config_key = 'tenant_' || p_tenant_id || '_config'
        );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.get_tenant_info IS 
    'Get information about a specific tenant';

-- Function: List all tenants (admin only)
CREATE OR REPLACE FUNCTION pggit.list_tenants()
RETURNS TABLE (
    tenant_id INTEGER,
    branch_count BIGINT,
    object_count BIGINT
) AS $$
BEGIN
    -- Check if user is admin
    IF NOT pg_has_role(current_user, 'pggit_admin', 'MEMBER') THEN
        RAISE EXCEPTION 'Only administrators can list all tenants';
    END IF;
    
    RETURN QUERY
    SELECT 
        t.tenant_id,
        (SELECT count(*) FROM pggit.branches b WHERE b.tenant_id = t.tenant_id),
        (SELECT count(*) FROM pggit.objects o WHERE o.tenant_id = t.tenant_id)
    FROM (
        SELECT DISTINCT tenant_id FROM pggit.branches
    ) t
    ORDER BY t.tenant_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
STABLE;

COMMENT ON FUNCTION pggit.list_tenants IS 
    'List all tenants (admin only)';

-- ============================================================================
-- Create pggit_admin Role
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pggit_admin') THEN
        CREATE ROLE pggit_admin;
        RAISE NOTICE 'Created pggit_admin role';
    END IF;
END;
$$;

-- ============================================================================
-- Grant Permissions
-- ============================================================================

-- Allow all users to use RLS-protected tables
GRANT ALL ON pggit.branches TO PUBLIC;
GRANT ALL ON pggit.objects TO PUBLIC;
GRANT ALL ON pggit.history TO PUBLIC;
GRANT ALL ON pggit.merge_history TO PUBLIC;
GRANT ALL ON pggit.commits TO PUBLIC;

-- Grant admin role permissions
GRANT pggit_admin TO PUBLIC WITH ADMIN OPTION;

-- Grant tenant management functions
GRANT EXECUTE ON FUNCTION pggit.create_tenant(TEXT, JSONB) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_tenant_info(INTEGER) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.list_tenants() TO PUBLIC;
