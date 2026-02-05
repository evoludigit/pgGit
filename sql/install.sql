-- pggit Database Versioning Extension - Single Installation Script
--
-- This script installs the complete PostgreSQL-native database versioning system.
-- It combines all individual scripts into one file for easy installation.
--
-- Usage: psql -d your_database -f install.sql

\echo 'Installing pggit Database Versioning Extension...'

-- Include all component scripts
\i 001_schema.sql
\i 002_schema_version.sql
\i 003_event_triggers.sql
\i 004_missing_tables.sql
\i 005_migration_functions.sql
\i 006_utility_views.sql
\i 007_example_usage.sql
\i 008_ddl_hashing.sql
\i 009_performance_optimizations.sql
\i 010_git_core_implementation.sql
\i 011_ai_migration_analysis.sql
\i 012_size_management.sql
\i 013_zero_downtime_deployment.sql
\i 014_branch_merge_operations.sql
\i 015_create_commit.sql
\i 016_data_branching_cow.sql
\i 017_merge_operations.sql
\i 018_performance_monitoring.sql
\i 019_advanced_merge_operations.sql
\i 020_ai_accuracy_tracking.sql
\i 021_batch_operations_monitoring.sql
\i 022_cold_hot_storage.sql
\i 023_schema_diffing_foundation.sql
\i 024_storage_tier_stubs.sql
\i 025_advanced_workflows.sql
\i 026_versioning_stubs.sql
\i 027_advanced_reporting.sql
\i 028_analytics_insights.sql
\i 029_performance_optimization.sql
\i 030_chaos_engineering_core.sql
\i 031_time_travel.sql
\i 032_advanced_ml_optimization.sql
\i 033_advanced_conflict_resolution.sql
\i 034_backup_integration.sql
\i 035_backup_automation.sql
\i 036_backup_management.sql
\i 037_backup_recovery.sql
\i 038_error_codes.sql
\i 039_audit_log.sql
\i 999_migrate_schemas_to_v0.sql

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
