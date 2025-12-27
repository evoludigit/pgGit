# Load Testing Guide - Phase 8 API

This directory contains comprehensive load testing infrastructure for the PGGIT Phase 8 API using the Locust framework.

## Installation

### Prerequisites
- Python 3.10+
- Locust 2.14+
- FastAPI API running on `http://localhost:8000`

### Setup

```bash
# Install Locust
pip install locust

# Or if using uv:
uv pip install locust websockets

# Verify installation
locust --version
```

## Quick Start

### 1. Smoke Test (Quick Verification)
```bash
# Run quick 1-minute smoke test with 1 user
locust -f locustfile.py --headless -u 1 -r 1 --run-time 1m
```

### 2. Normal Load Test
```bash
# Run with 10 users ramping up at 2 users/second for 5 minutes
locust -f locustfile.py --headless -u 10 -r 2 --run-time 5m
```

### 3. Peak Load Test
```bash
# Run with 100 users ramping up at 10 users/second for 10 minutes
locust -f locustfile.py --headless -u 100 -r 10 --run-time 10m
```

### 4. Web UI (Interactive)
```bash
# Start Locust with web interface
locust -f locustfile.py

# Then open http://localhost:8089 in your browser
```

## Test Scenarios

Available scenarios are defined in `test_scenarios.py`:

| Scenario | Users | Duration | Purpose |
|----------|-------|----------|---------|
| **smoke_test** | 1 | 1 min | Quick verification API is up |
| **normal_load** | 10 | 5 min | Baseline traffic pattern |
| **peak_load** | 100 | 10 min | High volume scenario |
| **spike_test** | 100 | 3 min | Sudden traffic spike |
| **sustained_load** | 25 | 30 min | Long-running stability |
| **ramp_up** | 50 | 15 min | Gradual load increase |
| **websocket_heavy** | 50 | 10 min | Real-time updates focus |
| **cache_invalidation** | 20 | 10 min | Cache operations |
| **stress_test** | 200+ | 15 min | Maximum load |

## Running Scenarios

### Command Line
```bash
# Run specific scenario with custom parameters
locust -f locustfile.py --headless \
    --users 100 \
    --spawn-rate 10 \
    --run-time 10m \
    --csv=results/load_test

# Run only specific tags
locust -f locustfile.py --headless -u 50 -r 5 --run-time 5m --tags rest_endpoints

# Run WebSocket tests only
locust -f locustfile.py --headless -u 20 -r 2 --run-time 5m --tags websocket
```

### Python Script
```python
from test_scenarios import SCENARIOS

# Get scenario configuration
scenario = SCENARIOS['peak_load']

# Run with scenario parameters
# locust -u {scenario.users} -r {scenario.spawn_rate} --run-time {scenario.duration_minutes}m
```

## Test Tags

Use tags to filter which endpoints to test:

```bash
# Test only webhook endpoints
locust -f locustfile.py -u 50 -r 5 --run-time 5m --tags webhooks

# Test webhooks and alerts
locust -f locustfile.py -u 50 -r 5 --run-time 5m --tags webhooks,alerts

# Exclude WebSocket
locust -f locustfile.py -u 50 -r 5 --run-time 5m --tags rest_endpoints
```

Available tags:
- `webhooks` - Webhook CRUD operations
- `alerts` - Alert retrieval and acknowledgment
- `dashboard` - Dashboard metrics endpoints
- `cache` - Cache management endpoints
- `health` - Health check endpoints
- `websocket` - WebSocket connections
- `rest_endpoints` - All REST endpoints
- `read` - Read-only operations
- `write` - Write operations
- `admin` - Admin endpoints

## Interpreting Results

### Response Time Metrics
```
Name          #Reqs  #Fails  Avg (ms)  Min (ms)  Max (ms)  Median  P95  P99
alerts_list   1500   15      85        20        450       75      150  300
```

- **#Reqs**: Total requests made
- **#Fails**: Failed requests
- **Avg**: Average response time
- **P95/P99**: 95th/99th percentile (performance SLA targets)

### Performance Targets

Expected response times (from `test_scenarios.py`):

| Endpoint | P50 | P95 | P99 | Error Rate |
|----------|-----|-----|-----|-----------|
| webhooks_list | 50ms | 150ms | 300ms | <0.5% |
| alerts_list | 75ms | 200ms | 400ms | <0.5% |
| webhook_detail | 40ms | 100ms | 200ms | <0.5% |
| cache_stats | 30ms | 75ms | 150ms | <0.1% |
| health_check | 10ms | 25ms | 50ms | <0.0% |
| websocket_connect | 100ms | 300ms | 600ms | <1.0% |

## CSV Results

Locust generates CSV files with detailed metrics:

```bash
# Results saved to results/ directory
results/load_test_stats.csv      # Per-endpoint statistics
results/load_test_stats_history.csv  # Time-series data
results/load_test_failures.csv   # Failed requests
```

### Analyzing CSV Results
```python
import pandas as pd

# Load statistics
stats = pd.read_csv('results/load_test_stats.csv')
print(stats[['Name', 'Average Response Time', 'P95', 'P99']])

# Find slowest endpoints
slowest = stats.nlargest(5, 'Average Response Time')
print(f"\nSlowest endpoints:\n{slowest}")

# Check failure rate
failures = stats[stats['Failure Rate'] > 0]
print(f"\nFailed endpoints:\n{failures[['Name', 'Failure Rate']]}")
```

## Advanced Testing

### Custom Load Curves
```python
# Modify locustfile.py to use custom wait times
class CustomUser(HttpUser):
    wait_time = lambda self: time.random.expovariate(1/5)  # 5 sec avg
```

### Authentication Setup
Update the JWT token in `locustfile.py`:
```python
class LoadTestConfig:
    JWT_TOKEN = "your-actual-jwt-token-here"
```

### WebSocket Testing
WebSocket tests are automatically included. Monitor:
- Connection establishment time
- Message throughput
- Connection stability (dropped connections)

### Load Ramping
```bash
# Ramp from 1 to 100 users over 5 minutes
locust -f locustfile.py -u 100 -r 1 --run-time 5m
```

## Troubleshooting

### Connection Refused
```
Error: Connection refused
```
Make sure FastAPI is running:
```bash
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### Too Many Open Files
```
Error: OSError: [Errno 24] Too many open files
```
Increase system limits:
```bash
ulimit -n 65536
```

### Slow Tests
- Check API performance with deep health check: `curl http://localhost:8000/health/deep`
- Monitor database load: `SELECT count(*) FROM pg_stat_activity;`
- Check cache hit rates: `curl http://localhost:8000/api/v1/cache/stats`

### WebSocket Connection Issues
- Ensure WebSocket URL is correct
- Check token authentication
- Verify server supports WebSocket upgrades
- Check for firewall/proxy issues

## Performance Tuning

### Before Load Testing
1. Run deep health check: `curl http://localhost:8000/health/deep`
2. Verify database is responsive
3. Check cache is initialized
4. Warm up cache if needed: `curl http://localhost:8000/api/v1/cache/stats`

### While Testing
- Monitor CPU: `top`, `htop`
- Monitor memory: `free -h`, `ps aux`
- Monitor network: `netstat -i`, `ifstat`
- Monitor database connections: `SELECT count(*) FROM pg_stat_activity;`

### Common Bottlenecks
1. **Database Connection Pool** - Check pool size and connection wait times
2. **Cache Layer** - Monitor L1/L2 cache hit rates
3. **Network I/O** - Check bandwidth and latency
4. **Application Threads** - Check async event loop efficiency

## Continuous Integration

### GitHub Actions Example
```yaml
- name: Load Test API
  run: |
    locust -f tests/load/locustfile.py \
      --headless -u 50 -r 5 --run-time 5m \
      --csv=results/load_test

- name: Check Performance SLA
  run: python tests/load/check_sla.py results/load_test_stats.csv
```

## Next Steps

After load testing:

1. **Day 4 Task 2**: Performance profiling & optimization
   - Profile endpoints under load
   - Identify bottlenecks
   - Optimize slow queries
   - Tune cache TTLs

2. **Day 4 Task 3**: Integration testing
   - WebSocket under load
   - Cache warming effectiveness
   - Cache invalidation triggers
   - End-to-end API testing

3. **Day 5**: Code review & documentation
   - Review test results
   - Document findings
   - Prepare deployment

## References

- [Locust Documentation](https://docs.locust.io/)
- [FastAPI Performance](https://fastapi.tiangolo.com/)
- [Load Testing Best Practices](https://en.wikipedia.org/wiki/Load_testing)
