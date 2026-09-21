-- pggit v1.0 — Row-Level Security Policies
-- Tenant isolation for multi-tenant deployments

-- ---------------------------------------------------------------------------
-- Enable RLS on all tenant-aware tables
-- ---------------------------------------------------------------------------

ALTER TABLE pggit.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.commits ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.merge_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.merge_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.tags ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Tenant Isolation Policies
-- Policy: Users can see rows where tenant_id matches their session tenant,
--         OR tenant_id is NULL (shared/admin rows)
-- ---------------------------------------------------------------------------

CREATE POLICY tenant_isolation ON pggit.branches
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.commits
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.objects
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.history
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.merge_history
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.merge_conflicts
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

CREATE POLICY tenant_isolation ON pggit.tags
    FOR ALL
    TO PUBLIC
    USING (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    )
    WITH CHECK (
        tenant_id IS NULL 
        OR tenant_id = pggit_internal.current_tenant_id()
    );

COMMENT ON POLICY tenant_isolation ON pggit.branches IS
    'Restrict access to rows matching the current session tenant_id, or shared rows (NULL).';
