# pgGit SQL File Organization Plan
## 4-Digit Hexadecimal Semantic Numbering System

---

## Design Principles

1. **Semantic Categories**: First hex digit = major category (16 categories)
2. **Subcategories**: Second hex digit = subcategory (16 per category)
3. **Sequence**: Last two digits = sequence within subcategory (00-FF = 256 files)
4. **Future-proof**: 16 × 16 × 256 = 65,536 possible files
5. **Self-documenting**: Numbers reveal category at a glance
6. **Easy reorganization**: Insert files without renumbering (use gaps)

---

## Category Structure (First Hex Digit)

```
0x0xxx - Core Schema & Infrastructure
0x1xxx - DDL Tracking & Event Triggers  
0x2xxx - Branching & Version Control
0x3xxx - Merging & Conflict Resolution
0x4xxx - Data Management & Storage
0x5xxx - Security, Auth & Multi-tenancy
0x6xxx - Monitoring, Metrics & Observability
0x7xxx - Performance Optimization & Indexing
0x8xxx - Utilities, Helpers & Common Functions
0x9xxx - Testing, QA & Validation
0xAxxx - Migration & Upgrade Scripts
0xBxxx - Enterprise Features
0xCxxx - Integration & APIs
0xDxxx - Reserved for Future Expansion
0xExxx - Reserved for Future Expansion
0xFxxx - Reserved for Future Expansion
```

---

## Detailed Subcategory Breakdown

### 0x0xxx - Core Schema & Infrastructure

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x0000-0x000F | Schema Creation | CREATE SCHEMA, extensions, enums | 000_schema.sql |
| 0x0010-0x001F | Core Tables | Main tables (objects, branches, history) | 000_schema.sql |
| 0x0020-0x002F | Types & Enums | Custom types, enums, domains | 000_schema.sql |
| 0x0030-0x003F | Configuration | Config tables, settings | 043_pggit_configuration.sql |
| 0x0040-0x004F | Version Management | Schema versioning | 001_schema_version.sql |
| 0x0050-0x005F | Audit Foundation | Core audit logging | 038_audit_log.sql, 040-042 |
| 0x0060-0x006F | Utility Functions | Common helpers | 005_utility_views.sql |
| 0x0070-0x007F | Validation | Input validation, sanitization | (spread across files) |
| 0x0080-0x008F | Error Handling | Error codes, exceptions | 037_error_codes.sql |
| 0x0090-0x009F | Examples & Docs | Example usage, documentation | 006_example_usage.sql |
| 0x00A0-0x00AF | Reserved | | |
| 0x00B0-0x00BF | Reserved | | |
| 0x00C0-0x00CF | Reserved | | |
| 0x00D0-0x00DF | Reserved | | |
| 0x00E0-0x00EF | Reserved | | |
| 0x00F0-0x00FF | Reserved | | |

### 0x1xxx - DDL Tracking & Event Triggers

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x1000-0x100F | Event Trigger Setup | ddl_command_end, sql_drop triggers | 002_event_triggers.sql |
| 0x1010-0x101F | DDL Capture Functions | handle_ddl_command, extractors | 002_event_triggers.sql |
| 0x1020-0x102F | DDL Hashing | Content hashing, normalization | 007_ddl_hashing.sql |
| 0x1030-0x103F | DDL Normalization | DDL text normalization | 007_ddl_hashing.sql |
| 0x1040-0x104F | Object Extraction | Extract table columns, metadata | (in 002_event_triggers) |
| 0x1050-0x105F | Dependency Tracking | Track object dependencies | (in 000_schema) |
| 0x1060-0x106F | Enhanced Triggers | Advanced trigger logic | 048_pggit_enhanced_triggers.sql |
| 0x1070-0x107F | Trigger Performance | Trigger optimization | 008_performance_optimizations.sql |
| 0x1080-0x108F | DDL Filtering | Filter temp tables, system objects | (in 002_event_triggers) |
| 0x1090-0x109F | DDL Metadata | Metadata extraction and storage | (spread) |
| 0x10A0-0x10AF | Reserved | | |
| 0x10B0-0x10BF | Reserved | | |
| 0x10C0-0x10CF | Reserved | | |
| 0x10D0-0x10DF | Reserved | | |
| 0x10E0-0x10EF | Reserved | | |
| 0x10F0-0x10FF | Reserved | | |

### 0x2xxx - Branching & Version Control

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x2000-0x200F | Branch Core | create_branch, switch_branch | 009_git_core_implementation.sql |
| 0x2010-0x201F | Branch Operations | delete_branch, rename_branch | 009_git_core_implementation.sql |
| 0x2020-0x202F | Branch Metadata | Branch info, stats | 009_git_core_implementation.sql |
| 0x2030-0x203F | Branch Protection | Protected branches, policies | 009_git_core_implementation.sql |
| 0x2040-0x204F | Branch Listing | list_branches, filtering | 009_git_core_implementation.sql |
| 0x2050-0x205F | Branch Ancestry | Parent tracking, lineage | 009_git_core_implementation.sql |
| 0x2060-0x206F | Data Branching | Copy-on-write data branches | 015_data_branching_cow.sql, 058_pggit_v2_branching.sql |
| 0x2070-0x207F | Branch Storage | Storage stats, efficiency | 021_cold_hot_storage.sql |
| 0x2080-0x208F | Branch Utilities | Helper functions | (spread) |
| 0x2090-0x209F | Reserved | | |
| 0x20A0-0x20AF | Reserved | | |
| 0x20B0-0x20BF | Reserved | | |
| 0x20C0-0x20CF | Reserved | | |
| 0x20D0-0x20DF | Reserved | | |
| 0x20E0-0x20EF | Reserved | | |
| 0x20F0-0x20FF | Reserved | | |

### 0x3xxx - Merging & Conflict Resolution

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x3000-0x300F | Merge Core | merge function | 016_merge_operations.sql |
| 0x3010-0x301F | Conflict Detection | detect_conflicts | 016_merge_operations.sql, 013_branch_merge_operations.sql |
| 0x3020-0x302F | Conflict Resolution | resolve_conflict | 016_merge_operations.sql, 044-045 |
| 0x3030-0x303F | Merge History | merge_history table | 016_merge_operations.sql |
| 0x3040-0x304F | Merge Strategies | auto, manual, ours, theirs | 016_merge_operations.sql, 018_advanced_merge_operations.sql |
| 0x3050-0x305F | Merge Status | get_merge_status, abort | 016_merge_operations.sql |
| 0x3060-0x306F | Advanced Merge | Complex merge scenarios | 018_advanced_merge_operations.sql, 032_advanced_conflict_resolution.sql |
| 0x3070-0x307F | Data Conflicts | Row-level conflict detection | 015_data_branching_cow.sql |
| 0x3080-0x308F | Resolution API | Public API for conflict resolution | 044_pggit_conflict_resolution_api.sql |
| 0x3090-0x309F | Reserved | | |
| 0x30A0-0x30AF | Reserved | | |
| 0x30B0-0x30BF | Reserved | | |
| 0x30C0-0x30CF | Reserved | | |
| 0x30D0-0x30DF | Reserved | | |
| 0x30E0-0x30EF | Reserved | | |
| 0x30F0-0x30FF | Reserved | | |

### 0x4xxx - Data Management & Storage

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x4000-0x400F | Objects Table | Core objects table operations | 000_schema.sql |
| 0x4010-0x401F | History Table | DDL history tracking | 000_schema.sql |
| 0x4020-0x402F | Commits Table | Commit tracking | 014_create_commit.sql |
| 0x4030-0x403F | Dependencies | Object dependency tracking | (in 000_schema) |
| 0x4040-0x404F | Storage Management | Size management | 021_cold_hot_storage.sql, 011_size_management.sql |
| 0x4050-0x405F | Data Branches | CoW table management | 015_data_branching_cow.sql |
| 0x4060-0x406F | Archive & Retention | Data lifecycle | 024_history_management.sql |
| 0x4070-0x407F | Backup Integration | Backup procedures | 033-036 backup files |
| 0x4080-0x408F | Storage Tiers | Hot/cold storage | 021_cold_hot_storage.sql, 023_storage_tier_stubs.sql |
| 0x4090-0x409F | Data Recovery | Recovery procedures | 036_backup_recovery.sql |
| 0x40A0-0x40AF | Reserved | | |
| 0x40B0-0x40BF | Reserved | | |
| 0x40C0-0x40CF | Reserved | | |
| 0x40D0-0x40DF | Reserved | | |
| 0x40E0-0x40EF | Reserved | | |
| 0x40F0-0x40FF | Reserved | | |

### 0x5xxx - Security, Auth & Multi-tenancy

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x5000-0x500F | Authentication | User auth, sessions | (minimal) |
| 0x5010-0x501F | Authorization | Permissions, roles | 027_row_level_security.sql |
| 0x5020-0x502F | Row-Level Security | RLS policies | 027_row_level_security.sql |
| 0x5030-0x503F | Multi-tenancy | Tenant isolation | 027_row_level_security.sql |
| 0x5040-0x504F | Encryption | Data encryption | (minimal) |
| 0x5050-0x505F | Audit Security | Audit access control | 040-042 audit files |
| 0x5060-0x506F | Compliance | GDPR, HIPAA helpers | (minimal) |
| 0x5070-0x507F | Access Control | Fine-grained permissions | 027_row_level_security.sql |
| 0x5080-0x508F | Security Utilities | Security helpers | (spread) |
| 0x5090-0x509F | Reserved | | |
| 0x50A0-0x50AF | Reserved | | |
| 0x50B0-0x50BF | Reserved | | |
| 0x50C0-0x50CF | Reserved | | |
| 0x50D0-0x50DF | Reserved | | |
| 0x50E0-0x50EF | Reserved | | |
| 0x50F0-0x50FF | Reserved | | |

### 0x6xxx - Monitoring, Metrics & Observability

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x6000-0x600F | Metrics Core | metrics table | 025_monitoring.sql |
| 0x6010-0x601F | Metrics Collection | record_metric functions | 025_monitoring.sql, 053_pggit_monitoring.sql |
| 0x6020-0x602F | Prometheus Export | prometheus_metrics() | 025_monitoring.sql, 054_pggit_observability.sql |
| 0x6030-0x603F | Health Checks | health_check() | 025_monitoring.sql, 060_pggit_v2_monitoring.sql |
| 0x6040-0x604F | Alerting | Alert conditions | 025_monitoring.sql |
| 0x6050-0x605F | Performance Monitoring | Query performance | 017_performance_monitoring.sql, 028_performance_optimization.sql |
| 0x6060-0x606F | Trigger Monitoring | DDL trigger stats | 008_performance_optimizations.sql |
| 0x6070-0x607F | Storage Monitoring | Size, growth tracking | 021_cold_hot_storage.sql |
| 0x6080-0x608F | Analytics | Advanced analytics | 057_pggit_v2_analytics.sql |
| 0x6090-0x609F | Reserved | | |
| 0x60A0-0x60AF | Reserved | | |
| 0x60B0-0x60BF | Reserved | | |
| 0x60C0-0x60CF | Reserved | | |
| 0x60D0-0x60DF | Reserved | | |
| 0x60E0-0x60EF | Reserved | | |
| 0x60F0-0x60FF | Reserved | | |

### 0x7xxx - Performance Optimization & Indexing

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x7000-0x700F | Index Management | Create/drop indexes | 028_advanced_indexes.sql |
| 0x7010-0x701F | BRIN Indexes | Block range indexes | 028_advanced_indexes.sql |
| 0x7020-0x702F | Covering Indexes | Include columns | 028_advanced_indexes.sql |
| 0x7030-0x703F | Partial Indexes | Filtered indexes | 028_advanced_indexes.sql |
| 0x7040-0x704F | Expression Indexes | Computed indexes | 028_advanced_indexes.sql |
| 0x7050-0x705F | Index Analysis | Usage stats | 028_advanced_indexes.sql |
| 0x7060-0x706F | Query Optimization | Query tuning | 008_performance_optimizations.sql |
| 0x7070-0x707F | Caching | Internal cache | 026_internal_schema.sql |
| 0x7080-0x708F | Partitioning | Table partitioning | (minimal) |
| 0x7090-0x709F | Reserved | | |
| 0x70A0-0x70AF | Reserved | | |
| 0x70B0-0x70BF | Reserved | | |
| 0x70C0-0x70CF | Reserved | | |
| 0x70D0-0x70DF | Reserved | | |
| 0x70E0-0x70EF | Reserved | | |
| 0x70F0-0x70FF | Reserved | | |

### 0x8xxx - Utilities, Helpers & Common Functions

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x8000-0x800F | String Utilities | Format, sanitize | (spread) |
| 0x8010-0x801F | Hashing Functions | SHA-256, MD5 | (in 007_ddl_hashing) |
| 0x8020-0x802F | Validation | Input validation | (spread) |
| 0x8030-0x803F | Date/Time | Timestamp handling | (spread) |
| 0x8040-0x804F | JSON Utilities | JSONB helpers | (spread) |
| 0x8050-0x805F | Naming | Object naming | (spread) |
| 0x8060-0x806F | Internal Helpers | Private functions | 026_internal_schema.sql |
| 0x8070-0x807F | Configuration | Config management | 043_pggit_configuration.sql |
| 0x8080-0x808F | Reserved | | |
| 0x8090-0x809F | Reserved | | |
| 0x80A0-0x80AF | Reserved | | |
| 0x80B0-0x80BF | Reserved | | |
| 0x80C0-0x80CF | Reserved | | |
| 0x80D0-0x80DF | Reserved | | |
| 0x80E0-0x80EF | Reserved | | |
| 0x80F0-0x80FF | Reserved | | |

### 0x9xxx - Testing, QA & Validation

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0x9000-0x900F | Test Infrastructure | Test tables | 062_test_helpers.sql |
| 0x9010-0x901F | Unit Tests | Test functions | 062_test_helpers.sql |
| 0x9020-0x902F | Property Tests | Hypothesis-style | 029_chaos_engineering_core.sql |
| 0x9030-0x903F | Chaos Tests | Fault injection | 029_chaos_engineering_core.sql |
| 0x9040-0x904F | Benchmark Tests | Performance tests | (new test files) |
| 0x9050-0x905F | Validation | Schema validation | (spread) |
| 0x9060-0x906F | Coverage | Coverage tracking | (minimal) |
| 0x9070-0x907F | Reserved | | |
| 0x9080-0x908F | Reserved | | |
| 0x9090-0x909F | Reserved | | |
| 0x90A0-0x90AF | Reserved | | |
| 0x90B0-0x90BF | Reserved | | |
| 0x90C0-0x90CF | Reserved | | |
| 0x90D0-0x90DF | Reserved | | |
| 0x90E0-0x90EF | Reserved | | |
| 0x90F0-0x90FF | Reserved | | |

### 0xAxxx - Migration & Upgrade

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0xA000-0xA00F | Migration Core | Migration infrastructure | 050-052 migration files |
| 0xA010-0xA01F | Schema Migration | Upgrade scripts | 039_migrate_schemas_to_v0.sql |
| 0xA020-0xA02F | Data Migration | Data transformation | 003_missing_tables.sql, 004_migration_functions.sql |
| 0xA030-0xA03F | Version Management | Version tracking | 001_schema_version.sql |
| 0xA040-0xA04F | Migration Tools | Helper functions | 004_migration_functions.sql |
| 0xA050-0xA05F | Reserved | | |
| 0xA060-0xA06F | Reserved | | |
| 0xA070-0xA07F | Reserved | | |
| 0xA080-0xA08F | Reserved | | |
| 0xA090-0xA09F | Reserved | | |
| 0xA0A0-0xA0AF | Reserved | | |
| 0xA0B0-0xA0BF | Reserved | | |
| 0xA0C0-0xA0CF | Reserved | | |
| 0xA0D0-0xA0DF | Reserved | | |
| 0xA0E0-0xA0EF | Reserved | | |
| 0xA0F0-0xA0FF | Reserved | | |

### 0xBxxx - Enterprise Features

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0xB000-0xB00F | Workflow | Advanced workflows | 024_advanced_workflows.sql |
| 0xB010-0xB01F | Reporting | Analytics, reports | 026_advanced_reporting.sql |
| 0xB020-0xB02F | CQRS | Command query separation | 046_pggit_cqrs_support.sql |
| 0xB030-0xB03F | Operations | Operational tools | 055_pggit_operations.sql |
| 0xB040-0xB04F | Reserved | | |
| 0xB050-0xB05F | Reserved | | |
| 0xB060-0xB06F | Reserved | | |
| 0xB070-0xB07F | Reserved | | |
| 0xB080-0xB08F | Reserved | | |
| 0xB090-0xB09F | Reserved | | |
| 0xB0A0-0xB0AF | Reserved | | |
| 0xB0B0-0xB0BF | Reserved | | |
| 0xB0C0-0xB0CF | Reserved | | |
| 0xB0D0-0xB0DF | Reserved | | |
| 0xB0E0-0xB0EF | Reserved | | |
| 0xB0F0-0xB0FF | Reserved | | |

### 0xCxxx - Integration & APIs

| Range | Subcategory | Description | Current Files |
|-------|-------------|-------------|---------------|
| 0xC000-0xC00F | API Core | Public API functions | 044-045 conflict resolution API |
| 0xC010-0xC01F | Diff API | Schema diffing | 047_pggit_diff_functionality.sql |
| 0xC020-0xC02F | Function Versioning | Version management | 049_pggit_function_versioning.sql |
| 0xC030-0xC03F | AI Integration | AI migration tools | 010_ai_migration_analysis.sql |
| 0xC040-0xC04F | ML Optimization | Machine learning | 031_advanced_ml_optimization.sql |
| 0xC050-0xC05F | Time Travel | Temporal queries | 030_time_travel.sql |
| 0xC060-0xC06F | Analytics Insights | Advanced analytics | 027_analytics_insights.sql |
| 0xC070-0xC07F | Developer Tools | Dev helpers | 059_pggit_v2_developers.sql |
| 0xC080-0xC08F | Views | System views | 005_utility_views.sql, 061_pggit_v2_views.sql |
| 0xC090-0xC09F | Reserved | | |
| 0xC0A0-0xC0AF | Reserved | | |
| 0xC0B0-0xC0BF | Reserved | | |
| 0xC0C0-0xC0CF | Reserved | | |
| 0xC0D0-0xC0DF | Reserved | | |
| 0xC0E0-0xC0EF | Reserved | | |
| 0xC0F0-0xC0FF | Reserved | | |

---

## Current File Mapping

### Files to Renumber

| Current File | Proposed New Name | Category | Notes |
|--------------|-------------------|----------|-------|
| 000_schema.sql | 0x0000_core_schema.sql | Core | Main schema creation |
| 001_schema_version.sql | 0x0040_version_control.sql | Core | Version tracking |
| 002_event_triggers.sql | 0x1000_event_triggers.sql | DDL | Event trigger setup |
| 003_missing_tables.sql | 0xA020_migration_tables.sql | Migration | Migration helpers |
| 004_migration_functions.sql | 0xA040_migration_functions.sql | Migration | Migration tools |
| 005_utility_views.sql | 0x00C0_utility_views.sql | Core | Utility views |
| 006_example_usage.sql | 0x0090_example_usage.sql | Core | Documentation |
| 007_ddl_hashing.sql | 0x1020_ddl_hashing.sql | DDL | Hashing & normalization |
| 008_performance_optimizations.sql | 0x7060_query_optimization.sql | Performance | Query tuning |
| 009_git_core_implementation.sql | 0x2000_branching_core.sql | Branching | Core branch functions |
| 010_ai_migration_analysis.sql | 0xC030_ai_integration.sql | Integration | AI features |
| 011_size_management.sql | 0x4040_storage_management.sql | Data | Storage tracking |
| 012_zero_downtime_deployment.sql | 0x0120_deployment.sql | Core | Deployment helpers |
| 013_branch_merge_operations.sql | 0x3010_conflict_detection.sql | Merging | Conflict detection |
| 014_create_commit.sql | 0x4020_commit_tracking.sql | Data | Commit infrastructure |
| 015_data_branching_cow.sql | 0x2060_data_branching.sql | Branching | CoW implementation |
| 016_merge_operations.sql | 0x3000_merge_core.sql | Merging | Merge functions |
| 017_performance_monitoring.sql | 0x6050_performance_monitoring.sql | Monitoring | Performance metrics |
| 018_advanced_merge_operations.sql | 0x3060_advanced_merge.sql | Merging | Complex merges |
| 019_ai_accuracy_tracking.sql | 0xC040_ml_tracking.sql | Integration | ML tracking |
| 020_batch_operations_monitoring.sql | 0x6030_batch_monitoring.sql | Monitoring | Batch metrics |
| 021_cold_hot_storage.sql | 0x4080_storage_tiers.sql | Data | Storage tiering |
| 022_schema_diffing_foundation.sql | 0xC010_diff_api.sql | Integration | Diff API |
| 023_production_mode.sql | 0x0030_production_mode.sql | Core | Production settings |
| 023_storage_tier_stubs.sql | DELETE or MERGE | Data | Duplicate - merge into 021 |
| 024_advanced_workflows.sql | 0xB000_workflows.sql | Enterprise | Advanced workflows |
| 024_history_management.sql | 0x4060_retention.sql | Data | Retention policies |
| 025_monitoring.sql | 0x6000_metrics_core.sql | Monitoring | Core metrics |
| 025_versioning_stubs.sql | DELETE or MERGE | Core | Duplicate - merge into 001 |
| 026_advanced_reporting.sql | 0xB010_reporting.sql | Enterprise | Reporting |
| 026_internal_schema.sql | 0x8060_internal_helpers.sql | Utilities | Internal API |
| 027_analytics_insights.sql | 0xC060_analytics.sql | Integration | Analytics |
| 027_row_level_security.sql | 0x5020_rls_policies.sql | Security | RLS implementation |
| 028_advanced_indexes.sql | 0x7000_index_management.sql | Performance | Index management |
| 028_performance_optimization.sql | 0x7060_performance_tuning.sql | Performance | Optimization |
| 029_chaos_engineering_core.sql | 0x9020_chaos_tests.sql | Testing | Chaos testing |
| 030_time_travel.sql | 0xC050_time_travel.sql | Integration | Temporal queries |
| 031_advanced_ml_optimization.sql | 0xC041_ml_optimization.sql | Integration | ML optimization |
| 032_advanced_conflict_resolution.sql | 0x3061_conflict_resolution.sql | Merging | Conflict resolution |
| 033_backup_integration.sql | 0x4070_backup_procedures.sql | Data | Backup procedures |
| 034_backup_automation.sql | 0x4071_backup_automation.sql | Data | Backup automation |
| 035_backup_management.sql | 0x4072_backup_management.sql | Data | Backup management |
| 036_backup_recovery.sql | 0x4073_backup_recovery.sql | Data | Backup recovery |
| 037_error_codes.sql | 0x0080_error_handling.sql | Core | Error handling |
| 038_audit_log.sql | 0x0050_audit_foundation.sql | Core | Audit logging |
| 039_migrate_schemas_to_v0.sql | 0xA010_schema_migration.sql | Migration | Schema migration |
| 040_pggit_audit_schema.sql | 0x0051_audit_schema.sql | Core | Audit schema |
| 041_pggit_audit_extended.sql | 0x0052_audit_extended.sql | Core | Extended audit |
| 042_pggit_audit_functions.sql | 0x0053_audit_functions.sql | Core | Audit functions |
| 043_pggit_configuration.sql | 0x0030_configuration.sql | Core | Configuration |
| 044_pggit_conflict_resolution_api.sql | 0x3080_resolution_api.sql | Merging | Resolution API |
| 045_pggit_conflict_resolution_minimal.sql | DELETE or MERGE | Merging | Duplicate - merge into 044 |
| 046_pggit_cqrs_support.sql | 0xB020_cqrs_support.sql | Enterprise | CQRS |
| 047_pggit_diff_functionality.sql | 0xC011_diff_functions.sql | Integration | Diff functions |
| 048_pggit_enhanced_triggers.sql | 0x1060_enhanced_triggers.sql | DDL | Enhanced triggers |
| 049_pggit_function_versioning.sql | 0xC021_function_versioning.sql | Integration | Function versioning |
| 050_pggit_migration_core.sql | 0xA000_migration_core.sql | Migration | Migration core |
| 051_pggit_migration_execution.sql | 0xA001_migration_execution.sql | Migration | Migration execution |
| 052_pggit_migration_integration.sql | 0xA002_migration_integration.sql | Migration | Migration integration |
| 053_pggit_monitoring.sql | 0x6010_metrics_collection.sql | Monitoring | Metrics collection |
| 054_pggit_observability.sql | 0x6020_prometheus_export.sql | Monitoring | Prometheus |
| 055_pggit_operations.sql | 0xB030_operations.sql | Enterprise | Operations |
| 056_pggit_performance.sql | 0x7070_performance_tools.sql | Performance | Performance tools |
| 057_pggit_v2_analytics.sql | 0x6080_analytics.sql | Monitoring | Analytics |
| 058_pggit_v2_branching.sql | 0x2070_v2_branching.sql | Branching | V2 branching |
| 059_pggit_v2_developers.sql | 0xC070_developer_tools.sql | Integration | Developer tools |
| 060_pggit_v2_monitoring.sql | 0x6030_v2_monitoring.sql | Monitoring | V2 monitoring |
| 061_pggit_v2_views.sql | 0xC080_v2_views.sql | Integration | V2 views |
| 062_test_helpers.sql | 0x9000_test_infrastructure.sql | Testing | Test infrastructure |
| install.sql | KEEP AS-IS | - | Installation entry point |

---

## Implementation Strategy

### Phase 1: Consolidate Duplicates (Week 1)
1. Merge 023_storage_tier_stubs.sql into 021_cold_hot_storage.sql
2. Merge 025_versioning_stubs.sql into 001_schema_version.sql
3. Merge 045_pggit_conflict_resolution_minimal.sql into 044_pggit_conflict_resolution_api.sql
4. Delete duplicate files
5. Test that everything still works

### Phase 2: Rename Files (Week 2)
1. Create new files with hex names
2. Copy content from old files to new files
3. Update all references
4. Test build process
5. Delete old files

### Phase 3: Reorganize Content (Week 3)
1. Move functions to appropriate hex categories
2. Update internal function calls
3. Ensure proper ordering
4. Test complete installation
5. Run full test suite

### Phase 4: Update Build Process (Week 4)
1. Update file concatenation script
2. Update Makefile
3. Update CI/CD
4. Update documentation
5. Final testing

---

## Benefits of This System

1. **Self-Documenting**: File name reveals purpose
2. **Logical Grouping**: Easy to find related files
3. **Future Expansion**: 65,536 possible slots
4. **Insert Flexibility**: Can add files between existing ones
5. **Build Optimization**: Build scripts can target specific categories
6. **Testing Granularity**: Can test categories independently
7. **Documentation**: Easy to explain architecture

---

## File Naming Convention

```
0x<category><subcategory><sequence>_<descriptive_name>.sql

Examples:
0x0000_core_schema.sql          - Core schema (category 0, subcat 0, seq 0)
0x1000_event_triggers.sql       - Event triggers (category 1, subcat 0, seq 0)
0x2000_branching_core.sql       - Branching core (category 2, subcat 0, seq 0)
0x3000_merge_core.sql           - Merge core (category 3, subcat 0, seq 0)
0x4000_objects_table.sql       - Objects table (category 4, subcat 0, seq 0)
0x5020_rls_policies.sql         - RLS policies (category 5, subcat 2, seq 0)
0x6000_metrics_core.sql         - Metrics core (category 6, subcat 0, seq 0)
0x7000_index_management.sql     - Index management (category 7, subcat 0, seq 0)
0x8060_internal_helpers.sql     - Internal helpers (category 8, subcat 6, seq 0)
0x9000_test_infrastructure.sql  - Test infrastructure (category 9, subcat 0, seq 0)
```

---

## Directory Structure

```
sql/
├── core/                    # 0x0xxx files
│   ├── 0x0000_core_schema.sql
│   └── ...
├── ddl/                     # 0x1xxx files
│   ├── 0x1000_event_triggers.sql
│   └── ...
├── branching/               # 0x2xxx files
│   ├── 0x2000_branching_core.sql
│   └── ...
├── merging/                 # 0x3xxx files
│   ├── 0x3000_merge_core.sql
│   └── ...
├── data/                    # 0x4xxx files
│   ├── 0x4000_objects_table.sql
│   └── ...
├── security/                # 0x5xxx files
│   ├── 0x5000_authentication.sql
│   └── ...
├── monitoring/              # 0x6xxx files
│   ├── 0x6000_metrics_core.sql
│   └── ...
├── performance/             # 0x7xxx files
│   ├── 0x7000_index_management.sql
│   └── ...
├── utilities/               # 0x8xxx files
│   ├── 0x8000_string_utilities.sql
│   └── ...
├── testing/                 # 0x9xxx files
│   ├── 0x9000_test_infrastructure.sql
│   └── ...
├── migration/               # 0xAxxx files
│   ├── 0xA000_migration_core.sql
│   └── ...
├── enterprise/              # 0xBxxx files
│   ├── 0xB000_workflows.sql
│   └── ...
├── integration/             # 0xCxxx files
│   ├── 0xC000_api_core.sql
│   └── ...
├── reserved_d/              # 0xDxxx (future)
├── reserved_e/              # 0xExxx (future)
└── reserved_f/              # 0xFxxx (future)
```

---

## Build Script Update

```bash
#!/bin/bash
# New build script for hex-organized files

# Concatenate in category order
for category in core ddl branching merging data security monitoring performance utilities testing migration enterprise integration; do
    cat sql/$category/*.sql
done

# Alternative: simple numeric sort
# cat sql/*/*.sql | sort
```

---

## Summary

This system provides:
- ✅ 65,536 possible file slots (hex 0x0000-0xFFFF)
- ✅ 16 major categories
- ✅ 16 subcategories per category
- ✅ 256 files per subcategory
- ✅ Self-documenting names
- ✅ Logical organization
- ✅ Easy reorganization
- ✅ Future expansion room
- ✅ Category-based builds
- ✅ Clear architecture mapping

**Recommendation**: Implement this system after Pass 5 is complete and stable. It provides the organizational foundation needed for long-term maintenance of a world-class PostgreSQL extension.
