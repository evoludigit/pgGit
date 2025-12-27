# Phase 8 Week 2C: Deployment Guide

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Kubernetes Deployment](#kubernetes-deployment)
3. [Production Environment Setup](#production-environment-setup)
4. [Database Migration & Backup](#database-migration--backup)
5. [Scaling Guidelines](#scaling-guidelines)
6. [Monitoring & Alerts](#monitoring--alerts)
7. [Troubleshooting](#troubleshooting)

---

## Pre-Deployment Checklist

### Security

- [ ] All webhook URLs validated (HTTPS-only, no private IPs)
- [ ] HMAC-SHA256 signatures implemented
- [ ] AES-256-GCM encryption configured
- [ ] Signing keys generated and securely stored
- [ ] TLS 1.2+ enforced
- [ ] Secrets manager (Vault/AWS Secrets Manager) configured
- [ ] All credentials rotated
- [ ] Rate limiting configured
- [ ] Audit logging enabled

### Infrastructure

- [ ] Kubernetes cluster provisioned (1.24+)
- [ ] PostgreSQL 14+ instance ready
- [ ] Redis cluster for rate limiting (optional)
- [ ] Prometheus/Grafana deployed
- [ ] Secrets manager accessible
- [ ] Network policies configured
- [ ] Load balancer configured
- [ ] SSL/TLS certificates provisioned

### Testing

- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] Load tests completed (1000+ deliveries)
- [ ] Security scanning passed (OWASP ZAP, Trivy)
- [ ] Performance validated (< 10ms functions)
- [ ] Failover tested
- [ ] Rollback tested

### Documentation

- [ ] Architecture documented
- [ ] Runbooks created
- [ ] Disaster recovery plan documented
- [ ] Team trained on monitoring
- [ ] Support procedures documented

---

## Kubernetes Deployment

### Prerequisites

```bash
# 1. Install kubectl, helm
kubectl version --client
helm version

# 2. Access to Kubernetes cluster
kubectl cluster-info

# 3. Create namespace
kubectl create namespace pggit
kubectl config set-context --current --namespace=pggit
```

### Helm Chart Structure

```yaml
# helm/webhook-delivery/values.yaml

replicaCount: 3

image:
  registry: gcr.io
  repository: your-org/webhook-worker
  tag: "1.0.0"
  pullPolicy: IfNotPresent

# Worker configuration
worker:
  batchSize: 10
  pollInterval: 1.0
  httpTimeout: 5.0
  maxRetries: 3

# Database
database:
  host: postgres.default.svc.cluster.local
  port: 5432
  name: pggit
  # credentials from secrets

# Rate limiting
rateLimiting:
  globalRPS: 1000
  perWebhookRPS: 10
  perRequesterRPS: 100

# Scaling
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

# Resources
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"

# Health checks
healthCheck:
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Deploy Webhook Workers

```bash
# 1. Create secrets
kubectl create secret generic pggit-secrets \
  --from-literal=database_url="postgresql://..." \
  --from-literal=encryption_key="..." \
  --from-literal=signing_secret="..."

# 2. Deploy using Helm
helm install webhook-delivery ./helm/webhook-delivery \
  -f helm/webhook-delivery/values.yaml \
  --namespace pggit

# 3. Verify deployment
kubectl get pods -n pggit
kubectl logs -l app=webhook-worker -n pggit --tail=50

# 4. Check readiness
kubectl get endpoints webhook-delivery -n pggit
```

### Kubernetes YAML Examples

```yaml
# k8s/deployment.yaml - Manual deployment alternative

apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-worker
  namespace: pggit
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webhook-worker
  template:
    metadata:
      labels:
        app: webhook-worker
        version: v1
    spec:
      serviceAccountName: webhook-worker
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      containers:
      - name: webhook-worker
        image: gcr.io/your-org/webhook-worker:1.0.0
        imagePullPolicy: IfNotPresent

        ports:
        - name: metrics
          containerPort: 8000
          protocol: TCP

        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: pggit-secrets
              key: database_url
        - name: WORKER_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: BATCH_SIZE
          value: "10"
        - name: LOG_LEVEL
          value: "info"

        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"

        # Liveness probe - restart if failed
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        # Readiness probe - traffic only if ready
        readinessProbe:
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2

        # Security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL

        volumeMounts:
        - name: tmp
          mountPath: /tmp

      volumes:
      - name: tmp
        emptyDir: {}

      # Pod Disruption Budget for high availability
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - webhook-worker
              topologyKey: kubernetes.io/hostname

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: webhook-worker-pdb
  namespace: pggit
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: webhook-worker

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webhook-worker-hpa
  namespace: pggit
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webhook-worker
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 1
        periodSeconds: 15
      selectPolicy: Max
```

---

## Production Environment Setup

### 1. PostgreSQL Configuration

```sql
-- Production PostgreSQL settings

-- Connection pooling (use PgBouncer)
-- pgbouncer.ini
[databases]
pggit = host=postgres.rds.amazonaws.com port=5432 dbname=pggit

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3

-- PostgreSQL tuning for pggit
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Enable WAL archiving for backup
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET wal_keep_segments = 64;

SELECT pg_reload_conf();

-- Create read replica for monitoring queries
-- (doesn't impact write performance)
```

### 2. Environment Variables

```bash
# .env.production

# Database
DATABASE_URL=postgresql://user:pass@postgres.prod:5432/pggit
DB_POOL_MIN=5
DB_POOL_MAX=25
DB_CONNECT_TIMEOUT=10

# Worker configuration
WORKER_ID=worker-${HOSTNAME}
BATCH_SIZE=20  # Increase for production
POLL_INTERVAL=0.5  # More frequent polling
HTTP_TIMEOUT=5.0
MAX_RETRIES=3

# Security
HTTPS_ONLY=true
TLS_MIN_VERSION=1.2
ENCRYPTION_MASTER_KEY=${VAULT_ENCRYPTION_KEY}
WEBHOOK_SIGNING_SECRET=${VAULT_SIGNING_SECRET}

# Rate limiting
RATE_LIMIT_GLOBAL_RPS=1000
RATE_LIMIT_PER_REQUESTER_RPS=100
REDIS_URL=redis://redis.prod:6379/0

# Monitoring
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=8000
LOG_LEVEL=info

# Sentry error tracking (optional)
SENTRY_DSN=${VAULT_SENTRY_DSN}

# Datadog APM (optional)
DD_ENABLED=true
DD_AGENT_HOST=datadog-agent.monitoring
DD_AGENT_PORT=8126
```

### 3. Secrets Management

```bash
# Using HashiCorp Vault

# 1. Create secrets
vault kv put secret/pggit/production \
  database_url="postgresql://..." \
  encryption_key="$(openssl rand -base64 32)" \
  signing_secret="$(openssl rand -base64 32)" \
  jwt_secret="$(openssl rand -base64 32)"

# 2. Create Kubernetes secret from Vault
kubectl create secret generic pggit-secrets \
  --from-literal=database_url="$(vault kv get -field=database_url secret/pggit/production)" \
  --from-literal=encryption_key="$(vault kv get -field=encryption_key secret/pggit/production)"

# 3. Rotate secrets (monthly)
vault kv put secret/pggit/production \
  database_url="postgresql://..." \
  encryption_key="$(openssl rand -base64 32)" \
  signing_secret="$(openssl rand -base64 32)"

kubectl delete secret pggit-secrets
kubectl create secret generic pggit-secrets \
  --from-literal=encryption_key="..."
```

---

## Database Migration & Backup

### 1. Schema Migration

```bash
# Apply production schema
psql -h postgres.prod -U admin -d pggit \
  < sql/v1.0.0/phase8_week2_postgres_schema.sql

# Verify tables created
psql -h postgres.prod -U admin -d pggit \
  -c "SELECT tablename FROM pg_tables WHERE schemaname='pggit';"
```

### 2. Backup Strategy

```bash
# Daily backups to S3
#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="pggit_backup_${TIMESTAMP}.sql.gz"

# Backup
pg_dump --host=postgres.prod --username=admin --format=custom \
  pggit | gzip > /tmp/${BACKUP_FILE}

# Upload to S3
aws s3 cp /tmp/${BACKUP_FILE} s3://pggit-backups/daily/

# Keep local copy for quick restore
cp /tmp/${BACKUP_FILE} /backups/local/

# Clean old files (keep 30 days)
find /backups/local -name "*.gz" -mtime +30 -delete

# Cleanup temp
rm /tmp/${BACKUP_FILE}
```

### 3. Point-in-Time Recovery (PITR)

```sql
-- Enable PITR
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'test ! -f /mnt/server/archivedir/%f && cp %p /mnt/server/archivedir/%f';

-- Test restore from backup
pg_restore --host=recovery.server --username=admin --dbname=pggit \
  --verbose /tmp/pggit_backup_20240101_000000.sql.gz
```

---

## Scaling Guidelines

### Horizontal Scaling

```yaml
# Scale webhook workers based on queue depth

# Metrics to monitor:
# - Queue depth (alert if > 1000)
# - Success rate (alert if < 99%)
# - P99 latency (alert if > 2s)

# Scale up if:
# - Queue depth > 500
# - CPU > 80%
# - Memory > 85%

# Scale down if:
# - Queue depth < 100
# - CPU < 30%
# - Memory < 40%

# Recommended scaling:
# 3 replicas: < 100 deliveries/sec
# 5 replicas: 100-500 deliveries/sec
# 10 replicas: 500-1000 deliveries/sec
# 20+ replicas: > 1000 deliveries/sec
```

### Database Scaling

```sql
-- Monitor database performance
SELECT
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_time DESC
LIMIT 10;

-- Identify slow queries
EXPLAIN ANALYZE
SELECT * FROM pggit.get_ready_deliveries(100);

-- Create indexes if needed
CREATE INDEX idx_delivery_queue_status_created
ON pggit.alert_delivery_queue(delivery_status, created_at);
```

---

## Monitoring & Alerts

### Prometheus Alert Rules

```yaml
# k8s/prometheus-rules.yaml

groups:
- name: webhook_delivery
  interval: 30s
  rules:
    # High failure rate
    - alert: HighWebhookFailureRate
      expr: |
        (sum(rate(webhook_deliveries_total{status="failed"}[5m])) /
         sum(rate(webhook_deliveries_total[5m]))) > 0.05
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High webhook failure rate (>5%)"
        description: "Current failure rate: {{ $value | humanizePercentage }}"

    # Queue backlog
    - alert: QueueBacklogHigh
      expr: webhook_queue_depth > 1000
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Webhook queue backlog"
        description: "{{ $value }} deliveries pending"

    # Worker down
    - alert: WebhookWorkerDown
      expr: worker_health_status == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Webhook worker down"
        description: "Worker {{ $labels.worker_id }} not responding"

    # Circuit breaker opens
    - alert: CircuitBreakerOpen
      expr: increase(circuit_breaker_opens_total[1h]) > 0
      labels:
        severity: warning
      annotations:
        summary: "Circuit breaker opened for webhook {{ $labels.webhook_id }}"
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Webhook Delivery Production",
    "panels": [
      {
        "title": "Delivery Rate",
        "targets": [
          {
            "expr": "rate(webhook_deliveries_total[5m])"
          }
        ]
      },
      {
        "title": "Success Rate",
        "targets": [
          {
            "expr": "sum(rate(webhook_deliveries_total{status=\"delivered\"}[5m])) / sum(rate(webhook_deliveries_total[5m]))"
          }
        ]
      },
      {
        "title": "Queue Depth",
        "targets": [
          {
            "expr": "webhook_queue_depth"
          }
        ]
      },
      {
        "title": "Worker Health",
        "targets": [
          {
            "expr": "worker_health_status"
          }
        ]
      }
    ]
  }
}
```

---

## Troubleshooting

### Common Issues

#### 1. High Queue Depth

```sql
-- Check what's backed up
SELECT delivery_status, COUNT(*) as count,
       MIN(created_at) as oldest
FROM pggit.alert_delivery_queue
GROUP BY delivery_status
ORDER BY count DESC;

-- Check degraded webhooks
SELECT * FROM pggit.v_degraded_webhooks
ORDER BY consecutive_failures DESC;

-- Solution: Scale up workers
kubectl scale deployment webhook-worker --replicas=10 -n pggit
```

#### 2. Database Connection Issues

```bash
# Check connection pool
psql -h postgres.prod -U admin -d pggit \
  -c "SELECT count(*) as connections FROM pg_stat_activity;"

# Increase pool size if needed
# Edit docker-compose or K8s config and redeploy

# Check database health
psql -h postgres.prod -U admin -d pggit \
  -c "SELECT version();"
```

#### 3. Worker OOM (Out of Memory)

```bash
# Check memory usage
kubectl top pods -n pggit

# Increase memory limits
kubectl set resources deployment webhook-worker \
  --limits=memory=2Gi -n pggit

# Restart pods to pick up new limits
kubectl rollout restart deployment/webhook-worker -n pggit
```

---

## Rollback Procedure

```bash
# If deployment fails:

# 1. Check current state
kubectl get deployment webhook-worker -n pggit
kubectl rollout history deployment/webhook-worker -n pggit

# 2. Rollback to previous version
kubectl rollout undo deployment/webhook-worker -n pggit

# 3. Verify rollback
kubectl get pods -n pggit
kubectl logs -l app=webhook-worker -n pggit --tail=20

# 4. Investigate failure
kubectl describe pod <pod-name> -n pggit
```

---

## Post-Deployment Validation

```bash
#!/bin/bash

echo "=== Post-Deployment Validation ==="

# 1. Check pod status
echo "Checking pod status..."
kubectl get pods -n pggit

# 2. Verify connectivity
echo "Verifying database connectivity..."
kubectl exec -it deployment/webhook-worker -n pggit \
  -- psql -h postgres.prod -U admin -d pggit -c "SELECT version();"

# 3. Check metrics
echo "Checking Prometheus metrics..."
curl http://prometheus.monitoring:9090/api/v1/query?query=webhook_deliveries_total

# 4. Load test
echo "Running load test..."
for i in {1..100}; do
  psql -h postgres.prod -U admin -d pggit -c \
    "INSERT INTO pggit.alert_delivery_queue (...) VALUES (...);"
done

# 5. Monitor queue
echo "Monitoring queue processing..."
watch 'psql -h postgres.prod -U admin -d pggit \
  -c "SELECT delivery_status, COUNT(*) FROM pggit.alert_delivery_queue GROUP BY delivery_status;"'
```

---

## References

- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/
- **PostgreSQL High Availability**: https://wiki.postgresql.org/wiki/High_Availability,_Load_Balancing,_and_Replication
- **Helm**: https://helm.sh/docs/
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator

