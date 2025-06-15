-- Demo Data for pggit
-- This script creates sample data to demonstrate pggit functionality

-- Create extension (should already be done by init scripts)
CREATE EXTENSION IF NOT EXISTS pggit CASCADE;

-- Create some demo tables to track
CREATE TABLE demo_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE demo_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES demo_users(id),
    total_amount DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE demo_products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(8,2) NOT NULL,
    category VARCHAR(50),
    in_stock BOOLEAN DEFAULT true
);

-- Insert some sample data
INSERT INTO demo_users (username, email) VALUES
('alice', 'alice@example.com'),
('bob', 'bob@example.com'),
('charlie', 'charlie@example.com');

INSERT INTO demo_products (name, price, category) VALUES
('Laptop', 999.99, 'Electronics'),
('Book', 29.99, 'Education'),
('Coffee Mug', 12.50, 'Kitchen');

INSERT INTO demo_orders (user_id, total_amount, status) VALUES
(1, 999.99, 'completed'),
(2, 42.49, 'pending'),
(3, 12.50, 'shipped');

-- Make some schema changes to generate history
ALTER TABLE demo_users ADD COLUMN last_login TIMESTAMP;
ALTER TABLE demo_orders ADD COLUMN shipping_address TEXT;
CREATE INDEX idx_users_email ON demo_users(email);

-- Add some comments
COMMENT ON TABLE demo_users IS 'Demo user accounts';
COMMENT ON COLUMN demo_users.last_login IS 'Track user activity';

-- Create a view
CREATE VIEW demo_user_orders AS
SELECT 
    u.username,
    u.email,
    COUNT(o.id) as order_count,
    SUM(o.total_amount) as total_spent
FROM demo_users u
LEFT JOIN demo_orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email;

-- Demo complete - pggit should have tracked all these changes automatically
SELECT 'Demo data loaded successfully! pggit has tracked ' || COUNT(*) || ' objects.' as status
FROM pggit.objects;

-- Show what was tracked
SELECT 
    object_type,
    schema_name,
    object_name,
    current_version,
    created_at
FROM pggit.objects 
WHERE schema_name = 'public' 
  AND object_name LIKE 'demo_%'
ORDER BY created_at;

-- Show recent history
SELECT 
    h.object_name,
    h.change_type,
    h.version,
    h.change_description,
    h.change_timestamp
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
WHERE o.schema_name = 'public' 
  AND o.object_name LIKE 'demo_%'
ORDER BY h.change_timestamp DESC
LIMIT 10;