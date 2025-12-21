-- pgGit Conflict Resolution - Minimal Implementation
-- Provides conflict tracking and resolution API

-- Table to track conflicts
CREATE TABLE IF NOT EXISTS pggit.conflict_registry (
    conflict_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conflict_type text NOT NULL CHECK (conflict_type IN ('merge', 'version', 'constraint', 'dependency')),
    object_type text,
    object_identifier text,
    branch1_name text,
    branch2_name text,
    conflict_data jsonb,
    status text DEFAULT 'unresolved' CHECK (status IN ('unresolved', 'resolved', 'ignored')),
    created_at timestamptz DEFAULT now(),
    resolved_at timestamptz,
    resolved_by text,
    resolution_type text,
    resolution_reason text
);

-- Function to register a conflict
CREATE OR REPLACE FUNCTION pggit.register_conflict(
    conflict_type text,
    object_type text,
    object_identifier text,
    conflict_data jsonb DEFAULT '{}'::jsonb
) RETURNS uuid AS $$
DECLARE
    conflict_id uuid;
BEGIN
    INSERT INTO pggit.conflict_registry (
        conflict_type,
        object_type,
        object_identifier,
        conflict_data
    ) VALUES (
        conflict_type,
        object_type,
        object_identifier,
        conflict_data
    ) RETURNING conflict_registry.conflict_id INTO conflict_id;

    RETURN conflict_id;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve a conflict
CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    conflict_id uuid,
    resolution text,
    reason text DEFAULT NULL,
    custom_resolution jsonb DEFAULT NULL
) RETURNS void AS $$
BEGIN
    -- Update conflict record to resolved
    UPDATE pggit.conflict_registry
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = current_user,
        resolution_type = resolution,
        resolution_reason = reason
    WHERE conflict_registry.conflict_id = resolve_conflict.conflict_id;
END;
$$ LANGUAGE plpgsql;

-- View for recent conflicts
CREATE OR REPLACE VIEW pggit.recent_conflicts AS
SELECT
    conflict_id,
    conflict_type,
    object_identifier,
    status,
    created_at
FROM pggit.conflict_registry
ORDER BY created_at DESC
LIMIT 50;
