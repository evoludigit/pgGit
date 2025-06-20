-- pgGit User-Friendly Conflict Resolution API
-- Provides easy-to-use functions for resolving conflicts

-- Table to track conflicts for easy resolution
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

-- Main conflict resolution function
CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    conflict_id uuid,
    resolution text, -- 'use_current', 'use_tracked', 'merge', 'custom'
    reason text DEFAULT NULL,
    custom_resolution jsonb DEFAULT NULL
) RETURNS void AS $$
DECLARE
    conflict_record record;
BEGIN
    -- Get conflict details
    SELECT * INTO conflict_record
    FROM pggit.conflict_registry
    WHERE conflict_registry.conflict_id = resolve_conflict.conflict_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conflict % not found', conflict_id;
    END IF;
    
    IF conflict_record.status = 'resolved' THEN
        RAISE EXCEPTION 'Conflict % already resolved', conflict_id;
    END IF;
    
    -- Apply resolution based on type
    CASE conflict_record.conflict_type
        WHEN 'merge' THEN
            PERFORM pggit.resolve_merge_conflict(conflict_record, resolution, custom_resolution);
        WHEN 'version' THEN
            PERFORM pggit.resolve_version_conflict(conflict_record, resolution);
        WHEN 'constraint' THEN
            PERFORM pggit.resolve_constraint_conflict(conflict_record, resolution);
        WHEN 'dependency' THEN
            PERFORM pggit.resolve_dependency_conflict(conflict_record, resolution);
    END CASE;
    
    -- Update conflict record
    UPDATE pggit.conflict_registry
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = current_user,
        resolution_type = resolution,
        resolution_reason = reason
    WHERE conflict_registry.conflict_id = resolve_conflict.conflict_id;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve merge conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_merge_conflict(
    conflict_record record,
    resolution text,
    custom_resolution jsonb DEFAULT NULL
) RETURNS void AS $$
DECLARE
    object_data record;
BEGIN
    CASE resolution
        WHEN 'use_current' THEN
            -- Keep current branch version
            -- Note: Resolution is tracked in conflict_registry, not versioned_objects
            NULL;
            
        WHEN 'use_tracked' THEN
            -- Use incoming branch version
            -- Note: Resolution is tracked in conflict_registry, not versioned_objects
            NULL;
            
        WHEN 'merge' THEN
            -- Automatic three-way merge
            PERFORM pggit.merge_object_versions(
                conflict_record.object_identifier,
                conflict_record.conflict_data->>'base_version',
                conflict_record.conflict_data->>'current_version',
                conflict_record.conflict_data->>'tracked_version'
            );
            
        WHEN 'custom' THEN
            -- Apply custom resolution
            IF custom_resolution IS NULL THEN
                RAISE EXCEPTION 'Custom resolution requires resolution data';
            END IF;
            
            -- Apply custom DDL or data changes
            IF custom_resolution ? 'sql' THEN
                EXECUTE custom_resolution->>'sql';
            END IF;
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve version conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_version_conflict(
    conflict_record record,
    resolution text
) RETURNS void AS $$
BEGIN
    CASE resolution
        WHEN 'use_current' THEN
            -- Accept current version, ignore tracked changes
            UPDATE pggit.version_history
            SET is_current = true
            WHERE object_id = (
                SELECT object_id FROM pggit.versioned_objects 
                WHERE object_name = conflict_record.object_identifier
            );
            
        WHEN 'use_tracked' THEN
            -- Replace with tracked version
            PERFORM pggit.restore_object_version(
                conflict_record.object_identifier,
                (conflict_record.conflict_data->>'tracked_version_id')::uuid
            );
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve constraint conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_constraint_conflict(
    conflict_record record,
    resolution text
) RETURNS void AS $$
DECLARE
    constraint_name text;
    table_name text;
BEGIN
    constraint_name := conflict_record.conflict_data->>'constraint_name';
    table_name := conflict_record.conflict_data->>'table_name';
    
    CASE resolution
        WHEN 'use_current' THEN
            -- Keep current constraint, remove from tracking
            DELETE FROM pggit.pending_constraints
            WHERE constraint_name = constraint_name;
            
        WHEN 'use_tracked' THEN
            -- Drop current and apply tracked constraint
            EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
                table_name, constraint_name);
            
            -- Apply tracked constraint
            EXECUTE conflict_record.conflict_data->>'tracked_definition';
            
        WHEN 'merge' THEN
            -- Create new constraint that satisfies both
            RAISE NOTICE 'Automatic constraint merge not implemented';
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve dependency conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_dependency_conflict(
    conflict_record record,
    resolution text
) RETURNS void AS $$
BEGIN
    -- Handle circular dependencies or missing dependencies
    CASE resolution
        WHEN 'use_current' THEN
            -- Keep current dependency order
            NULL;
            
        WHEN 'use_tracked' THEN
            -- Reorder based on tracked dependencies
            PERFORM pggit.reorder_dependencies(
                conflict_record.conflict_data->>'object_list'
            );
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- Function to verify and fix consistency
CREATE OR REPLACE FUNCTION pggit.verify_consistency(
    fix_issues boolean DEFAULT false,
    verbose boolean DEFAULT false
) RETURNS TABLE (
    check_name text,
    status text,
    details text,
    fixed boolean
) AS $$
DECLARE
    issue_count integer := 0;
BEGIN
    -- Check 1: Version history consistency
    RETURN QUERY
    WITH version_check AS (
        SELECT 
            vo.object_id,
            vo.object_name,
            COUNT(DISTINCT vh.version_id) as version_count,
            COUNT(DISTINCT vh.version_id) FILTER (WHERE vh.is_current) as current_count
        FROM pggit.versioned_objects vo
        LEFT JOIN pggit.version_history vh ON vh.object_id = vo.object_id
        GROUP BY vo.object_id, vo.object_name
        HAVING COUNT(DISTINCT vh.version_id) FILTER (WHERE vh.is_current) != 1
    )
    SELECT 
        'version_history'::text,
        'error'::text,
        format('Object %s has %s current versions', object_name, current_count)::text,
        CASE 
            WHEN fix_issues THEN pggit.fix_version_consistency(object_id)
            ELSE false
        END
    FROM version_check;
    
    -- Check 2: Orphaned objects
    RETURN QUERY
    WITH orphan_check AS (
        SELECT vo.object_id, vo.object_name
        FROM pggit.versioned_objects vo
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname || '.' || c.relname = vo.object_name
        )
    )
    SELECT 
        'orphaned_objects'::text,
        'warning'::text,
        format('Object %s no longer exists in database', object_name)::text,
        CASE 
            WHEN fix_issues THEN pggit.remove_orphaned_object(object_id)
            ELSE false
        END
    FROM orphan_check;
    
    -- Check 3: Blob integrity
    RETURN QUERY
    WITH blob_check AS (
        SELECT b.blob_id, b.hash
        FROM pggit.blobs b
        WHERE b.size > 0 
          AND length(b.data) != b.size
    )
    SELECT 
        'blob_integrity'::text,
        'error'::text,
        format('Blob %s size mismatch', blob_id)::text,
        false::boolean -- Cannot auto-fix blob corruption
    FROM blob_check;
    
    -- Check 4: Commit tree consistency
    RETURN QUERY
    WITH tree_check AS (
        SELECT c.commit_id, c.tree_id
        FROM pggit.commits c
        WHERE NOT EXISTS (
            SELECT 1 FROM pggit.trees t
            WHERE t.tree_id = c.tree_id
        )
    )
    SELECT 
        'commit_trees'::text,
        'error'::text,
        format('Commit %s references missing tree %s', commit_id, tree_id)::text,
        false::boolean
    FROM tree_check;
    
    -- Summary
    IF verbose THEN
        RETURN QUERY
        SELECT 
            'summary'::text,
            CASE 
                WHEN issue_count = 0 THEN 'ok'::text
                ELSE 'issues_found'::text
            END,
            format('Total issues: %s', issue_count)::text,
            NULL::boolean;
    END IF;
    
    -- Return empty result set if not verbose
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Helper function to fix version consistency
CREATE OR REPLACE FUNCTION pggit.fix_version_consistency(
    object_id integer
) RETURNS boolean AS $$
DECLARE
    latest_version_id uuid;
BEGIN
    -- Find the most recent version
    SELECT version_id INTO latest_version_id
    FROM pggit.version_history
    WHERE version_history.object_id = fix_version_consistency.object_id
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Set all versions to not current
    UPDATE pggit.version_history
    SET is_current = false
    WHERE version_history.object_id = fix_version_consistency.object_id;
    
    -- Set only the latest as current
    UPDATE pggit.version_history
    SET is_current = true
    WHERE version_id = latest_version_id;
    
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- Helper function to remove orphaned objects
CREATE OR REPLACE FUNCTION pggit.remove_orphaned_object(
    object_id integer
) RETURNS boolean AS $$
BEGIN
    -- Archive the object data before removal
    INSERT INTO pggit.archived_objects (object_id, object_data, archived_at)
    SELECT 
        vo.object_id,
        jsonb_build_object(
            'object_name', vo.object_name,
            'object_type', vo.object_type,
            'versions', (
                SELECT jsonb_agg(vh.*)
                FROM pggit.version_history vh
                WHERE vh.object_id = vo.object_id
            )
        ),
        now()
    FROM pggit.versioned_objects vo
    WHERE vo.object_id = remove_orphaned_object.object_id;
    
    -- Remove from active tracking
    DELETE FROM pggit.versioned_objects
    WHERE versioned_objects.object_id = remove_orphaned_object.object_id;
    
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$ LANGUAGE plpgsql;

-- Table for archived objects
CREATE TABLE IF NOT EXISTS pggit.archived_objects (
    archive_id serial PRIMARY KEY,
    object_id integer,
    object_data jsonb,
    archived_at timestamptz DEFAULT now(),
    archived_by text DEFAULT current_user
);

-- Function to list current conflicts
CREATE OR REPLACE FUNCTION pggit.list_conflicts(
    status_filter text DEFAULT 'unresolved'
) RETURNS TABLE (
    conflict_id uuid,
    conflict_type text,
    object_type text,
    object_identifier text,
    created_at timestamptz,
    description text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.conflict_id,
        c.conflict_type,
        c.object_type,
        c.object_identifier,
        c.created_at,
        CASE c.conflict_type
            WHEN 'merge' THEN format('Merge conflict on %s between branches', c.object_identifier)
            WHEN 'version' THEN format('Version mismatch for %s', c.object_identifier)
            WHEN 'constraint' THEN format('Constraint conflict: %s', c.conflict_data->>'constraint_name')
            WHEN 'dependency' THEN format('Dependency conflict for %s', c.object_identifier)
        END as description
    FROM pggit.conflict_registry c
    WHERE (status_filter IS NULL OR c.status = status_filter)
    ORDER BY c.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for interactive conflict resolution
CREATE OR REPLACE FUNCTION pggit.show_conflict_details(
    conflict_id uuid
) RETURNS TABLE (
    detail_type text,
    detail_value text
) AS $$
DECLARE
    conflict_record record;
BEGIN
    SELECT * INTO conflict_record
    FROM pggit.conflict_registry
    WHERE conflict_registry.conflict_id = show_conflict_details.conflict_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conflict % not found', conflict_id;
    END IF;
    
    -- Basic details
    RETURN QUERY VALUES
        ('Type', conflict_record.conflict_type),
        ('Object', conflict_record.object_identifier),
        ('Status', conflict_record.status),
        ('Created', conflict_record.created_at::text);
    
    -- Type-specific details
    CASE conflict_record.conflict_type
        WHEN 'merge' THEN
            RETURN QUERY VALUES
                ('Base Version', conflict_record.conflict_data->>'base_version'),
                ('Current Version', conflict_record.conflict_data->>'current_version'),
                ('Incoming Version', conflict_record.conflict_data->>'tracked_version');
                
        WHEN 'constraint' THEN
            RETURN QUERY VALUES
                ('Constraint Name', conflict_record.conflict_data->>'constraint_name'),
                ('Table', conflict_record.conflict_data->>'table_name'),
                ('Current Definition', conflict_record.conflict_data->>'current_definition'),
                ('Tracked Definition', conflict_record.conflict_data->>'tracked_definition');
    END CASE;
    
    -- Resolution options
    RETURN QUERY VALUES
        ('Resolution Options', ''),
        ('  use_current', 'Keep current version'),
        ('  use_tracked', 'Use incoming version'),
        ('  merge', 'Attempt automatic merge'),
        ('  custom', 'Apply custom resolution');
END;
$$ LANGUAGE plpgsql;