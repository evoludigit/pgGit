-- pgGit Operational Commands
-- Emergency controls and maintenance functions

-- Function to temporarily disable pgGit
CREATE OR REPLACE FUNCTION pggit.emergency_disable(
    duration interval DEFAULT '1 hour'::interval
) RETURNS timestamptz AS $$
DECLARE
    resume_time timestamptz;
BEGIN
    resume_time := now() + duration;
    
    -- Disable all pgGit event triggers
    BEGIN
        ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_drop_trigger DISABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_enhanced_ddl_trigger DISABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_enhanced_drop_trigger DISABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    
    -- Log the emergency disable
    INSERT INTO pggit.system_events (event_type, event_data)
    VALUES ('emergency_disable', jsonb_build_object(
        'disabled_at', now(),
        'resume_at', resume_time,
        'duration', duration::text,
        'disabled_by', current_user,
        'reason', 'Emergency disable requested'
    ));
    
    -- Create a notice for DBAs
    RAISE WARNING 'pgGit EMERGENCY DISABLED until %. Use pggit.emergency_enable() to re-enable sooner.', resume_time;
    
    RETURN resume_time;
END;
$$ LANGUAGE plpgsql;

-- Function to re-enable pgGit after emergency disable
CREATE OR REPLACE FUNCTION pggit.emergency_enable() RETURNS void AS $$
DECLARE
    last_disable record;
BEGIN
    -- Check if actually disabled
    SELECT * INTO last_disable
    FROM pggit.system_events
    WHERE event_type = 'emergency_disable'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF last_disable IS NULL OR (last_disable.event_data->>'resume_at')::timestamptz < now() THEN
        RAISE NOTICE 'pgGit is not currently emergency disabled';
    END IF;
    
    -- Re-enable triggers
    BEGIN
        ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_drop_trigger ENABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_enhanced_ddl_trigger ENABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    BEGIN
        ALTER EVENT TRIGGER pggit_enhanced_drop_trigger ENABLE;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
    
    -- Log the re-enable
    INSERT INTO pggit.system_events (event_type, event_data)
    VALUES ('emergency_enable', jsonb_build_object(
        'enabled_at', now(),
        'enabled_by', current_user,
        'was_disabled_since', last_disable.created_at
    ));
    
    RAISE NOTICE 'pgGit has been re-enabled';
END;
$$ LANGUAGE plpgsql;

-- Function to purge old history
CREATE OR REPLACE FUNCTION pggit.purge_history(
    older_than interval DEFAULT '6 months'::interval,
    keep_milestones boolean DEFAULT true,
    dry_run boolean DEFAULT true
) RETURNS TABLE (
    action text,
    object_type text,
    count bigint,
    space_freed text
) AS $$
DECLARE
    cutoff_date timestamptz;
    total_size_before bigint;
    total_size_after bigint;
BEGIN
    cutoff_date := now() - older_than;
    
    -- Get current size
    SELECT pg_total_relation_size('pggit.blobs') +
           pg_total_relation_size('pggit.commits') +
           pg_total_relation_size('pggit.trees') +
           pg_total_relation_size('pggit.version_history')
    INTO total_size_before;
    
    IF dry_run THEN
        -- Report what would be deleted
        RETURN QUERY
        SELECT 
            'would_delete'::text,
            'commits'::text,
            COUNT(*)::bigint,
            pg_size_pretty(SUM(pg_column_size(c.*)))::text
        FROM pggit.commits c
        WHERE c.created_at < cutoff_date
          AND (NOT keep_milestones OR c.metadata->>'milestone' IS NULL);
        
        RETURN QUERY
        SELECT 
            'would_delete'::text,
            'versions'::text,
            COUNT(*)::bigint,
            pg_size_pretty(SUM(pg_column_size(vh.*)))::text
        FROM pggit.version_history vh
        WHERE vh.created_at < cutoff_date
          AND NOT vh.is_current;
        
        RETURN QUERY
        SELECT 
            'would_delete'::text,
            'blobs'::text,
            COUNT(*)::bigint,
            pg_size_pretty(SUM(b.size))::text
        FROM pggit.blobs b
        WHERE NOT EXISTS (
            SELECT 1 FROM pggit.tree_entries te
            WHERE te.blob_id = b.blob_id
        );
    ELSE
        -- Actually purge data
        
        -- Archive important commits before deletion
        INSERT INTO pggit.archived_commits
        SELECT * FROM pggit.commits c
        WHERE c.created_at < cutoff_date
          AND c.metadata->>'important' = 'true';
        
        -- Delete old commits
        WITH deleted_commits AS (
            DELETE FROM pggit.commits c
            WHERE c.created_at < cutoff_date
              AND (NOT keep_milestones OR c.metadata->>'milestone' IS NULL)
            RETURNING *
        )
        SELECT 'deleted'::text, 'commits'::text, COUNT(*)::bigint, 
               pg_size_pretty(SUM(pg_column_size(dc.*)))::text
        FROM deleted_commits dc;
        
        -- Delete old versions
        WITH deleted_versions AS (
            DELETE FROM pggit.version_history vh
            WHERE vh.created_at < cutoff_date
              AND NOT vh.is_current
              AND NOT EXISTS (
                  SELECT 1 FROM pggit.commits c
                  WHERE c.tree_id IN (
                      SELECT tree_id FROM pggit.tree_entries te
                      WHERE te.entry_type = 'version' 
                        AND te.entry_name = vh.version_id::text
                  )
              )
            RETURNING *
        )
        SELECT 'deleted'::text, 'versions'::text, COUNT(*)::bigint,
               pg_size_pretty(SUM(pg_column_size(dv.*)))::text
        FROM deleted_versions dv;
        
        -- Delete orphaned blobs
        WITH deleted_blobs AS (
            DELETE FROM pggit.blobs b
            WHERE NOT EXISTS (
                SELECT 1 FROM pggit.tree_entries te
                WHERE te.blob_id = b.blob_id
            )
            RETURNING *
        )
        SELECT 'deleted'::text, 'blobs'::text, COUNT(*)::bigint,
               pg_size_pretty(SUM(db.size))::text
        FROM deleted_blobs db;
        
        -- Vacuum to reclaim space
        VACUUM ANALYZE pggit.blobs, pggit.commits, pggit.trees, pggit.version_history;
        
        -- Get new size
        SELECT pg_total_relation_size('pggit.blobs') +
               pg_total_relation_size('pggit.commits') +
               pg_total_relation_size('pggit.trees') +
               pg_total_relation_size('pggit.version_history')
        INTO total_size_after;
        
        RETURN QUERY
        SELECT 'summary'::text, 'space_reclaimed'::text, 1::bigint,
               pg_size_pretty(total_size_before - total_size_after)::text;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Archive table for important commits
CREATE TABLE IF NOT EXISTS pggit.archived_commits (
    LIKE pggit.commits INCLUDING ALL,
    archived_at timestamptz DEFAULT now()
);

-- Function to export schema snapshot
CREATE OR REPLACE FUNCTION pggit.export_schema_snapshot(
    path text DEFAULT NULL,
    schemas text[] DEFAULT NULL
) RETURNS text AS $$
DECLARE
    schema_sql text := '';
    schema_name text;
    object_count integer := 0;
BEGIN
    -- Default to all non-system schemas if not specified
    IF schemas IS NULL THEN
        schemas := ARRAY(
            SELECT nspname 
            FROM pg_namespace 
            WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pggit')
              AND nspname NOT LIKE 'pg_%'
        );
    END IF;
    
    -- Generate schema DDL
    FOREACH schema_name IN ARRAY schemas
    LOOP
        schema_sql := schema_sql || format(E'\n\n-- Schema: %s\n', schema_name);
        
        -- Export schema creation
        schema_sql := schema_sql || format('CREATE SCHEMA IF NOT EXISTS %I;%s', 
            schema_name, E'\n\n');
        
        -- Export tables
        schema_sql := schema_sql || E'-- Tables\n';
        SELECT schema_sql || string_agg(
            format('CREATE TABLE %I.%I (%s);', 
                schema_name, 
                tablename,
                pggit.get_table_definition(schema_name, tablename)
            ), E'\n'
        )
        INTO schema_sql
        FROM pg_tables
        WHERE schemaname = schema_name;
        
        -- Export functions
        schema_sql := schema_sql || E'\n\n-- Functions\n';
        SELECT schema_sql || string_agg(
            pg_get_functiondef(p.oid), E'\n\n'
        )
        INTO schema_sql
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = schema_name;
        
        -- Count objects
        SELECT object_count + COUNT(*)
        INTO object_count
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = schema_name;
    END LOOP;
    
    -- Add metadata
    schema_sql := format(E'-- pgGit Schema Snapshot\n-- Generated: %s\n-- Objects: %s\n-- Schemas: %s\n\n%s',
        now()::text,
        object_count,
        array_to_string(schemas, ', '),
        schema_sql
    );
    
    -- Write to file if path provided (requires pg_file extension)
    IF path IS NOT NULL THEN
        -- Would need pg_file_write or COPY
        RAISE NOTICE 'File export not available. Use psql \o % to save output', path;
    END IF;
    
    RETURN schema_sql;
END;
$$ LANGUAGE plpgsql;

-- Helper function to get table definition
CREATE OR REPLACE FUNCTION pggit.get_table_definition(
    schema_name text,
    table_name text
) RETURNS text AS $$
DECLARE
    column_sql text;
BEGIN
    SELECT string_agg(
        format('%I %s%s%s',
            column_name,
            data_type,
            CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END,
            CASE WHEN column_default IS NOT NULL 
                 THEN ' DEFAULT ' || column_default 
                 ELSE '' 
            END
        ), ', '
        ORDER BY ordinal_position
    )
    INTO column_sql
    FROM information_schema.columns
    WHERE table_schema = schema_name
      AND information_schema.columns.table_name = get_table_definition.table_name;
    
    RETURN column_sql;
END;
$$ LANGUAGE plpgsql;

-- Function to compare environments
CREATE OR REPLACE FUNCTION pggit.compare_environments(
    env1_name text,
    env2_name text,
    connection_string1 text DEFAULT NULL,
    connection_string2 text DEFAULT NULL
) RETURNS TABLE (
    object_type text,
    object_name text,
    env1_status text,
    env2_status text,
    difference text
) AS $$
BEGIN
    -- This would require dblink or foreign data wrapper
    -- For now, provide a comparison framework
    
    IF connection_string1 IS NOT NULL AND connection_string2 IS NOT NULL THEN
        -- Would use dblink to compare
        RAISE NOTICE 'Remote comparison requires dblink extension';
    ELSE
        -- Compare local branches
        RETURN QUERY
        WITH env1_objects AS (
            SELECT 
                vo.object_type,
                vo.object_name,
                vh.version_major || '.' || vh.version_minor || '.' || vh.version_patch as version
            FROM pggit.versioned_objects vo
            JOIN pggit.version_history vh ON vh.object_id = vo.object_id
            JOIN pggit.branches b ON b.branch_name = env1_name
            WHERE vh.is_current = true
        ),
        env2_objects AS (
            SELECT 
                vo.object_type,
                vo.object_name,
                vh.version_major || '.' || vh.version_minor || '.' || vh.version_patch as version
            FROM pggit.versioned_objects vo
            JOIN pggit.version_history vh ON vh.object_id = vo.object_id
            JOIN pggit.branches b ON b.branch_name = env2_name
            WHERE vh.is_current = true
        )
        SELECT 
            COALESCE(e1.object_type, e2.object_type) as object_type,
            COALESCE(e1.object_name, e2.object_name) as object_name,
            COALESCE(e1.version, 'missing') as env1_status,
            COALESCE(e2.version, 'missing') as env2_status,
            CASE 
                WHEN e1.object_name IS NULL THEN 'Only in ' || env2_name
                WHEN e2.object_name IS NULL THEN 'Only in ' || env1_name
                WHEN e1.version != e2.version THEN 'Version mismatch'
                ELSE 'Same'
            END as difference
        FROM env1_objects e1
        FULL OUTER JOIN env2_objects e2 
            ON e1.object_type = e2.object_type 
            AND e1.object_name = e2.object_name
        WHERE e1.version IS DISTINCT FROM e2.version
        ORDER BY object_type, object_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Performance monitoring function
CREATE OR REPLACE FUNCTION pggit.performance_report(
    days_back integer DEFAULT 7
) RETURNS TABLE (
    metric_name text,
    metric_value numeric,
    metric_unit text
) AS $$
BEGIN
    -- DDL operations tracked
    RETURN QUERY
    SELECT 
        'DDL operations tracked'::text,
        COUNT(*)::numeric,
        'operations'::text
    FROM pggit.system_events
    WHERE created_at > now() - (days_back || ' days')::interval
      AND event_type = 'ddl_tracked';
    
    -- Storage used
    RETURN QUERY
    SELECT 
        'Storage used'::text,
        (pg_total_relation_size('pggit.blobs') / 1024.0 / 1024.0)::numeric,
        'MB'::text;
    
    -- Average tracking time
    RETURN QUERY
    SELECT 
        'Avg tracking time'::text,
        AVG(EXTRACT(MILLISECONDS FROM (event_data->>'duration')::interval))::numeric,
        'ms'::text
    FROM pggit.system_events
    WHERE event_type = 'tracking_complete'
      AND created_at > now() - (days_back || ' days')::interval;
    
    -- Compression ratio
    RETURN QUERY
    WITH compression_stats AS (
        SELECT 
            SUM(original_size) as total_original,
            SUM(size) as total_compressed
        FROM pggit.blobs
        WHERE compression_type IS NOT NULL
    )
    SELECT 
        'Compression ratio'::text,
        (1.0 - (total_compressed::numeric / NULLIF(total_original, 0)))::numeric * 100,
        '%'::text
    FROM compression_stats;
    
    -- Conflicts encountered
    RETURN QUERY
    SELECT 
        'Conflicts encountered'::text,
        COUNT(*)::numeric,
        'conflicts'::text
    FROM pggit.conflict_registry
    WHERE created_at > now() - (days_back || ' days')::interval;
END;
$$ LANGUAGE plpgsql;

-- Status dashboard function
CREATE OR REPLACE FUNCTION pggit.status() RETURNS TABLE (
    component text,
    status text,
    details text
) AS $$
BEGIN
    -- Tracking status
    RETURN QUERY
    SELECT 
        'Tracking'::text,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM pg_event_trigger 
                WHERE evtname LIKE 'pggit%' AND evtenabled = 'O'
            ) THEN 'enabled'
            ELSE 'disabled'
        END,
        format('%s triggers active', 
            (SELECT COUNT(*) FROM pg_event_trigger 
             WHERE evtname LIKE 'pggit%' AND evtenabled = 'O')
        );
    
    -- Deployment mode
    RETURN QUERY
    SELECT 
        'Deployment Mode'::text,
        CASE 
            WHEN (SELECT is_active FROM pggit.deployment_state LIMIT 1) 
            THEN 'active'
            ELSE 'inactive'
        END,
        COALESCE(
            (SELECT deployment_name FROM pggit.deployment_mode 
             WHERE deployment_id = (SELECT current_deployment_id 
                                   FROM pggit.deployment_state)
            ),
            'No active deployment'
        );
    
    -- Storage
    RETURN QUERY
    SELECT 
        'Storage'::text,
        'ok'::text,
        format('Using %s across %s objects',
            pg_size_pretty(pg_total_relation_size('pggit.blobs')),
            (SELECT COUNT(*) FROM pggit.versioned_objects)
        );
    
    -- Recent activity
    RETURN QUERY
    SELECT 
        'Recent Activity'::text,
        'info'::text,
        format('%s changes in last hour',
            (SELECT COUNT(*) FROM pggit.commits 
             WHERE created_at > now() - interval '1 hour')
        );
END;
$$ LANGUAGE plpgsql;