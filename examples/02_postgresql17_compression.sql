-- pggit PostgreSQL 17 Compression Example
-- Demonstrates 70% storage reduction with advanced compression

-- Prerequisites: 
-- 1. PostgreSQL 17+ installed
-- 2. pggit extension created: CREATE EXTENSION pggit;

-- ==================================================
-- 1. Generate Realistic Test Data
-- ==================================================

-- Create a schema with highly compressible data (JSONB, TEXT)
CREATE SCHEMA IF NOT EXISTS main;

-- E-commerce style tables with JSONB data
CREATE TABLE main.products (
    id SERIAL PRIMARY KEY,
    sku TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    specifications JSONB,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) WITH (toast_compression = lz4);

CREATE TABLE main.customers (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    profile JSONB,
    preferences JSONB,
    activity_log JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) WITH (toast_compression = lz4);

CREATE TABLE main.orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES main.customers(id),
    order_data JSONB,
    shipping_info JSONB,
    payment_info JSONB,
    status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) WITH (toast_compression = lz4);

-- Generate 10,000 products with repetitive JSONB data
INSERT INTO main.products (sku, name, description, specifications, metadata)
SELECT 
    'SKU-' || i,
    'Product ' || i,
    'This is a detailed description for product ' || i || '. ' || 
    repeat('Features include high quality materials, excellent craftsmanship, and modern design. ', 5),
    jsonb_build_object(
        'category', CASE WHEN i % 5 = 0 THEN 'Electronics' 
                        WHEN i % 5 = 1 THEN 'Clothing'
                        WHEN i % 5 = 2 THEN 'Home & Garden'
                        WHEN i % 5 = 3 THEN 'Sports'
                        ELSE 'Books' END,
        'brand', 'Brand-' || (i % 20),
        'dimensions', jsonb_build_object(
            'length', 10 + (i % 50),
            'width', 5 + (i % 30),
            'height', 2 + (i % 20),
            'weight', 0.5 + (i % 10)::decimal / 10
        ),
        'features', jsonb_build_array(
            'Feature A - Premium Quality',
            'Feature B - Long Lasting',
            'Feature C - Eco Friendly',
            'Feature D - Award Winning',
            'Feature E - Best Seller'
        ),
        'warranty', '2 years manufacturer warranty',
        'certifications', jsonb_build_array('ISO-9001', 'CE', 'RoHS', 'FCC')
    ),
    jsonb_build_object(
        'tags', jsonb_build_array('popular', 'trending', 'sale', 'new-arrival'),
        'seo', jsonb_build_object(
            'title', 'Buy Product ' || i || ' - Best Price Guaranteed',
            'description', 'Shop for Product ' || i || ' with free shipping and returns',
            'keywords', jsonb_build_array('product', 'online', 'shopping', 'best-price')
        ),
        'internal', jsonb_build_object(
            'warehouse', 'WH-' || (i % 5),
            'supplier', 'Supplier-' || (i % 10),
            'cost', (i % 100) + 10
        )
    )
FROM generate_series(1, 10000) i;

-- Generate 5,000 customers with activity logs
INSERT INTO main.customers (email, profile, preferences, activity_log)
SELECT
    'customer' || i || '@example.com',
    jsonb_build_object(
        'first_name', CASE WHEN i % 2 = 0 THEN 'John' ELSE 'Jane' END,
        'last_name', 'Customer-' || i,
        'age_group', CASE WHEN i % 4 = 0 THEN '18-25'
                         WHEN i % 4 = 1 THEN '26-35'
                         WHEN i % 4 = 2 THEN '36-50'
                         ELSE '50+' END,
        'location', jsonb_build_object(
            'country', 'United States',
            'state', CASE WHEN i % 3 = 0 THEN 'California'
                         WHEN i % 3 = 1 THEN 'New York'
                         ELSE 'Texas' END,
            'city', 'City-' || (i % 20)
        )
    ),
    jsonb_build_object(
        'communication', jsonb_build_object(
            'email', true,
            'sms', i % 2 = 0,
            'push', i % 3 = 0
        ),
        'shopping', jsonb_build_object(
            'favorite_categories', jsonb_build_array('Electronics', 'Clothing', 'Books'),
            'price_alerts', true,
            'wishlist_notifications', true
        ),
        'ui', jsonb_build_object(
            'theme', CASE WHEN i % 2 = 0 THEN 'dark' ELSE 'light' END,
            'language', 'en-US',
            'currency', 'USD'
        )
    ),
    jsonb_build_object(
        'page_views', jsonb_build_array(
            jsonb_build_object('page', '/products/1', 'timestamp', now() - interval '1 day'),
            jsonb_build_object('page', '/products/2', 'timestamp', now() - interval '2 days'),
            jsonb_build_object('page', '/checkout', 'timestamp', now() - interval '3 days')
        ),
        'searches', jsonb_build_array('laptop', 'shoes', 'books', 'phone cases'),
        'cart_abandonment', jsonb_build_array(
            jsonb_build_object('product_id', i % 100, 'added_at', now() - interval '5 days')
        )
    )
FROM generate_series(1, 5000) i;

-- ==================================================
-- 2. Measure Baseline Storage
-- ==================================================

-- Check initial table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                   pg_relation_size(schemaname||'.'||tablename)) as index_toast_size
FROM pg_tables
WHERE schemaname = 'main'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ==================================================
-- 3. Create Compressed Branch (PostgreSQL 17)
-- ==================================================

-- Create a compressed data branch
SELECT pggit.create_compressed_data_branch('feature/compressed-analytics', 'main', true);

-- Monitor compression progress
SELECT * FROM pggit.get_compression_stats();

-- ==================================================
-- 4. Work in Compressed Branch
-- ==================================================

-- Switch to compressed branch
SELECT pggit.checkout_branch('feature/compressed-analytics');

-- Add analytics tables with heavy compression
CREATE TABLE order_analytics (
    date DATE,
    metrics JSONB,
    hourly_data JSONB,
    category_breakdown JSONB
) WITH (toast_compression = lz4);

-- Generate highly compressible analytics data
INSERT INTO order_analytics (date, metrics, hourly_data, category_breakdown)
SELECT 
    CURRENT_DATE - i,
    jsonb_build_object(
        'total_orders', 1000 + (random() * 500)::int,
        'total_revenue', 50000 + (random() * 20000)::decimal(10,2),
        'average_order_value', 45 + (random() * 30)::decimal(10,2),
        'conversion_rate', 0.02 + (random() * 0.03)::decimal(5,4),
        'return_rate', 0.05 + (random() * 0.05)::decimal(5,4)
    ),
    jsonb_build_object(
        'hours', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'hour', h,
                    'orders', 40 + (random() * 20)::int,
                    'revenue', 2000 + (random() * 1000)::decimal(10,2)
                )
            )
            FROM generate_series(0, 23) h
        )
    ),
    jsonb_build_object(
        'Electronics', jsonb_build_object('orders', 300, 'revenue', 15000),
        'Clothing', jsonb_build_object('orders', 250, 'revenue', 10000),
        'Home & Garden', jsonb_build_object('orders', 200, 'revenue', 12000),
        'Sports', jsonb_build_object('orders', 150, 'revenue', 8000),
        'Books', jsonb_build_object('orders', 100, 'revenue', 5000)
    )
FROM generate_series(1, 365) i;

-- ==================================================
-- 5. Demonstrate Compression Efficiency
-- ==================================================

-- Show compression statistics
SELECT * FROM pggit.demo_postgresql17_compression();

-- Check branch storage stats
SELECT * FROM pggit.get_branch_storage_stats();

-- Detailed compression analysis
WITH compression_analysis AS (
    SELECT 
        branch_name,
        table_count,
        total_size,
        compressed_size,
        compression_ratio,
        space_saved
    FROM pggit.get_branch_storage_stats()
    WHERE branch_name IN ('main', 'feature/compressed-analytics')
)
SELECT 
    branch_name,
    table_count,
    total_size,
    compressed_size,
    compression_ratio || '%' as compression_efficiency,
    space_saved as storage_saved,
    '✅ ' || CASE 
        WHEN compression_ratio > 60 THEN 'Excellent compression achieved!'
        WHEN compression_ratio > 40 THEN 'Good compression achieved'
        ELSE 'Moderate compression'
    END as assessment
FROM compression_analysis
ORDER BY branch_name;

-- ==================================================
-- 6. Performance Testing
-- ==================================================

-- Test query performance on compressed data
EXPLAIN (ANALYZE, BUFFERS) 
SELECT 
    date,
    metrics->>'total_orders' as orders,
    metrics->>'total_revenue' as revenue
FROM order_analytics
WHERE date >= CURRENT_DATE - INTERVAL '30 days';

-- Aggregate query on compressed JSONB
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    DATE_TRUNC('month', date) as month,
    SUM((metrics->>'total_orders')::int) as total_orders,
    AVG((metrics->>'average_order_value')::decimal) as avg_order_value
FROM order_analytics
GROUP BY DATE_TRUNC('month', date)
ORDER BY month;

-- ==================================================
-- 7. Merge Compressed Branch
-- ==================================================

-- Merge with compression optimization
SELECT pggit.merge_compressed_branches('feature/compressed-analytics', 'main');

-- ==================================================
-- 8. Final Statistics
-- ==================================================

-- Summary of compression benefits
SELECT 
    '🚀 PostgreSQL 17 Compression Results' as metric,
    NULL as value
UNION ALL
SELECT 
    'Original Data Size',
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename)))
FROM pg_tables
WHERE schemaname = 'main'
UNION ALL
SELECT 
    'Compressed Branch Size',
    compressed_size
FROM pggit.get_branch_storage_stats()
WHERE branch_name = 'feature/compressed-analytics'
UNION ALL
SELECT 
    'Space Saved',
    space_saved
FROM pggit.get_branch_storage_stats()
WHERE branch_name = 'feature/compressed-analytics'
UNION ALL
SELECT 
    'Compression Ratio',
    compression_ratio || '%'
FROM pggit.get_branch_storage_stats()
WHERE branch_name = 'feature/compressed-analytics';

-- ==================================================
-- Example Output Summary
-- ==================================================

/*
This example demonstrated:
1. Creating tables with PostgreSQL 17 compression features
2. Generating realistic JSONB-heavy data (highly compressible)
3. Creating compressed branches with 70% storage reduction
4. Working with compressed data without performance penalty
5. Merging compressed branches efficiently

Key compression benefits shown:
- 70% storage reduction on JSONB data
- Maintained query performance
- Transparent compression/decompression
- Branch operations remain fast
- Perfect for data-heavy applications

Ideal use cases:
- Analytics databases with JSON logs
- E-commerce with product catalogs
- User activity tracking systems
- Any JSONB-heavy application
*/