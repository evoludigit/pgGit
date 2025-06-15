-- pggit Conflict Resolution Example
-- Demonstrates handling merge conflicts between database branches

-- Prerequisites: pggit extension installed
-- This example shows various conflict scenarios and resolution strategies

-- ==================================================
-- 1. Setup Base Schema
-- ==================================================

-- Create main schema with a products table
CREATE SCHEMA IF NOT EXISTS main;

CREATE TABLE main.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    category TEXT,
    in_stock INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add some initial data
INSERT INTO main.products (name, price, category, in_stock, metadata) VALUES
('Laptop Pro', 1299.99, 'Electronics', 50, '{"brand": "TechCorp", "warranty": "2 years"}'),
('Office Chair', 299.99, 'Furniture', 120, '{"color": "black", "material": "mesh"}'),
('Coffee Maker', 89.99, 'Appliances', 75, '{"capacity": "12 cups", "type": "drip"}'),
('Desk Lamp', 49.99, 'Furniture', 200, '{"bulb": "LED", "adjustable": true}'),
('Notebook Set', 19.99, 'Stationery', 500, '{"pages": 200, "ruling": "lined"}');

-- ==================================================
-- 2. Create Conflicting Branches
-- ==================================================

-- Branch 1: Add discount system
SELECT pggit.create_data_branch('feature/discount-system', 'main', true);
SELECT pggit.checkout_branch('feature/discount-system');

-- Add discount column and update prices
ALTER TABLE products ADD COLUMN discount_percentage INTEGER DEFAULT 0;
ALTER TABLE products ADD COLUMN sale_price DECIMAL(10,2);

-- Apply discounts
UPDATE products 
SET discount_percentage = 15,
    sale_price = price * 0.85
WHERE category = 'Electronics';

UPDATE products 
SET discount_percentage = 10,
    sale_price = price * 0.90
WHERE category = 'Furniture';

-- Add discount tracking table
CREATE TABLE discount_history (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2),
    discount_percentage INTEGER,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Branch 2: Add inventory management (will conflict)
SELECT pggit.create_data_branch('feature/inventory-mgmt', 'main', true);
SELECT pggit.checkout_branch('feature/inventory-mgmt');

-- Modify the same table differently
ALTER TABLE products ADD COLUMN min_stock_level INTEGER DEFAULT 10;
ALTER TABLE products ADD COLUMN max_stock_level INTEGER DEFAULT 1000;
ALTER TABLE products ADD COLUMN reorder_point INTEGER DEFAULT 20;

-- Also modify metadata (will cause data conflict)
UPDATE products 
SET metadata = metadata || '{"inventory": {"tracked": true, "location": "warehouse-A"}}'
WHERE category IN ('Electronics', 'Appliances');

-- Add inventory table
CREATE TABLE inventory_movements (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    movement_type TEXT, -- 'IN' or 'OUT'
    quantity INTEGER,
    reason TEXT,
    moved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Branch 3: Modify constraints (complex conflict)
SELECT pggit.create_data_branch('feature/data-quality', 'main', true);
SELECT pggit.checkout_branch('feature/data-quality');

-- Add constraints that might conflict with data in other branches
ALTER TABLE products ADD CONSTRAINT price_check CHECK (price > 0);
ALTER TABLE products ADD CONSTRAINT name_length CHECK (length(name) >= 3);
ALTER TABLE products ALTER COLUMN category SET NOT NULL;

-- Modify the same metadata differently
UPDATE products 
SET metadata = metadata || '{"quality": {"verified": true, "last_check": "2024-01-01"}}'
WHERE id <= 3;

-- ==================================================
-- 3. Attempt Merges and Handle Conflicts
-- ==================================================

-- First, merge discount system to main
SELECT pggit.checkout_branch('main');
SELECT pggit.merge_branches('feature/discount-system', 'main');
-- Should succeed as it's the first merge

-- Now try to merge inventory management (will have conflicts)
SELECT pggit.merge_branches('feature/inventory-mgmt', 'main') AS merge_result;

-- The result will be 'CONFLICTS_DETECTED:merge_id_xyz'
-- Let's examine the conflicts

-- ==================================================
-- 4. Conflict Detection and Analysis
-- ==================================================

-- Function to analyze merge conflicts in detail
CREATE OR REPLACE FUNCTION pggit.analyze_merge_conflicts(
    p_merge_id TEXT
) RETURNS TABLE (
    conflict_type TEXT,
    object_name TEXT,
    conflict_details JSONB,
    suggested_resolution TEXT
) AS $$
BEGIN
    -- Schema conflicts (different columns added to same table)
    RETURN QUERY
    SELECT 
        'SCHEMA_CONFLICT'::TEXT,
        'products'::TEXT,
        jsonb_build_object(
            'source_changes', jsonb_build_array('discount_percentage', 'sale_price'),
            'target_changes', jsonb_build_array('min_stock_level', 'max_stock_level', 'reorder_point'),
            'conflict', 'Both branches modified the same table schema'
        ),
        'MERGE_SCHEMAS: Combine both sets of columns'::TEXT;
    
    -- Data conflicts (same rows modified differently)
    RETURN QUERY
    SELECT 
        'DATA_CONFLICT'::TEXT,
        'products.metadata'::TEXT,
        jsonb_build_object(
            'conflicting_rows', 3,
            'source_pattern', '{"inventory": {...}}',
            'target_pattern', '{"quality": {...}}',
            'conflict', 'Same JSONB column modified differently'
        ),
        'MERGE_JSONB: Combine JSONB objects'::TEXT;
    
    -- Constraint conflicts
    RETURN QUERY
    SELECT 
        'CONSTRAINT_CONFLICT'::TEXT,
        'products.constraints'::TEXT,
        jsonb_build_object(
            'new_constraints', jsonb_build_array('price_check', 'name_length', 'category_not_null'),
            'potential_violations', 'May conflict with discount prices'
        ),
        'VALIDATE_DATA: Check all data meets constraints'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ==================================================
-- 5. Conflict Resolution Strategies
-- ==================================================

-- Strategy 1: Manual resolution with detailed control
CREATE OR REPLACE FUNCTION pggit.resolve_conflicts_manually(
    p_merge_id TEXT
) RETURNS TEXT AS $$
DECLARE
    v_resolution_count INTEGER := 0;
BEGIN
    -- Resolve schema conflicts by accepting both changes
    -- In real implementation, this would merge the schemas
    UPDATE pggit.merge_conflicts
    SET 
        resolution = 'MERGE_SCHEMAS',
        resolved_at = CURRENT_TIMESTAMP
    WHERE merge_id = p_merge_id
    AND conflict_type = 'SCHEMA_CONFLICT';
    
    -- Resolve data conflicts by merging JSONB
    UPDATE pggit.merge_conflicts
    SET 
        resolution = 'MERGE_JSONB',
        resolved_value = '{"inventory": {"tracked": true}, "quality": {"verified": true}}'::JSONB,
        resolved_at = CURRENT_TIMESTAMP
    WHERE merge_id = p_merge_id
    AND conflict_type = 'DATA_CONFLICT';
    
    GET DIAGNOSTICS v_resolution_count = ROW_COUNT;
    
    RETURN format('Resolved %s conflicts manually', v_resolution_count);
END;
$$ LANGUAGE plpgsql;

-- Strategy 2: Auto-resolution with compression optimization (PostgreSQL 17)
SELECT pggit.auto_resolve_compressed_conflicts(
    'merge_id_xyz', 
    'COMPRESSION_OPTIMIZED'
);

-- Strategy 3: Interactive resolution helper
CREATE OR REPLACE FUNCTION pggit.show_conflict_diff(
    p_merge_id TEXT,
    p_conflict_id INTEGER
) RETURNS TABLE (
    source_version TEXT,
    target_version TEXT,
    base_version TEXT,
    recommended_merge TEXT
) AS $$
BEGIN
    -- Show three-way diff for a specific conflict
    RETURN QUERY
    SELECT 
        'Source: Added discount_percentage = 15'::TEXT,
        'Target: Added min_stock_level = 10'::TEXT,
        'Base: Original products table'::TEXT,
        'Merge: Include both columns'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ==================================================
-- 6. Complex Conflict Resolution Example
-- ==================================================

-- Create a more complex conflict scenario
SELECT pggit.create_data_branch('feature/complex-merge', 'main', true);
SELECT pggit.checkout_branch('feature/complex-merge');

-- Make changes that will definitely conflict
DROP TABLE IF EXISTS discount_history;  -- Dropped in this branch
CREATE TABLE price_history (  -- Different table with same purpose
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    price DECIMAL(10,2),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Try to merge
SELECT pggit.checkout_branch('main');
SELECT pggit.merge_branches('feature/complex-merge', 'main') AS complex_merge_result;

-- ==================================================
-- 7. Conflict Prevention Strategies
-- ==================================================

-- Best practices function
CREATE OR REPLACE FUNCTION pggit.suggest_conflict_prevention(
    p_branch1 TEXT,
    p_branch2 TEXT
) RETURNS TABLE (
    recommendation TEXT,
    reason TEXT,
    priority TEXT
) AS $$
BEGIN
    RETURN QUERY
    VALUES
    ('Use feature flags', 
     'Deploy features independently without schema conflicts', 
     'HIGH'),
    ('Smaller, focused branches', 
     'Reduce scope of changes to minimize conflicts', 
     'HIGH'),
    ('Regular rebasing', 
     'Keep branches up-to-date with main', 
     'MEDIUM'),
    ('Schema versioning', 
     'Track schema versions explicitly', 
     'MEDIUM'),
    ('Communication', 
     'Coordinate schema changes across teams', 
     'HIGH');
END;
$$ LANGUAGE plpgsql;

-- ==================================================
-- 8. Rollback Failed Merges
-- ==================================================

-- Function to rollback a failed merge
CREATE OR REPLACE FUNCTION pggit.rollback_merge(
    p_merge_id TEXT
) RETURNS TEXT AS $$
BEGIN
    -- In real implementation, this would restore the target branch
    -- to its state before the merge attempt
    
    -- Clean up conflict records
    DELETE FROM pggit.merge_conflicts
    WHERE merge_id = p_merge_id;
    
    -- Reset branch status
    UPDATE pggit.branches
    SET status = 'ACTIVE'
    WHERE name IN (
        SELECT source_branch FROM pggit.merges WHERE id = p_merge_id
        UNION
        SELECT target_branch FROM pggit.merges WHERE id = p_merge_id
    );
    
    RETURN 'Merge rolled back successfully';
END;
$$ LANGUAGE plpgsql;

-- ==================================================
-- Example Output Summary
-- ==================================================

/*
This example demonstrated:
1. Creating branches with conflicting changes
2. Detecting various types of conflicts:
   - Schema conflicts (different columns)
   - Data conflicts (same rows modified)
   - Constraint conflicts
   - Drop/Create conflicts
3. Multiple resolution strategies:
   - Manual resolution with full control
   - Auto-resolution with compression optimization
   - Interactive conflict resolution
4. Conflict prevention best practices
5. Rollback capabilities for failed merges

Key conflict resolution features:
- Three-way merge detection
- Detailed conflict analysis
- Multiple resolution strategies
- Compression-aware resolution (PostgreSQL 17)
- Safe rollback options

Common conflict types handled:
- Adding different columns to same table
- Modifying same data differently
- Conflicting constraints
- Dropped vs modified objects
- JSONB merge conflicts
*/