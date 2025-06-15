-- Example usage of the database versioning system
-- This demonstrates how the PostgreSQL-only implementation works

-- First, let's create the extension (run scripts 001-004 first)
-- \i 001_schema.sql
-- \i 002_event_triggers.sql
-- \i 003_migration_functions.sql
-- \i 004_utility_views.sql

-- Example 1: Create a table (automatically tracked by event triggers)
CREATE TABLE public.customers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Check the version
SELECT * FROM pggit.get_version('public.customers');

-- Example 2: Alter the table (version automatically incremented)
ALTER TABLE public.customers 
ADD COLUMN phone VARCHAR(20);

ALTER TABLE public.customers 
ADD COLUMN is_active BOOLEAN DEFAULT true;

-- View version history
SELECT * FROM pggit.get_history('public.customers');

-- Example 3: Create related table with foreign key
CREATE TABLE public.orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending'
);

-- The system automatically detects the foreign key dependency
SELECT * FROM pggit.dependency_graph 
WHERE dependent_name LIKE '%orders%' OR depends_on_name LIKE '%orders%';

-- Example 4: Impact analysis - what would be affected if we change customers table?
SELECT * FROM pggit.get_impact_analysis('public.customers');

-- Example 5: Make a breaking change
ALTER TABLE public.customers 
ALTER COLUMN name TYPE VARCHAR(200);

-- This is tracked as a major version change
SELECT * FROM pggit.recent_changes 
WHERE object_name = 'public.customers';

-- Example 6: Generate a migration script for current changes
SELECT pggit.generate_migration(
    'v1.0.0',
    'Initial customer and order tables setup'
);

-- Example 7: View all table versions
SELECT * FROM pggit.show_table_versions();

-- Example 8: Create a view (also tracked)
CREATE VIEW public.active_customers AS
SELECT id, email, name, phone
FROM customers
WHERE is_active = true;

-- Example 9: Check compatibility between related objects
SELECT * FROM pggit.check_compatibility(
    'public.orders',
    'public.customers'
);

-- Example 10: Generate a comprehensive version report
SELECT * FROM pggit.generate_version_report('public');

-- Example 11: View pending migrations
SELECT * FROM pggit.pending_migrations;

-- Example 12: Create an index (tracked with parent relationship)
CREATE INDEX idx_customers_email ON public.customers(email);

-- View the complete object hierarchy
SELECT 
    object_type,
    full_name,
    version_string,
    parent_name
FROM pggit.object_versions
WHERE full_name LIKE '%customer%'
ORDER BY object_type, full_name;

-- Example 13: Detect schema changes
-- First, make a change outside of the tracking system
ALTER TABLE public.customers 
ADD COLUMN loyalty_points INTEGER DEFAULT 0;

-- Now detect untracked changes
SELECT * FROM pggit.detect_schema_changes('public');

-- Example 14: View high-change objects (potential areas of instability)
SELECT report_data 
FROM pggit.generate_version_report('public')
WHERE report_section = 'high_change_objects';

-- Example 15: Clean demonstration - drop a table
DROP TABLE public.orders CASCADE;

-- The system marks it as inactive and records the drop
SELECT * FROM pggit.recent_changes 
WHERE change_type = 'DROP';

-- Summary: Key functions to remember
-- 
-- pggit.get_version(object_name) - Get current version
-- pggit.get_history(object_name) - Get version history
-- pggit.get_impact_analysis(object_name) - See what depends on an object
-- pggit.generate_migration() - Create migration scripts
-- pggit.show_table_versions() - Quick overview of all tables
-- pggit.detect_schema_changes() - Find untracked changes
-- pggit.generate_version_report() - Comprehensive report

-- The system tracks all DDL changes automatically through event triggers!