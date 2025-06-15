-- pggit Basic Branching Example
-- This example demonstrates basic database branching capabilities

-- Prerequisites: pggit extension installed
-- CREATE EXTENSION pggit;

-- ==================================================
-- 1. Create a Simple Schema
-- ==================================================

-- Start with a basic user management schema
CREATE SCHEMA IF NOT EXISTS main;

CREATE TABLE main.users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE main.roles (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE main.user_roles (
    user_id INTEGER REFERENCES main.users(id),
    role_id INTEGER REFERENCES main.roles(id),
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id)
);

-- Add some initial data
INSERT INTO main.roles (name, description) VALUES
('admin', 'Full system administrator'),
('editor', 'Can edit content'),
('viewer', 'Read-only access');

INSERT INTO main.users (username, email, full_name) VALUES
('alice', 'alice@example.com', 'Alice Johnson'),
('bob', 'bob@example.com', 'Bob Smith'),
('carol', 'carol@example.com', 'Carol Davis');

INSERT INTO main.user_roles (user_id, role_id) VALUES
(1, 1), -- alice is admin
(2, 2), -- bob is editor
(3, 3); -- carol is viewer

-- ==================================================
-- 2. Create a Feature Branch
-- ==================================================

-- Create a branch for adding user profiles feature
SELECT pggit.create_data_branch('feature/user-profiles', 'main', true);

-- Switch to the feature branch
SELECT pggit.checkout_branch('feature/user-profiles');

-- Add new profile table in the branch
CREATE TABLE users_profiles (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    bio TEXT,
    avatar_url TEXT,
    website_url TEXT,
    location TEXT,
    preferences JSONB DEFAULT '{}',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add profile data for existing users
INSERT INTO users_profiles (user_id, bio, preferences) VALUES
(1, 'System administrator with 10 years experience', '{"theme": "dark", "notifications": true}'),
(2, 'Content editor and writer', '{"theme": "light", "language": "en"}'),
(3, 'Data analyst and viewer', '{"theme": "auto", "timezone": "UTC"}');

-- Modify the users table to add a profile indicator
ALTER TABLE users ADD COLUMN has_profile BOOLEAN DEFAULT false;
UPDATE users SET has_profile = true WHERE id IN (1, 2, 3);

-- ==================================================
-- 3. Create Another Branch for Different Feature
-- ==================================================

-- Create a branch for adding authentication features
SELECT pggit.create_data_branch('feature/authentication', 'main', true);

-- Switch to authentication branch
SELECT pggit.checkout_branch('feature/authentication');

-- Add authentication columns (different from profile feature)
ALTER TABLE users ADD COLUMN password_hash TEXT;
ALTER TABLE users ADD COLUMN two_factor_enabled BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN last_login TIMESTAMP;

-- Create sessions table
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER REFERENCES users(id),
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==================================================
-- 4. Check Branch Differences
-- ==================================================

-- See what branches exist
SELECT * FROM pggit.list_branches();

-- Check storage efficiency
SELECT * FROM pggit.get_branch_storage_stats();

-- ==================================================
-- 5. Merge Profile Feature to Main
-- ==================================================

-- First, validate the branch
SELECT * FROM pggit.validate_branch_integrity('feature/user-profiles');

-- Merge the user profiles feature
SELECT pggit.merge_branches('feature/user-profiles', 'main');

-- Switch back to main to see the changes
SELECT pggit.checkout_branch('main');

-- Verify the profile table exists in main
SELECT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'main' AND table_name = 'users_profiles'
) as profile_table_merged;

-- ==================================================
-- 6. Handle Potential Conflicts
-- ==================================================

-- Try to merge authentication branch (may have conflicts)
SELECT pggit.merge_branches('feature/authentication', 'main');

-- If conflicts detected, you would see:
-- CONFLICTS_DETECTED:merge_id_xyz

-- In case of conflicts, you can:
-- 1. Review conflicts
-- 2. Auto-resolve with strategy
-- 3. Manual resolution

-- ==================================================
-- 7. Cleanup
-- ==================================================

-- List merged branches that can be cleaned up
SELECT pggit.cleanup_merged_branches(true); -- dry run

-- Actually clean up merged branches
-- SELECT pggit.cleanup_merged_branches(false);

-- ==================================================
-- Example Output Summary
-- ==================================================

/*
This example demonstrated:
1. Creating a production-like schema with relationships
2. Creating isolated feature branches with real data
3. Making independent changes in different branches
4. Merging completed features back to main
5. Handling potential conflicts between branches
6. Monitoring storage efficiency throughout

Key benefits shown:
- Complete isolation between features
- Safe experimentation without affecting main
- Automatic conflict detection
- Storage efficiency through copy-on-write
- Git-like workflow for databases
*/