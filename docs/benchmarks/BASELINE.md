# Performance Baseline

## Overview

This document establishes performance baselines for pgGit operations. These metrics help detect performance regressions and guide optimization efforts.

## Environment

- **Date**: 2025-12-20
- **pgGit Version**: 0.1.1
- **PostgreSQL Version**: 15.x
- **Hardware**: GitHub Actions (variable performance)
- **Dataset**: Clean database with pgGit installed

## Baseline Metrics

### DDL Tracking Overhead
- **Operation**: Create 100 tables with tracking enabled
- **Expected**: < 500ms
- **Current**: 118ms (426 objects tracked)
- **Notes**: Event trigger overhead: ~1.2ms per table

### Version Retrieval
- **Operation**: Get versions for 100 tables
- **Expected**: < 50ms
- **Current**: 4.5ms
- **Notes**: Indexed query performance: ~0.045ms per lookup

### History Queries
- **Operation**: Count history records in last hour
- **Expected**: < 10ms
- **Current**: 0.6ms (426 records found)
- **Notes**: Index effectiveness: ~0.001ms per record

### Migration Generation
- **Operation**: Generate migration script
- **Expected**: < 100ms
- **Current**: ~0.17ms (basic generation)
- **Notes**: SQL generation overhead minimal

## Performance Targets

### Response Time Goals
- **DDL Operations**: < 100ms per operation
- **Version Queries**: < 10ms per query
- **History Queries**: < 100ms for 1000 records
- **Migration Generation**: < 5 seconds for 1000 changes

### Scalability Goals
- **Objects Tracked**: 10,000+ objects
- **History Records**: 100,000+ records
- **Concurrent Users**: 10+ simultaneous users
- **Database Size**: 100GB+ databases

## Running Benchmarks

```bash
# Run the baseline benchmark
psql -d your_database -f tests/benchmarks/baseline.sql

# Compare against previous runs
# Look for >10% performance regressions
```

## Performance Monitoring

### CI Integration
Performance benchmarks run on every PR to detect regressions.

### Alert Thresholds
- **Warning**: >5% slowdown
- **Error**: >10% slowdown
- **Critical**: >25% slowdown

### Optimization Priorities
1. **DDL Tracking**: Most frequent operation
2. **Version Queries**: User-facing feature
3. **History Queries**: Audit and debugging
4. **Migration Generation**: Deployment critical

## Historical Performance

| Date | DDL Tracking | Version Query | History Query | Migration Gen |
|------|-------------|---------------|---------------|---------------|
| 2025-12-20 | 118ms (100 tables) | 4.5ms (100 queries) | 0.6ms (426 records) | ~0.17ms |
| Future | Target: <50ms | Target: <2ms | Target: <0.5ms | Target: <0.1ms |

## Contributing

When making performance-impacting changes:

1. Run benchmarks before and after
2. Document performance impact
3. Update this baseline if improving performance
4. Create issue if degrading performance >5%

## Troubleshooting

### Slow DDL Operations
- Check event trigger overhead
- Verify indexes on pggit.objects and pggit.history
- Consider disabling tracking for bulk operations

### Slow Queries
- Check query plans with EXPLAIN ANALYZE
- Verify index usage
- Consider partitioning for large history tables

### High Memory Usage
- Monitor work_mem settings
- Check for memory leaks in functions
- Consider streaming for large result sets