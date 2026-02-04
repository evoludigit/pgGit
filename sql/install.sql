-- pggit Database Versioning Extension - Single Installation Script
-- 
-- This script installs the complete PostgreSQL-native database versioning system.
-- It combines all individual scripts into one file for easy installation.
--
-- Usage: psql -d your_database -f install.sql

\echo 'Installing pggit Database Versioning Extension...'

-- Include all component scripts
\i 001_schema.sql
\i 002_event_triggers.sql
\i 003_migration_functions.sql
\i test_helpers.sql
\i 004_utility_views.sql
\i 009_ddl_hashing.sql
\i 017_performance_optimizations.sql
\i 020_git_core_implementation.sql
\i 030_ai_migration_analysis.sql
\i 040_size_management.sql
\i 050_create_commit.sql
\i 050_branch_merge_operations.sql
\i 055_storage_tier_stubs.sql
\i 056_versioning_stubs.sql
\i pggit_cqrs_support.sql
\i 051_data_branching_cow.sql
\i 052_merge_operations.sql
\i 053_advanced_merge_operations.sql
\i pggit_conflict_resolution_minimal.sql
\i pggit_diff_functionality.sql
\i 060_time_travel.sql
\i 070_backup_integration.sql
\i 071_backup_automation.sql
\i 072_backup_management.sql
\i 073_backup_recovery.sql
\i 074_error_codes.sql
\i 075_audit_log.sql
\i 061_advanced_ml_optimization.sql
\i 062_advanced_conflict_resolution.sql

\echo ''
\echo 'Installation complete!'
\echo ''
\echo 'Quick start:'
\echo '  - Database size overview: SELECT * FROM pggit.database_size_overview;'
\echo '  - Generate pruning recommendations: SELECT * FROM pggit.generate_pruning_recommendations();'
\echo '  - List branches by size: SELECT * FROM pggit.top_space_consumers;'
\echo '  - Analyze migration with AI: SELECT * FROM pggit.analyze_migration_with_ai_enhanced(''id'', ''SQL'');'
\echo '  - View backup audit logs: SELECT * FROM pggit.operation_audit ORDER BY started_at DESC LIMIT 10;'
\echo '  - Check backup system health: SELECT * FROM pggit.cleanup_expired_backups(TRUE);'
\echo ''
\echo 'Phase 3 Features (Reliability & Error Handling):'
\echo '  - Enterprise-grade concurrency protection with advisory locks'
\echo '  - Idempotent operations safe to retry'
\echo '  - Comprehensive audit logging for compliance'
\echo '  - Structured error codes with actionable hints'
\echo '  - Transaction safety for destructive operations'
\echo ''
\echo 'For full documentation, see docs/README.md'