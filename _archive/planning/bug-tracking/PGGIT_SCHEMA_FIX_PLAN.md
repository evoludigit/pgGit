# Fix Plan: pggit Schema Critical Issues

**Date**: 2025-12-21
**Priority**: P0 (CRITICAL - BLOCKS ALL DDL)
**Impact**: Affects all 10+ test files
**Effort**: 1-2 hours

---

## Problem Summary

The `pggit.ensure_object()` function has an ambiguous signature that causes PostgreSQL to fail when called with fewer than all parameters, even though defaults are provided.

**Current Signature**:
```sql
CREATE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,          -- Position 4
    p_metadata JSONB DEFAULT '{}',            -- Position 5
    p_branch_name TEXT DEFAULT 'main'         -- Position 6
) RETURNS INTEGER
```

**Problem Calls**:
```sql
-- Called with 5 args (positions 1-5, skipping p_branch_name)
pggit.ensure_object(
    'TABLE'::pggit.object_type,
    v_schema_name,
    v_object_name,
    NULL,                    -- p_parent_name
    v_metadata               -- p_metadata
)
-- Missing: p_branch_name (should use default 'main')
```

**Error**:
```
ERROR: function pggit.ensure_object(pggit.object_type, text, text, <NULL>, jsonb) is not unique
```

---

## Root Cause Analysis

PostgreSQL's function overload resolution rules state:
- When a parameter has a DEFAULT value, it can be omitted
- But PostgreSQL must still be able to uniquely identify which function to call
- If the omitted parameter is followed by other parameters that also have defaults, ambiguity occurs

**Why It's Ambiguous**:
```
Function: f(a, b, c DEFAULT x, d DEFAULT y, e DEFAULT z)

Call: f(a_val, b_val, c_val, d_val)
Could mean:
  1. f(a_val, b_val, c_val, d_val, z)     <- Use default for e
  2. Could this match another overload?

PostgreSQL tries to be safe and requires all defaults to be at the END
of the parameter list with no non-default parameters after them.
```

---

## Solution Options

### Option A: Reorder Parameters (RECOMMENDED - 30 min)
**Keep the 6-parameter version, move p_branch_name earlier or remove it**

**Best sub-option: Move p_branch_name to position 2**
```sql
CREATE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_branch_name TEXT DEFAULT 'main',       -- MOVED UP
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER
```

But this breaks all existing calls!

---

### Option B: Create Helper Functions (RECOMMENDED - 1 hour)
**Keep existing function, create wrapper functions with different signatures**

**New Functions**:
```sql
-- 5-parameter version (most common call pattern)
CREATE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
BEGIN
    RETURN pggit.ensure_object(
        p_object_type,
        p_schema_name,
        p_object_name,
        p_parent_name,
        p_metadata,
        'main'  -- Use default branch
    );
END;
$$ LANGUAGE plpgsql;
```

**Advantages**:
- ✅ No changes to existing calls
- ✅ Maintains backward compatibility
- ✅ Fixes the ambiguity
- ✅ Clear intent (5-arg version uses 'main', 6-arg can specify branch)

---

### Option C: Make p_branch_name Optional Position (RECOMMENDED - 1.5 hours)
**Create simplified function that doesn't take p_branch_name at all**

```sql
-- Rename current 6-parameter function
CREATE FUNCTION pggit.ensure_object_with_branch(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}',
    p_branch_name TEXT DEFAULT 'main'
) RETURNS INTEGER AS $$
-- ... existing implementation
$$;

-- Create simpler 5-parameter wrapper with original name
CREATE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
BEGIN
    RETURN pggit.ensure_object_with_branch(
        p_object_type, p_schema_name, p_object_name,
        p_parent_name, p_metadata, 'main'
    );
END;
$$ LANGUAGE plpgsql;
```

---

## Recommended Solution: Option B

**Reasoning**:
1. ✅ Simplest to implement
2. ✅ No changes needed to calling code
3. ✅ Fixes the ambiguity completely
4. ✅ Clear that 5-arg version uses default branch
5. ✅ If someone needs custom branch, they can use the 6-arg version later

---

## Implementation Steps

### Step 1: Read and understand current implementation
```bash
grep -A 50 "CREATE OR REPLACE FUNCTION pggit.ensure_object" sql/001_schema.sql
```

### Step 2: Find the end of the 6-parameter function
```bash
# Find where the function definition ends
grep -n "^); LANGUAGE" sql/001_schema.sql | grep -A 1 "ensure_object"
```

### Step 3: Add the 5-parameter wrapper after the 6-parameter function

**Location**: In `sql/001_schema.sql`, right after the 6-parameter `ensure_object` function ends

**Code to add**:
```sql
-- 5-parameter wrapper function for backward compatibility
-- This version always uses 'main' as the branch name
CREATE OR REPLACE FUNCTION pggit.ensure_object(
    p_object_type pggit.object_type,
    p_schema_name TEXT,
    p_object_name TEXT,
    p_parent_name TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS INTEGER AS $$
DECLARE
    v_result INTEGER;
BEGIN
    -- Call the 6-parameter version with 'main' as default branch
    SELECT pggit.ensure_object(
        p_object_type,
        p_schema_name,
        p_object_name,
        p_parent_name,
        p_metadata,
        'main'  -- Use default branch
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
```

### Step 4: Verify the fix

**Test 1: Can we install the schema?**
```bash
cd sql && psql -U postgres -d postgres -f 001_schema.sql 2>&1 | grep -i error
# Expected: No output (no errors)
```

**Test 2: Can we call it with 5 arguments?**
```bash
psql -U postgres -d postgres << 'EOF'
-- Create a simple object with 5 args (should work now)
SELECT pggit.ensure_object(
    'TABLE'::pggit.object_type,
    'public',
    'test_table',
    NULL,
    '{}'::jsonb
);
EOF
```

**Test 3: Can we call it with 6 arguments?**
```bash
psql -U postgres -d postgres << 'EOF'
SELECT pggit.ensure_object(
    'TABLE'::pggit.object_type,
    'public',
    'test_table_2',
    NULL,
    '{}'::jsonb,
    'dev'  -- Custom branch
);
EOF
```

**Test 4: Can we call it with fewer arguments (relying on defaults)?**
```bash
psql -U postgres -d postgres << 'EOF'
SELECT pggit.ensure_object(
    'TABLE'::pggit.object_type,
    'public',
    'test_table_3'
);
EOF
```

### Step 5: Run actual tests

```bash
# Run core test
psql -U postgres -d postgres -f tests/test-core.sql 2>&1 | grep -E "ERROR|PASS" | head -20
```

**Expected**: No "function pggit.ensure_object... is not unique" error

---

## Verification Checklist

- [ ] Wrapper function added to sql/001_schema.sql
- [ ] Function installs without errors
- [ ] 5-parameter calls work
- [ ] 6-parameter calls work
- [ ] Default arguments work
- [ ] test-core.sql runs without ambiguity errors
- [ ] All 14 test files run further than before
- [ ] No regressions in existing functionality

---

## Expected Outcome

**Before Fix**:
```
psql:tests/test-core.sql:59: ERROR: function pggit.ensure_object(pggit.object_type, text, text, <NULL>, jsonb) is not unique
```

**After Fix**:
```
Tests proceed further - may encounter different errors (expected)
but NOT the "is not unique" error anymore
```

---

## Related Issues

This fix will likely reveal **other bugs** that were hidden by this error:
1. Missing CQRS functions (test-cqrs-support.sql)
2. Missing data branching functions (test-data-branching.sql)
3. Missing pggit_v0 schema (test-proper-three-way-merge.sql)
4. Missing AI functions (test-ai.sql)

These are **expected and good** - we want to see them so we can fix them next.

---

## Time Estimate

| Task | Duration |
|------|----------|
| Understand current function | 10 min |
| Find insertion point | 5 min |
| Write wrapper function | 10 min |
| Test with 5 args | 5 min |
| Test with 6 args | 5 min |
| Run test-core.sql | 5 min |
| Fix any issues | 15 min |
| **TOTAL** | **55 min** |

---

## Success Criteria

- [ ] `pggit.ensure_object()` ambiguity error is gone
- [ ] Both 5 and 6 parameter versions work
- [ ] Tests proceed further (more functionality tested)
- [ ] No regressions in existing calls

Ready to implement?
