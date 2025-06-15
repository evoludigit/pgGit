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
\i 004_utility_views.sql

\echo ''
\echo 'Installation complete!'
\echo ''
\echo 'Quick start:'
\echo '  - Check version: SELECT * FROM pggit.get_version(''public.your_table'');'
\echo '  - View history: SELECT * FROM pggit.get_history(''public.your_table'');'
\echo '  - Show all versions: SELECT * FROM pggit.show_table_versions();'
\echo '  - Generate migration: SELECT pggit.generate_migration();'
\echo ''
\echo 'For full documentation, see sql/README.md'