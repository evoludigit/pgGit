-- Transaction Isolation and Concurrent Operation Safety
-- Addresses Viktor's concern about missing transaction isolation

-- ============================================
-- PART 1: Locking and Concurrency Control
-- ============================================

-- Operation locks to prevent concurrent schema changes
CREATE TABLE IF NOT EXISTS pggit.operation_locks (
    lock_id SERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    locked_object TEXT, -- schema, table, or branch name
    lock_mode TEXT NOT NULL CHECK (lock_mode IN ('SHARED', 'EXCLUSIVE')),
    session_pid INTEGER NOT NULL DEFAULT pg_backend_pid(),
    acquired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

CREATE UNIQUE INDEX idx_operation_locks_unique ON pggit.operation_locks(operation_type, locked_object, lock_mode)
WHERE expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP;

CREATE INDEX idx_operation_locks_session ON pggit.operation_locks(session_pid);
CREATE INDEX idx_operation_locks_expires ON pggit.operation_locks(expires_at);

-- Acquire operation lock
CREATE OR REPLACE FUNCTION pggit.acquire_operation_lock(
    p_operation_type TEXT,
    p_locked_object TEXT DEFAULT NULL,
    p_lock_mode TEXT DEFAULT 'EXCLUSIVE',
    p_timeout_seconds INTEGER DEFAULT 30
) RETURNS TEXT AS $$
DECLARE
    v_lock_id INTEGER;
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_timeout_time TIMESTAMP := CURRENT_TIMESTAMP + (p_timeout_seconds || ' seconds')::INTERVAL;
    v_existing_lock RECORD;
BEGIN
    -- Clean up expired locks first
    DELETE FROM pggit.operation_locks 
    WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP;
    
    -- Clean up locks from dead sessions
    DELETE FROM pggit.operation_locks
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_stat_activity 
        WHERE pid = operation_locks.session_pid
    );
    
    -- Loop until we can acquire the lock or timeout
    LOOP
        -- Check for conflicting locks
        SELECT * INTO v_existing_lock
        FROM pggit.operation_locks
        WHERE operation_type = p_operation_type
        AND (locked_object IS NULL OR locked_object = p_locked_object OR p_locked_object IS NULL)
        AND (
            lock_mode = 'EXCLUSIVE' OR 
            p_lock_mode = 'EXCLUSIVE' OR
            (lock_mode = 'SHARED' AND p_lock_mode = 'SHARED' AND session_pid != pg_backend_pid())
        )
        AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        AND session_pid != pg_backend_pid()
        LIMIT 1;
        
        IF v_existing_lock IS NULL THEN
            -- No conflicting locks, acquire the lock
            INSERT INTO pggit.operation_locks (
                operation_type, locked_object, lock_mode, 
                expires_at, metadata
            ) VALUES (
                p_operation_type, p_locked_object, p_lock_mode,
                CURRENT_TIMESTAMP + INTERVAL '1 hour', -- Auto-expire after 1 hour
                jsonb_build_object(
                    'acquired_by_function', 'acquire_operation_lock',
                    'timeout_seconds', p_timeout_seconds
                )
            ) RETURNING lock_id INTO v_lock_id;
            
            RETURN format('Acquired %s lock %s for %s (lock_id: %s)', 
                p_lock_mode, p_operation_type, COALESCE(p_locked_object, 'global'), v_lock_id);
        END IF;
        
        -- Check timeout
        IF CURRENT_TIMESTAMP >= v_timeout_time THEN
            RAISE EXCEPTION 'Timeout waiting for lock on % % (blocked by session %)', 
                p_operation_type, 
                COALESCE(p_locked_object, 'global'),
                v_existing_lock.session_pid;
        END IF;
        
        -- Wait a bit before retrying
        PERFORM pg_sleep(0.1);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Release operation lock
CREATE OR REPLACE FUNCTION pggit.release_operation_lock(
    p_operation_type TEXT,
    p_locked_object TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM pggit.operation_locks
    WHERE operation_type = p_operation_type
    AND (locked_object = p_locked_object OR (locked_object IS NULL AND p_locked_object IS NULL))
    AND session_pid = pg_backend_pid();
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    IF v_deleted_count = 0 THEN
        RAISE WARNING 'No lock found to release for % %', p_operation_type, COALESCE(p_locked_object, 'global');
    END IF;
    
    RETURN format('Released %s locks for %s %s', 
        v_deleted_count, p_operation_type, COALESCE(p_locked_object, 'global'));
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 2: Transactional Branch Operations
-- ============================================

-- Create branch with full transaction safety
CREATE OR REPLACE FUNCTION pggit.create_branch_safe(
    p_branch_name TEXT,
    p_from_branch TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_lock_result TEXT;
BEGIN
    -- Acquire exclusive lock for branch creation
    v_lock_result := pggit.acquire_operation_lock(
        'CREATE_BRANCH', 
        p_branch_name, 
        'EXCLUSIVE',
        60 -- 60 second timeout
    );
    
    BEGIN
        -- Perform branch creation within transaction
        v_result := pggit.create_branch(p_branch_name, p_from_branch);
        
        -- Release lock on success
        PERFORM pggit.release_operation_lock('CREATE_BRANCH', p_branch_name);
        
        RETURN v_result;
        
    EXCEPTION WHEN OTHERS THEN
        -- Release lock on error
        PERFORM pggit.release_operation_lock('CREATE_BRANCH', p_branch_name);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Checkout with transaction safety
CREATE OR REPLACE FUNCTION pggit.checkout_safe(
    p_branch_name TEXT,
    p_create_new BOOLEAN DEFAULT FALSE
) RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_current_branch TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_current_branch FROM pggit.HEAD;
    
    -- Acquire locks for both source and target branches
    IF v_current_branch IS NOT NULL THEN
        PERFORM pggit.acquire_operation_lock('CHECKOUT', v_current_branch, 'SHARED', 30);
    END IF;
    
    PERFORM pggit.acquire_operation_lock('CHECKOUT', p_branch_name, 'SHARED', 30);
    
    BEGIN
        -- Perform checkout
        IF p_create_new THEN
            v_result := pggit.checkout_with_apply(p_branch_name, true);
        ELSE
            v_result := pggit.checkout_with_apply(p_branch_name, false);
        END IF;
        
        -- Release locks
        IF v_current_branch IS NOT NULL THEN
            PERFORM pggit.release_operation_lock('CHECKOUT', v_current_branch);
        END IF;
        PERFORM pggit.release_operation_lock('CHECKOUT', p_branch_name);
        
        RETURN v_result;
        
    EXCEPTION WHEN OTHERS THEN
        -- Release locks on error
        IF v_current_branch IS NOT NULL THEN
            PERFORM pggit.release_operation_lock('CHECKOUT', v_current_branch);
        END IF;
        PERFORM pggit.release_operation_lock('CHECKOUT', p_branch_name);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Commit with transaction safety
CREATE OR REPLACE FUNCTION pggit.commit_safe(
    p_message TEXT
) RETURNS UUID AS $$
DECLARE
    v_result UUID;
    v_current_branch TEXT;
BEGIN
    -- Get current branch
    SELECT current_branch INTO v_current_branch FROM pggit.HEAD;
    
    IF v_current_branch IS NULL THEN
        RAISE EXCEPTION 'No branch checked out';
    END IF;
    
    -- Acquire exclusive lock for commit
    PERFORM pggit.acquire_operation_lock('COMMIT', v_current_branch, 'EXCLUSIVE', 60);
    
    BEGIN
        -- Perform commit
        v_result := pggit.commit(p_message);
        
        -- Release lock
        PERFORM pggit.release_operation_lock('COMMIT', v_current_branch);
        
        RETURN v_result;
        
    EXCEPTION WHEN OTHERS THEN
        -- Release lock on error
        PERFORM pggit.release_operation_lock('COMMIT', v_current_branch);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Merge with transaction safety
CREATE OR REPLACE FUNCTION pggit.merge_safe(
    p_source_branch TEXT,
    p_merge_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_result UUID;
    v_target_branch TEXT;
BEGIN
    -- Get current branch as target
    SELECT current_branch INTO v_target_branch FROM pggit.HEAD;
    
    IF v_target_branch IS NULL THEN
        RAISE EXCEPTION 'No branch checked out';
    END IF;
    
    -- Acquire exclusive locks for both branches
    PERFORM pggit.acquire_operation_lock('MERGE', v_target_branch, 'EXCLUSIVE', 120);
    PERFORM pggit.acquire_operation_lock('MERGE', p_source_branch, 'SHARED', 120);
    
    BEGIN
        -- Perform merge
        v_result := pggit.merge(p_source_branch, p_merge_message);
        
        -- Release locks
        PERFORM pggit.release_operation_lock('MERGE', v_target_branch);
        PERFORM pggit.release_operation_lock('MERGE', p_source_branch);
        
        RETURN v_result;
        
    EXCEPTION WHEN OTHERS THEN
        -- Release locks on error
        PERFORM pggit.release_operation_lock('MERGE', v_target_branch);
        PERFORM pggit.release_operation_lock('MERGE', p_source_branch);
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Session Isolation and State Management
-- ============================================

-- Session state tracking
CREATE TABLE IF NOT EXISTS pggit.session_state (
    session_id TEXT PRIMARY KEY DEFAULT encode(gen_random_bytes(16), 'hex'),
    session_pid INTEGER NOT NULL DEFAULT pg_backend_pid(),
    current_branch TEXT,
    working_schema TEXT,
    isolation_level TEXT DEFAULT 'READ_committed',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_session_state_pid ON pggit.session_state(session_pid);
CREATE INDEX idx_session_state_branch ON pggit.session_state(current_branch);

-- Initialize session state
CREATE OR REPLACE FUNCTION pggit.init_session_state(
    p_branch_name TEXT DEFAULT 'main'
) RETURNS TEXT AS $$
DECLARE
    v_session_id TEXT;
    v_schema_name TEXT;
BEGIN
    -- Clean up old sessions
    DELETE FROM pggit.session_state
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_stat_activity 
        WHERE pid = session_state.session_pid
    );
    
    -- For now, all branches use their own schema or public
    -- This could be enhanced to store schema mapping elsewhere
    v_schema_name := COALESCE('branch_' || p_branch_name, 'public');
    
    -- Create or update session state
    INSERT INTO pggit.session_state (
        session_pid, current_branch, working_schema
    ) VALUES (
        pg_backend_pid(), p_branch_name, v_schema_name
    ) ON CONFLICT (session_pid) DO UPDATE SET
        current_branch = EXCLUDED.current_branch,
        working_schema = EXCLUDED.working_schema,
        last_activity = CURRENT_TIMESTAMP
    RETURNING session_id INTO v_session_id;
    
    -- Set session configuration
    PERFORM set_config('pggit.session_id', v_session_id, false);
    PERFORM set_config('pggit.current_branch', p_branch_name, false);
    PERFORM set_config('pggit.working_schema', v_schema_name, false);
    
    RETURN format('Initialized session state: %s (branch: %s, schema: %s)', 
        v_session_id, p_branch_name, v_schema_name);
END;
$$ LANGUAGE plpgsql;

-- Update session activity
CREATE OR REPLACE FUNCTION pggit.update_session_activity() 
RETURNS void AS $$
BEGIN
    UPDATE pggit.session_state
    SET last_activity = CURRENT_TIMESTAMP
    WHERE session_pid = pg_backend_pid();
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Deadlock Detection and Prevention
-- ============================================

-- Deadlock detection for Git operations
CREATE OR REPLACE FUNCTION pggit.detect_potential_deadlocks()
RETURNS TABLE (
    session1_pid INTEGER,
    session1_operation TEXT,
    session1_locked_object TEXT,
    session2_pid INTEGER,
    session2_operation TEXT,
    session2_locked_object TEXT,
    deadlock_risk TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH lock_pairs AS (
        SELECT 
            l1.session_pid as pid1,
            l1.operation_type as op1,
            l1.locked_object as obj1,
            l2.session_pid as pid2,
            l2.operation_type as op2,
            l2.locked_object as obj2
        FROM pggit.operation_locks l1
        JOIN pggit.operation_locks l2 ON l1.session_pid != l2.session_pid
        WHERE (l1.expires_at IS NULL OR l1.expires_at > CURRENT_TIMESTAMP)
        AND (l2.expires_at IS NULL OR l2.expires_at > CURRENT_TIMESTAMP)
    )
    SELECT 
        lp.pid1,
        lp.op1,
        lp.obj1,
        lp.pid2,
        lp.op2,
        lp.obj2,
        CASE 
            WHEN lp.obj1 = lp.obj2 AND lp.op1 != lp.op2 THEN 'HIGH'
            WHEN lp.obj1 IS NULL OR lp.obj2 IS NULL THEN 'MEDIUM'
            ELSE 'LOW'
        END as deadlock_risk
    FROM lock_pairs lp
    WHERE EXISTS (
        SELECT 1 FROM lock_pairs lp2 
        WHERE lp2.pid1 = lp.pid2 AND lp2.pid2 = lp.pid1
    );
END;
$$ LANGUAGE plpgsql;

-- Lock ordering to prevent deadlocks
CREATE OR REPLACE FUNCTION pggit.acquire_ordered_locks(
    p_locks JSONB -- Array of {operation_type, locked_object, lock_mode}
) RETURNS TEXT AS $$
DECLARE
    v_lock JSONB;
    v_acquired_locks TEXT[] := ARRAY[]::TEXT[];
    v_lock_key TEXT;
BEGIN
    -- Sort locks by a consistent order to prevent deadlocks
    FOR v_lock IN 
        SELECT value FROM jsonb_array_elements(p_locks)
        ORDER BY 
            value->>'operation_type',
            COALESCE(value->>'locked_object', ''),
            value->>'lock_mode'
    LOOP
        v_lock_key := pggit.acquire_operation_lock(
            v_lock->>'operation_type',
            v_lock->>'locked_object',
            v_lock->>'lock_mode'
        );
        v_acquired_locks := v_acquired_locks || v_lock_key;
    END LOOP;
    
    RETURN format('Acquired %s locks in order: %s', 
        array_length(v_acquired_locks, 1),
        array_to_string(v_acquired_locks, ', ')
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Recovery and Error Handling
-- ============================================

-- Recovery from failed operations
CREATE TABLE IF NOT EXISTS pggit.operation_recovery (
    id SERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    operation_context JSONB NOT NULL,
    failure_reason TEXT,
    recovery_action TEXT,
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    recovered_at TIMESTAMP,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'recovered', 'failed'))
);

-- Automatic cleanup of stale locks and sessions
CREATE OR REPLACE FUNCTION pggit.cleanup_stale_operations()
RETURNS TABLE (
    cleaned_locks INTEGER,
    cleaned_sessions INTEGER,
    recovered_operations INTEGER
) AS $$
DECLARE
    v_cleaned_locks INTEGER;
    v_cleaned_sessions INTEGER;
    v_recovered_ops INTEGER := 0;
BEGIN
    -- Clean up expired locks
    DELETE FROM pggit.operation_locks 
    WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_cleaned_locks = ROW_COUNT;
    
    -- Clean up locks from dead sessions
    DELETE FROM pggit.operation_locks
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_stat_activity 
        WHERE pid = operation_locks.session_pid
    );
    v_cleaned_locks := v_cleaned_locks + ROW_COUNT;
    
    -- Clean up dead sessions
    DELETE FROM pggit.session_state
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_stat_activity 
        WHERE pid = session_state.session_pid
    );
    GET DIAGNOSTICS v_cleaned_sessions = ROW_COUNT;
    
    -- TODO: Implement operation recovery logic
    
    RETURN QUERY SELECT v_cleaned_locks, v_cleaned_sessions, v_recovered_ops;
END;
$$ LANGUAGE plpgsql;

-- Monitoring view for active operations
CREATE OR REPLACE VIEW pggit.active_operations AS
SELECT 
    ol.operation_type,
    ol.locked_object,
    ol.lock_mode,
    ol.session_pid,
    sa.usename as username,
    sa.application_name,
    sa.client_addr,
    sa.state,
    sa.query_start,
    ol.acquired_at,
    CURRENT_TIMESTAMP - ol.acquired_at as lock_duration,
    ss.current_branch,
    ss.working_schema
FROM pggit.operation_locks ol
LEFT JOIN pg_stat_activity sa ON sa.pid = ol.session_pid
LEFT JOIN pggit.session_state ss ON ss.session_pid = ol.session_pid
WHERE ol.expires_at IS NULL OR ol.expires_at > CURRENT_TIMESTAMP
ORDER BY ol.acquired_at;

-- ============================================
-- PART 6: Transaction Wrapper Functions
-- ============================================

-- Execute function within transaction with automatic cleanup
CREATE OR REPLACE FUNCTION pggit.execute_with_transaction_safety(
    p_function_name TEXT,
    p_function_args JSONB DEFAULT '{}'::jsonb,
    p_timeout_seconds INTEGER DEFAULT 300
) RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_session_locks INTEGER;
BEGIN
    -- Set statement timeout
    EXECUTE format('SET statement_timeout = %s', p_timeout_seconds * 1000);
    
    -- Initialize session tracking
    PERFORM pggit.update_session_activity();
    
    BEGIN
        -- Execute the function dynamically
        CASE p_function_name
            WHEN 'create_branch' THEN
                v_result := to_jsonb(pggit.create_branch_safe(
                    p_function_args->>'branch_name',
                    p_function_args->>'from_branch'
                ));
            WHEN 'checkout' THEN
                v_result := to_jsonb(pggit.checkout_safe(
                    p_function_args->>'branch_name',
                    COALESCE((p_function_args->>'create_new')::boolean, false)
                ));
            WHEN 'commit' THEN
                v_result := to_jsonb(pggit.commit_safe(
                    p_function_args->>'message'
                ));
            WHEN 'merge' THEN
                v_result := to_jsonb(pggit.merge_safe(
                    p_function_args->>'source_branch',
                    p_function_args->>'merge_message'
                ));
            ELSE
                RAISE EXCEPTION 'Unknown function: %', p_function_name;
        END CASE;
        
        -- Update session activity on success
        PERFORM pggit.update_session_activity();
        
        RETURN jsonb_build_object(
            'success', true,
            'result', v_result,
            'duration_ms', EXTRACT(milliseconds FROM (CURRENT_TIMESTAMP - v_start_time))
        );
        
    EXCEPTION WHEN OTHERS THEN
        -- Cleanup on error
        PERFORM pggit.cleanup_session_locks();
        
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'duration_ms', EXTRACT(milliseconds FROM (CURRENT_TIMESTAMP - v_start_time))
        );
    END;
    
    -- Reset statement timeout
    RESET statement_timeout;
END;
$$ LANGUAGE plpgsql;

-- Cleanup locks for current session
CREATE OR REPLACE FUNCTION pggit.cleanup_session_locks()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM pggit.operation_locks
    WHERE session_pid = pg_backend_pid();
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.acquire_operation_lock IS 'Acquire operation lock with timeout and deadlock prevention';
COMMENT ON FUNCTION pggit.create_branch_safe IS 'Create branch with full transaction safety and locking';
COMMENT ON FUNCTION pggit.execute_with_transaction_safety IS 'Execute Git operations with transaction safety and error recovery';
COMMENT ON VIEW pggit.active_operations IS 'Monitor active Git operations and their locks';