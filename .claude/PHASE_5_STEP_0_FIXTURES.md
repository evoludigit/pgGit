# Phase 5 Step 0: Test Fixtures & Implementation Patterns

**Status**: Pre-Implementation Planning
**Date**: 2025-12-26
**Purpose**: Design comprehensive test fixtures and extraction of implementation patterns

---

## Overview

This document provides:
1. **Complex Test History Architecture** - Multi-branch commit/merge history for testing
2. **Fixture Patterns** - Reusable components for testing all Phase 5 functions
3. **Timestamp Management** - Handling historical queries and time-travel
4. **Edge Case Scenarios** - Complex historical situations to test

---

## Part 1: Test History Architecture

### Timeline Structure

Design a rich history that tests all Phase 5 functions:

```
2025-12-26 10:00:00 (T0): Main branch created
├─ 2025-12-26 10:15:00 (T1): CREATE TABLE users (id INT, name VARCHAR)
├─ 2025-12-26 10:30:00 (T2): CREATE FUNCTION count_users() RETURNS INT
├─ 2025-12-26 10:45:00 (T3): ALTER TABLE users ADD COLUMN email VARCHAR
│  └─ 2025-12-26 11:00:00 (T4): Feature-A branch created from main
│     ├─ 2025-12-26 11:15:00 (T4b): ALTER TABLE users ADD COLUMN phone VARCHAR
│     ├─ 2025-12-26 11:30:00 (T4c): CREATE INDEX idx_users_email ON users(email)
│     └─ 2025-12-26 11:45:00 (T4d): CREATE TABLE orders (id INT, user_id INT FK)
│
├─ 2025-12-26 11:00:00 (T4): Feature-B branch created from main
│  ├─ 2025-12-26 11:15:00 (T4e): ALTER TABLE users RENAME COLUMN email TO email_address
│  ├─ 2025-12-26 11:30:00 (T4f): ALTER FUNCTION count_users() BODY CHANGED
│  └─ 2025-12-26 11:45:00 (T4g): CREATE TABLE payments (id INT, order_id INT FK)
│
├─ 2025-12-26 12:00:00 (T5): Merge feature-a -> main (UNION strategy)
│  └─ Result: users has email, phone; orders table added
│
├─ 2025-12-26 12:30:00 (T6): Merge feature-b -> main (MANUAL_REVIEW -> resolved)
│  └─ Result: email_address (from B), payments table added
│
└─ 2025-12-26 13:00:00 (T7): ALTER TABLE users DROP COLUMN email_address

Final state:
- users: id, name, phone, email_address (deleted in T7)
- orders: id, user_id (from feature-a via merge)
- payments: id, order_id (from feature-b via merge)
- count_users(): function (modified version from feature-b)
```

### Objects Created

**Main branch objects**:
1. users (TABLE)
   - T1: CREATE with id, name
   - T3: ALTER ADD email
   - T5: MERGED from feature-a (phone added)
   - T6: MERGED from feature-b (email_address rename)
   - T7: ALTER DROP email_address

2. count_users (FUNCTION)
   - T2: CREATE
   - T6: MERGED function body from feature-b

**Feature-A branch objects**:
1. orders (TABLE) - NEW
   - T4d: CREATE TABLE orders

2. users modifications
   - T4b: ALTER users ADD phone

3. indexes
   - T4c: CREATE INDEX idx_users_email

**Feature-B branch objects**:
1. payments (TABLE) - NEW
   - T4g: CREATE TABLE payments

2. users modifications
   - T4e: ALTER users RENAME email

3. function modifications
   - T4f: ALTER FUNCTION count_users()

### Fixture Class Implementation

```python
class Phase5HistoryFixture:
    """
    Comprehensive fixture for Phase 5 historical queries.

    Creates:
    - 2-3 branches with parent relationships
    - 5+ schema objects with rich modification history
    - 7+ historical commits with accurate timestamps
    - 2 merge operations with conflict resolution
    - Deterministic hashes for reproducible testing
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
            'T0': base_time,                          # 10:00
            'T1': base_time + timedelta(minutes=15),  # 10:15
            'T2': base_time + timedelta(minutes=30),  # 10:30
            'T3': base_time + timedelta(minutes=45),  # 10:45
            'T4': base_time + timedelta(hours=1),     # 11:00
            'T4b': base_time + timedelta(minutes=75), # 11:15
            'T4c': base_time + timedelta(minutes=90), # 11:30
            'T4d': base_time + timedelta(minutes=105),# 11:45
            'T4e': base_time + timedelta(minutes=75), # 11:15
            'T4f': base_time + timedelta(minutes=90), # 11:30
            'T4g': base_time + timedelta(minutes=105),# 11:45
            'T5': base_time + timedelta(hours=2),     # 12:00
            'T6': base_time + timedelta(minutes=150), # 12:30
            'T7': base_time + timedelta(hours=3),     # 13:00
        }

    def setup(self):
        """Create complete fixture data"""
        self._create_branches()
        self._create_commits_and_objects()
        self._create_merge_operations()

    def teardown(self):
        """Clean up all fixture data"""
        # Delete in reverse order of creation
        self._delete_merge_operations()
        self._delete_object_history()
        self._delete_objects()
        self._delete_commits()
        self._delete_branches()

    def _create_branches(self):
        """Create branch hierarchy"""
        # Main branch
        self.branch_ids['main'] = self._insert_branch(
            name='main',
            parent_id=None,
            created_at=self.timestamps['T0'],
            created_by='system'
        )

        # Feature branches
        for branch_name in ['feature-a', 'feature-b']:
            self.branch_ids[branch_name] = self._insert_branch(
                name=branch_name,
                parent_id=self.branch_ids['main'],
                created_at=self.timestamps['T4'],
                created_by='developer'
            )

    def _create_commits_and_objects(self):
        """Create commits with associated object history"""

        # T1: CREATE TABLE users on main
        users_id = self._create_object('users', 'TABLE', 'public')
        self._insert_commit(
            branch='main',
            timestamp=self.timestamps['T1'],
            message='CREATE TABLE users',
            author='developer',
            hash='hash_commit_T1'
        )
        self._insert_object_history(
            object_id=users_id,
            branch='main',
            change_type='CREATE',
            after_definition='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))',
            commit='hash_commit_T1',
            timestamp=self.timestamps['T1']
        )

        # T2: CREATE FUNCTION count_users on main
        func_id = self._create_object('count_users', 'FUNCTION', 'public')
        self._insert_commit(
            branch='main',
            timestamp=self.timestamps['T2'],
            message='CREATE FUNCTION count_users()',
            author='developer',
            hash='hash_commit_T2'
        )
        self._insert_object_history(
            object_id=func_id,
            branch='main',
            change_type='CREATE',
            after_definition='CREATE FUNCTION public.count_users() RETURNS INT...',
            commit='hash_commit_T2',
            timestamp=self.timestamps['T2']
        )

        # T3: ALTER TABLE users on main
        self._insert_commit(
            branch='main',
            timestamp=self.timestamps['T3'],
            message='ALTER TABLE users ADD email',
            author='developer',
            hash='hash_commit_T3'
        )
        self._insert_object_history(
            object_id=users_id,
            branch='main',
            change_type='ALTER',
            before_definition='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))',
            after_definition='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))',
            commit='hash_commit_T3',
            timestamp=self.timestamps['T3']
        )

        # T4b: Feature-A: ALTER TABLE users ADD phone
        self._insert_commit(
            branch='feature-a',
            timestamp=self.timestamps['T4b'],
            message='ALTER TABLE users ADD phone',
            author='developer-a',
            hash='hash_commit_T4b'
        )
        self._insert_object_history(
            object_id=users_id,
            branch='feature-a',
            change_type='ALTER',
            before_definition='CREATE TABLE users (id INT, name VARCHAR(100))',
            after_definition='CREATE TABLE users (id INT, name VARCHAR(100), phone VARCHAR(20))',
            commit='hash_commit_T4b',
            timestamp=self.timestamps['T4b']
        )

        # T4c: Feature-A: CREATE INDEX
        idx_id = self._create_object('idx_users_email', 'INDEX', 'public')
        self._insert_commit(
            branch='feature-a',
            timestamp=self.timestamps['T4c'],
            message='CREATE INDEX idx_users_email',
            author='developer-a',
            hash='hash_commit_T4c'
        )
        self._insert_object_history(
            object_id=idx_id,
            branch='feature-a',
            change_type='CREATE',
            after_definition='CREATE INDEX idx_users_email ON users(email)',
            commit='hash_commit_T4c',
            timestamp=self.timestamps['T4c']
        )

        # T4d: Feature-A: CREATE TABLE orders
        orders_id = self._create_object('orders', 'TABLE', 'public')
        self._insert_commit(
            branch='feature-a',
            timestamp=self.timestamps['T4d'],
            message='CREATE TABLE orders',
            author='developer-a',
            hash='hash_commit_T4d'
        )
        self._insert_object_history(
            object_id=orders_id,
            branch='feature-a',
            change_type='CREATE',
            after_definition='CREATE TABLE orders (id INT PRIMARY KEY, user_id INT REFERENCES users(id))',
            commit='hash_commit_T4d',
            timestamp=self.timestamps['T4d']
        )

        # T4e: Feature-B: ALTER TABLE users RENAME email
        self._insert_commit(
            branch='feature-b',
            timestamp=self.timestamps['T4e'],
            message='ALTER TABLE users RENAME email to email_address',
            author='developer-b',
            hash='hash_commit_T4e'
        )
        self._insert_object_history(
            object_id=users_id,
            branch='feature-b',
            change_type='ALTER',
            before_definition='CREATE TABLE users (id INT, name VARCHAR(100))',
            after_definition='CREATE TABLE users (id INT, name VARCHAR(100), email_address VARCHAR(100))',
            commit='hash_commit_T4e',
            timestamp=self.timestamps['T4e']
        )

        # T4f: Feature-B: ALTER FUNCTION
        self._insert_commit(
            branch='feature-b',
            timestamp=self.timestamps['T4f'],
            message='ALTER FUNCTION count_users() - improved implementation',
            author='developer-b',
            hash='hash_commit_T4f'
        )
        self._insert_object_history(
            object_id=func_id,
            branch='feature-b',
            change_type='ALTER',
            before_definition='CREATE FUNCTION public.count_users() RETURNS INT...',
            after_definition='CREATE FUNCTION public.count_users() RETURNS INT AS improved...',
            commit='hash_commit_T4f',
            timestamp=self.timestamps['T4f']
        )

        # T4g: Feature-B: CREATE TABLE payments
        payments_id = self._create_object('payments', 'TABLE', 'public')
        self._insert_commit(
            branch='feature-b',
            timestamp=self.timestamps['T4g'],
            message='CREATE TABLE payments',
            author='developer-b',
            hash='hash_commit_T4g'
        )
        self._insert_object_history(
            object_id=payments_id,
            branch='feature-b',
            change_type='CREATE',
            after_definition='CREATE TABLE payments (id INT PRIMARY KEY, order_id INT)',
            commit='hash_commit_T4g',
            timestamp=self.timestamps['T4g']
        )

        # T7: ALTER TABLE users DROP phone/email_address
        self._insert_commit(
            branch='main',
            timestamp=self.timestamps['T7'],
            message='ALTER TABLE users DROP old columns',
            author='developer',
            hash='hash_commit_T7'
        )
        self._insert_object_history(
            object_id=users_id,
            branch='main',
            change_type='ALTER',
            before_definition='CREATE TABLE users (...with phone/email_address...)',
            after_definition='CREATE TABLE users (id INT, name VARCHAR(100))',
            commit='hash_commit_T7',
            timestamp=self.timestamps['T7']
        )

    def _create_merge_operations(self):
        """Create merge operation records"""
        # T5: Merge feature-a -> main
        self._insert_merge(
            source_branch='feature-a',
            target_branch='main',
            timestamp=self.timestamps['T5'],
            strategy='UNION',
            status='SUCCESS',
            merged_by='maintainer'
        )

        # T6: Merge feature-b -> main (with conflict resolution)
        self._insert_merge(
            source_branch='feature-b',
            target_branch='main',
            timestamp=self.timestamps['T6'],
            strategy='MANUAL_REVIEW',
            status='SUCCESS',
            merged_by='maintainer'
        )

    # Helper methods
    def _insert_branch(self, name, parent_id, created_at, created_by):
        """Insert branch and return ID"""
        sql = """
            INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at, created_by, status)
            VALUES (%s, %s, %s, %s, 'ACTIVE')
            RETURNING branch_id
        """
        result = self._execute(sql, (name, parent_id, created_at, created_by))
        return result[0]['branch_id']

    def _create_object(self, object_name, object_type, schema_name):
        """Create object and return ID"""
        sql = """
            INSERT INTO pggit.schema_objects (object_type, schema_name, object_name,
                                             current_definition, content_hash, is_active)
            VALUES (%s, %s, %s, %s, %s, true)
            RETURNING object_id
        """
        definition = f"CREATE {object_type} {schema_name}.{object_name}"
        hash_value = hashlib.sha256(definition.encode()).hexdigest()
        result = self._execute(sql, (object_type, schema_name, object_name, definition, hash_value))
        return result[0]['object_id']

    def _insert_commit(self, branch, timestamp, message, author, hash):
        """Insert commit record"""
        sql = """
            INSERT INTO pggit.commits (branch_id, author_name, author_time,
                                      commit_message, commit_hash, object_changes)
            VALUES (%s, %s, %s, %s, %s, '{}')
        """
        branch_id = self.branch_ids[branch]
        self._execute_insert(sql, (branch_id, author, timestamp, message, hash))

    def _insert_object_history(self, object_id, branch, change_type,
                               after_definition, commit, timestamp, before_definition=None):
        """Insert object history record"""
        sql = """
            INSERT INTO pggit.object_history (object_id, branch_id, change_type,
                                             before_definition, after_definition,
                                             commit_hash, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """
        branch_id = self.branch_ids[branch]
        self._execute_insert(sql, (object_id, branch_id, change_type,
                                  before_definition, after_definition, commit, timestamp))

    def _insert_merge(self, source_branch, target_branch, timestamp, strategy, status, merged_by):
        """Insert merge operation"""
        sql = """
            INSERT INTO pggit.merge_operations (id, source_branch_id, target_branch_id,
                                               merge_strategy, status, merged_at, merged_by)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """
        merge_id = str(uuid.uuid4())
        source_id = self.branch_ids[source_branch]
        target_id = self.branch_ids[target_branch]
        self._execute_insert(sql, (merge_id, source_id, target_id, strategy, status, timestamp, merged_by))

    def _execute(self, sql, params):
        """Execute SELECT query"""
        with self.conn.cursor() as cursor:
            cursor.execute(sql, params)
            if cursor.description:
                columns = [desc[0] for desc in cursor.description]
                return [dict(zip(columns, row)) for row in cursor.fetchall()]
            return []

    def _execute_insert(self, sql, params):
        """Execute INSERT query"""
        with self.conn.cursor() as cursor:
            cursor.execute(sql, params)
        self.conn.commit()
```

---

## Part 2: Test Patterns & Helpers

### Pattern 1: Query at Different Timestamps

```python
def test_query_at_different_timestamps():
    """Query schema at various points in time"""
    fixture = setup_fixture()

    # At T1: Only users table exists
    schema_T1 = fixture.query_at_timestamp('main', fixture.timestamps['T1'])
    assert len(schema_T1) == 1
    assert schema_T1[0]['object_name'] == 'users'
    assert schema_T1[0]['was_active'] == True

    # At T2: users + count_users function
    schema_T2 = fixture.query_at_timestamp('main', fixture.timestamps['T2'])
    assert len(schema_T2) == 2

    # At T3: users has email column
    schema_T3 = fixture.query_at_timestamp('main', fixture.timestamps['T3'])
    users_T3 = [s for s in schema_T3 if s['object_name'] == 'users'][0]
    assert 'email' in users_T3['definition']

    # At T5 (after merge): includes orders from feature-a
    schema_T5 = fixture.query_at_timestamp('main', fixture.timestamps['T5'])
    assert any(s['object_name'] == 'orders' for s in schema_T5)
```

### Pattern 2: Commit History Filtering

```python
def test_commit_history_filters():
    """Test filtering commit history"""
    fixture = setup_fixture()

    # All commits on main
    all_commits = fixture.get_commit_history('main')
    assert len(all_commits) >= 7  # T1-T7

    # Commits by specific author
    dev_commits = fixture.get_commit_history('main', author_name='developer-a')
    # Should get 0 on main (dev-a only on feature-a)
    assert len(dev_commits) == 0

    # Time range filter
    commits_T1_T3 = fixture.get_commit_history('main',
        since_timestamp=fixture.timestamps['T1'],
        until_timestamp=fixture.timestamps['T3']
    )
    assert len(commits_T1_T3) == 3  # T1, T2, T3
```

### Pattern 3: Object Timeline

```python
def test_object_timeline():
    """Test timeline of object changes"""
    fixture = setup_fixture()

    # users table timeline on main
    timeline = fixture.get_object_timeline('users', 'main')

    # Should show T1 (CREATE), T3 (ALTER add email), T7 (ALTER drop)
    # May include merged changes from feature-a, feature-b

    assert timeline[0]['change_type'] == 'CREATE'
    assert timeline[0]['timeline_version'] == 1

    # Second change should be ALTER
    assert any(t['change_type'] == 'ALTER' for t in timeline)
```

### Pattern 4: Audit Trail

```python
def test_audit_trail():
    """Test complete audit trail"""
    fixture = setup_fixture()

    # Audit trail for users object
    trail = fixture.get_audit_trail(
        p_object_name='users',
        p_branch_name='main'
    )

    # Should include all changes to users
    assert len(trail) >= 2  # At least CREATE + ALTER

    # Verify before/after definitions
    for record in trail:
        if record['change_type'] == 'ALTER':
            assert record['before_definition'] is not None
            assert record['after_definition'] is not None
            assert record['definition_diff_summary'] is not None
```

---

## Part 3: Edge Cases & Solutions

### Edge Case 1: Query Before Object Existed

**Problem**: Query at T0 when no objects exist yet.

**Solution**:
```python
def test_query_before_creation():
    schema = query_at_timestamp('main', T0)
    assert len(schema) == 0  # No objects yet
```

### Edge Case 2: Object Created and Deleted

**Problem**: Track object that was created, modified, then deleted.

**Solution**:
```
T1: CREATE TABLE temp
T3: ALTER TABLE temp...
T5: DROP TABLE temp
T6: Query at timestamp - should NOT include temp (was_active=False)
T7: Query at T4 - SHOULD include temp (before drop)
```

### Edge Case 3: Merge with Conflict Resolution

**Problem**: Track changes through MANUAL_REVIEW merge with conflict resolutions.

**Solution**:
```python
# Object modified on both feature-a and feature-b
# Merge strategy MANUAL_REVIEW
# merge_conflict_resolutions shows which version was chosen
# Timeline should reflect final merged state
```

### Edge Case 4: Deleted Branch Query

**Problem**: Query history of branch that has been deleted.

**Solution**:
```python
# Can still query deleted branch's history
# Status='DELETED' in branches table, but history preserved
# Works same as active branch
```

---

## Part 4: Performance Optimization Patterns

### Index Strategy

```sql
-- Critical for query_at_timestamp performance
CREATE INDEX idx_object_history_obj_time
ON pggit.object_history(object_id, created_at DESC);

-- For commit history filtering
CREATE INDEX idx_commits_branch_author
ON pggit.commits(branch_id, author_name, author_time DESC);

-- For audit trail queries
CREATE INDEX idx_object_history_branch_type
ON pggit.object_history(branch_id, change_type, created_at DESC);
```

### Query Optimization Techniques

1. **Pagination** - Always use LIMIT for large result sets
2. **Filtering Early** - Apply WHERE clauses before aggregations
3. **Lazy Loading** - Don't fetch definitions until needed
4. **Caching** - Cache frequently accessed timelines

---

**Status**: Fixture architecture designed and ready for implementation

**Created**: 2025-12-26
