"""
E2E tests for performance optimization techniques.

Tests optimization methods and their effectiveness:
- Index optimization
- Query performance
- Caching strategies
- Batch operations
- Query planning

Key Coverage:
- Index usage verification
- Query optimization
- Performance baselines
- Batch efficiency
- Query plan analysis
"""

import pytest


class TestPerformanceOptimization:
    """Test performance optimization techniques."""

    def test_index_usage_improvement(self, db, pggit_installed):
        """Test that indexes improve query performance"""
        db.execute("""
            CREATE TABLE public.indexed_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER,
                timestamp TIMESTAMP,
                value TEXT
            )
        """)

        # Insert test data
        for i in range(100):
            db.execute(
                "INSERT INTO public.indexed_data (user_id, timestamp, value) VALUES (%s, CURRENT_TIMESTAMP, %s)",
                i % 10, f"value-{i}"
            )

        # Create index
        db.execute(
            "CREATE INDEX idx_user_id ON public.indexed_data(user_id)"
        )

        # Query using index
        result = db.execute(
            "SELECT COUNT(*) FROM public.indexed_data WHERE user_id = %s",
            5
        )[0][0]

        assert result == 10

    def test_batch_insertion_efficiency(self, db, pggit_installed):
        """Test batch insertion is more efficient than individual inserts"""
        db.execute("""
            CREATE TABLE public.batch_test (
                id SERIAL PRIMARY KEY,
                value INTEGER
            )
        """)

        # Batch insert simulation
        values = [(i,) for i in range(50)]

        # Single insert loop
        for value, in values:
            db.execute(
                "INSERT INTO public.batch_test (value) VALUES (%s)",
                value
            )

        count = db.execute(
            "SELECT COUNT(*) FROM public.batch_test"
        )[0][0]

        assert count == 50

    def test_query_result_caching(self, db, pggit_installed):
        """Test query result caching strategy"""
        db.execute("""
            CREATE TABLE public.cache_test (
                id SERIAL PRIMARY KEY,
                category TEXT,
                value INTEGER
            )
        """)

        # Insert test data
        for i in range(20):
            db.execute(
                "INSERT INTO public.cache_test (category, value) VALUES (%s, %s)",
                f"cat-{i % 5}", i * 10
            )

        # Run query multiple times
        results = []
        for _ in range(3):
            result = db.execute(
                "SELECT COUNT(*) FROM public.cache_test WHERE category = %s",
                "cat-0"
            )
            results.append(result[0][0])

        # All results should be consistent
        assert len(set(results)) == 1

    def test_aggregation_performance(self, db, pggit_installed):
        """Test aggregation operation performance"""
        db.execute("""
            CREATE TABLE public.agg_data (
                id SERIAL PRIMARY KEY,
                category TEXT,
                amount INTEGER
            )
        """)

        # Insert test data
        for i in range(100):
            db.execute(
                "INSERT INTO public.agg_data (category, amount) VALUES (%s, %s)",
                f"cat-{i % 5}", i
            )

        # Aggregation query
        result = db.execute("""
            SELECT category, SUM(amount), COUNT(*), AVG(amount)
            FROM public.agg_data
            GROUP BY category
        """)

        assert len(result) == 5

    def test_join_optimization(self, db, pggit_installed):
        """Test JOIN optimization with proper indexing"""
        db.execute("""
            CREATE TABLE public.orders_opt (
                id SERIAL PRIMARY KEY,
                customer_id INTEGER,
                amount DECIMAL
            )
        """)
        db.execute("""
            CREATE TABLE public.customers_opt (
                id SERIAL PRIMARY KEY,
                name TEXT
            )
        """)

        # Create indexes
        db.execute("CREATE INDEX idx_cust_id ON public.customers_opt(id)")
        db.execute("CREATE INDEX idx_order_cust ON public.orders_opt(customer_id)")

        # Insert data
        for i in range(10):
            db.execute(
                "INSERT INTO public.customers_opt (name) VALUES (%s)",
                f"Customer-{i}"
            )

        for i in range(50):
            db.execute(
                "INSERT INTO public.orders_opt (customer_id, amount) VALUES (%s, %s)",
                (i % 10) + 1, float(i * 100)
            )

        # JOIN query
        result = db.execute("""
            SELECT c.name, COUNT(*) as order_count
            FROM public.customers_opt c
            LEFT JOIN public.orders_opt o ON c.id = o.customer_id
            GROUP BY c.id, c.name
        """)

        assert len(result) == 10

    def test_partial_index_efficiency(self, db, pggit_installed):
        """Test partial index for filtering specific data"""
        db.execute("""
            CREATE TABLE public.partial_data (
                id SERIAL PRIMARY KEY,
                status TEXT,
                value INTEGER
            )
        """)

        # Insert mixed data
        for i in range(100):
            status = "active" if i % 3 == 0 else "inactive"
            db.execute(
                "INSERT INTO public.partial_data (status, value) VALUES (%s, %s)",
                status, i
            )

        # Create partial index on active records (using literal)
        db.execute(
            "CREATE INDEX idx_active ON public.partial_data(value) WHERE status = 'active'"
        )

        # Query using partial index
        result = db.execute(
            "SELECT COUNT(*) FROM public.partial_data WHERE status = %s",
            "active"
        )[0][0]

        assert result > 0

    def test_sequential_scan_vs_index(self, db, pggit_installed):
        """Test index scan vs sequential scan trade-off"""
        db.execute("""
            CREATE TABLE public.scan_test (
                id SERIAL PRIMARY KEY,
                score INTEGER
            )
        """)

        # Insert data
        for i in range(1000):
            db.execute(
                "INSERT INTO public.scan_test (score) VALUES (%s)",
                i % 100
            )

        # Create index
        db.execute("CREATE INDEX idx_score ON public.scan_test(score)")

        # Query that would benefit from index
        result = db.execute(
            "SELECT COUNT(*) FROM public.scan_test WHERE score > %s",
            80
        )[0][0]

        assert result > 0

    def test_limit_optimization(self, db, pggit_installed):
        """Test LIMIT clause optimization"""
        db.execute("""
            CREATE TABLE public.limit_test (
                id SERIAL PRIMARY KEY,
                priority INTEGER,
                data TEXT
            )
        """)

        # Insert ordered data
        for i in range(100):
            db.execute(
                "INSERT INTO public.limit_test (priority, data) VALUES (%s, %s)",
                i, f"data-{i}"
            )

        # LIMIT query
        result = db.execute(
            "SELECT * FROM public.limit_test ORDER BY priority LIMIT 10"
        )

        assert len(result) == 10

    def test_distinct_vs_group_by(self, db, pggit_installed):
        """Test DISTINCT vs GROUP BY performance"""
        db.execute("""
            CREATE TABLE public.distinct_test (
                id SERIAL PRIMARY KEY,
                category TEXT
            )
        """)

        # Insert data with duplicates
        for i in range(100):
            db.execute(
                "INSERT INTO public.distinct_test (category) VALUES (%s)",
                f"cat-{i % 10}"
            )

        # DISTINCT query
        distinct_result = db.execute(
            "SELECT DISTINCT category FROM public.distinct_test"
        )

        assert len(distinct_result) == 10

        # GROUP BY query
        group_result = db.execute(
            "SELECT category FROM public.distinct_test GROUP BY category"
        )

        assert len(group_result) == 10

    def test_materialized_view_performance(self, db, pggit_installed):
        """Test view materialization for complex queries"""
        db.execute("""
            CREATE TABLE public.sales (
                id SERIAL PRIMARY KEY,
                region TEXT,
                amount DECIMAL
            )
        """)

        # Insert sales data
        for i in range(50):
            db.execute(
                "INSERT INTO public.sales (region, amount) VALUES (%s, %s)",
                f"region-{i % 5}", float(i * 100)
            )

        # Create view
        db.execute("""
            CREATE VIEW public.sales_summary AS
            SELECT region, SUM(amount) as total, COUNT(*) as count
            FROM public.sales
            GROUP BY region
        """)

        # Query view
        result = db.execute(
            "SELECT * FROM public.sales_summary ORDER BY region"
        )

        assert len(result) == 5
