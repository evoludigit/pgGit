-- A+ Quality UAT Test Data with Full Git-like Workflow
-- Creates commits, branches, and comprehensive test scenarios

-- Clean start
DROP SCHEMA IF EXISTS uat_test CASCADE;
CREATE SCHEMA uat_test;

-- Create initial test tables
CREATE TABLE uat_test.customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE,
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
    customer_id INTEGER REFERENCES uat_test.customers(id),
    product_id INTEGER REFERENCES uat_test.products(id),
    quantity INTEGER NOT NULL DEFAULT 1,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial data
INSERT INTO uat_test.customers (name, email) VALUES
('Alice Johnson', 'alice@example.com'),
('Bob Smith', 'bob@example.com'),
('Carol Davis', 'carol@example.com');

INSERT INTO uat_test.products (name, price, category) VALUES
('Laptop Pro', 1299.99, 'Electronics'),
('Wireless Mouse', 29.99, 'Electronics'),
('Office Chair', 199.99, 'Furniture');

INSERT INTO uat_test.orders (customer_id, product_id, quantity) VALUES
(1, 1, 1),
(2, 2, 2),
(3, 3, 1);

-- Create initial commit
SELECT pggit_v2.create_basic_commit('Initial schema setup with customers, products, and orders tables');

-- Create feature branch for new feature
SELECT pggit_v2.create_branch('feature/user-preferences', 'Add user preference system');

-- Switch to feature branch context (simulated)
-- Add new table in feature branch
CREATE TABLE uat_test.user_preferences (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES uat_test.customers(id),
    preference_key VARCHAR(50) NOT NULL,
    preference_value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(customer_id, preference_key)
);

-- Add some preferences
INSERT INTO uat_test.user_preferences (customer_id, preference_key, preference_value) VALUES
(1, 'theme', 'dark'),
(1, 'notifications', 'email'),
(2, 'theme', 'light'),
(3, 'language', 'es');

-- Create commit for feature
SELECT pggit_v2.create_basic_commit('Add user preferences system with theme and notification settings');

-- Create another branch for bug fix
SELECT pggit_v2.create_branch('bugfix/order-validation', 'Fix order validation logic');

-- Switch to bugfix branch (simulated)
-- Add constraint to orders table
ALTER TABLE uat_test.orders ADD CONSTRAINT check_quantity_positive CHECK (quantity > 0);
ALTER TABLE uat_test.orders ADD CONSTRAINT check_price_positive CHECK (
    (SELECT price FROM uat_test.products WHERE id = product_id) > 0
);

-- Create commit for bugfix
SELECT pggit_v2.create_basic_commit('Add validation constraints for order quantity and product pricing');

-- Create release branch
SELECT pggit_v2.create_branch('release/v2.1.0', 'Release branch for version 2.1.0');

-- Add final touches (simulated)
COMMENT ON TABLE uat_test.user_preferences IS 'User preference settings for personalization';
COMMENT ON TABLE uat_test.orders IS 'Customer order records with validation';

-- Final release commit
SELECT pggit_v2.create_basic_commit('Final release preparations and documentation');

-- Create test data summary
DO $$
DECLARE
    v_commit_count INTEGER;
    v_branch_count INTEGER;
    v_object_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_commit_count FROM pggit_v2.commit_graph;
    SELECT COUNT(*) INTO v_branch_count FROM pggit_v2.refs WHERE type = 'branch';
    SELECT COUNT(*) INTO v_object_count FROM pggit.objects WHERE schema_name = 'uat_test';

    RAISE NOTICE 'A+ Quality UAT Test Data Created:';
    RAISE NOTICE '  Commits: %', v_commit_count;
    RAISE NOTICE '  Branches: %', v_branch_count;
    RAISE NOTICE '  Schema Objects: %', v_object_count;
    RAISE NOTICE '  Ready for comprehensive workflow testing';
END $$;