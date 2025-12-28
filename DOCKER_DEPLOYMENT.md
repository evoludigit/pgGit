# Docker Deployment Guide

**Status**: Production-ready
**Version**: v0.1.0
**Last Updated**: December 28, 2025

## Overview

This guide covers deploying pgGit using Docker containers. The system consists of:

- **pggit-api**: FastAPI application (main API)
- **postgres**: PostgreSQL 16 database
- **redis**: Redis 7 caching layer
- **webhook-worker-1/2/3**: Background webhook delivery workers

## Quick Start (Development)

```bash
# 1. Clone repository
git clone <repository-url>
cd pggit

# 2. Create environment file
cp .env.example .env.local

# 3. Configure database password (required)
echo "POSTGRES_PASSWORD=your-secure-password" >> .env.local

# 4. Start all services
docker-compose up -d

# 5. Check health
curl http://localhost:8000/health

# 6. View logs
docker-compose logs -f pggit-api
```

**Services Running**:
- API: http://localhost:8000
- API Docs: http://localhost:8000/api/docs
- PostgreSQL: localhost:5432
- Redis: localhost:6379
- Worker 1 Metrics: http://localhost:8100
- Worker 2 Metrics: http://localhost:8101
- Worker 3 Metrics: http://localhost:8102

## Production Deployment

### Prerequisites

1. **Docker**: Version 20.10+
2. **Docker Compose**: Version 2.0+
3. **Secrets Manager**: AWS Secrets Manager, HashiCorp Vault, or similar
4. **TLS Certificates**: For HTTPS endpoints

### Production Configuration

Create `.env.prod` file with production secrets:

```bash
# Database (use secrets manager!)
POSTGRES_USER=pggit_prod
POSTGRES_PASSWORD=<from-secrets-manager>
POSTGRES_DB=pggit_production

# API
API_PORT=8000
LOG_LEVEL=info
CORS_ORIGINS='["https://api.yourdomain.com","https://yourdomain.com"]'

# JWT (CRITICAL: Generate secure key!)
JWT_SECRET_KEY=<generate-with-openssl-rand-base64-32>

# Workers
WORKER_BATCH_SIZE=10
WORKER_POLL_INTERVAL=1.0
WORKER_HTTP_TIMEOUT=5.0
```

### Deployment Steps

```bash
# 1. Pull latest code
git pull origin main

# 2. Build images
docker-compose -f docker-compose.prod.yml build

# 3. Run database migrations (if needed)
docker-compose -f docker-compose.prod.yml run --rm pggit-api \
  python -m alembic upgrade head

# 4. Start services
docker-compose -f docker-compose.prod.yml up -d

# 5. Verify health
docker-compose -f docker-compose.prod.yml exec pggit-api \
  curl http://localhost:8000/health/deep

# 6. Check logs
docker-compose -f docker-compose.prod.yml logs -f
```

## Service Architecture

### pggit-api (FastAPI Application)

**Image**: Built from `Dockerfile`
**Port**: 8000
**Dependencies**: postgres (healthy), redis (healthy)

**Configuration** (via environment):
```bash
# Database connection
DATABASE__HOST=postgres
DATABASE__PORT=5432
DATABASE__DATABASE=pggit
DATABASE__USERNAME=postgres
DATABASE__PASSWORD=<secret>
DATABASE__POOL_MIN_SIZE=10
DATABASE__POOL_MAX_SIZE=50

# Cache
CACHE__TYPE=redis
CACHE__REDIS__HOST=redis
CACHE__REDIS__PORT=6379
CACHE__REDIS__DB=0
CACHE__TTL_SECONDS=300

# API
ENVIRONMENT=production
LOG_LEVEL=info

# CORS
CORS__ORIGINS='["https://yourdomain.com"]'

# JWT
JWT_SECRET_KEY=<secret>
JWT_ALGORITHM=HS256
```

**Health Check**: `GET /health` (30s interval)

**Resource Limits** (production):
- CPU: 2 cores max, 1 core reserved
- Memory: 2GB max, 1GB reserved

### postgres (PostgreSQL 16)

**Image**: `postgres:16-alpine`
**Port**: 5432 (internal only in production)
**Volume**: `postgres_data` → `/var/lib/postgresql/data`

**Configuration**:
```bash
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<secret>
POSTGRES_DB=pggit
```

**Initialization**:
- Schema loaded from `sql/v1.0.0/` on first start
- Persistent data in named volume

**Health Check**: `pg_isready` (10s interval)

**Resource Limits** (production):
- CPU: 2 cores max, 1 core reserved
- Memory: 4GB max, 2GB reserved

### redis (Redis 7)

**Image**: `redis:7-alpine`
**Port**: 6379 (internal only in production)
**Volume**: `redis_data` → `/data`

**Configuration**:
```bash
--appendonly yes                    # Persistence
--maxmemory 512mb                   # Memory limit
--maxmemory-policy allkeys-lru      # Eviction policy
```

**Health Check**: `redis-cli ping` (10s interval)

**Resource Limits** (production):
- CPU: 1 core max, 0.5 core reserved
- Memory: 1GB max, 512MB reserved

### webhook-worker-1/2/3 (Background Workers)

**Image**: Built from `services/Dockerfile`
**Ports**: 8100, 8101, 8102 (Prometheus metrics, internal only in production)
**Dependencies**: postgres (healthy), pggit-api (healthy)

**Configuration**:
```bash
DATABASE_URL=postgresql://user:pass@postgres:5432/pggit
WORKER_ID=worker-1  # Unique per worker
BATCH_SIZE=10
POLL_INTERVAL=1.0
HTTP_TIMEOUT=5.0
LOG_LEVEL=info
```

**Health Check**: TCP connection to metrics port (30s interval)

**Resource Limits** (production):
- CPU: 1 core max, 0.5 core reserved
- Memory: 512MB max, 256MB reserved

## Networking

**Network**: `pggit-network` (bridge driver)

**Development** (`docker-compose.yml`):
- All ports exposed to host for debugging
- PostgreSQL: 5432
- Redis: 6379
- API: 8000
- Workers: 8100-8102

**Production** (`docker-compose.prod.yml`):
- Only API port exposed (8000)
- All other services internal-only
- Use reverse proxy (nginx, traefik) for TLS termination

## Volume Management

**Development Volumes**:
- `pggit-postgres-data`: Database files
- `pggit-redis-data`: Redis persistence

**Production Volumes**:
- `pggit-postgres-data-prod`: Database files
- `pggit-redis-data-prod`: Redis persistence

**Backup Strategy**:
```bash
# Backup PostgreSQL
docker-compose exec postgres pg_dump -U postgres pggit > backup.sql

# Backup Redis
docker-compose exec redis redis-cli SAVE
docker cp pggit-redis:/data/dump.rdb redis-backup.rdb
```

**Restore Strategy**:
```bash
# Restore PostgreSQL
docker-compose exec -T postgres psql -U postgres pggit < backup.sql

# Restore Redis
docker cp redis-backup.rdb pggit-redis:/data/dump.rdb
docker-compose restart redis
```

## Monitoring

### Health Checks

**API Health**:
```bash
curl http://localhost:8000/health
# {"status":"healthy","service":"pggit-api","version":"1.0.0"}

curl http://localhost:8000/health/deep
# Includes: database, schema, cache status
```

**Database Health**:
```bash
docker-compose exec postgres pg_isready -U postgres
```

**Redis Health**:
```bash
docker-compose exec redis redis-cli ping
```

### Logs

**View all logs**:
```bash
docker-compose logs -f
```

**View specific service**:
```bash
docker-compose logs -f pggit-api
docker-compose logs -f postgres
docker-compose logs -f webhook-worker-1
```

**Structured logging** (JSON format):
```bash
docker-compose logs pggit-api | jq .
```

### Prometheus Metrics

**Worker Metrics**:
- http://localhost:8100/metrics (worker-1)
- http://localhost:8101/metrics (worker-2)
- http://localhost:8102/metrics (worker-3)

**Available Metrics**:
- `webhook_deliveries_total`: Total delivery attempts
- `webhook_delivery_duration_seconds`: Delivery latency
- `webhook_delivery_failures_total`: Failed deliveries

## Scaling

### Horizontal Scaling (API)

```yaml
# docker-compose.scale.yml
services:
  pggit-api:
    deploy:
      replicas: 3
```

```bash
docker-compose -f docker-compose.prod.yml \
  -f docker-compose.scale.yml up -d
```

### Horizontal Scaling (Workers)

Add more workers in `docker-compose.yml`:
```yaml
webhook-worker-4:
  # Copy worker-3 config, change:
  # - container_name: pggit-worker-4
  # - WORKER_ID: worker-4
  # - ports: "8103:8000"
```

### Database Scaling

For high load:
1. Increase connection pool: `DATABASE__POOL_MAX_SIZE=100`
2. Use read replicas (configure separately)
3. Consider managed PostgreSQL (AWS RDS, Google Cloud SQL)

### Cache Scaling

For high load:
1. Increase Redis memory: `--maxmemory 1gb`
2. Use Redis Cluster (configure separately)
3. Consider managed Redis (AWS ElastiCache, Google Memorystore)

## Security Hardening

### Production Checklist

- [ ] **Generate secure JWT secret**: `openssl rand -base64 32`
- [ ] **Use secrets manager** for passwords
- [ ] **Enable TLS** via reverse proxy (nginx, traefik)
- [ ] **Restrict CORS** to production domains only
- [ ] **Remove volume mounts** (use immutable images)
- [ ] **Set resource limits** to prevent resource exhaustion
- [ ] **Enable firewall** rules (UFW, iptables)
- [ ] **Configure logging** to external service (ELK, Splunk)
- [ ] **Set up monitoring** (Prometheus, Grafana)
- [ ] **Regular backups** automated via cron

### Network Security

**Production**: Use private network, expose only API behind reverse proxy:

```yaml
# nginx.conf
server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Troubleshooting

### API Won't Start

**Symptom**: `pggit-api` container exits immediately

**Check**:
```bash
docker-compose logs pggit-api
```

**Common Issues**:
1. Database not ready → Check postgres health: `docker-compose ps postgres`
2. Missing environment variables → Check `.env` file
3. Port conflict → Check if port 8000 is in use: `lsof -i :8000`

### Database Connection Errors

**Symptom**: `connection refused` or `authentication failed`

**Check**:
```bash
# Verify postgres is running
docker-compose ps postgres

# Check postgres logs
docker-compose logs postgres

# Test connection manually
docker-compose exec pggit-api psql -h postgres -U postgres -d pggit
```

**Fix**:
1. Verify `POSTGRES_PASSWORD` matches in all services
2. Ensure postgres health check passes
3. Check network connectivity: `docker network inspect pggit-network`

### Redis Cache Errors

**Symptom**: `Could not connect to Redis`

**Check**:
```bash
# Verify redis is running
docker-compose ps redis

# Test connection
docker-compose exec pggit-api redis-cli -h redis ping
```

**Fix**:
1. Verify redis health check passes
2. Check `CACHE__REDIS__HOST=redis`
3. Try restarting redis: `docker-compose restart redis`

### Performance Issues

**Symptom**: Slow API responses

**Check**:
```bash
# View resource usage
docker stats

# Check slow requests in logs
docker-compose logs pggit-api | grep "Slow request"

# Check database connections
docker-compose exec postgres psql -U postgres -d pggit \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

**Fix**:
1. Increase connection pool: `DATABASE__POOL_MAX_SIZE=100`
2. Increase cache memory: `--maxmemory 1gb` for redis
3. Scale API horizontally (see Scaling section)
4. Check database indexes via `/health/deep`

## Development vs Production

| Feature | Development | Production |
|---------|-------------|------------|
| **Compose File** | `docker-compose.yml` | `docker-compose.prod.yml` |
| **Volume Mounts** | Yes (hot reload) | No (immutable images) |
| **Exposed Ports** | All services | API only |
| **Resource Limits** | None | Enforced |
| **Restart Policy** | `unless-stopped` | `always` |
| **Secrets** | `.env.local` | Secrets manager |
| **Logging** | `log_statement=all` | `log_statement=ddl` |
| **TLS** | No | Yes (via nginx) |

## Maintenance

### Update Application

```bash
# 1. Pull latest code
git pull origin main

# 2. Rebuild images
docker-compose -f docker-compose.prod.yml build

# 3. Recreate containers (zero-downtime with multiple replicas)
docker-compose -f docker-compose.prod.yml up -d

# 4. Verify health
curl https://api.yourdomain.com/health/deep
```

### Database Migrations

```bash
# Run migrations
docker-compose -f docker-compose.prod.yml run --rm pggit-api \
  python -m alembic upgrade head

# Rollback (if needed)
docker-compose -f docker-compose.prod.yml run --rm pggit-api \
  python -m alembic downgrade -1
```

### Cleanup

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (⚠️ deletes data!)
docker-compose down -v

# Remove unused images
docker image prune -a

# Remove all unused resources
docker system prune -a --volumes
```

## Support

For issues or questions:
- GitHub Issues: <repository-url>/issues
- Documentation: See `README.md`, `API.md`, `DEPLOYMENT.md`
- Health Check: `GET /health/deep` for system diagnostics
