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
\i pggit_cqrs_support.sql
\i 051_data_branching_cow.sql
\i pggit_conflict_resolution_minimal.sql
\i pggit_diff_functionality.sql

\echo ''
\echo 'Installation complete!'
\echo ''
\echo 'Quick start:'
\echo '  - Database size overview: SELECT * FROM pggit.database_size_overview;'
\echo '  - Generate pruning recommendations: SELECT * FROM pggit.generate_pruning_recommendations();'
\echo '  - List branches by size: SELECT * FROM pggit.top_space_consumers;'
\echo '  - Analyze migration with AI: SELECT * FROM pggit.analyze_migration_with_ai_enhanced(''id'', ''SQL'');'
\echo ''
\echo 'For full documentation, see docs/README.md'