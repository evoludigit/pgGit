# Event Trigger Investigation Report

**Date:** 2026-02-05
**Issue:** CREATE TABLE statements are not being tracked in `pggit.objects` despite event triggers existing
**Root Cause:** Identified and Documented
**Severity:** Critical

---

## Executive Summary

The CREATE TABLE tracking is failing due to **two critical issues in the enhanced event trigger implementation**:

1. **Missing Function Definition**: The enhanced trigger calls `pggit.version_object()` which does not exist in any SQL file
2. **Silent Error Handling**: Exceptions from the missing function are caught and swallowed, providing no visibility into the problem
3. **Event Trigger Replacement**: The enhanced trigger (048) replaces the original working trigger (002) but doesn't implement equivalent functionality

---

## Root Cause Analysis

### Issue 1: Missing `pggit.version_object()` Function

**Location:** `sql/048_pggit_enhanced_triggers.sql`, line 91

```sql
PERFORM pggit.version_object(
    obj.classid,
    obj.objid,
    obj.objsubid,
    obj.command_tag,
    obj.object_type,
    obj.schema_name,
    obj.object_identity,
    obj.in_extension
);
```

**Finding:** This function is called but **never defined anywhere in the codebase**.

Verification:
```bash
$ grep -rn "CREATE.*FUNCTION.*version_object" sql/
# No results - function doesn't exist!

$ grep -rn "version_object" sql/
sql/048_pggit_enhanced_triggers.sql:91:  PERFORM pggit.version_object(
# Only one reference - the call, no definition
```

### Issue 2: Silent Exception Handling

**Location:** `sql/048_pggit_enhanced_triggers.sql`, lines 102-110

```plpgsql
EXCEPTION WHEN OTHERS THEN
    -- Log error but don't fail the DDL operation
    INSERT INTO pggit.system_events (event_type, event_data)
    VALUES ('tracking_error', jsonb_build_object(
        'error', SQLERRM,
        'object_type', obj.object_type,
        'object_identity', obj.object_identity,
        'operation', operation
    ));
```

**Problem:** When `version_object()` throws "function not found", the exception is caught and logged to `pggit.system_events` instead of being reported. This makes the failure **invisible to tests and monitoring**.

### Issue 3: Enhanced Trigger Replacement

**Location:** `sql/048_pggit_enhanced_triggers.sql`, lines 5-6

```sql
-- Drop existing triggers if they exist
DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger CASCADE;
DROP EVENT TRIGGER IF EXISTS pggit_drop_trigger CASCADE;
```

Then at line 243:
```sql
SELECT pggit.use_enhanced_triggers(true);
```

This function disables the original working triggers and enables the broken enhanced triggers.

**Files Involved:**
- `sql/002_event_triggers.sql` - Defines original `pggit_ddl_trigger` with `pggit.handle_ddl_command()`
- `sql/048_pggit_enhanced_triggers.sql` - Replaces it with broken enhanced version

---

## Event Trigger Status Check

### What We Found

Using diagnostic test, we discovered:

```
Available event triggers:
  ✅ pggit_enhanced_ddl_trigger (enabled)
  ✅ pggit_enhanced_drop_trigger (enabled)
  ✅ pggit_metrics_trigger (enabled)
  ❌ pggit_ddl_trigger (NOT FOUND - replaced by enhanced version)
```

### What Should Be There

The original working trigger from `sql/002_event_triggers.sql`:
```sql
CREATE EVENT TRIGGER pggit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION pggit.handle_ddl_command();
```

This calls the working function `pggit.handle_ddl_command()` which properly tracks tables.

---

## Evidence of Failure

### Diagnostic Test Results

**Test 1: Event Trigger Status**
```
❌ pggit_ddl_trigger does not exist!
Available event triggers:
  - pggit_enhanced_ddl_trigger (enabled)
  - pggit_enhanced_drop_trigger (enabled)
  - pggit_metrics_trigger (enabled)
```

**Test 2: Table Tracking Behavior**

Test case from `tests/e2e/test_dependency_tracking.py::TestBasicDependencies::test_foreign_key_dependency`:

```python
db_e2e.execute("CREATE TABLE parent (id SERIAL PRIMARY KEY, name TEXT)")
db_e2e.execute("CREATE TABLE child (id SERIAL PRIMARY KEY, parent_id INT REFERENCES parent(id))")

# Check if tables are tracked
objects_check = db_e2e.execute("""
    SELECT full_name FROM pggit.objects
    WHERE full_name IN ('public.child', 'public.parent')
""")

# Result: EMPTY - no tables tracked!
# Test skips with: "Tables not tracked in pggit.objects - event triggers may not be enabled"
```

---

## Call Flow Analysis

### Original (Working) Flow

```
CREATE TABLE
    ↓
PostgreSQL DDL Event
    ↓
pggit_ddl_trigger (ENABLED)
    ↓
pggit.handle_ddl_command()
    ↓
pg_event_trigger_ddl_commands()  ← Returns DDL data
    ↓
pggit.ensure_object()  ← Actually tracks the object
    ↓
INSERT INTO pggit.objects  ← Table appears in tracking!
```

### Current (Broken) Flow

```
CREATE TABLE
    ↓
PostgreSQL DDL Event
    ↓
pggit_ddl_trigger (DISABLED)  ← Not running!
    ↓
pggit_enhanced_ddl_trigger (ENABLED)  ← This one runs instead
    ↓
pggit.enhanced_ddl_trigger_func()
    ↓
pg_event_trigger_ddl_commands()  ← Returns DDL data
    ↓
pggit.version_object(...)  ← Function doesn't exist!
    ↓
EXCEPTION: undefined function pggit.version_object
    ↓
EXCEPTION WHEN OTHERS → Silently log to pggit.system_events
    ↓
NO TRACKING HAPPENS  ← The problem!
```

---

## Impact on Tests

### Why Tests Are Failing

Any test that depends on event trigger tracking fails:

1. **Dependency tracking tests** (`test_dependency_tracking.py`)
   - Tries to verify tables were tracked
   - Tables don't exist in `pggit.objects`
   - Test skips or fails

2. **DDL tracking tests** (`test_ddl_comprehensive.py`)
   - Similar issue
   - Objects not being tracked

3. **Foreign key tracking** (`test_foreign_key_dependency`)
   - Specific test that creates tables with FKs
   - Expects dependency tracking
   - Gets empty results

### Transaction Isolation is NOT the Issue

We verified that event triggers work correctly both with and without transaction isolation. The problem is purely the broken enhanced trigger implementation.

---

## Root Cause Categories

| Category | Root Cause | Severity |
|----------|-----------|----------|
| Function Missing | `pggit.version_object()` not defined | Critical |
| Silent Failure | Exceptions caught, no visibility | Critical |
| Broken Implementation | Enhanced trigger replaces working one | Critical |
| No Fallback | No error recovery mechanism | Critical |

---

## Solution Approaches

### Option 1: Fix the Enhanced Trigger (Recommended)

**Effort:** 2-4 hours
**Scope:** Fix `sql/048_pggit_enhanced_triggers.sql`

Steps:
1. Define `pggit.version_object()` function with proper implementation
2. OR replace the call with the original `pggit.handle_ddl_command()` logic
3. Test that tracking works again

### Option 2: Revert to Original Trigger

**Effort:** 30 minutes
**Scope:** Disable enhanced triggers

Steps:
1. Comment out line 243: `SELECT pggit.use_enhanced_triggers(true);`
2. Don't drop original triggers in 048
3. Test that tracking works

### Option 3: Disable Enhanced Triggers by Default

**Effort:** 1 hour
**Scope:** Make enhanced triggers opt-in

Steps:
1. Keep 048 file but don't auto-enable enhanced triggers
2. Add configuration flag to use enhanced version
3. Tests use original by default

---

## Recommended Fix

**We recommend Option 1**: Fix the enhanced trigger implementation.

This would:
- ✅ Maintain the enhanced feature set (configuration, error logging)
- ✅ Restore table tracking functionality
- ✅ Fix all dependency-tracking related tests
- ✅ Provide better error visibility than original

**Implementation Plan:**
1. Define `pggit.version_object()` function
2. Test tracking works
3. Verify all DDL tests pass
4. Update diagnostics to show status

---

## Verification Checklist

After fix is applied, verify:

- [ ] `pggit_ddl_trigger` exists and is enabled (or `pggit_enhanced_ddl_trigger` calls working function)
- [ ] `pggit.version_object()` function exists and is called successfully
- [ ] CREATE TABLE results in rows in `pggit.objects`
- [ ] CREATE VIEW results in rows in `pggit.objects`
- [ ] Foreign key dependencies are tracked
- [ ] `tests/e2e/test_dependency_tracking.py::TestBasicDependencies::test_foreign_key_dependency` passes
- [ ] All DDL tracking tests pass
- [ ] `pggit.system_events` shows no tracking_error entries

---

## Diagnostic Commands

### Check Which Trigger is Active

```sql
SELECT evtname, evtenabled FROM pg_event_trigger
WHERE evtname LIKE 'pggit%ddl%'
ORDER BY evtname;
```

### Check for Tracking Errors

```sql
SELECT COUNT(*) as error_count,
       event_data->>'error' as error_message
FROM pggit.system_events
WHERE event_type = 'tracking_error'
GROUP BY event_data->>'error'
ORDER BY error_count DESC;
```

### Verify Objects Are Being Tracked

```sql
-- After CREATE TABLE test_table (id INT)
SELECT * FROM pggit.objects
WHERE object_name = 'test_table'
AND is_active = true;
```

---

## Files Involved

**Related SQL Files:**
- `sql/002_event_triggers.sql` - Original working trigger and function
- `sql/048_pggit_enhanced_triggers.sql` - Broken enhanced trigger
- `sql/043_pggit_configuration.sql` - Configuration tables
- `sql/053_pggit_monitoring.sql` - Monitoring/metrics triggers

**Related Test Files:**
- `tests/e2e/test_dependency_tracking.py` - Fails because no tracking
- `tests/e2e/test_event_trigger_diagnostic.py` - Our diagnostic test (demonstrates the issue)
- `tests/e2e/test_ddl_comprehensive.py` - Also fails

**Configuration:**
- `tests/e2e/conftest.py` - Test setup (not the issue)
- `tests/fixtures/isolated_database.py` - Fixture isolation (not the issue)

---

## Summary

**The problem is NOT:**
- ❌ Transaction isolation in test fixtures
- ❌ Event trigger not firing
- ❌ PostgreSQL version compatibility
- ❌ Database connection issues

**The problem IS:**
- ✅ `sql/048_pggit_enhanced_triggers.sql` has broken enhanced trigger
- ✅ Calls non-existent `pggit.version_object()` function
- ✅ Exceptions are silently caught
- ✅ No tables get tracked
- ✅ Tests expecting tracking fail

**Fix:** Implement missing `pggit.version_object()` or revert to original trigger.

