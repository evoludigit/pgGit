-- Comprehensive Error Handling and Recovery System
-- Addresses production-readiness concerns

-- ============================================
-- PART 1: Error Classification and Logging
-- ============================================

-- Error severity levels
CREATE TYPE pggit.error_severity AS ENUM (
    'INFO',
    'WARNING', 
    'ERROR',
    'CRITICAL',
    'FATAL'
);

-- Error categories
CREATE TYPE pggit.error_category AS ENUM (
    'VALIDATION_ERROR',
    'LOCK_TIMEOUT',
    'SCHEMA_CONFLICT',
    'DDL_EXECUTION_FAILED',
    'MERGE_CONFLICT',
    'DEPENDENCY_VIOLATION',
    'RESOURCE_EXHAUSTED',
    'CORRUPTION_DETECTED',
    'NETWORK_ERROR',
    'PERMISSION_DENIED'
);

-- Comprehensive error log
CREATE TABLE IF NOT EXISTS pggit.error_log (
    id SERIAL PRIMARY KEY,
    operation_id UUID DEFAULT gen_random_uuid(),
    operation_type TEXT NOT NULL,
    error_category pggit.error_category NOT NULL,
    error_severity pggit.error_severity NOT NULL,
    error_code TEXT,
    error_message TEXT NOT NULL,
    error_details JSONB,
    stack_trace TEXT,
    session_context JSONB,
    recovery_attempted BOOLEAN DEFAULT false,
    recovery_successful BOOLEAN,
    recovery_actions JSONB,
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

CREATE INDEX idx_error_log_operation ON pggit.error_log(operation_type);
CREATE INDEX idx_error_log_category ON pggit.error_log(error_category);
CREATE INDEX idx_error_log_severity ON pggit.error_log(error_severity);
CREATE INDEX idx_error_log_time ON pggit.error_log(occurred_at);

-- ============================================
-- PART 2: Error Handling Framework
-- ============================================

-- Log error with context
CREATE OR REPLACE FUNCTION pggit.log_error(
    p_operation_type TEXT,
    p_error_category pggit.error_category,
    p_error_severity pggit.error_severity,
    p_error_message TEXT,
    p_error_details JSONB DEFAULT NULL,
    p_operation_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_operation_id UUID;
    v_session_context JSONB;
    v_stack_trace TEXT;
BEGIN
    -- Generate operation ID if not provided
    v_operation_id := COALESCE(p_operation_id, gen_random_uuid());
    
    -- Collect session context
    v_session_context := jsonb_build_object(
        'session_pid', pg_backend_pid(),
        'current_user', current_user,
        'current_database', current_database(),
        'application_name', current_setting('application_name', true),
        'client_addr', inet_client_addr(),
        'current_branch', current_setting('pggit.current_branch', true),
        'working_schema', current_setting('pggit.working_schema', true)
    );
    
    -- Get stack trace for debugging
    BEGIN
        GET STACKED DIAGNOSTICS v_stack_trace = PG_CONTEXT;
    EXCEPTION WHEN OTHERS THEN
        v_stack_trace := 'Stack trace unavailable';
    END;
    
    -- Insert error log
    INSERT INTO pggit.error_log (
        operation_id,
        operation_type,
        error_category,
        error_severity,
        error_message,
        error_details,
        stack_trace,
        session_context
    ) VALUES (
        v_operation_id,
        p_operation_type,
        p_error_category,
        p_error_severity,
        p_error_message,
        p_error_details,
        v_stack_trace,
        v_session_context
    );
    
    -- Send notification for critical errors
    IF p_error_severity IN ('CRITICAL', 'FATAL') THEN
        PERFORM pggit.notify_critical_error(v_operation_id, p_error_message);
    END IF;
    
    RETURN v_operation_id;
END;
$$ LANGUAGE plpgsql;

-- Handle specific error types with recovery
CREATE OR REPLACE FUNCTION pggit.handle_error_with_recovery(
    p_error_code TEXT,
    p_error_message TEXT,
    p_operation_context JSONB
) RETURNS JSONB AS $$
DECLARE
    v_error_category pggit.error_category;
    v_recovery_result JSONB;
    v_operation_id UUID;
BEGIN
    -- Classify error
    v_error_category := pggit.classify_error(p_error_code, p_error_message);
    
    -- Log the error
    v_operation_id := pggit.log_error(
        p_operation_context->>'operation_type',
        v_error_category,
        'ERROR',
        p_error_message,
        jsonb_build_object(
            'error_code', p_error_code,
            'context', p_operation_context
        )
    );
    
    -- Attempt recovery based on error type
    v_recovery_result := pggit.attempt_error_recovery(
        v_error_category,
        p_error_code,
        p_operation_context,
        v_operation_id
    );
    
    -- Update error log with recovery result
    UPDATE pggit.error_log
    SET 
        recovery_attempted = true,
        recovery_successful = (v_recovery_result->>'success')::boolean,
        recovery_actions = v_recovery_result
    WHERE operation_id = v_operation_id;
    
    RETURN v_recovery_result;
END;
$$ LANGUAGE plpgsql;

-- Classify errors into categories
CREATE OR REPLACE FUNCTION pggit.classify_error(
    p_error_code TEXT,
    p_error_message TEXT
) RETURNS pggit.error_category AS $$
BEGIN
    CASE 
        WHEN p_error_code IN ('42601', '42701', '42703') THEN
            RETURN 'VALIDATION_ERROR';
        WHEN p_error_code = '55P03' OR p_error_message ~* 'lock.*timeout' THEN
            RETURN 'LOCK_TIMEOUT';
        WHEN p_error_code IN ('23503', '23505', '23514') THEN
            RETURN 'DEPENDENCY_VIOLATION';
        WHEN p_error_code = '42P01' OR p_error_message ~* 'does not exist' THEN
            RETURN 'SCHEMA_CONFLICT';
        WHEN p_error_code = '53200' OR p_error_message ~* 'out of memory|disk full' THEN
            RETURN 'RESOURCE_EXHAUSTED';
        WHEN p_error_code IN ('42501', '28000') THEN
            RETURN 'PERMISSION_DENIED';
        WHEN p_error_message ~* 'conflict|merge.*fail' THEN
            RETURN 'MERGE_CONFLICT';
        ELSE
            RETURN 'DDL_EXECUTION_FAILED';
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Automated Recovery Strategies
-- ============================================

-- Attempt error recovery
CREATE OR REPLACE FUNCTION pggit.attempt_error_recovery(
    p_error_category pggit.error_category,
    p_error_code TEXT,
    p_operation_context JSONB,
    p_operation_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_recovery_actions JSONB := '[]'::jsonb;
    v_success BOOLEAN := false;
    v_retry_count INTEGER := 0;
    v_max_retries INTEGER := 3;
BEGIN
    CASE p_error_category
        WHEN 'LOCK_TIMEOUT' THEN
            -- Retry with exponential backoff
            FOR v_retry_count IN 1..v_max_retries LOOP
                PERFORM pg_sleep(POWER(2, v_retry_count)); -- 2, 4, 8 seconds
                
                BEGIN
                    -- Retry the original operation
                    PERFORM pggit.retry_operation(p_operation_context);
                    v_success := true;
                    EXIT;
                EXCEPTION WHEN OTHERS THEN
                    v_recovery_actions := v_recovery_actions || 
                        jsonb_build_object(
                            'action', 'retry_after_backoff',
                            'attempt', v_retry_count,
                            'delay_seconds', POWER(2, v_retry_count),
                            'result', 'failed'
                        );
                END;
            END LOOP;
            
        WHEN 'DEPENDENCY_VIOLATION' THEN
            -- Try to resolve dependencies
            v_success := pggit.resolve_dependency_violation(
                p_operation_context,
                v_recovery_actions
            );
            
        WHEN 'SCHEMA_CONFLICT' THEN
            -- Try to resolve schema conflicts
            v_success := pggit.resolve_schema_conflict(
                p_operation_context,
                v_recovery_actions
            );
            
        WHEN 'MERGE_CONFLICT' THEN
            -- Provide conflict resolution options
            v_recovery_actions := pggit.generate_conflict_resolution_options(
                p_operation_context
            );
            v_success := false; -- Manual intervention required
            
        WHEN 'RESOURCE_EXHAUSTED' THEN
            -- Clean up and retry
            PERFORM pggit.cleanup_resources();
            v_recovery_actions := v_recovery_actions || 
                jsonb_build_object('action', 'cleanup_resources', 'result', 'completed');
            
            -- Retry once after cleanup
            BEGIN
                PERFORM pggit.retry_operation(p_operation_context);
                v_success := true;
            EXCEPTION WHEN OTHERS THEN
                v_success := false;
            END;
            
        WHEN 'VALIDATION_ERROR' THEN
            -- Try to fix validation issues
            v_success := pggit.fix_validation_error(
                p_error_code,
                p_operation_context,
                v_recovery_actions
            );
            
        ELSE
            -- Generic recovery: rollback and cleanup
            PERFORM pggit.emergency_rollback(p_operation_context);
            v_recovery_actions := v_recovery_actions || 
                jsonb_build_object('action', 'emergency_rollback', 'result', 'completed');
    END CASE;
    
    RETURN jsonb_build_object(
        'success', v_success,
        'retry_count', v_retry_count,
        'recovery_actions', v_recovery_actions,
        'manual_intervention_required', NOT v_success
    );
END;
$$ LANGUAGE plpgsql;

-- Retry operation from context
CREATE OR REPLACE FUNCTION pggit.retry_operation(
    p_operation_context JSONB
) RETURNS void AS $$
DECLARE
    v_operation_type TEXT;
BEGIN
    v_operation_type := p_operation_context->>'operation_type';
    
    CASE v_operation_type
        WHEN 'create_branch' THEN
            PERFORM pggit.create_branch_safe(
                p_operation_context->>'branch_name',
                p_operation_context->>'from_branch'
            );
        WHEN 'checkout' THEN
            PERFORM pggit.checkout_safe(
                p_operation_context->>'branch_name',
                COALESCE((p_operation_context->>'create_new')::boolean, false)
            );
        WHEN 'commit' THEN
            PERFORM pggit.commit_safe(
                p_operation_context->>'message'
            );
        WHEN 'merge' THEN
            PERFORM pggit.merge_safe(
                p_operation_context->>'source_branch',
                p_operation_context->>'merge_message'
            );
        ELSE
            RAISE EXCEPTION 'Cannot retry unknown operation: %', v_operation_type;
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Specific Recovery Functions
-- ============================================

-- Resolve dependency violations
CREATE OR REPLACE FUNCTION pggit.resolve_dependency_violation(
    p_operation_context JSONB,
    INOUT p_recovery_actions JSONB
) RETURNS BOOLEAN AS $$
DECLARE
    v_table_name TEXT;
    v_constraint_name TEXT;
    v_success BOOLEAN := false;
BEGIN
    -- Extract details from context
    v_table_name := p_operation_context->>'table_name';
    v_constraint_name := p_operation_context->>'constraint_name';
    
    -- Try to temporarily disable foreign key checks
    BEGIN
        EXECUTE format('ALTER TABLE %I DISABLE TRIGGER ALL', v_table_name);
        
        -- Retry the operation
        PERFORM pggit.retry_operation(p_operation_context);
        
        -- Re-enable triggers
        EXECUTE format('ALTER TABLE %I ENABLE TRIGGER ALL', v_table_name);
        
        p_recovery_actions := p_recovery_actions || 
            jsonb_build_object(
                'action', 'temporarily_disable_constraints',
                'table', v_table_name,
                'result', 'success'
            );
        
        v_success := true;
        
    EXCEPTION WHEN OTHERS THEN
        -- Re-enable triggers on error
        BEGIN
            EXECUTE format('ALTER TABLE %I ENABLE TRIGGER ALL', v_table_name);
        EXCEPTION WHEN OTHERS THEN
            NULL; -- Ignore cleanup errors
        END;
        
        p_recovery_actions := p_recovery_actions || 
            jsonb_build_object(
                'action', 'temporarily_disable_constraints',
                'table', v_table_name,
                'result', 'failed',
                'error', SQLERRM
            );
    END;
    
    RETURN v_success;
END;
$$ LANGUAGE plpgsql;

-- Resolve schema conflicts
CREATE OR REPLACE FUNCTION pggit.resolve_schema_conflict(
    p_operation_context JSONB,
    INOUT p_recovery_actions JSONB
) RETURNS BOOLEAN AS $$
DECLARE
    v_missing_object TEXT;
    v_object_type TEXT;
    v_success BOOLEAN := false;
BEGIN
    v_missing_object := p_operation_context->>'missing_object';
    v_object_type := p_operation_context->>'object_type';
    
    -- Try to create missing object as empty placeholder
    BEGIN
        CASE v_object_type
            WHEN 'table' THEN
                EXECUTE format('CREATE TABLE IF NOT EXISTS %I (temp_column INTEGER)', v_missing_object);
            WHEN 'schema' THEN
                EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_missing_object);
            ELSE
                -- Cannot auto-resolve unknown object types
                RETURN false;
        END CASE;
        
        p_recovery_actions := p_recovery_actions || 
            jsonb_build_object(
                'action', 'create_placeholder_object',
                'object_type', v_object_type,
                'object_name', v_missing_object,
                'result', 'success'
            );
        
        v_success := true;
        
    EXCEPTION WHEN OTHERS THEN
        p_recovery_actions := p_recovery_actions || 
            jsonb_build_object(
                'action', 'create_placeholder_object',
                'object_type', v_object_type,
                'object_name', v_missing_object,
                'result', 'failed',
                'error', SQLERRM
            );
    END;
    
    RETURN v_success;
END;
$$ LANGUAGE plpgsql;

-- Generate conflict resolution options
CREATE OR REPLACE FUNCTION pggit.generate_conflict_resolution_options(
    p_operation_context JSONB
) RETURNS JSONB AS $$
DECLARE
    v_source_branch TEXT;
    v_target_branch TEXT;
    v_options JSONB := '[]'::jsonb;
BEGIN
    v_source_branch := p_operation_context->>'source_branch';
    v_target_branch := p_operation_context->>'target_branch';
    
    -- Generate resolution options
    v_options := v_options || 
        jsonb_build_object(
            'option', 'manual_resolution',
            'description', 'Manually resolve conflicts using conflict resolution tools',
            'command', format('SELECT * FROM pggit.show_merge_conflicts(''%s'', ''%s'')', 
                v_source_branch, v_target_branch)
        );
    
    v_options := v_options || 
        jsonb_build_object(
            'option', 'abort_merge',
            'description', 'Abort the merge and return to previous state',
            'command', format('SELECT pggit.abort_merge(''%s'')', v_target_branch)
        );
    
    v_options := v_options || 
        jsonb_build_object(
            'option', 'force_theirs',
            'description', 'Accept all changes from source branch',
            'command', format('SELECT pggit.merge_force(''%s'', ''theirs'')', v_source_branch)
        );
    
    v_options := v_options || 
        jsonb_build_object(
            'option', 'force_ours',
            'description', 'Keep all changes from target branch',
            'command', format('SELECT pggit.merge_force(''%s'', ''ours'')', v_source_branch)
        );
    
    RETURN jsonb_build_object(
        'conflict_type', 'merge_conflict',
        'source_branch', v_source_branch,
        'target_branch', v_target_branch,
        'resolution_options', v_options
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Emergency Recovery Functions
-- ============================================

-- Emergency rollback
CREATE OR REPLACE FUNCTION pggit.emergency_rollback(
    p_operation_context JSONB
) RETURNS void AS $$
DECLARE
    v_current_branch TEXT;
    v_last_good_commit UUID;
BEGIN
    -- Get current branch
    v_current_branch := current_setting('pggit.current_branch', true);
    
    IF v_current_branch IS NULL THEN
        RETURN; -- Cannot rollback without branch context
    END IF;
    
    -- Find last good commit (simplified - would be more sophisticated in production)
    SELECT c.parent_id INTO v_last_good_commit
    FROM pggit.commits c
    JOIN pggit.refs r ON r.target_commit_id = c.id
    WHERE r.ref_name = v_current_branch
    AND c.parent_id IS NOT NULL;
    
    IF v_last_good_commit IS NOT NULL THEN
        -- Attempt emergency reset
        BEGIN
            PERFORM pggit.reset_hard(v_last_good_commit);
        EXCEPTION WHEN OTHERS THEN
            -- If reset fails, at least clean up locks
            PERFORM pggit.cleanup_session_locks();
        END;
    END IF;
    
    -- Clean up any remaining locks
    PERFORM pggit.cleanup_session_locks();
END;
$$ LANGUAGE plpgsql;

-- Resource cleanup
CREATE OR REPLACE FUNCTION pggit.cleanup_resources()
RETURNS void AS $$
BEGIN
    -- Clean up temp tables
    PERFORM pggit.cleanup_temp_objects();
    
    -- Clean up stale locks
    PERFORM pggit.cleanup_stale_operations();
    
    -- Run garbage collection
    PERFORM pggit.cleanup_unreferenced_blobs(1); -- Clean blobs older than 1 day
    
    -- Vacuum critical tables
    VACUUM ANALYZE pggit.commits;
    VACUUM ANALYZE pggit.blobs;
    VACUUM ANALYZE pggit.operation_locks;
END;
$$ LANGUAGE plpgsql;

-- Clean up temporary objects
CREATE OR REPLACE FUNCTION pggit.cleanup_temp_objects()
RETURNS INTEGER AS $$
DECLARE
    v_temp_object RECORD;
    v_cleaned INTEGER := 0;
BEGIN
    FOR v_temp_object IN 
        SELECT schemaname, tablename
        FROM pg_tables 
        WHERE tablename LIKE 'pggit_temp_%'
        OR tablename LIKE 'pggit_temp_%'
    LOOP
        BEGIN
            EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', 
                v_temp_object.schemaname, v_temp_object.tablename);
            v_cleaned := v_cleaned + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Ignore cleanup failures
            NULL;
        END;
    END LOOP;
    
    RETURN v_cleaned;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Health Checks and Monitoring
-- ============================================

-- System health check
CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details JSONB,
    severity pggit.error_severity
) AS $$
BEGIN
    -- Check for critical errors in last hour
    RETURN QUERY
    SELECT 
        'critical_errors_last_hour'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'FAILING' ELSE 'PASSING' END,
        jsonb_build_object('count', COUNT(*)),
        'CRITICAL'::pggit.error_severity
    FROM pggit.error_log
    WHERE error_severity = 'CRITICAL'
    AND occurred_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';
    
    -- Check for stale locks
    RETURN QUERY
    SELECT 
        'stale_locks'::TEXT,
        CASE WHEN COUNT(*) > 5 THEN 'WARNING' WHEN COUNT(*) > 10 THEN 'FAILING' ELSE 'PASSING' END,
        jsonb_build_object('count', COUNT(*)),
        CASE WHEN COUNT(*) > 10 THEN 'ERROR'::pggit.error_severity ELSE 'WARNING'::pggit.error_severity END
    FROM pggit.operation_locks
    WHERE acquired_at < CURRENT_TIMESTAMP - INTERVAL '1 hour';
    
    -- Check storage usage
    RETURN QUERY
    SELECT 
        'storage_usage'::TEXT,
        CASE WHEN total_size_mb > 1000 THEN 'WARNING' WHEN total_size_mb > 5000 THEN 'FAILING' ELSE 'PASSING' END,
        jsonb_build_object('total_size_mb', total_size_mb, 'total_blobs', total_blobs),
        CASE WHEN total_size_mb > 5000 THEN 'ERROR'::pggit.error_severity ELSE 'WARNING'::pggit.error_severity END
    FROM pggit.storage_statistics;
    
    -- Check for unresolved merge conflicts
    RETURN QUERY
    SELECT 
        'unresolved_conflicts'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'WARNING' ELSE 'PASSING' END,
        jsonb_build_object('count', COUNT(*)),
        'WARNING'::pggit.error_severity
    FROM pggit.error_log
    WHERE error_category = 'MERGE_CONFLICT'
    AND resolved_at IS NULL
    AND occurred_at > CURRENT_TIMESTAMP - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

-- Notify critical errors
CREATE OR REPLACE FUNCTION pggit.notify_critical_error(
    p_operation_id UUID,
    p_error_message TEXT
) RETURNS void AS $$
BEGIN
    -- Send PostgreSQL notification
    PERFORM pg_notify(
        'pggit_critical_error',
        jsonb_build_object(
            'operation_id', p_operation_id,
            'message', p_error_message,
            'timestamp', CURRENT_TIMESTAMP
        )::text
    );
    
    -- Could also integrate with external monitoring systems here
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.log_error IS 'Log errors with comprehensive context and classification';
COMMENT ON FUNCTION pggit.handle_error_with_recovery IS 'Handle errors with automated recovery strategies';
COMMENT ON FUNCTION pggit.health_check IS 'Perform comprehensive system health check';
COMMENT ON FUNCTION pggit.emergency_rollback IS 'Emergency rollback to last known good state';