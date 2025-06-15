-- Complete Workflow Example: E-commerce Database with pg_gitversion
-- This demonstrates real usage of pg_gitversion's automatic tracking

-- ============================================
-- PART 1: Install Extension
-- ============================================

CREATE EXTENSION IF NOT EXISTS pg_gitversion;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_gitversion';

-- ============================================
-- PART 2: Create Initial Schema
-- ============================================

-- All DDL commands are automatically tracked!

CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES categories(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_categories_parent ON categories(parent_id);
CREATE INDEX idx_categories_slug ON categories(slug);

-- Check the automatic versioning
SELECT * FROM gitversion.get_version('public.categories');
-- Notice: Version 1 (1.0.0) - automatically tracked!

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    category_id INTEGER REFERENCES categories(id),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER DEFAULT 0 CHECK (stock_quantity >= 0),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_active ON products(is_active) WHERE is_active = true;

-- View all tracked objects so far
SELECT 
    object_type,
    full_name,
    version_string,
    created_at
FROM gitversion.object_versions
ORDER BY created_at;

-- ============================================
-- PART 3: Check Dependencies
-- ============================================

-- Detect all foreign key dependencies
SELECT gitversion.detect_foreign_keys();

-- View the dependency graph
SELECT * FROM gitversion.dependency_graph;

-- See what depends on categories
SELECT * FROM gitversion.get_impact_analysis('public.categories');

-- ============================================
-- PART 4: Schema Evolution
-- ============================================

-- Add new features (all automatically tracked)
ALTER TABLE products ADD COLUMN weight_kg DECIMAL(8,3);
ALTER TABLE products ADD COLUMN dimensions_cm JSONB;

-- Check version bump
SELECT * FROM gitversion.get_version('public.products');
-- Version increased! Minor bump for new columns

-- View the history
SELECT * FROM gitversion.get_history('public.products');

-- Add a breaking change
ALTER TABLE products ALTER COLUMN description SET NOT NULL;

-- Check version again
SELECT * FROM gitversion.get_version('public.products');
-- Major version bump for breaking change!

-- ============================================
-- PART 5: Create More Tables
-- ============================================

CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0)
);

-- Update dependencies
SELECT gitversion.detect_foreign_keys();

-- ============================================
-- PART 6: View Current State
-- ============================================

-- Summary of all tables
SELECT * FROM gitversion.show_table_versions();

-- Recent changes
SELECT 
    rc.change_type,
    rc.object_type,
    rc.full_name,
    rc.change_description,
    rc.created_at,
    rc.created_by
FROM gitversion.recent_changes rc
LIMIT 20;

-- Object counts by type
SELECT 
    object_type,
    COUNT(*) as count,
    MAX(version) as highest_version
FROM gitversion.objects
WHERE is_active = true
GROUP BY object_type
ORDER BY object_type;

-- ============================================
-- PART 7: Generate Migration
-- ============================================

-- Generate a migration script for all changes
SELECT gitversion.generate_migration(
    'initial_schema_v1',
    'Complete e-commerce schema with products, orders, and customers'
);

-- View the generated migration
SELECT 
    version,
    description,
    created_at,
    length(up_script) as up_script_size,
    length(down_script) as down_script_size
FROM gitversion.migrations
WHERE version = 'initial_schema_v1';

-- To see the actual migration scripts:
SELECT up_script FROM gitversion.migrations WHERE version = 'initial_schema_v1';

-- ============================================
-- PART 8: More Schema Changes
-- ============================================

-- Add inventory tracking
CREATE TABLE inventory_movements (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id),
    movement_type VARCHAR(20) NOT NULL,
    quantity INTEGER NOT NULL,
    reference_type VARCHAR(50),
    reference_id INTEGER,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add wishlists
CREATE TABLE wishlists (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    product_id INTEGER NOT NULL REFERENCES products(id),
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(customer_id, product_id)
);

-- Complex view
CREATE VIEW order_summary AS
SELECT 
    o.id,
    o.order_number,
    c.email as customer_email,
    c.first_name || ' ' || c.last_name as customer_name,
    o.status,
    o.total_amount,
    COUNT(oi.id) as item_count,
    o.created_at
FROM orders o
JOIN customers c ON c.id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, o.order_number, c.email, c.first_name, c.last_name, 
         o.status, o.total_amount, o.created_at;

-- ============================================
-- PART 9: Dependency Analysis
-- ============================================

-- What happens if we want to change products table?
SELECT * FROM gitversion.get_impact_analysis('public.products');
-- Shows: order_items, inventory_movements, wishlists depend on it!

-- Check for circular dependencies
SELECT 
    o.full_name,
    gitversion.has_circular_dependency(o.id) as has_circular
FROM gitversion.objects o
WHERE o.object_type = 'TABLE' AND o.is_active = true;

-- Get safe drop order (reverse dependency order)
SELECT 
    unnest(gitversion.get_dependency_order(
        ARRAY(SELECT id FROM gitversion.objects WHERE object_type = 'TABLE' AND is_active = true)
    )) as object_id
) 
SELECT 
    o.full_name,
    o.object_type
FROM gitversion.objects o
WHERE o.id = object_id;

-- ============================================
-- PART 10: Generate Version Report
-- ============================================

-- Comprehensive report
SELECT * FROM gitversion.generate_version_report('public');

-- Custom summary query
SELECT 
    'Summary' as metric,
    COUNT(DISTINCT o.id) as total_objects,
    COUNT(DISTINCT h.id) as total_changes,
    MAX(o.version) as highest_version,
    COUNT(DISTINCT DATE(h.created_at)) as days_active
FROM gitversion.objects o
LEFT JOIN gitversion.history h ON h.object_id = o.id
WHERE o.is_active = true;

-- Changes by user
SELECT 
    created_by,
    COUNT(*) as change_count,
    COUNT(DISTINCT DATE(created_at)) as active_days,
    MIN(created_at) as first_change,
    MAX(created_at) as last_change
FROM gitversion.history
GROUP BY created_by
ORDER BY change_count DESC;

-- ============================================
-- PART 11: Schema Documentation
-- ============================================

-- Add comments (tracked as patch version changes)
COMMENT ON TABLE products IS 'Core product catalog';
COMMENT ON COLUMN products.sku IS 'Stock keeping unit - must be unique';
COMMENT ON COLUMN products.dimensions_cm IS 'JSON object with width, height, depth in centimeters';

-- Check version after comments
SELECT * FROM gitversion.get_version('public.products');
-- Patch version increased!

-- ============================================
-- PART 12: Generate Final Migration
-- ============================================

-- Generate migration for new changes
SELECT gitversion.generate_migration(
    'add_inventory_and_wishlists',
    'Added inventory tracking, wishlists, and order summary view'
);

-- List all migrations
SELECT 
    version,
    description,
    created_at,
    applied_at,
    CASE 
        WHEN applied_at IS NULL THEN 'Pending'
        ELSE 'Applied'
    END as status
FROM gitversion.migrations
ORDER BY created_at;

-- ============================================
-- BONUS: Useful Queries
-- ============================================

-- Find most changed objects
SELECT 
    o.full_name,
    o.object_type,
    o.version,
    COUNT(h.id) as change_count
FROM gitversion.objects o
JOIN gitversion.history h ON h.object_id = o.id
WHERE o.is_active = true
GROUP BY o.id, o.full_name, o.object_type, o.version
ORDER BY change_count DESC
LIMIT 10;

-- Version timeline
SELECT 
    DATE(created_at) as change_date,
    COUNT(*) as changes_made,
    COUNT(DISTINCT object_id) as objects_changed,
    STRING_AGG(DISTINCT change_type::TEXT, ', ') as change_types
FROM gitversion.history
GROUP BY DATE(created_at)
ORDER BY change_date DESC;

-- Schema complexity metrics
SELECT 
    'Tables' as object_type, COUNT(*) as count FROM gitversion.objects WHERE object_type = 'TABLE' AND is_active = true
UNION ALL
SELECT 'Columns', COUNT(*) FROM gitversion.objects WHERE object_type = 'COLUMN' AND is_active = true  
UNION ALL
SELECT 'Indexes', COUNT(*) FROM gitversion.objects WHERE object_type = 'INDEX' AND is_active = true
UNION ALL
SELECT 'Constraints', COUNT(*) FROM gitversion.objects WHERE object_type = 'CONSTRAINT' AND is_active = true
UNION ALL
SELECT 'Dependencies', COUNT(*) FROM gitversion.dependencies;