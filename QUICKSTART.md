# Phase 8 Week 2 Quick Start Guide

## 5-Minute Setup

### Prerequisites

```bash
# Check Python version
python3.10 --version  # Should be 3.10+

# Check PostgreSQL is running
pg_isready
```

### Installation

```bash
# 1. Install dependencies
uv pip install -e ".[dev]"

# 2. Create database
createdb pggit

# 3. Initialize schema
psql pggit < schema.sql

# 4. Start API server
python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

### Verify It Works

```bash
# In another terminal
curl http://localhost:8000/health

# Should respond with:
# {"status":"healthy","timestamp":"2024-01-15T10:30:00Z"}
```

## Common Tasks

### View API Documentation

Open your browser:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Test Webhook Management

```bash
# List webhooks
curl http://localhost:8000/api/v1/webhooks

# Create a webhook
curl -X POST http://localhost:8000/api/v1/webhooks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-webhook",
    "url": "https://example.com/webhook",
    "is_active": true
  }'

# Update a webhook
curl -X PUT http://localhost:8000/api/v1/webhooks/1 \
  -H "Content-Type: application/json" \
  -d '{"is_active": false}'

# Delete a webhook
curl -X DELETE http://localhost:8000/api/v1/webhooks/1
```

### Test Alert Management

```bash
# List alerts
curl http://localhost:8000/api/v1/alerts

# Get alert details
curl http://localhost:8000/api/v1/alerts/1

# Acknowledge alerts
curl -X POST http://localhost:8000/api/v1/alerts/acknowledge \
  -H "Content-Type: application/json" \
  -d '{"alert_ids": [1, 2, 3]}'
```

### View Cache Statistics

```bash
# Get cache stats
curl http://localhost:8000/api/v1/cache/stats

# Response includes:
# - hit_rate: percentage of cache hits
# - cache_hits: total successful cache hits
# - cache_misses: total cache misses
# - current_size_bytes: current cache size
```

### Warm Cache

```bash
# Manually warm cache
curl -X POST http://localhost:8000/api/v1/cache/warm

# Response includes:
# - status: "success"
# - warmed_entries: number of entries loaded
# - duration_ms: time taken
```

### Check Deep Health

```bash
# Get comprehensive health status
curl http://localhost:8000/health/deep

# Response includes database, cache, and webhook health
```

## Running Tests

### Run All Tests

```bash
pytest tests/
```

### Run Specific Test Suite

```bash
# Integration tests only
pytest tests/integration/test_phase8_week2_api.py

# Run with verbose output
pytest tests/integration/ -v

# Run with coverage
pytest tests/ --cov=api --cov-report=html
```

### Run Performance Tests

```bash
# Load testing (requires locust)
locust -f tests/load/locustfile.py --headless -u 10 -r 1 --run-time 1m

# Performance analysis
python tests/performance/profile_and_optimize.py results/load_test_stats.csv
```

## Environment Configuration

Create `.env` file in project root:

```bash
# API Configuration
API_HOST=0.0.0.0
API_PORT=8000
API_WORKERS=4
API_LOG_LEVEL=INFO

# Database Configuration
DATABASE_URL=postgresql://user:password@localhost:5432/pggit
DATABASE_POOL_SIZE=20

# Cache Configuration
CACHE_ENABLED=true
CACHE_TTL_WEBHOOK_LIST=120
CACHE_TTL_ALERTS_LIST=120

# Security
SECRET_KEY=your-secret-key-here
DEBUG=false
```

## Troubleshooting

### API Won't Start

```bash
# Check if port is in use
lsof -i :8000

# Kill the process using port 8000
kill -9 <PID>

# Try starting again
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### Database Connection Error

```bash
# Verify PostgreSQL is running
pg_isready

# Start PostgreSQL if needed
sudo systemctl start postgresql

# Verify database exists
psql -l | grep pggit

# Check connection string in .env
echo $DATABASE_URL
```

### Import Error: No Module Named 'api'

```bash
# Ensure you're in the project root
pwd  # Should be /home/lionel/code/pggit

# Reinstall package in development mode
uv pip install -e ".[dev]"
```

### Tests Fail with ModuleNotFoundError

```bash
# Reinstall development dependencies
uv pip install -e ".[dev]"

# Make sure pytest can find modules
export PYTHONPATH=$(pwd):$PYTHONPATH

# Run tests again
pytest tests/
```

## Project Structure

```
pggit/
├── api/                          # FastAPI application
│   ├── main.py                  # API entry point
│   ├── endpoints/               # REST endpoints
│   ├── schemas/                 # Pydantic models
│   └── cache.py                 # Cache management
├── tests/
│   ├── integration/             # Integration tests
│   ├── load/                    # Load testing
│   └── performance/             # Performance analysis
├── sql/                         # Database schema
├── API.md                       # API documentation
├── DEPLOYMENT.md                # Deployment guide
├── OPERATIONS.md                # Operations guide
├── QUICKSTART.md                # This file
├── pyproject.toml               # Project configuration
└── README.md                    # Project overview
```

## Key Files to Know

| File | Purpose |
|------|---------|
| `API.md` | Complete API endpoint documentation |
| `DEPLOYMENT.md` | Production deployment instructions |
| `OPERATIONS.md` | Daily operations and troubleshooting |
| `api/main.py` | FastAPI application entry point |
| `tests/integration/test_phase8_week2_api.py` | Integration test suite |

## Common Commands

```bash
# Start development server
python -m uvicorn api.main:app --reload

# Run tests
pytest tests/ -v

# Run linting
ruff check .

# Format code
ruff format .

# Check database connectivity
psql $DATABASE_URL -c "SELECT 1;"

# Warm cache
curl -X POST http://localhost:8000/api/v1/cache/warm

# View cache stats
curl http://localhost:8000/api/v1/cache/stats | jq '.hit_rate'

# Check health
curl http://localhost:8000/health | jq '.status'
```

## Next Steps

1. **Read API Documentation**: See `API.md` for complete endpoint reference
2. **Review Integration Tests**: Check `tests/integration/` for usage examples
3. **Deploy to Production**: Follow `DEPLOYMENT.md` for production setup
4. **Monitor Performance**: Use `OPERATIONS.md` for monitoring guidance

## Getting Help

- **API Questions**: See `API.md` → Troubleshooting section
- **Deployment Issues**: See `DEPLOYMENT.md` → Troubleshooting section
- **Operations**: See `OPERATIONS.md` → Troubleshooting section
- **Code Issues**: Check integration tests in `tests/integration/`

## Support Resources

- **FastAPI Docs**: https://fastapi.tiangolo.com/
- **PostgreSQL Docs**: https://www.postgresql.org/docs/
- **Uvicorn Docs**: https://www.uvicorn.org/
- **Pytest Docs**: https://docs.pytest.org/

## Quick Reference: Common API Endpoints

### Webhooks
- `GET /api/v1/webhooks` - List all webhooks
- `POST /api/v1/webhooks` - Create new webhook
- `GET /api/v1/webhooks/{id}` - Get webhook details
- `PUT /api/v1/webhooks/{id}` - Update webhook
- `DELETE /api/v1/webhooks/{id}` - Delete webhook

### Alerts
- `GET /api/v1/alerts` - List alerts
- `GET /api/v1/alerts/{id}` - Get alert details
- `POST /api/v1/alerts/acknowledge` - Acknowledge alerts

### Cache
- `GET /api/v1/cache/stats` - View cache statistics
- `POST /api/v1/cache/warm` - Warm the cache
- `POST /api/v1/cache/invalidate` - Clear cache entries

### Health
- `GET /health` - Basic health check
- `GET /health/deep` - Deep health check with details

### Documentation
- `GET /docs` - Swagger UI (interactive)
- `GET /redoc` - ReDoc (alternative format)
- `GET /openapi.json` - OpenAPI schema

## Example Workflow

```bash
# 1. Verify API is running
curl http://localhost:8000/health

# 2. Create a test webhook
WEBHOOK=$(curl -X POST http://localhost:8000/api/v1/webhooks \
  -H "Content-Type: application/json" \
  -d '{"name":"test","url":"https://example.com/webhook"}' | jq '.id')

# 3. List webhooks to confirm
curl http://localhost:8000/api/v1/webhooks | jq '.items'

# 4. Check cache is working
curl http://localhost:8000/api/v1/cache/stats | jq '.hit_rate'

# 5. Update webhook
curl -X PUT http://localhost:8000/api/v1/webhooks/$WEBHOOK \
  -H "Content-Type: application/json" \
  -d '{"description":"Updated test webhook"}'

# 6. Clean up - delete webhook
curl -X DELETE http://localhost:8000/api/v1/webhooks/$WEBHOOK
```
