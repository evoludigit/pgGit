# Performance Profiling & Optimization Guide

This guide explains how to use the performance profiling tools to analyze load test results, identify bottlenecks, and implement optimizations.

## Overview

The performance profiling system consists of:

1. **PerformanceAnalyzer** - Parses Locust CSV results and identifies bottlenecks
2. **OptimizationPlan** - Generates structured improvement recommendations
3. **Performance Targets** - Defined in `test_scenarios.py` for SLA validation

## Running Performance Analysis

### Quick Start

```bash
# Run a load test and save CSV results
cd tests/load
./run_load_test.sh normal_load --csv results/load_test

# Analyze the results
cd ../performance
python profile_and_optimize.py ../load/results/load_test_stats.csv
```

### Using the Analyzer Programmatically

```python
from profile_and_optimize import PerformanceAnalyzer, OptimizationPlan

# Analyze load test results
analyzer = PerformanceAnalyzer('results/load_test_stats.csv')
analyzer.parse_csv()
analyzer.identify_bottlenecks()
analyzer.generate_recommendations()
analyzer.print_summary()

# Generate optimization plan
plan_gen = OptimizationPlan(analyzer)
plan_gen.print_plan()

# Get cache TTL recommendations
cache_config = analyzer.get_cache_tuning()
print(f"Cache TTLs: {cache_config}")
```

## Understanding the Metrics

### Endpoint Metrics

Each endpoint is analyzed with the following metrics:

| Metric | Meaning | Target |
|--------|---------|--------|
| **Requests** | Total number of requests made | - |
| **Failures** | Number of failed requests | 0 |
| **Avg (ms)** | Average response time | Varies by endpoint |
| **P95 (ms)** | 95th percentile latency | Important SLA metric |
| **P99 (ms)** | 99th percentile latency | Important SLA metric |
| **Error Rate** | Percentage of failed requests | < 1% typically |

### Performance Targets

Performance targets are defined in `test_scenarios.py`:

```python
# Example targets
"webhooks_list": PerformanceTarget(
    p50_ms=50,
    p95_ms=150,
    p99_ms=300,
    error_rate_percent=0.5,
    min_throughput_rps=100
)
```

## Bottleneck Detection

The analyzer identifies three types of bottlenecks:

### 1. High Latency Bottlenecks

```
CRITICAL: webhooks_list P99 latency 450ms exceeds 500ms target
WARNING: alerts_list P99 latency 350ms exceeds 300ms target
```

**Thresholds:**
- CRITICAL: P99 > 500ms
- WARNING: P99 > 300ms

**Solutions:**
- Increase cache TTLs
- Optimize database queries
- Add indexes
- Implement L2 caching

### 2. High Error Rate Bottlenecks

```
CRITICAL: dashboard_overview error rate 2.5% exceeds 1% threshold
```

**Thresholds:**
- CRITICAL: Error rate > 1%

**Solutions:**
- Fix application bugs
- Increase retry logic
- Add circuit breakers
- Scale resources

### 3. High Variance Bottlenecks

```
WARNING: merge_branches has high variance (max 5000ms vs P99 1200ms)
```

**Indicates:**
- Inconsistent performance
- Potential resource contention
- GC pauses or system issues

**Solutions:**
- Monitor system resources
- Tune thread pools
- Implement connection pooling

## Optimization Recommendations

The system provides three levels of optimizations:

### Immediate Actions (1-2 hours)

High-impact, low-effort changes:
- Increase cache TTLs for high-traffic endpoints
- Enable L2 Redis caching for dashboard endpoints
- Tune connection pool sizes

**Impact:** 15-25% latency reduction

### Short-term Actions (4-8 hours)

Medium-effort optimizations:
- Optimize database indexes
- Implement query pagination
- Analyze slow queries

**Impact:** 20-30% latency reduction

### Long-term Actions (Next sprint)

High-effort, high-impact changes:
- Implement materialized views
- Add read replicas
- Refactor hot code paths

**Impact:** 40-50% latency reduction

## Cache TTL Tuning

The analyzer automatically recommends cache TTLs based on:

1. **Traffic Volume:**
   - High (>1000 req/day): 5 minutes
   - Medium (>100 req/day): 2 minutes
   - Low (>10 req/day): 1 minute
   - Very low: 30 seconds

2. **Response Latency:**
   - Slow (P99 > 200ms): Minimum 5 minutes
   - Fast (P99 < 50ms): Maximum 1 minute

**Example Output:**

```
Cache TTL Recommendations:
    webhook_detail       60s
    webhooks_list        120s
    alerts_list          120s
    dashboard_overview   300s
    health_check         30s
```

## Implementing Optimizations

### Step 1: Identify Bottlenecks

```bash
python profile_and_optimize.py results/load_test_stats.csv
```

Review the bottlenecks section and prioritize by severity.

### Step 2: Apply Immediate Fixes

```python
# Update cache TTLs in api/cache.py
CACHE_TTL_CONFIG = {
    'webhook_detail': 60,
    'webhooks_list': 120,
    'alerts_list': 120,
    'dashboard_overview': 300,
}

# Increase connection pool
DATABASE_POOL_SIZE = 20
```

### Step 3: Optimize Queries

For slow endpoints, check:
- Missing indexes
- N+1 query problems
- Unnecessary joins
- Large result sets

```bash
# Analyze query performance
EXPLAIN ANALYZE SELECT * FROM alerts WHERE status='pending';

# Add missing indexes
CREATE INDEX idx_alerts_status ON alerts(status);
```

### Step 4: Re-test and Validate

```bash
# Run load test again
./run_load_test.sh normal_load --csv results/load_test_v2

# Compare results
python profile_and_optimize.py results/load_test_v2_stats.csv
```

## CSV Output Format

The load test generates three CSV files:

### `*_stats.csv` - Summary Statistics

```
Name,Type,# requests,# failures,Median Response Time,Average Response Time,Min Response Time,Max Response Time,Average Content Length,Requests/s,Failure Rate,%,95%,99%
webhooks_list,GET,1500,0,50,55,20,300,245,50.0,0.0%,150,300
alerts_list,GET,1200,12,75,85,25,450,512,40.0,1.0%,200,400
```

### `*_stats_history.csv` - Time Series Data

```
Type,Name,# requests,# failures,Median Response Time,Average Response Time,Min Response Time,Max Response Time,Average Content Length,Requests/s
0,webhooks_list,150,0,50,55,20,200,245,50.0
5,webhooks_list,160,1,52,58,21,250,245,53.3
```

### `*_failures.csv` - Failure Details

```
Method,Name,# occurrences,Failure
GET,webhooks_list[GET /api/v1/webhooks],5,"ConnectionError: ('Connection aborted.',)"
POST,alerts_acknowledge[POST /api/v1/alerts/acknowledge],7,"HTTPError: 500 Server Error"
```

## Example Analysis Session

```bash
# 1. Run smoke test
locust -f locustfile.py --headless -u 5 -r 1 --run-time 1m \
    --csv=results/smoke_test

# 2. Analyze results
python profile_and_optimize.py results/smoke_test_stats.csv

# Output shows:
# - 5 endpoints tested
# - 2 warnings (P99 latency)
# - Cache TTL recommendations
# - Optimization plan

# 3. Apply recommended changes
# - Update cache TTLs in config
# - Add database indexes
# - Increase connection pool

# 4. Re-test with peak load
locust -f locustfile.py --headless -u 100 -r 10 --run-time 5m \
    --csv=results/peak_load

# 5. Compare improvements
python profile_and_optimize.py results/peak_load_stats.csv

# Expected improvements:
# - 20-30% latency reduction
# - Lower P99 percentiles
# - Fewer timeout errors
```

## Troubleshooting

### High P99 Latency

**Check:**
1. Database query performance (EXPLAIN ANALYZE)
2. Cache hit rates
3. Connection pool exhaustion
4. System resource usage (CPU, memory, disk I/O)

**Fix:**
1. Optimize slow queries
2. Increase cache TTLs
3. Increase connection pool
4. Scale infrastructure

### High Error Rate

**Check:**
1. Application error logs
2. Database connectivity
3. Resource limits
4. External service availability

**Fix:**
1. Fix bugs
2. Add retries
3. Implement circuit breakers
4. Scale resources

### High Variance in Response Times

**Check:**
1. GC pause times
2. Lock contention
3. Disk I/O patterns
4. Network latency

**Fix:**
1. Tune JVM/Python GC
2. Reduce lock contention
3. Add connection pooling
4. Optimize network requests

## Performance Targets Summary

| Endpoint | P50 | P95 | P99 | Error Rate |
|----------|-----|-----|-----|-----------|
| health_check | 10ms | 25ms | 50ms | <0.0% |
| cache_stats | 30ms | 75ms | 150ms | <0.1% |
| webhook_detail | 40ms | 100ms | 200ms | <0.5% |
| webhooks_list | 50ms | 150ms | 300ms | <0.5% |
| alerts_list | 75ms | 200ms | 400ms | <0.5% |
| dashboard_overview | 100ms | 250ms | 500ms | <1.0% |
| websocket_connect | 100ms | 300ms | 600ms | <1.0% |

## Next Steps

After profiling and optimization:

1. **Day 4 Task 3**: Integration testing
   - Test WebSocket under load
   - Verify cache effectiveness
   - Test cache invalidation

2. **Day 5**: Code review & documentation
   - Review optimizations
   - Document findings
   - Prepare deployment

## References

- Load Testing Guide: `tests/load/README.md`
- Test Scenarios: `tests/load/test_scenarios.py`
- API Documentation: `api/README.md`
