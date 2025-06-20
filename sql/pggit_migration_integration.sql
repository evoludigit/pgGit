-- pgGit Integration with Traditional Migration Tools
-- Support for Flyway, Liquibase, and other migration frameworks

-- Table to track external migrations
CREATE TABLE IF NOT EXISTS pggit.external_migrations (
    migration_id bigint PRIMARY KEY,
    tool_name text NOT NULL,
    migration_name text,
    checksum text,
    pggit_commit_id uuid, -- Foreign key removed: pggit.commits may not have commit_id column
    pggit_version_start uuid,
    pggit_version_end uuid,
    applied_at timestamptz DEFAULT now(),
    applied_by text DEFAULT current_user,
    execution_time interval,
    success boolean DEFAULT true,
    error_message text
);

-- Index for quick lookups
CREATE INDEX idx_external_migrations_tool ON pggit.external_migrations(tool_name, applied_at DESC);

-- Function to start tracking a migration
CREATE OR REPLACE FUNCTION pggit.begin_migration(
    migration_id bigint,
    tool_name text DEFAULT 'flyway',
    migration_name text DEFAULT NULL
) RETURNS uuid AS $$
DECLARE
    deployment_id uuid;
    version_start uuid;
BEGIN
    -- Check if migration already exists
    IF EXISTS (SELECT 1 FROM pggit.external_migrations WHERE external_migrations.migration_id = begin_migration.migration_id) THEN
        RAISE EXCEPTION 'Migration % already tracked', migration_id;
    END IF;
    
    -- Get current schema version
    SELECT pggit.get_current_version() INTO version_start;
    
    -- Start deployment mode for the migration
    deployment_id := pggit.begin_deployment(
        format('Migration %s: %s', migration_id, COALESCE(migration_name, 'unnamed'))
    );
    
    -- Insert migration record
    INSERT INTO pggit.external_migrations (
        migration_id,
        tool_name,
        migration_name,
        pggit_version_start
    ) VALUES (
        migration_id,
        tool_name,
        migration_name,
        version_start
    );
    
    RETURN deployment_id;
END;
$$ LANGUAGE plpgsql;

-- Function to complete migration tracking
CREATE OR REPLACE FUNCTION pggit.end_migration(
    migration_id bigint,
    checksum text DEFAULT NULL,
    success boolean DEFAULT true,
    error_message text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    migration_record record;
    version_end uuid;
    commit_id uuid;
    start_time timestamptz;
BEGIN
    -- Get migration record
    SELECT * INTO migration_record
    FROM pggit.external_migrations
    WHERE external_migrations.migration_id = end_migration.migration_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Migration % not found', migration_id;
    END IF;
    
    -- Get end version
    SELECT pggit.get_current_version() INTO version_end;
    
    -- End deployment mode
    BEGIN
        PERFORM pggit.end_deployment(
            format('Migration %s completed', migration_id)
        );
        
        -- Get the commit that was just created
        SELECT c.commit_id INTO commit_id
        FROM pggit.commits c
        ORDER BY c.created_at DESC
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        -- Deployment might have already ended
        NULL;
    END;
    
    -- Update migration record
    UPDATE pggit.external_migrations
    SET pggit_version_end = version_end,
        pggit_commit_id = commit_id,
        checksum = end_migration.checksum,
        success = end_migration.success,
        error_message = end_migration.error_message,
        execution_time = now() - applied_at
    WHERE external_migrations.migration_id = end_migration.migration_id;
END;
$$ LANGUAGE plpgsql;

-- Function to link existing migration to pgGit
CREATE OR REPLACE FUNCTION pggit.link_migration(
    migration_id bigint,
    description text DEFAULT NULL,
    tool_name text DEFAULT 'flyway'
) RETURNS void AS $$
DECLARE
    commit_id uuid;
BEGIN
    -- Create a commit for the migration
    INSERT INTO pggit.commits (branch_name, commit_message, commit_sql, author)
    VALUES (
        'main',
        COALESCE(description, format('External migration %s from %s', migration_id, tool_name)),
        '-- External migration linked retroactively',
        current_user
    ) RETURNING commit_id INTO commit_id;
    
    -- Link to migration record if it exists
    UPDATE pggit.external_migrations
    SET pggit_commit_id = commit_id
    WHERE external_migrations.migration_id = link_migration.migration_id;
    
    -- Create record if it doesn't exist
    IF NOT FOUND THEN
        INSERT INTO pggit.external_migrations (
            migration_id,
            tool_name,
            pggit_commit_id,
            migration_name
        ) VALUES (
            migration_id,
            tool_name,
            commit_id,
            description
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to validate migration consistency
CREATE OR REPLACE FUNCTION pggit.validate_migrations(
    tool_name text DEFAULT NULL
) RETURNS TABLE (
    migration_id bigint,
    status text,
    message text
) AS $$
BEGIN
    RETURN QUERY
    WITH migration_gaps AS (
        -- Find gaps in migration sequence
        SELECT 
            m1.migration_id + 1 as gap_start,
            MIN(m2.migration_id) - 1 as gap_end
        FROM pggit.external_migrations m1
        LEFT JOIN pggit.external_migrations m2 
            ON m2.migration_id > m1.migration_id
            AND (tool_name IS NULL OR m2.tool_name = tool_name)
        WHERE (tool_name IS NULL OR m1.tool_name = tool_name)
          AND m2.migration_id IS NOT NULL
          AND m2.migration_id > m1.migration_id + 1
        GROUP BY m1.migration_id
    ),
    validation_results AS (
        -- Check for gaps
        SELECT 
            NULL::bigint as migration_id,
            'gap'::text as status,
            format('Missing migrations %s to %s', gap_start, gap_end) as message
        FROM migration_gaps
        
        UNION ALL
        
        -- Check for failed migrations
        SELECT 
            migration_id,
            'failed'::text,
            format('Migration failed: %s', COALESCE(error_message, 'Unknown error'))
        FROM pggit.external_migrations
        WHERE NOT success
          AND (tool_name IS NULL OR external_migrations.tool_name = validate_migrations.tool_name)
        
        UNION ALL
        
        -- Check for migrations without pgGit commits
        SELECT 
            migration_id,
            'unlinked'::text,
            'Migration not linked to pgGit commit'
        FROM pggit.external_migrations
        WHERE pggit_commit_id IS NULL
          AND (tool_name IS NULL OR external_migrations.tool_name = validate_migrations.tool_name)
    )
    SELECT * FROM validation_results
    ORDER BY migration_id NULLS FIRST;
END;
$$ LANGUAGE plpgsql;

-- Integration with Flyway
CREATE OR REPLACE FUNCTION pggit.integrate_flyway(
    schema_name text DEFAULT 'public'
) RETURNS void AS $$
BEGIN
    -- Create trigger on Flyway's schema_version table
    EXECUTE format($trigger$
        CREATE OR REPLACE FUNCTION %I.pggit_flyway_sync() 
        RETURNS TRIGGER AS $func$
        BEGIN
            IF TG_OP = 'INSERT' AND NEW.success THEN
                -- Start tracking the migration
                PERFORM pggit.begin_migration(
                    NEW.installed_rank,
                    'flyway',
                    NEW.description
                );
            ELSIF TG_OP = 'UPDATE' AND NEW.success AND OLD.success IS DISTINCT FROM NEW.success THEN
                -- Migration completed
                PERFORM pggit.end_migration(
                    NEW.installed_rank,
                    NEW.checksum::text,
                    NEW.success
                );
            END IF;
            RETURN NEW;
        END;
        $func$ LANGUAGE plpgsql;
        
        CREATE TRIGGER pggit_flyway_integration
        AFTER INSERT OR UPDATE ON %I.flyway_schema_history
        FOR EACH ROW EXECUTE FUNCTION %I.pggit_flyway_sync();
    $trigger$, schema_name, schema_name, schema_name);
    
    RAISE NOTICE 'Flyway integration enabled for schema %', schema_name;
END;
$$ LANGUAGE plpgsql;

-- Integration with Liquibase
CREATE OR REPLACE FUNCTION pggit.integrate_liquibase(
    schema_name text DEFAULT 'public'
) RETURNS void AS $$
BEGIN
    -- Create trigger on Liquibase's databasechangelog table
    EXECUTE format($trigger$
        CREATE OR REPLACE FUNCTION %I.pggit_liquibase_sync() 
        RETURNS TRIGGER AS $func$
        BEGIN
            IF TG_OP = 'INSERT' THEN
                -- Track the changeset
                PERFORM pggit.link_migration(
                    -- Use orderexecuted as migration ID
                    NEW.orderexecuted,
                    format('Liquibase: %s by %s', NEW.id, NEW.author),
                    'liquibase'
                );
            END IF;
            RETURN NEW;
        END;
        $func$ LANGUAGE plpgsql;
        
        CREATE TRIGGER pggit_liquibase_integration
        AFTER INSERT ON %I.databasechangelog
        FOR EACH ROW EXECUTE FUNCTION %I.pggit_liquibase_sync();
    $trigger$, schema_name, schema_name, schema_name);
    
    RAISE NOTICE 'Liquibase integration enabled for schema %', schema_name;
END;
$$ LANGUAGE plpgsql;

-- View to show migration history with pgGit correlation
CREATE OR REPLACE VIEW pggit.migration_history AS
SELECT 
    m.migration_id,
    m.tool_name,
    m.migration_name,
    m.applied_at,
    m.applied_by,
    m.execution_time,
    m.success,
    c.commit_id,
    c.message as commit_message,
    c.tree_id,
    (SELECT COUNT(*) 
     FROM pggit.tree_entries te 
     WHERE te.tree_id = c.tree_id) as objects_changed
FROM pggit.external_migrations m
LEFT JOIN pggit.commits c ON c.commit_id = m.pggit_commit_id
ORDER BY m.applied_at DESC;

-- Function to export schema state at migration point
CREATE OR REPLACE FUNCTION pggit.export_migration_schema(
    migration_id bigint,
    output_path text DEFAULT NULL
) RETURNS text AS $$
DECLARE
    migration_record record;
    schema_sql text;
BEGIN
    -- Get migration record
    SELECT * INTO migration_record
    FROM pggit.external_migrations
    WHERE external_migrations.migration_id = export_migration_schema.migration_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Migration % not found', migration_id;
    END IF;
    
    -- Get schema at that point in time
    IF migration_record.pggit_commit_id IS NOT NULL THEN
        -- Use pgGit to reconstruct schema at that commit
        schema_sql := pggit.get_schema_at_commit(migration_record.pggit_commit_id);
    ELSE
        RAISE EXCEPTION 'Migration % has no associated pgGit commit', migration_id;
    END IF;
    
    -- Export to file if path provided
    IF output_path IS NOT NULL THEN
        -- Would need COPY or pg_file_write extension
        RAISE NOTICE 'Schema export to file not implemented. Use psql \o command';
    END IF;
    
    RETURN schema_sql;
END;
$$ LANGUAGE plpgsql;

-- Function to show migration impact
CREATE OR REPLACE FUNCTION pggit.analyze_migration_impact(
    migration_id bigint
) RETURNS TABLE (
    object_type text,
    object_name text,
    operation text,
    impact_level text
) AS $$
BEGIN
    RETURN QUERY
    WITH migration_changes AS (
        SELECT 
            vo.object_type,
            vo.schema_name || '.' || vo.object_name as object_name,
            vo.operation,
            CASE 
                WHEN vo.operation IN ('DROP', 'ALTER') THEN 'high'
                WHEN vo.operation = 'CREATE' THEN 'medium'
                ELSE 'low'
            END as impact_level
        FROM pggit.external_migrations m
        JOIN pggit.version_history vh ON vh.version_id BETWEEN m.pggit_version_start AND m.pggit_version_end
        JOIN pggit.versioned_objects vo ON vo.object_id = vh.object_id
        WHERE m.migration_id = analyze_migration_impact.migration_id
    )
    SELECT * FROM migration_changes
    ORDER BY 
        CASE impact_level 
            WHEN 'high' THEN 1 
            WHEN 'medium' THEN 2 
            ELSE 3 
        END,
        object_type,
        object_name;
END;
$$ LANGUAGE plpgsql;