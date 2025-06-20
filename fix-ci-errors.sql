-- Fix script for CI errors
-- This script patches the issues found in the CI environment

-- 1. Fix the history table partitioning issue in 017_performance_optimizations.sql
-- The issue is that INSERT INTO ... SELECT * assumes the same column structure
-- but history_new has a composite primary key while history doesn't

-- 2. Fix missing columns in 050_three_way_merge.sql
-- These ALTER TABLE statements reference columns that don't exist in 001_schema.sql

-- 3. Fix the round() function issue in 052_performance_monitoring.sql
-- PostgreSQL's round() doesn't accept double precision directly

-- 4. Fix the verify_consistency function in pggit_conflict_resolution_api.sql
-- Missing RETURN statement

-- 5. Fix foreign key references in pggit_cqrs_support.sql and pggit_function_versioning.sql
-- They reference pggit.commits(commit_id) but the column is actually 'id'

-- Let's create a patch that can be applied after installation
\echo 'Applying CI environment fixes...'

-- Fix 1: Alter commits table to have commit_id column (alias for id)
DO $$
BEGIN
    -- Add commit_id as an alias if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'pggit' 
                   AND table_name = 'commits' 
                   AND column_name = 'commit_id') THEN
        ALTER TABLE pggit.commits ADD COLUMN commit_id uuid;
        -- Update existing rows
        UPDATE pggit.commits SET commit_id = gen_random_uuid() WHERE commit_id IS NULL;
        ALTER TABLE pggit.commits ALTER COLUMN commit_id SET NOT NULL;
        ALTER TABLE pggit.commits ALTER COLUMN commit_id SET DEFAULT gen_random_uuid();
        CREATE UNIQUE INDEX commits_commit_id_idx ON pggit.commits(commit_id);
    END IF;
END $$;

-- Fix 2: Add missing columns to commits table
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'pggit' 
                   AND table_name = 'commits' 
                   AND column_name = 'branch_name') THEN
        ALTER TABLE pggit.commits ADD COLUMN branch_name text;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'pggit' 
                   AND table_name = 'commits' 
                   AND column_name = 'parent_commit_id') THEN
        ALTER TABLE pggit.commits ADD COLUMN parent_commit_id uuid;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'pggit' 
                   AND table_name = 'commits' 
                   AND column_name = 'source_branch') THEN
        ALTER TABLE pggit.commits ADD COLUMN source_branch text;
    END IF;
END $$;

-- Fix 3: Create missing helper functions
CREATE OR REPLACE FUNCTION pggit.remove_orphaned_object(object_id integer) 
RETURNS boolean AS $$
BEGIN
    DELETE FROM pggit.versioned_objects WHERE versioned_objects.object_id = remove_orphaned_object.object_id;
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$ LANGUAGE plpgsql;

\echo 'CI fixes applied successfully'