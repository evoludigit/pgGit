# Phase 6 Step 0: Test Fixtures & Implementation Patterns

**Status**: Pre-Implementation Planning
**Date**: 2025-12-26
**Purpose**: Design comprehensive test fixtures and extraction of implementation patterns

---

## Overview

This document provides:
1. **Complex Rollback Scenario Architecture** - Multi-branch history with dependencies
2. **Fixture Patterns** - Reusable components for testing all Phase 6 functions
3. **Dependency Management** - Complex object relationships to test
4. **Edge Case Scenarios** - Challenging rollback situations

---

## Part 1: Test History Architecture

### Timeline Structure

Design a rich history that tests all Phase 6 rollback scenarios:

```
2025-12-26 10:00:00 (T0): Main branch created
├─ 2025-12-26 10:15:00 (T1): CREATE TABLE users (id, name)
├─ 2025-12-26 10:30:00 (T2): CREATE TABLE orders (id, user_id FK users.id)
├─ 2025-12-26 10:45:00 (T3): ALTER TABLE users ADD email VARCHAR
├─ 2025-12-26 11:00:00 (T4): CREATE INDEX idx_users_email ON users(email)
├─ 2025-12-26 11:15:00 (T5): ALTER TABLE orders ADD amount DECIMAL
├─ 2025-12-26 11:30:00 (T6): CREATE FUNCTION count_users() RETURNS INT
│  └─ 2025-12-26 11:45:00 (T7): Feature-A branch created from T6
│     ├─ 2025-12-26 12:00:00 (T7b): ALTER TABLE users DROP email
│     ├─ 2025-12-26 12:15:00 (T7c): CREATE TABLE payments (id, order_id FK orders.id)
│     └─ 2025-12-26 12:30:00 (T7d): ALTER FUNCTION count_users() MODIFY BODY
│
├─ 2025-12-26 12:00:00 (T8): Feature-B branch created from T6
│  ├─ 2025-12-26 12:15:00 (T8b): ALTER TABLE users ADD phone VARCHAR
│  ├─ 2025-12-26 12:30:00 (T8c): CREATE TABLE products (id, price)
│  └─ 2025-12-26 12:45:00 (T8d): ALTER TABLE orders ADD product_id FK products.id
│
├─ 2025-12-26 13:00:00 (T9): Merge feature-a -> main (UNION strategy)
│  └─ Result: users without email, with payments table, function body from T7d
│
├─ 2025-12-26 13:30:00 (T10): Merge feature-b -> main (CONFLICT)
│  └─ Result: Merge conflict on users table, take target version
│
└─ 2025-12-26 14:00:00 (T11): ALTER TABLE users DROP COLUMN name
```

### Objects Created

**Initial Objects (T1-T6)**:
1. `users` table: id, name
2. `orders` table: id, user_id (FK users)
3. `count_users` function

**Modifications on Main**:
- T3: users.email added
- T4: idx_users_email created
- T5: orders.amount added
- T11: users.name dropped

**Feature-A Modifications (T7b-T7d)**:
- T7b: users.email removed
- T7c: payments table created
- T7d: count_users function modified

**Feature-B Modifications (T8b-T8d)**:
- T8b: users.phone added
- T8c: products table created
- T8d: orders.product_id added (FK products)

### Dependency Graph

```
users
├── orders (FK: user_id -> users.id)
├── idx_users_email (INDEX on email column)
└── count_users (FUNCTION that SELECTs from users)

orders
├── payments (FK: order_id -> orders.id)
└── products (via product_id FK)

products
└── orders (FK: product_id -> products.id)
```

---

## Part 2: Fixture Class Implementation

### Python Fixture Class

```python
from datetime import datetime, timedelta
import hashlib
from typing import Dict, List, Tuple

class Phase6RollbackFixture:
    """
    Comprehensive fixture for Phase 6 rollback testing.

    Creates:
    - 3 branches with parent relationships
    - 7+ schema objects with rich modification history
    - 11 commits with accurate timestamps
    - 2 merge operations
    - Complex dependencies (FK, INDEX, FUNCTION)
    """

    def __init__(self, db_connection):
        self.conn = db_connection
        self.branch_ids = {}
        self.object_ids = {}
        self.commit_hashes = {}
        self.timestamps = {}
        self._setup_base_timestamps()

    def _setup_base_timestamps(self):
        """Setup timeline of test timestamps"""
        base_time = datetime(2025, 12, 26, 10, 0, 0)
        self.timestamps = {
            'T0': base_time,                           # 10:00
            'T1': base_time + timedelta(minutes=15),   # 10:15
            'T2': base_time + timedelta(minutes=30),   # 10:30
            'T3': base_time + timedelta(minutes=45),   # 10:45
            'T4': base_time + timedelta(hours=1),      # 11:00
            'T5': base_time + timedelta(minutes=75),   # 11:15
            'T6': base_time + timedelta(minutes=90),   # 11:30
            'T7': base_time + timedelta(minutes=105),  # 11:45
            'T7b': base_time + timedelta(hours=2),     # 12:00
            'T7c': base_time + timedelta(minutes=135), # 12:15
            'T7d': base_time + timedelta(minutes=150), # 12:30
            'T8': base_time + timedelta(hours=2),      # 12:00
            'T8b': base_time + timedelta(minutes=135), # 12:15
            'T8c': base_time + timedelta(minutes=150), # 12:30
            'T8d': base_time + timedelta(minutes=165), # 12:45
            'T9': base_time + timedelta(hours=3),      # 13:00
            'T10': base_time + timedelta(minutes=210), # 13:30
            'T11': base_time + timedelta(hours=4),     # 14:00
        }

    def setup(self):
        """Create complete fixture data"""
        self._create_branches()
        self._create_objects()
        self._create_commits_and_history()
        self._create_dependencies()

    def teardown(self):
        """Clean up all fixture data"""
        try:
            with self.conn.cursor() as cur:
                cur.execute("DELETE FROM pggit.object_dependencies")
                cur.execute("DELETE FROM pggit.merge_operations")
                cur.execute("DELETE FROM pggit.object_history")
                cur.execute("DELETE FROM pggit.commits")
                cur.execute("DELETE FROM pggit.schema_objects")
                cur.execute("DELETE FROM pggit.branches WHERE branch_name != 'main'")
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            pass

    def _create_branches(self):
        """Create branch hierarchy"""
        with self.conn.cursor() as cur:
            # Get/create main branch
            cur.execute(
                "SELECT branch_id FROM pggit.branches WHERE branch_name = 'main'"
            )
            result = cur.fetchone()
            if result:
                self.branch_ids['main'] = result[0]
            else:
                cur.execute(
                    "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at, "
                    "created_by, status) VALUES (%s, %s, %s, %s, %s) RETURNING branch_id",
                    ('main', None, self.timestamps['T0'], 'system', 'ACTIVE')
                )
                self.branch_ids['main'] = cur.fetchone()[0]

            # Create feature branches
            for branch_name, parent_time in [('feature-a', 'T7'), ('feature-b', 'T8')]:
                cur.execute("DELETE FROM pggit.branches WHERE branch_name = %s", (branch_name,))
                cur.execute(
                    "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at, "
                    "created_by, status) VALUES (%s, %s, %s, %s, %s) RETURNING branch_id",
                    (branch_name, self.branch_ids['main'], self.timestamps[parent_time],
                     'developer', 'ACTIVE')
                )
                self.branch_ids[branch_name] = cur.fetchone()[0]
        self.conn.commit()

    def _create_objects(self):
        """Create schema objects"""
        with self.conn.cursor() as cur:
            # users table
            users_def = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))"
            users_hash = hashlib.sha256(users_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('TABLE', 'public', 'users', users_def, users_hash, True)
            )
            self.object_ids['users'] = cur.fetchone()[0]

            # orders table
            orders_def = "CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)"
            orders_hash = hashlib.sha256(orders_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('TABLE', 'public', 'orders', orders_def, orders_hash, True)
            )
            self.object_ids['orders'] = cur.fetchone()[0]

            # count_users function
            func_def = "CREATE FUNCTION count_users() RETURNS INT"
            func_hash = hashlib.sha256(func_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('FUNCTION', 'public', 'count_users', func_def, func_hash, True)
            )
            self.object_ids['count_users'] = cur.fetchone()[0]

        self.conn.commit()

    def _create_commits_and_history(self):
        """Create commits and object history"""
        with self.conn.cursor() as cur:
            # T1: CREATE TABLE users
            self._insert_commit(cur, 'main', 'T1', 'CREATE TABLE users', 'hash_T1')
            self._insert_history(cur, 'users', 'main', 'CREATE',
                'CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))', 'hash_T1', 'T1')

            # T2: CREATE TABLE orders
            self._insert_commit(cur, 'main', 'T2', 'CREATE TABLE orders', 'hash_T2')
            self._insert_history(cur, 'orders', 'main', 'CREATE',
                'CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)', 'hash_T2', 'T2')

            # T3: ALTER TABLE users ADD email
            self._insert_commit(cur, 'main', 'T3', 'ALTER TABLE users ADD email', 'hash_T3')
            self._insert_history(cur, 'users', 'main', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100), email VARCHAR(100))',
                'hash_T3', 'T3',
                before_def='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))')

            # T4: CREATE INDEX
            idx_def = "CREATE INDEX idx_users_email ON users(email)"
            idx_hash = hashlib.sha256(idx_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('INDEX', 'public', 'idx_users_email', idx_def, idx_hash, True)
            )
            self._insert_commit(cur, 'main', 'T4', 'CREATE INDEX idx_users_email', 'hash_T4')

            # T5: ALTER TABLE orders ADD amount
            self._insert_commit(cur, 'main', 'T5', 'ALTER TABLE orders ADD amount', 'hash_T5')
            self._insert_history(cur, 'orders', 'main', 'ALTER',
                'CREATE TABLE orders (id INT, user_id INT, amount DECIMAL)',
                'hash_T5', 'T5',
                before_def='CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)')

            # T6: CREATE FUNCTION count_users
            self._insert_commit(cur, 'main', 'T6', 'CREATE FUNCTION count_users', 'hash_T6')
            self._insert_history(cur, 'count_users', 'main', 'CREATE',
                'CREATE FUNCTION count_users() RETURNS INT', 'hash_T6', 'T6')

            # Feature-A commits (T7b-T7d)
            self._insert_commit(cur, 'feature-a', 'T7b', 'ALTER TABLE users DROP email', 'hash_T7b')
            self._insert_history(cur, 'users', 'feature-a', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100))',
                'hash_T7b', 'T7b',
                before_def='CREATE TABLE users (id INT, name VARCHAR(100), email VARCHAR(100))')

            # T7c: CREATE TABLE payments
            payments_def = "CREATE TABLE payments (id INT PRIMARY KEY, order_id INT)"
            payments_hash = hashlib.sha256(payments_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('TABLE', 'public', 'payments', payments_def, payments_hash, True)
            )
            self.object_ids['payments'] = cur.fetchone()[0]

            self._insert_commit(cur, 'feature-a', 'T7c', 'CREATE TABLE payments', 'hash_T7c')
            self._insert_history(cur, 'payments', 'feature-a', 'CREATE',
                'CREATE TABLE payments (id INT PRIMARY KEY, order_id INT)', 'hash_T7c', 'T7c')

            # T7d: ALTER FUNCTION
            self._insert_commit(cur, 'feature-a', 'T7d', 'ALTER FUNCTION count_users', 'hash_T7d')
            self._insert_history(cur, 'count_users', 'feature-a', 'ALTER',
                'CREATE FUNCTION count_users() RETURNS INT AS improved',
                'hash_T7d', 'T7d',
                before_def='CREATE FUNCTION count_users() RETURNS INT')

            # Feature-B commits (T8b-T8d)
            self._insert_commit(cur, 'feature-b', 'T8b', 'ALTER TABLE users ADD phone', 'hash_T8b')
            self._insert_history(cur, 'users', 'feature-b', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100), phone VARCHAR(20))',
                'hash_T8b', 'T8b',
                before_def='CREATE TABLE users (id INT, name VARCHAR(100))')

            # T8c: CREATE TABLE products
            products_def = "CREATE TABLE products (id INT PRIMARY KEY, price DECIMAL)"
            products_hash = hashlib.sha256(products_def.encode()).hexdigest()
            cur.execute(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
                "current_definition, content_hash, is_active) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id",
                ('TABLE', 'public', 'products', products_def, products_hash, True)
            )
            self.object_ids['products'] = cur.fetchone()[0]

            self._insert_commit(cur, 'feature-b', 'T8c', 'CREATE TABLE products', 'hash_T8c')
            self._insert_history(cur, 'products', 'feature-b', 'CREATE',
                'CREATE TABLE products (id INT PRIMARY KEY, price DECIMAL)', 'hash_T8c', 'T8c')

            # T8d: ALTER TABLE orders ADD product_id
            self._insert_commit(cur, 'feature-b', 'T8d', 'ALTER TABLE orders ADD product_id', 'hash_T8d')
            self._insert_history(cur, 'orders', 'feature-b', 'ALTER',
                'CREATE TABLE orders (id INT, user_id INT, amount DECIMAL, product_id INT)',
                'hash_T8d', 'T8d',
                before_def='CREATE TABLE orders (id INT, user_id INT, amount DECIMAL)')

        self.conn.commit()

    def _create_dependencies(self):
        """Create object dependency records"""
        with self.conn.cursor() as cur:
            # orders depends on users (FK)
            cur.execute(
                "INSERT INTO pggit.object_dependencies (source_object_id, target_object_id, "
                "dependency_type, strength) VALUES (%s, %s, %s, %s)",
                (self.object_ids['orders'], self.object_ids['users'], 'FK', 'HARD')
            )

            # payments depends on orders (FK)
            cur.execute(
                "INSERT INTO pggit.object_dependencies (source_object_id, target_object_id, "
                "dependency_type, strength) VALUES (%s, %s, %s, %s)",
                (self.object_ids['payments'], self.object_ids['orders'], 'FK', 'HARD')
            )

            # count_users function depends on users table
            cur.execute(
                "INSERT INTO pggit.object_dependencies (source_object_id, target_object_id, "
                "dependency_type, strength) VALUES (%s, %s, %s, %s)",
                (self.object_ids['count_users'], self.object_ids['users'], 'FUNCTION_CALL', 'SOFT')
            )

        self.conn.commit()

    def _insert_commit(self, cur, branch, timestamp_key, message, hash_val):
        """Insert commit"""
        cur.execute(
            "INSERT INTO pggit.commits (branch_id, author_name, author_time, "
            "commit_message, commit_hash, object_changes) "
            "VALUES (%s, %s, %s, %s, %s, '{}')",
            (self.branch_ids[branch], 'developer', self.timestamps[timestamp_key], message, hash_val)
        )

    def _insert_history(self, cur, object_name, branch, change_type, after_def, commit_hash,
                       timestamp_key, before_def=None, author='developer'):
        """Insert object history"""
        after_hash = hashlib.sha256(after_def.encode()).hexdigest()
        before_hash = hashlib.sha256(before_def.encode()).hexdigest() if before_def else None

        cur.execute(
            "INSERT INTO pggit.object_history (object_id, branch_id, change_type, "
            "before_definition, before_hash, after_definition, after_hash, "
            "commit_hash, author_name, author_time, created_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (self.object_ids[object_name], self.branch_ids[branch], change_type,
             before_def, before_hash, after_def, after_hash, commit_hash, author,
             self.timestamps[timestamp_key], self.timestamps[timestamp_key])
        )

    # Helper methods for test assertions
    def assert_object_exists(self, object_name: str, should_exist: bool = True) -> bool:
        """Check if object exists in schema_objects"""
        with self.conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM pggit.schema_objects WHERE object_name = %s",
                (object_name,)
            )
            result = cur.fetchone()
            exists = result is not None
            assert exists == should_exist, f"Object {object_name} existence mismatch"
            return exists

    def assert_definition_matches(self, object_name: str, expected_def: str) -> bool:
        """Check if object definition matches expected"""
        with self.conn.cursor() as cur:
            cur.execute(
                "SELECT current_definition FROM pggit.schema_objects WHERE object_name = %s",
                (object_name,)
            )
            result = cur.fetchone()
            if result:
                assert result[0] == expected_def, f"Definition mismatch for {object_name}"
                return True
            return False

    def count_dependencies(self, source_object_id: int = None, target_object_id: int = None) -> int:
        """Count dependencies"""
        with self.conn.cursor() as cur:
            if source_object_id:
                cur.execute(
                    "SELECT COUNT(*) FROM pggit.object_dependencies WHERE source_object_id = %s",
                    (source_object_id,)
                )
            else:
                cur.execute("SELECT COUNT(*) FROM pggit.object_dependencies")
            return cur.fetchone()[0]
```

---

## Part 3: Test Scenarios

### Scenario 1: Safe Single Commit Rollback
- Rollback T4 (CREATE INDEX)
- Should succeed - no dependencies, simple operation
- Verify index is dropped

### Scenario 2: Rollback with Dependencies
- Rollback T2 (CREATE TABLE orders)
- Should fail - T5 depends on orders
- Validate catches FK dependency

### Scenario 3: Rollback Sequence
- Rollback T5, then T3, then T1
- Should succeed in reverse order
- Verify all objects reverted

### Scenario 4: Range Rollback
- Rollback T3-T5 range
- Should reorder to DROP first, then ALTER
- Verify schema matches pre-T3 state

### Scenario 5: Merge Conflict
- Try to rollback merged commit from feature-a
- Should handle complex merge history
- Verify both branches' changes considered

### Scenario 6: Time-Travel
- Rollback to T4
- Should recreate state before T5, T6, T11
- Verify exact schema matches historical

### Scenario 7: Partial Undo
- Undo changes to orders table only
- Keep other table changes
- Verify orders reverted, users.email still present

---

**Created**: 2025-12-26
**Status**: Ready for Implementation Testing
