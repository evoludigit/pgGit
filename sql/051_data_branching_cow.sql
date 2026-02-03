-- pgGit Data Branching with Copy-on-Write
-- True data isolation using PostgreSQL 17 features
-- Enterprise-grade branching for data and schema

-- =====================================================
-- Core Data Branching Tables
-- =====================================================

CREATE SCHEMA IF NOT EXISTS pggit_branches;

-- Branch metadata with storage tracking
CREATE TABLE IF NOT EXISTS pggit.branch_storage_stats (
    branch_name TEXT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_size BIGINT DEFAULT 0,
    row_count BIGINT DEFAULT 0,
    compression_type TEXT DEFAULT 'none',
    cow_enabled BOOLEAN DEFAULT true,
    storage_efficiency DECIMAL(5,2) DEFAULT 100.0
);

-- Track branched tables
CREATE TABLE IF NOT EXISTS pggit.branched_tables (
    id SERIAL PRIMARY KEY,
    branch_name TEXT NOT NULL,
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    branch_schema TEXT NOT NULL,
    branch_table TEXT NOT NULL,
    branched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    row_count BIGINT,
    uses_cow BOOLEAN DEFAULT true,
    UNIQUE(branch_name, source_schema, source_table)
);

-- Data conflicts tracking
CREATE TABLE IF NOT EXISTS pggit.data_conflicts (
    conflict_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    merge_id UUID NOT NULL,
    table_name TEXT NOT NULL,
    primary_key_value TEXT NOT NULL,
    source_branch TEXT NOT NULL,
    target_branch TEXT NOT NULL,
    source_data JSONB,
    target_data JSONB,
    conflict_type TEXT, -- 'update-update', 'delete-update', etc.
    resolution TEXT, -- 'pending', 'source', 'target', 'manual'
    resolved_data JSONB,
    resolved_by TEXT,
    resolved_at TIMESTAMP
);

-- =====================================================
-- Copy-on-Write Implementation
-- =====================================================

-- Setup view-based routing for a table (enables transparent branch switching)
-- This replaces the original table with a view that routes to the correct branch
CREATE OR REPLACE FUNCTION pggit.setup_table_routing(
    p_schema TEXT,
    p_table TEXT
) RETURNS VOID AS $$
DECLARE
    v_base_table TEXT;
    v_pk_columns TEXT;
    v_all_columns TEXT;
    v_update_sets TEXT;
BEGIN
    v_base_table := '_pggit_main_' || p_table;

    -- Check if routing is already set up (view exists)
    IF EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = p_schema AND table_name = p_table
    ) THEN
        RETURN; -- Already set up
    END IF;

    -- Create base schema if needed (for storing original tables)
    EXECUTE 'CREATE SCHEMA IF NOT EXISTS pggit_base';

    -- Get primary key columns for the table
    SELECT string_agg(a.attname, ', ' ORDER BY array_position(i.indkey, a.attnum))
    INTO v_pk_columns
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = format('%I.%I', p_schema, p_table)::regclass
    AND i.indisprimary;

    -- Get all columns (excluding system columns)
    SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
    INTO v_all_columns
    FROM information_schema.columns
    WHERE table_schema = p_schema AND table_name = p_table
    AND column_name NOT LIKE '_pggit_%';

    -- Build UPDATE SET clause
    SELECT string_agg(column_name || ' = NEW.' || column_name, ', ')
    INTO v_update_sets
    FROM information_schema.columns
    WHERE table_schema = p_schema AND table_name = p_table
    AND column_name NOT LIKE '_pggit_%';

    -- Step 1: Move original table to base schema (avoids OID caching issues)
    EXECUTE format('ALTER TABLE %I.%I SET SCHEMA pggit_base', p_schema, p_table);
    EXECUTE format('ALTER TABLE pggit_base.%I RENAME TO %I', p_table, v_base_table);

    -- Step 2: Create router function for SELECT
    EXECUTE format($fn$
        CREATE OR REPLACE FUNCTION pggit.route_%I_select()
        RETURNS SETOF pggit_base.%I AS $inner$
        DECLARE
            v_branch TEXT;
            v_schema TEXT;
        BEGIN
            v_branch := current_setting('pggit.current_branch', true);
            IF v_branch IS NULL OR v_branch = '' OR v_branch = 'main' THEN
                RETURN QUERY SELECT * FROM pggit_base.%I;
            ELSE
                v_schema := 'pggit_branch_' || replace(v_branch, '/', '_');
                RETURN QUERY EXECUTE format('SELECT * FROM %%I.%I', v_schema);
            END IF;
        END;
        $inner$ LANGUAGE plpgsql STABLE
    $fn$, p_table, v_base_table, v_base_table, p_table);

    -- Step 3: Create the view
    EXECUTE format(
        'CREATE VIEW %I.%I AS SELECT * FROM pggit.route_%I_select()',
        p_schema, p_table, p_table
    );

    -- Step 4: Create INSTEAD OF INSERT trigger function
    EXECUTE format($fn$
        CREATE OR REPLACE FUNCTION pggit.route_%I_insert()
        RETURNS TRIGGER AS $inner$
        DECLARE
            v_branch TEXT;
            v_schema TEXT;
        BEGIN
            v_branch := current_setting('pggit.current_branch', true);
            IF v_branch IS NULL OR v_branch = '' OR v_branch = 'main' THEN
                INSERT INTO pggit_base.%I VALUES (NEW.*);
            ELSE
                v_schema := 'pggit_branch_' || replace(v_branch, '/', '_');
                EXECUTE format('INSERT INTO %%I.%I VALUES ($1.*)', v_schema) USING NEW;
            END IF;
            RETURN NEW;
        END;
        $inner$ LANGUAGE plpgsql
    $fn$, p_table, v_base_table, p_table);

    EXECUTE format(
        'CREATE TRIGGER %I_insert INSTEAD OF INSERT ON %I.%I FOR EACH ROW EXECUTE FUNCTION pggit.route_%I_insert()',
        p_table, p_schema, p_table, p_table
    );

    -- Step 5: Create INSTEAD OF UPDATE trigger function
    EXECUTE format($fn$
        CREATE OR REPLACE FUNCTION pggit.route_%I_update()
        RETURNS TRIGGER AS $inner$
        DECLARE
            v_branch TEXT;
            v_schema TEXT;
        BEGIN
            v_branch := current_setting('pggit.current_branch', true);
            IF v_branch IS NULL OR v_branch = '' OR v_branch = 'main' THEN
                UPDATE pggit_base.%I SET (%s) = (SELECT %s FROM (SELECT NEW.*) AS t) WHERE %s;
            ELSE
                v_schema := 'pggit_branch_' || replace(v_branch, '/', '_');
                EXECUTE format('UPDATE %%I.%I SET (%s) = (SELECT %s FROM (SELECT $1.*) AS t) WHERE %s', v_schema)
                USING NEW, OLD;
            END IF;
            RETURN NEW;
        END;
        $inner$ LANGUAGE plpgsql
    $fn$, p_table, v_base_table, v_all_columns, v_all_columns,
         COALESCE('(' || v_pk_columns || ') = (OLD.' || replace(v_pk_columns, ', ', ', OLD.') || ')', 'ctid = OLD.ctid'),
         p_table, v_all_columns, v_all_columns,
         COALESCE('(' || v_pk_columns || ') = ($2.' || replace(v_pk_columns, ', ', ', $2.') || ')', 'ctid = $2.ctid'));

    EXECUTE format(
        'CREATE TRIGGER %I_update INSTEAD OF UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION pggit.route_%I_update()',
        p_table, p_schema, p_table, p_table
    );

    -- Step 6: Create INSTEAD OF DELETE trigger function
    EXECUTE format($fn$
        CREATE OR REPLACE FUNCTION pggit.route_%I_delete()
        RETURNS TRIGGER AS $inner$
        DECLARE
            v_branch TEXT;
            v_schema TEXT;
        BEGIN
            v_branch := current_setting('pggit.current_branch', true);
            IF v_branch IS NULL OR v_branch = '' OR v_branch = 'main' THEN
                DELETE FROM pggit_base.%I WHERE %s;
            ELSE
                v_schema := 'pggit_branch_' || replace(v_branch, '/', '_');
                EXECUTE format('DELETE FROM %%I.%I WHERE %s', v_schema)
                USING OLD;
            END IF;
            RETURN OLD;
        END;
        $inner$ LANGUAGE plpgsql
    $fn$, p_table, v_base_table,
         COALESCE('(' || v_pk_columns || ') = (OLD.' || replace(v_pk_columns, ', ', ', OLD.') || ')', 'ctid = OLD.ctid'),
         p_table,
         COALESCE('(' || v_pk_columns || ') = ($1.' || replace(v_pk_columns, ', ', ', $1.') || ')', 'ctid = $1.ctid'));

    EXECUTE format(
        'CREATE TRIGGER %I_delete INSTEAD OF DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION pggit.route_%I_delete()',
        p_table, p_schema, p_table, p_table
    );

    RAISE NOTICE 'Set up view routing for %.%', p_schema, p_table;
END;
$$ LANGUAGE plpgsql;

-- Get the base table info for a routed table
-- Returns table name and schema as a composite
CREATE OR REPLACE FUNCTION pggit.get_base_table_info(
    p_schema TEXT,
    p_table TEXT,
    OUT base_schema TEXT,
    OUT base_table TEXT
) AS $$
BEGIN
    -- Check if this is a routed view
    IF EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = p_schema AND table_name = p_table
    ) THEN
        base_schema := 'pggit_base';
        base_table := '_pggit_main_' || p_table;
    ELSE
        base_schema := p_schema;
        base_table := p_table;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Create data branch with COW (array version for internal use)
CREATE OR REPLACE FUNCTION pggit.create_data_branch(
    p_branch_name TEXT,
    p_source_branch TEXT,
    p_tables TEXT[],
    p_use_cow BOOLEAN DEFAULT true
) RETURNS INT AS $$
DECLARE
    v_branch_schema TEXT;
    v_table TEXT;
    v_source_schema TEXT := 'public';
    v_base_info RECORD;
    v_branch_count INT := 0;
BEGIN
    -- Create branch schema
    v_branch_schema := 'pggit_branch_' || replace(p_branch_name, '/', '_');
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_branch_schema);

    -- Track branch in storage stats
    INSERT INTO pggit.branch_storage_stats (branch_name)
    VALUES (p_branch_name)
    ON CONFLICT (branch_name) DO NOTHING;

    -- Branch each table
    FOREACH v_table IN ARRAY p_tables LOOP
        -- Set up view routing if not already done
        PERFORM pggit.setup_table_routing(v_source_schema, v_table);

        -- Get the actual base table info (after routing setup)
        SELECT * INTO v_base_info FROM pggit.get_base_table_info(v_source_schema, v_table);

        -- Create branch copy from the base table
        EXECUTE format('CREATE TABLE %I.%I AS TABLE %I.%I',
            v_branch_schema, v_table,
            v_base_info.base_schema, v_base_info.base_table
        );

        -- Track branched table
        INSERT INTO pggit.branched_tables (
            branch_name, source_schema, source_table,
            branch_schema, branch_table, uses_cow
        ) VALUES (
            p_branch_name, v_source_schema, v_table,
            v_branch_schema, v_table, p_use_cow
        );

        v_branch_count := v_branch_count + 1;
    END LOOP;

    -- Update storage stats
    PERFORM pggit.update_branch_storage_stats(p_branch_name);

    RETURN v_branch_count;
END;
$$ LANGUAGE plpgsql;

-- Create data branch (simplified version for single table, test-friendly API)
CREATE OR REPLACE FUNCTION pggit.create_data_branch(
    p_table_name TEXT,
    p_source_branch TEXT,
    p_branch_name TEXT
) RETURNS INT AS $$
BEGIN
    -- Validate inputs
    IF p_table_name IS NULL OR p_table_name = '' THEN
        RAISE EXCEPTION 'Table name cannot be empty';
    END IF;

    IF p_branch_name IS NULL OR p_branch_name = '' THEN
        RAISE EXCEPTION 'Branch name cannot be empty';
    END IF;

    -- Delegate to array version with view-based routing
    RETURN pggit.create_data_branch(
        p_branch_name,
        p_source_branch,
        ARRAY[p_table_name]::TEXT[],
        true
    );
END;
$$ LANGUAGE plpgsql;

-- Create COW table branch (PostgreSQL 17+)
CREATE OR REPLACE FUNCTION pggit.create_cow_table_branch(
    p_source_schema TEXT,
    p_source_table TEXT,
    p_branch_schema TEXT,
    p_branch_table TEXT
) RETURNS VOID AS $$
BEGIN
    -- Use inheritance for COW-like behavior
    EXECUTE format(
        'CREATE TABLE %I.%I (LIKE %I.%I INCLUDING ALL) INHERITS (%I.%I)',
        p_branch_schema, p_branch_table,
        p_source_schema, p_source_table,
        p_source_schema, p_source_table
    );
    
    -- Add branch-specific system columns
    EXECUTE format(
        'ALTER TABLE %I.%I ADD COLUMN _pggit_branch_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP',
        p_branch_schema, p_branch_table
    );
    
    -- Create partial index for branch-specific rows
    EXECUTE format(
        'CREATE INDEX ON %I.%I (_pggit_branch_ts) WHERE _pggit_branch_ts IS NOT NULL',
        p_branch_schema, p_branch_table
    );
END;
$$ LANGUAGE plpgsql;

-- Switch active branch context
-- Uses session variable that view routing functions check at runtime
CREATE OR REPLACE FUNCTION pggit.switch_branch(
    p_branch_name TEXT
) RETURNS VOID AS $$
BEGIN
    -- Set session variable for current branch
    -- View router functions check this at query execution time (not plan time)
    PERFORM set_config('pggit.current_branch', COALESCE(p_branch_name, 'main'), false);
END;
$$ LANGUAGE plpgsql;

-- Create data branch with dependency tracking
CREATE OR REPLACE FUNCTION pggit.create_data_branch_with_dependencies(
    p_branch_name TEXT,
    p_source_branch TEXT,
    p_root_table TEXT,
    p_include_dependencies BOOLEAN DEFAULT true
) RETURNS TABLE (
    branch_name TEXT,
    tables_branched INT,
    branched_tables TEXT[]
) AS $$
DECLARE
    v_tables TEXT[] := ARRAY[]::TEXT[];
    v_processed TEXT[] := ARRAY[]::TEXT[];
    v_current_table TEXT;
    v_count INT;
BEGIN
    -- Start with root table
    v_tables := array_append(v_tables, p_root_table);
    
    -- Find all dependent tables if requested
    IF p_include_dependencies THEN
        v_tables := pggit.find_table_dependencies(p_root_table);
    END IF;
    
    -- Create branch with all tables
    v_count := pggit.create_data_branch(p_branch_name, p_source_branch, v_tables);
    
    RETURN QUERY
    SELECT p_branch_name, v_count, v_tables;
END;
$$ LANGUAGE plpgsql;

-- Find table dependencies
CREATE OR REPLACE FUNCTION pggit.find_table_dependencies(
    p_table_name TEXT,
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TEXT[] AS $$
DECLARE
    v_dependencies TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Find tables referenced by foreign keys
    -- Note: COLLATE "C" matches information_schema's collation
    WITH RECURSIVE deps AS (
        -- Start with the given table
        SELECT p_table_name COLLATE "C" AS table_name

        UNION

        -- Find all tables that reference current tables
        SELECT DISTINCT
            tc.table_name
        FROM deps d
        JOIN information_schema.table_constraints tc
            ON tc.constraint_type = 'FOREIGN KEY'
        JOIN information_schema.referential_constraints rc
            ON rc.constraint_name = tc.constraint_name
        JOIN information_schema.table_constraints tc2
            ON tc2.constraint_name = rc.unique_constraint_name
            AND tc2.table_name = d.table_name
        WHERE tc.table_schema = p_schema_name COLLATE "C"
    )
    SELECT array_agg(DISTINCT table_name) INTO v_dependencies FROM deps;
    
    RETURN v_dependencies;
END;
$$ LANGUAGE plpgsql;

-- Merge data branches with conflict detection
CREATE OR REPLACE FUNCTION pggit.merge_data_branches(
    p_source TEXT,
    p_target TEXT,
    p_conflict_resolution TEXT DEFAULT 'interactive'
) RETURNS TABLE (
    merge_id UUID,
    has_conflicts BOOLEAN,
    conflict_count INT,
    tables_merged INT
) AS $$
DECLARE
    v_merge_id UUID := gen_random_uuid();
    v_conflicts INT := 0;
    v_tables INT := 0;
    v_table RECORD;
BEGIN
    -- Find common tables between branches
    FOR v_table IN
        SELECT DISTINCT st.source_table
        FROM pggit.branched_tables st
        JOIN pggit.branched_tables tt 
            ON st.source_table = tt.source_table
        WHERE st.branch_name = p_source
        AND tt.branch_name = p_target
    LOOP
        -- Detect conflicts for this table
        v_conflicts := v_conflicts + pggit.detect_data_conflicts(
            v_merge_id, v_table.source_table, p_source, p_target
        );
        v_tables := v_tables + 1;
    END LOOP;
    
    -- Apply conflict resolution if no conflicts or auto-resolution requested
    IF v_conflicts = 0 OR p_conflict_resolution != 'interactive' THEN
        PERFORM pggit.apply_data_merge(v_merge_id, p_source, p_target, p_conflict_resolution);
    END IF;
    
    RETURN QUERY
    SELECT v_merge_id, v_conflicts > 0, v_conflicts, v_tables;
END;
$$ LANGUAGE plpgsql;

-- Detect data conflicts between branches
CREATE OR REPLACE FUNCTION pggit.detect_data_conflicts(
    p_merge_id UUID,
    p_table_name TEXT,
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS INT AS $$
DECLARE
    v_conflicts INT := 0;
    v_key_columns TEXT;
    v_sql TEXT;
    v_base_table TEXT;
BEGIN
    -- Get primary key columns from the base table (the original table, not branch copies or view)
    -- Branch copies made with CREATE TABLE AS don't preserve PK constraints
    v_base_table := 'pggit_base._pggit_main_' || p_table_name;
    BEGIN
        SELECT string_agg(a.attname, ', ' ORDER BY array_position(i.indkey, a.attnum))
        INTO v_key_columns
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = v_base_table::regclass
        AND i.indisprimary;
    EXCEPTION WHEN undefined_table THEN
        -- If base table doesn't exist, try the original table name
        SELECT string_agg(a.attname, ', ' ORDER BY array_position(i.indkey, a.attnum))
        INTO v_key_columns
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = p_table_name::regclass
        AND i.indisprimary;
    END;

    -- If no primary key found, skip conflict detection
    IF v_key_columns IS NULL THEN
        RAISE NOTICE 'No primary key found for %, skipping conflict detection', p_table_name;
        RETURN 0;
    END IF;
    
    -- Build conflict detection query
    -- Note: Use %I for schema names to properly quote identifiers with special chars (like hyphens)
    v_sql := format($SQL$
        INSERT INTO pggit.data_conflicts (
            merge_id, table_name, primary_key_value,
            source_branch, target_branch,
            source_data, target_data, conflict_type
        )
        SELECT
            %L, %L, s.%I::TEXT,
            %L, %L,
            row_to_json(s.*), row_to_json(t.*),
            CASE
                WHEN s.* IS NULL THEN 'delete-update'
                WHEN t.* IS NULL THEN 'update-delete'
                ELSE 'update-update'
            END
        FROM %I.%I s
        FULL OUTER JOIN %I.%I t
            ON s.%I = t.%I
        WHERE s.* IS DISTINCT FROM t.*
        AND (s.* IS NOT NULL OR t.* IS NOT NULL)
    $SQL$,
        p_merge_id, p_table_name, v_key_columns,
        p_source_branch, p_target_branch,
        'pggit_branch_' || replace(p_source_branch, '/', '_'), p_table_name,
        'pggit_branch_' || replace(p_target_branch, '/', '_'), p_table_name,
        v_key_columns, v_key_columns
    );
    
    EXECUTE v_sql;
    GET DIAGNOSTICS v_conflicts = ROW_COUNT;
    
    RETURN v_conflicts;
END;
$$ LANGUAGE plpgsql;

-- Apply data merge
CREATE OR REPLACE FUNCTION pggit.apply_data_merge(
    p_merge_id UUID,
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_resolution_strategy TEXT
) RETURNS VOID AS $$
DECLARE
    v_conflict RECORD;
    v_source_schema TEXT := 'pggit_branch_' || replace(p_source_branch, '/', '_');
    v_target_schema TEXT := 'pggit_branch_' || replace(p_target_branch, '/', '_');
BEGIN
    -- Update conflict resolutions based on strategy
    UPDATE pggit.data_conflicts
    SET resolution = CASE p_resolution_strategy
        WHEN 'source-wins' THEN 'source'
        WHEN 'target-wins' THEN 'target'
        WHEN 'theirs' THEN 'source'
        WHEN 'ours' THEN 'target'
        WHEN 'newer' THEN
            CASE WHEN (source_data->>'_pggit_timestamp')::timestamp >
                     (target_data->>'_pggit_timestamp')::timestamp
            THEN 'source' ELSE 'target' END
        ELSE 'manual'
    END,
    resolved_by = CURRENT_USER,
    resolved_at = CURRENT_TIMESTAMP
    WHERE merge_id = p_merge_id
    AND resolution = 'pending';

    -- Apply source-wins resolutions
    FOR v_conflict IN
        SELECT DISTINCT table_name
        FROM pggit.data_conflicts
        WHERE merge_id = p_merge_id
        AND resolution = 'source'
    LOOP
        -- Insert or update rows from source into target
        BEGIN
            EXECUTE format(
                'INSERT INTO %I.%I SELECT s.* FROM %I.%I s ' ||
                'ON CONFLICT (id) DO UPDATE SET (LIKE EXCLUDED) = (SELECT (LIKE EXCLUDED))',
                v_target_schema, v_conflict.table_name,
                v_source_schema, v_conflict.table_name
            );
        EXCEPTION WHEN OTHERS THEN
            -- If ON CONFLICT not supported, do simple insert
            EXECUTE format(
                'INSERT INTO %I.%I SELECT s.* FROM %I.%I s ' ||
                'WHERE NOT EXISTS (SELECT 1 FROM %I.%I t WHERE t.id = s.id)',
                v_target_schema, v_conflict.table_name,
                v_source_schema, v_conflict.table_name,
                v_target_schema, v_conflict.table_name
            );
        END;
    END LOOP;

    -- For target-wins, just insert new rows from source (don't update existing)
    FOR v_conflict IN
        SELECT DISTINCT table_name
        FROM pggit.data_conflicts
        WHERE merge_id = p_merge_id
        AND resolution = 'target'
    LOOP
        BEGIN
            EXECUTE format(
                'INSERT INTO %I.%I SELECT s.* FROM %I.%I s ' ||
                'WHERE NOT EXISTS (SELECT 1 FROM %I.%I t WHERE t.id = s.id)',
                v_target_schema, v_conflict.table_name,
                v_source_schema, v_conflict.table_name,
                v_target_schema, v_conflict.table_name
            );
        EXCEPTION WHEN OTHERS THEN
            -- Skip if insert fails
            NULL;
        END;
    END LOOP;

    -- Log merge completion
    RAISE NOTICE 'Data merge % completed with strategy %', p_merge_id, p_resolution_strategy;
END;
$$ LANGUAGE plpgsql;

-- Create temporal branch (point-in-time snapshot)
CREATE OR REPLACE FUNCTION pggit.create_temporal_branch(
    p_branch_name TEXT,
    p_source_branch TEXT,
    p_point_in_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS UUID AS $$
DECLARE
    v_snapshot_id UUID := gen_random_uuid();
    v_branch_schema TEXT := 'pggit_branch_' || replace(p_branch_name, '/', '_');
    v_source_schema TEXT := 'pggit_branch_' || replace(p_source_branch, '/', '_');
    v_table RECORD;
BEGIN
    -- Create new branch schema for temporal snapshot
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_branch_schema);

    -- For each table in source branch, create snapshot at p_point_in_time
    FOR v_table IN
        SELECT source_table FROM pggit.branched_tables
        WHERE branch_name = p_source_branch
    LOOP
        -- Create snapshot table (copy of current state)
        -- Note: True point-in-time recovery requires audit tables
        BEGIN
            EXECUTE format(
                'CREATE TABLE %I.%I AS TABLE %I.%I',
                v_branch_schema, v_table.source_table,
                v_source_schema, v_table.source_table
            );

            -- Add temporal metadata
            EXECUTE format(
                'ALTER TABLE %I.%I ADD COLUMN _pggit_snapshot_time TIMESTAMP DEFAULT %L',
                v_branch_schema, v_table.source_table,
                p_point_in_time
            );

        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Could not create temporal snapshot for table %: %',
                v_table.source_table, SQLERRM;
        END;

        -- Track this snapshot
        INSERT INTO pggit.branch_storage_stats (branch_name)
        VALUES (p_branch_name)
        ON CONFLICT (branch_name) DO NOTHING;
    END LOOP;

    RAISE NOTICE 'Temporal snapshot % created from branch % at %',
        v_snapshot_id, p_source_branch, p_point_in_time;

    RETURN v_snapshot_id;
END;
$$ LANGUAGE plpgsql;

-- Optimize branch storage
CREATE OR REPLACE FUNCTION pggit.optimize_branch_storage(
    p_branch TEXT,
    p_compression TEXT DEFAULT 'lz4',
    p_deduplicate BOOLEAN DEFAULT true
) RETURNS TABLE (
    branch TEXT,
    space_saved_mb DECIMAL,
    compression_ratio DECIMAL,
    optimization_time_ms INT
) AS $$
DECLARE
    v_start_time TIMESTAMP := clock_timestamp();
    v_original_size BIGINT;
    v_new_size BIGINT;
BEGIN
    -- Get original size
    SELECT total_size INTO v_original_size
    FROM pggit.branch_storage_stats
    WHERE branch_name = p_branch;
    
    -- Apply compression (PostgreSQL 14+)
    IF current_setting('server_version_num')::int >= 140000 THEN
        PERFORM pggit.compress_branch_tables(p_branch, p_compression);
    END IF;
    
    -- Deduplicate if requested
    IF p_deduplicate THEN
        PERFORM pggit.deduplicate_branch_data(p_branch);
    END IF;
    
    -- Update stats
    PERFORM pggit.update_branch_storage_stats(p_branch);
    
    -- Get new size
    SELECT total_size INTO v_new_size
    FROM pggit.branch_storage_stats
    WHERE branch_name = p_branch;
    
    RETURN QUERY
    SELECT 
        p_branch,
        (v_original_size - v_new_size) / 1024.0 / 1024.0,
        v_original_size::DECIMAL / NULLIF(v_new_size, 0),
        EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start_time)::INT;
END;
$$ LANGUAGE plpgsql;

-- Update branch storage statistics
CREATE OR REPLACE FUNCTION pggit.update_branch_storage_stats(
    p_branch_name TEXT
) RETURNS VOID AS $$
DECLARE
    v_total_size BIGINT := 0;
    v_total_rows BIGINT := 0;
    v_row RECORD;
BEGIN
    -- Calculate total size and rows for branch
    -- Use defensive approach: only sum sizes if tables exist
    FOR v_row IN
        SELECT branch_schema, branch_table
        FROM pggit.branched_tables
        WHERE branch_name = p_branch_name
    LOOP
        BEGIN
            -- Try to get size of this table
            v_total_size := v_total_size + COALESCE(
                pg_total_relation_size(format('%I.%I', v_row.branch_schema, v_row.branch_table)::regclass),
                0
            );
        EXCEPTION WHEN OTHERS THEN
            -- Table doesn't exist yet, skip it
            NULL;
        END;
    END LOOP;

    -- Get row counts from statistics
    SELECT
        COALESCE(SUM(n_live_tup), 0)
    INTO v_total_rows
    FROM pggit.branched_tables bt
    LEFT JOIN pg_stat_user_tables st
        ON st.schemaname = bt.branch_schema
        AND st.relname = bt.branch_table
    WHERE bt.branch_name = p_branch_name;

    -- Update stats
    UPDATE pggit.branch_storage_stats
    SET
        total_size = v_total_size,
        row_count = v_total_rows,
        last_modified = CURRENT_TIMESTAMP
    WHERE branch_name = p_branch_name;
END;
$$ LANGUAGE plpgsql;

-- Compress branch tables using column-level compression
CREATE OR REPLACE FUNCTION pggit.compress_branch_tables(
    p_branch TEXT,
    p_compression TEXT
) RETURNS VOID AS $$
DECLARE
    v_table RECORD;
    v_column RECORD;
    v_branch_schema TEXT := 'pggit_branch_' || replace(p_branch, '/', '_');
BEGIN
    -- For PostgreSQL 15+, apply column-level compression
    IF current_setting('server_version_num')::int >= 150000 THEN
        FOR v_table IN
            SELECT source_table FROM pggit.branched_tables
            WHERE branch_name = p_branch
        LOOP
            FOR v_column IN
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = v_branch_schema
                AND table_name = v_table.source_table
                AND data_type IN ('text', 'jsonb', 'bytea')
            LOOP
                BEGIN
                    EXECUTE format(
                        'ALTER TABLE %I.%I ALTER COLUMN %I SET COMPRESSION %s',
                        v_branch_schema, v_table.source_table,
                        v_column.column_name,
                        upper(p_compression)
                    );
                EXCEPTION WHEN OTHERS THEN
                    -- Skip if column doesn't support compression
                    NULL;
                END;
            END LOOP;
        END LOOP;
    END IF;

    RAISE NOTICE 'Branch % compression with % completed', p_branch, p_compression;
END;
$$ LANGUAGE plpgsql;

-- Deduplicate branch data (especially useful for ZSTD compression)
CREATE OR REPLACE FUNCTION pggit.deduplicate_branch_data(
    p_branch TEXT
) RETURNS VOID AS $$
DECLARE
    v_table RECORD;
    v_branch_schema TEXT := 'pggit_branch_' || replace(p_branch, '/', '_');
    v_dup_count INT := 0;
BEGIN
    -- Identify and mark duplicate rows within each table
    FOR v_table IN
        SELECT source_table FROM pggit.branched_tables
        WHERE branch_name = p_branch
    LOOP
        -- Find duplicate rows (same content)
        EXECUTE format(
            'WITH ranked AS (
                SELECT ctid, row_number() OVER (PARTITION BY * ORDER BY ctid DESC) as rn
                FROM %I.%I
            )
            DELETE FROM %I.%I WHERE ctid IN (
                SELECT ctid FROM ranked WHERE rn > 1
            )',
            v_branch_schema, v_table.source_table,
            v_branch_schema, v_table.source_table
        );

        GET DIAGNOSTICS v_dup_count = ROW_COUNT;

        RAISE NOTICE 'Removed % duplicate rows from %', v_dup_count, v_table.source_table;
    END LOOP;

    RAISE NOTICE 'Deduplication for branch % completed', p_branch;
END;
$$ LANGUAGE plpgsql;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_branched_tables_branch 
ON pggit.branched_tables(branch_name);

CREATE INDEX IF NOT EXISTS idx_data_conflicts_merge 
ON pggit.data_conflicts(merge_id);

CREATE INDEX IF NOT EXISTS idx_data_conflicts_resolution 
ON pggit.data_conflicts(resolution) WHERE resolution = 'pending';

-- Grant permissions
GRANT ALL ON SCHEMA pggit_branches TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;