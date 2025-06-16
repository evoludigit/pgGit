# Performance Guide

This guide covers performance considerations and monitoring for pggit.

## 🎯 Performance Overview

pggit is designed to be lightweight and efficient:
- **Event triggers**: Minimal overhead for DDL tracking
- **AI analysis**: Fast local processing with GPT-2
- **Storage**: Efficient change tracking without full schema duplication

## ⚡ Current Performance Features

### 1. Lightweight Event Triggers
```sql
-- Check event trigger performance
SELECT 
    tgname,
    tgenabled 
FROM pg_trigger 
WHERE tgname LIKE 'pggit%';
```

### 2. Efficient Storage
```sql
-- Monitor pggit storage usage
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'pggit';
```

### 3. AI Analysis Performance
```sql
-- Time AI analysis operations
\timing on
SELECT pggit.analyze_migration_with_ai('test', 'CREATE TABLE test (id INT);', 'manual');
\timing off
```

## 📊 Performance Monitoring

### Built-in Functions
```sql
-- Check database object count
SELECT COUNT(*) as total_objects FROM pggit.objects;

-- Check history size
SELECT COUNT(*) as total_changes FROM pggit.history;

-- Monitor function execution times
SELECT 
    funcname,
    calls,
    total_time,
    mean_time
FROM pg_stat_user_functions 
WHERE schemaname = 'pggit';
```

## 🚀 Optimization Tips

### For Large Databases
- Monitor event trigger performance impact
- Consider selective schema tracking if needed
- Use `EXPLAIN ANALYZE` on pggit queries for optimization

### For High-Frequency Changes
- Monitor `pggit.history` table growth
- Consider periodic cleanup of old history records
- Check AI analysis response times

## 📈 Benchmarking Your Installation

### Basic Performance Test
```bash
# Run comprehensive test suite and time it
time make test
```

### Database Size Impact
```sql
-- Measure pggit overhead
WITH database_size AS (
    SELECT pg_database_size(current_database()) as total_size
),
pggit_size AS (
    SELECT sum(pg_total_relation_size(schemaname||'.'||tablename)) as pggit_size
    FROM pg_tables 
    WHERE schemaname = 'pggit'
)
SELECT 
    pg_size_pretty(total_size) as database_size,
    pg_size_pretty(pggit_size) as pggit_size,
    round((pggit_size::float / total_size::float) * 100, 2) as overhead_percent
FROM database_size, pggit_size;
```

## 🎯 Best Practices

### 1. Monitoring
- Regularly check `pg_stat_user_functions` for pggit function performance
- Monitor `pggit.history` table growth
- Track AI analysis timing for performance regression

### 2. Optimization
- Keep PostgreSQL statistics up to date: `ANALYZE;`
- Consider indexing strategies for custom queries
- Monitor system resources during large migrations

### 3. Troubleshooting
- Use `EXPLAIN ANALYZE` for slow pggit queries
- Check PostgreSQL logs for event trigger issues
- Monitor memory usage during AI analysis

## 📞 Performance Support

Having performance issues?

- **Community**: [GitHub Issues](https://github.com/evoludigit/pggit/issues)
- **Documentation**: Check [Troubleshooting Guide](../getting-started/Troubleshooting.md)
- **Metrics**: Use the voluntary metrics collection function (see Contributing Guide)

---

*Performance monitoring is key to maintaining healthy pggit installations. Report any performance issues to help improve the project.*