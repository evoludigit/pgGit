-- UAT Test Data Setup for pggit_v2
-- Create test commits, branches, and schema changes

-- Create test schema for UAT
CREATE SCHEMA IF NOT EXISTS uat_test;

-- Create some test tables
CREATE TABLE uat_test.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE uat_test.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE uat_test.orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES uat_test.users(id),
    product_id INTEGER REFERENCES uat_test.products(id),
    quantity INTEGER NOT NULL,
    total_amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO uat_test.users (username, email) VALUES
('alice_uat', 'alice@uat.test'),
('bob_uat', 'bob@uat.test'),
('charlie_uat', 'charlie@uat.test');

INSERT INTO uat_test.products (name, price, category) VALUES
('Widget A', 19.99, 'Electronics'),
('Widget B', 29.99, 'Electronics'),
('Service X', 99.99, 'Services');

INSERT INTO uat_test.orders (user_id, product_id, quantity, total_amount) VALUES
(1, 1, 2, 39.98),
(2, 2, 1, 29.99),
(3, 3, 1, 99.99);

-- Create a commit to establish baseline
-- (Note: pggit_v2 doesn't create commits automatically, this is for testing)

-- Add some schema changes for testing
ALTER TABLE uat_test.users ADD COLUMN last_login TIMESTAMP;
ALTER TABLE uat_test.products ADD COLUMN in_stock BOOLEAN DEFAULT true;
CREATE INDEX idx_uat_users_email ON uat_test.users(email);
CREATE INDEX idx_uat_products_category ON uat_test.products(category);

-- Add comments
COMMENT ON TABLE uat_test.users IS 'UAT test users table';
COMMENT ON TABLE uat_test.products IS 'UAT test products catalog';

-- Create a test view
CREATE VIEW uat_test.user_order_summary AS
SELECT
    u.username,
    COUNT(o.id) as total_orders,
    SUM(o.total_amount) as total_spent
FROM uat_test.users u
LEFT JOIN uat_test.orders o ON u.id = o.user_id
GROUP BY u.id, u.username;

-- Test data setup complete
SELECT 'UAT test data loaded successfully - ' || COUNT(*) || ' objects tracked' as status
FROM pggit.objects
WHERE schema_name = 'uat_test';