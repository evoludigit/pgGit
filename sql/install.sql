-- pggit Database Versioning Extension - Single Installation Script
--
-- This script installs the complete PostgreSQL-native database versioning system.
-- It combines all individual scripts into one file for easy installation.
--
-- Usage: psql -d your_database -f install.sql

\echo 'Installing pggit Database Versioning Extension...'

-- Include all component scripts in order
\i 000_schema.sql
\i 001_schema_version.sql
\i 002_event_triggers.sql
\i 003_missing_tables.sql
\i 004_migration_functions.sql
\i 005_utility_views.sql
\i 006_example_usage.sql
\i 007_ddl_hashing.sql
\i 008_performance_optimizations.sql
\i 009_git_core_implementation.sql
\i 010_ai_migration_analysis.sql
\i 011_size_management.sql
\i 012_zero_downtime_deployment.sql
\i 013_branch_merge_operations.sql
\i 014_create_commit.sql
\i 015_data_branching_cow.sql
\i 016_merge_operations.sql
\i 017_performance_monitoring.sql
\i 018_advanced_merge_operations.sql
\i 019_ai_accuracy_tracking.sql
\i 020_batch_operations_monitoring.sql
\i 021_cold_hot_storage.sql
\i 022_schema_diffing_foundation.sql
\i 023_storage_tier_stubs.sql
\i 024_advanced_workflows.sql
\i 025_versioning_stubs.sql
\i 026_advanced_reporting.sql
\i 027_analytics_insights.sql
\i 028_performance_optimization.sql
\i 029_chaos_engineering_core.sql
\i 030_time_travel.sql
\i 031_advanced_ml_optimization.sql
\i 032_advanced_conflict_resolution.sql
\i 033_backup_integration.sql
\i 034_backup_automation.sql
\i 035_backup_management.sql
\i 036_backup_recovery.sql
\i 037_error_codes.sql
\i 038_audit_log.sql
\i 039_migrate_schemas_to_v0.sql
\i 041_pggit_audit_extended.sql
\i 042_pggit_audit_functions.sql
\i 043_pggit_audit_schema.sql
\i 044_pggit_configuration.sql
\i 045_pggit_conflict_resolution_api.sql
\i 046_pggit_conflict_resolution_minimal.sql
\i 047_pggit_cqrs_support.sql
\i 048_pggit_diff_functionality.sql
\i 049_pggit_enhanced_triggers.sql
\i 050_pggit_function_versioning.sql
\i 051_pggit_migration_core.sql
\i 052_pggit_migration_execution.sql
\i 053_pggit_migration_integration.sql
\i 054_pggit_monitoring.sql
\i 055_pggit_observability.sql
\i 056_pggit_operations.sql
\i 057_pggit_performance.sql
\i 058_pggit_v2_analytics.sql
\i 059_pggit_v2_branching.sql
\i 060_pggit_v2_developers.sql
\i 061_pggit_v2_monitoring.sql
\i 062_pggit_v2_views.sql
\i 063_test_helpers.sql

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
