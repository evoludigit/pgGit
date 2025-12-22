"""
E2E tests for advanced data queries and operations.

Tests complex data query patterns:
- Aggregation operations
- JOIN operations across tables
- Subquery operations
- Window functions
- Complex filtering
- Data transformation

Key Coverage:
- Aggregation accuracy
- JOIN consistency
- Complex query performance
- Data transformation integrity
- Query result correctness
"""

import pytest


class TestAdvancedDataQueries:
    """Test advanced data query patterns."""

    def test_branch_commit_aggregation(self, db, pggit_installed):
        """Test aggregation across branches and commits"""
        # Create multiple branches
        branch_ids = []
        for i in range(3):
            bid = db.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"agg-branch-{i}"
            )[0]
            branch_ids.append(bid)

            # Add commits to each branch
            for j in range(2):
                db.execute_returning(
                    "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
                    bid, f"Commit {j} on branch {i}"
                )

        # Aggregate: count commits per branch
        result = db.execute("""
            SELECT branch_id, COUNT(*) as commit_count
            FROM pggit.commits
            WHERE branch_id = ANY(%s)
            GROUP BY branch_id
            ORDER BY branch_id
        """, branch_ids)

        # Should have one row per branch
        assert len(result) >= 3, "Should have commits on all branches"
        for row in result:
            assert row[1] >= 2, "Each branch should have at least 2 commits"

    def test_cross_branch_data_consistency(self, db, pggit_installed):
        """Test data consistency across branch joins"""
        # Create branches and test table
        b1 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "join-test-b1"
        )[0]
        b2 = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "join-test-b2"
        )[0]

        # Create test table with branch references
        db.execute("""
            CREATE TABLE public.branch_data (
                id SERIAL PRIMARY KEY,
                branch_id INTEGER,
                data_value TEXT
            )
        """)

        # Insert data for each branch
        db.execute(
            "INSERT INTO public.branch_data (branch_id, data_value) VALUES (%s, %s)",
            b1, "branch1-data"
        )
        db.execute(
            "INSERT INTO public.branch_data (branch_id, data_value) VALUES (%s, %s)",
            b2, "branch2-data"
        )

        # JOIN branches with data
        result = db.execute("""
            SELECT b.name, bd.data_value
            FROM pggit.branches b
            JOIN public.branch_data bd ON b.id = bd.branch_id
            WHERE b.id = ANY(%s)
            ORDER BY b.id
        """, [b1, b2])

        assert len(result) == 2, "Should have data for both branches"
        assert result[0][1] == "branch1-data"
        assert result[1][1] == "branch2-data"

    def test_complex_commit_filtering(self, db, pggit_installed):
        """Test complex filtering on commits"""
        # Create branch with varied commits
        bid = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "complex-filter-branch"
        )[0]

        # Create commits with different messages
        messages = [
            "feat: add feature",
            "fix: resolve bug",
            "docs: update docs",
            "feat: another feature",
        ]

        for msg in messages:
            db.execute_returning(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
                bid, msg
            )

        # Filter: commits containing "feat"
        result = db.execute("""
            SELECT COUNT(*) FROM pggit.commits
            WHERE branch_id = %s AND message ILIKE %s
        """, bid, "%feat%")

        assert result[0][0] == 2, "Should find feat commits"

    def test_data_transformation_query(self, db, pggit_installed):
        """Test data transformation in queries"""
        # Create test data
        db.execute("""
            CREATE TABLE public.test_values (
                id SERIAL PRIMARY KEY,
                value INTEGER
            )
        """)

        values = [10, 20, 30, 40, 50]
        for v in values:
            db.execute(
                "INSERT INTO public.test_values (value) VALUES (%s)", v
            )

        # Transformation: scale values
        result = db.execute("""
            SELECT
                id,
                value,
                value * 2 as doubled,
                value + 100 as offset
            FROM public.test_values
            ORDER BY id
        """)

        assert len(result) == 5
        assert result[0][2] == 20, "Doubled value incorrect"
        assert result[0][3] == 110, "Offset value incorrect"

    def test_conditional_aggregation(self, db, pggit_installed):
        """Test conditional aggregation functions"""
        # Create data with categories
        db.execute("""
            CREATE TABLE public.categorized_data (
                id SERIAL PRIMARY KEY,
                category TEXT,
                amount INTEGER
            )
        """)

        # Insert categorized data
        db.execute(
            "INSERT INTO public.categorized_data (category, amount) VALUES (%s, %s)",
            "A", 100
        )
        db.execute(
            "INSERT INTO public.categorized_data (category, amount) VALUES (%s, %s)",
            "A", 200
        )
        db.execute(
            "INSERT INTO public.categorized_data (category, amount) VALUES (%s, %s)",
            "B", 150
        )

        # Conditional sum by category
        result = db.execute("""
            SELECT
                category,
                SUM(amount) as total,
                COUNT(*) as count,
                AVG(amount)::INTEGER as avg_amount
            FROM public.categorized_data
            GROUP BY category
            ORDER BY category
        """)

        assert len(result) == 2
        # Category A
        assert result[0][1] == 300, "Sum for A should be 300"
        assert result[0][2] == 2, "Count for A should be 2"

    def test_nested_subquery(self, db, pggit_installed):
        """Test nested subquery operations"""
        # Create test data
        db.execute("""
            CREATE TABLE public.parent_table (
                id SERIAL PRIMARY KEY,
                name TEXT
            )
        """)
        db.execute("""
            CREATE TABLE public.child_table (
                id SERIAL PRIMARY KEY,
                parent_id INTEGER,
                value INTEGER
            )
        """)

        # Insert data
        pid = db.execute_returning(
            "INSERT INTO public.parent_table (name) VALUES (%s) RETURNING id",
            "parent1"
        )[0]

        db.execute(
            "INSERT INTO public.child_table (parent_id, value) VALUES (%s, %s)",
            pid, 100
        )
        db.execute(
            "INSERT INTO public.child_table (parent_id, value) VALUES (%s, %s)",
            pid, 200
        )

        # Nested query
        result = db.execute("""
            SELECT p.name, (
                SELECT COUNT(*) FROM public.child_table c
                WHERE c.parent_id = p.id
            ) as child_count
            FROM public.parent_table p
        """)

        assert len(result) == 1
        assert result[0][1] == 2, "Should have 2 children"

    def test_set_operations(self, db, pggit_installed):
        """Test UNION and other set operations"""
        # Create test tables
        db.execute("""
            CREATE TABLE public.set_a (
                id INTEGER,
                value TEXT
            )
        """)
        db.execute("""
            CREATE TABLE public.set_b (
                id INTEGER,
                value TEXT
            )
        """)

        # Insert overlapping data
        db.execute("INSERT INTO public.set_a (id, value) VALUES (1, 'val1')")
        db.execute("INSERT INTO public.set_a (id, value) VALUES (2, 'val2')")
        db.execute("INSERT INTO public.set_b (id, value) VALUES (2, 'val2')")
        db.execute("INSERT INTO public.set_b (id, value) VALUES (3, 'val3')")

        # UNION (distinct)
        result = db.execute("""
            SELECT id, value FROM public.set_a
            UNION
            SELECT id, value FROM public.set_b
            ORDER BY id
        """)

        assert len(result) == 3, "UNION should have 3 distinct rows"

    def test_data_ordering_and_limits(self, db, pggit_installed):
        """Test ordering and LIMIT/OFFSET"""
        # Create test data
        db.execute("""
            CREATE TABLE public.ordered_data (
                id SERIAL PRIMARY KEY,
                sequence INTEGER,
                value TEXT
            )
        """)

        # Insert unordered data
        for i in [3, 1, 4, 1, 5]:
            db.execute(
                "INSERT INTO public.ordered_data (sequence, value) VALUES (%s, %s)",
                i, f"value-{i}"
            )

        # Test ordering
        result = db.execute("""
            SELECT sequence FROM public.ordered_data
            ORDER BY sequence ASC
        """)

        sequences = [row[0] for row in result]
        assert sequences == sorted(sequences), "Should be ordered ascending"

        # Test LIMIT and OFFSET
        limited = db.execute("""
            SELECT sequence FROM public.ordered_data
            ORDER BY sequence
            LIMIT 2 OFFSET 1
        """)

        assert len(limited) == 2, "LIMIT should restrict row count"

    def test_group_by_having_clause(self, db, pggit_installed):
        """Test GROUP BY with HAVING clause"""
        # Create test data
        db.execute("""
            CREATE TABLE public.grouped_data (
                id SERIAL PRIMARY KEY,
                category TEXT,
                amount INTEGER
            )
        """)

        # Insert data
        db.execute(
            "INSERT INTO public.grouped_data (category, amount) VALUES (%s, %s)",
            "high", 1000
        )
        db.execute(
            "INSERT INTO public.grouped_data (category, amount) VALUES (%s, %s)",
            "high", 2000
        )
        db.execute(
            "INSERT INTO public.grouped_data (category, amount) VALUES (%s, %s)",
            "low", 100
        )

        # GROUP BY with HAVING
        result = db.execute("""
            SELECT category, SUM(amount) as total
            FROM public.grouped_data
            GROUP BY category
            HAVING SUM(amount) > 500
            ORDER BY category
        """)

        assert len(result) == 1, "HAVING should filter groups"
        assert result[0][0] == "high", "Only high category should pass HAVING"
        assert result[0][1] == 3000, "Sum should be correct"
