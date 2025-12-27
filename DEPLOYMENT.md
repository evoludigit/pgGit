# Phase 8 Week 2 Deployment Guide

## Overview

This guide covers deploying the Phase 8 Week 2 FastAPI-based REST API with WebSocket support, caching infrastructure, and production-ready monitoring.

## System Requirements

### Minimum Requirements
- **CPU**: 2 cores (4 cores recommended for production)
- **RAM**: 2GB (4GB recommended)
- **Storage**: 10GB available space
- **PostgreSQL**: 13+ (15+ recommended)
- **Python**: 3.10+
- **Network**: Stable internet connection for external webhooks

### Production Requirements
- **CPU**: 8+ cores
- **RAM**: 8GB+
- **Storage**: 50GB+ (SSD recommended)
- **PostgreSQL**: 15+ with replication
- **Redis**: 6+ (for L2 caching)
- **Load Balancer**: nginx or HAProxy
- **Monitoring**: Prometheus + Grafana

## Installation

### 1. Prerequisites

```bash
# Install system dependencies
sudo apt-get update
sudo apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3.10-venv \
    postgresql-client \
    libpq-dev \
    build-essential \
    git

# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. Clone and Setup

```bash
# Clone repository
git clone <repo-url> pggit
cd pggit

# Create virtual environment
python3.10 -m venv venv
source venv/bin/activate

# Install dependencies
uv pip install -e ".[dev]"
```

### 3. Database Setup

```bash
# Create database
createdb pggit

# Initialize schema
psql pggit < schema.sql

# Run migrations (if applicable)
python -m alembic upgrade head
```

### 4. Configuration

Create `.env` file:

```bash
# API Configuration
API_HOST=0.0.0.0
API_PORT=8000
API_WORKERS=4
API_LOG_LEVEL=INFO

# Database Configuration
DATABASE_URL=postgresql://user:password@localhost:5432/pggit
DATABASE_POOL_SIZE=20
DATABASE_POOL_MAX_OVERFLOW=10

# Cache Configuration
CACHE_ENABLED=true
CACHE_TTL_WEBHOOK_LIST=120
CACHE_TTL_ALERTS_LIST=120
CACHE_TTL_DASHBOARD=300
REDIS_URL=redis://localhost:6379/0  # Optional, for L2 caching

# Security
SECRET_KEY=your-secret-key-here
CORS_ORIGINS=["http://localhost:3000"]

# Monitoring
SENTRY_DSN=  # Optional
PROMETHEUS_ENABLED=true

# Environment
ENVIRONMENT=production
DEBUG=false
```

### 5. Start the API Server

#### Development

```bash
cd /home/lionel/code/pggit
source venv/bin/activate

# Run development server
python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

#### Production with Gunicorn

```bash
# Install gunicorn
uv pip install gunicorn

# Run with gunicorn
gunicorn api.main:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:8000 \
    --access-logfile - \
    --error-logfile - \
    --log-level info
```

#### Production with systemd

Create `/etc/systemd/system/pggit-api.service`:

```ini
[Unit]
Description=pggit API Server
After=network.target postgresql.service

[Service]
Type=notify
User=pggit
WorkingDirectory=/home/pggit/pggit
Environment="PATH=/home/pggit/pggit/venv/bin"
ExecStart=/home/pggit/pggit/venv/bin/gunicorn \
    api.main:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind unix:/run/pggit/api.sock \
    --access-logfile /var/log/pggit/access.log \
    --error-logfile /var/log/pggit/error.log

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable pggit-api
sudo systemctl start pggit-api
```

## Docker Deployment

### Dockerfile

```dockerfile
FROM python:3.10-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run application
CMD ["gunicorn", "api.main:app", \
     "--workers", "4", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000"]
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://pggit:password@db:5432/pggit
      REDIS_URL: redis://cache:6379/0
    depends_on:
      - db
      - cache
    volumes:
      - ./logs:/app/logs
    restart: always

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: pggit
      POSTGRES_PASSWORD: password
      POSTGRES_DB: pggit
    volumes:
      - db_data:/var/lib/postgresql/data
    restart: always

  cache:
    image: redis:7-alpine
    restart: always
    volumes:
      - cache_data:/data

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - api
    restart: always

volumes:
  db_data:
  cache_data:
```

### Build and Run

```bash
# Build image
docker build -t pggit-api:latest .

# Run with docker-compose
docker-compose up -d

# View logs
docker-compose logs -f api
```

## nginx Configuration

Create `nginx.conf`:

```nginx
upstream pggit_api {
    server api:8000;
}

server {
    listen 80;
    server_name api.example.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    # SSL certificates
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain application/json;
    gzip_min_length 1000;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req zone=api burst=20 nodelay;

    # WebSocket upgrade
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    location / {
        proxy_pass http://pggit_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /api/v1/ws/ {
        proxy_pass http://pggit_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

## Monitoring and Logging

### Prometheus Metrics

The API exposes metrics at `/metrics`:

```bash
# Scrape configuration for prometheus.yml
scrape_configs:
  - job_name: 'pggit-api'
    static_configs:
      - targets: ['localhost:8000']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

### Key Metrics to Monitor

```
# Request metrics
http_requests_total
http_request_duration_seconds

# Cache metrics
cache_hits_total
cache_misses_total
cache_evictions_total

# Database metrics
db_connection_pool_size
db_query_duration_seconds
db_connections_active

# Webhook metrics
webhook_deliveries_total
webhook_delivery_duration_seconds
webhook_failures_total
```

### Logging Configuration

Configure logging in `api/main.py`:

```python
import logging
from logging.handlers import RotatingFileHandler

# Create logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# File handler
file_handler = RotatingFileHandler(
    'logs/api.log',
    maxBytes=10485760,  # 10MB
    backupCount=10
)
file_handler.setFormatter(logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
))
logger.addHandler(file_handler)
```

### Log Levels

- **DEBUG**: Detailed information for development
- **INFO**: General application events
- **WARNING**: Warning messages for potential issues
- **ERROR**: Error events
- **CRITICAL**: Critical system failures

Recommended production level: **INFO**

## Health Checks

### Basic Health Check

```bash
curl http://localhost:8000/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Deep Health Check

```bash
curl http://localhost:8000/health/deep
```

Response:
```json
{
  "status": "healthy",
  "database": {
    "status": "connected",
    "response_time_ms": 5
  },
  "cache": {
    "status": "operational",
    "hit_rate": 0.87
  },
  "webhooks": {
    "status": "operational",
    "active_count": 12,
    "failed_count": 0
  }
}
```

## Database Backup and Recovery

### Automated Backups

Create backup script `/usr/local/bin/backup-pggit.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/backups/pggit"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup database
pg_dump pggit | gzip > $BACKUP_DIR/pggit_$TIMESTAMP.sql.gz

# Keep only last 7 days
find $BACKUP_DIR -name "pggit_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/pggit_$TIMESTAMP.sql.gz"
```

Schedule with cron:

```bash
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/backup-pggit.sh
```

### Restore from Backup

```bash
# List available backups
ls -lh /backups/pggit/

# Restore specific backup
gunzip -c /backups/pggit/pggit_20240115_020000.sql.gz | psql pggit
```

## Performance Tuning

### PostgreSQL Optimization

```sql
-- Increase shared buffers (25% of system RAM)
ALTER SYSTEM SET shared_buffers = '4GB';

-- Increase effective cache size (50-75% of system RAM)
ALTER SYSTEM SET effective_cache_size = '12GB';

-- Increase work memory (RAM / max_connections / 2)
ALTER SYSTEM SET work_mem = '1GB';

-- Increase maintenance work memory
ALTER SYSTEM SET maintenance_work_mem = '1GB';

-- Reload configuration
SELECT pg_reload_conf();
```

### Connection Pool Optimization

```python
# In api/main.py
DATABASE_POOL_SIZE = 20          # Number of connections
DATABASE_POOL_MAX_OVERFLOW = 10  # Additional connections allowed
DATABASE_POOL_TIMEOUT = 30       # Connection timeout in seconds
```

### Cache Optimization

```python
# Cache warming on startup
@app.on_event("startup")
async def warm_cache():
    await cache_manager.warm_cache()

# Cache invalidation on data changes
@app.post("/api/v1/webhooks")
async def create_webhook(webhook: WebhookCreate):
    result = await webhook_service.create(webhook)
    await cache_manager.invalidate("webhooks_list")
    return result
```

## Scaling Considerations

### Horizontal Scaling

For multi-instance deployments:

1. **Shared Cache**: Use Redis instead of in-memory cache
2. **Session Management**: Store sessions in database
3. **Load Balancing**: Use sticky sessions for WebSocket connections
4. **Database**: Use connection pooling (PgBouncer recommended)

### PgBouncer Configuration

```ini
[databases]
pggit = host=db_primary port=5432 dbname=pggit

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3
```

### Vertical Scaling

For single-instance high-performance setup:

1. **Increase worker processes**: Match number of CPU cores
2. **Increase cache TTLs**: For frequently accessed data
3. **Enable L2 caching**: Use Redis for distributed cache
4. **Optimize database**: Add indexes, increase PostgreSQL memory

## Security Checklist

- [ ] Enable SSL/TLS encryption
- [ ] Configure CORS appropriately
- [ ] Use strong SECRET_KEY
- [ ] Enable rate limiting
- [ ] Configure firewall rules
- [ ] Enable database authentication
- [ ] Set up monitoring and alerting
- [ ] Regular security updates
- [ ] Database backups encrypted
- [ ] Application logs retained for audit
- [ ] API authentication/authorization configured
- [ ] Webhook signature verification enabled

## Troubleshooting

### API Won't Start

```bash
# Check logs
tail -f /var/log/pggit/error.log

# Verify database connectivity
psql postgresql://user:password@localhost:5432/pggit

# Check port availability
netstat -tlnp | grep 8000
```

### High Latency

```bash
# Check cache stats
curl http://localhost:8000/api/v1/cache/stats

# Warm cache
curl -X POST http://localhost:8000/api/v1/cache/warm

# Check database performance
EXPLAIN ANALYZE SELECT * FROM webhooks;
```

### WebSocket Disconnections

1. Check network connectivity
2. Verify proxy timeout settings (should be > 3600s)
3. Check connection limits: `ulimit -n`
4. Review server logs for errors

### Memory Issues

```bash
# Check memory usage
free -h

# Check process memory
ps aux | grep gunicorn

# Increase available memory or reduce worker count
```

## Deployment Checklist

### Pre-Deployment
- [ ] All tests pass: `pytest tests/`
- [ ] Linting passed: `ruff check .`
- [ ] Database migrations applied
- [ ] Configuration updated
- [ ] Backups scheduled
- [ ] Monitoring configured
- [ ] Load balancer configured
- [ ] SSL certificates valid

### Deployment
- [ ] Stop old instances gracefully
- [ ] Deploy new version
- [ ] Run database migrations
- [ ] Warm cache
- [ ] Verify health checks
- [ ] Monitor error rates for 5 minutes

### Post-Deployment
- [ ] Verify endpoints responding
- [ ] Check WebSocket connections
- [ ] Monitor performance metrics
- [ ] Review application logs
- [ ] Test critical workflows
- [ ] Verify monitoring alerts working

## Rollback Procedure

```bash
# If issues occur within 5 minutes of deployment:

# 1. Stop current version
sudo systemctl stop pggit-api

# 2. Restore previous version
git checkout <previous-commit>
source venv/bin/activate
uv pip install -e ".[dev]"

# 3. Start service
sudo systemctl start pggit-api

# 4. Verify
curl http://localhost:8000/health
```

## References

- **FastAPI Deployment**: https://fastapi.tiangolo.com/deployment/
- **Uvicorn**: https://www.uvicorn.org/
- **PostgreSQL Performance**: https://wiki.postgresql.org/wiki/Performance_Optimization
- **nginx Documentation**: https://nginx.org/en/docs/
- **Docker Documentation**: https://docs.docker.com/
- **API Documentation**: See `API.md`

