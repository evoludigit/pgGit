# Phase 8 Week 2C: Security Hardening for Webhook Delivery

## Overview

This document covers security hardening for the webhook delivery system:
- **Transport Security**: HTTPS-only delivery with certificate pinning
- **Request Integrity**: HMAC-SHA256 request signatures
- **Data Protection**: AES-256-GCM URL and secret encryption
- **Access Control**: Bearer token authentication
- **Compliance**: Rate limiting, audit logging, secrets rotation

## 1. Transport Security (HTTPS)

### 1.1 Webhook URL Validation

All webhook URLs must comply with security requirements:

```python
# In webhook_worker.py - Enhanced validation
from urllib.parse import urlparse
import ipaddress

def validate_webhook_url(url: str) -> bool:
    """Validate webhook URL for security compliance"""

    try:
        parsed = urlparse(url)

        # Rule 1: HTTPS-only (no http://)
        if parsed.scheme != 'https':
            raise ValueError("Webhook URLs must use HTTPS protocol")

        # Rule 2: No localhost or private IPs (SSRF protection)
        hostname = parsed.hostname
        if not hostname:
            raise ValueError("Invalid URL: missing hostname")

        # Resolve to IP and check for private ranges
        try:
            ip = ipaddress.ip_address(hostname)
            if ip.is_private or ip.is_loopback:
                raise ValueError(f"Webhook cannot target private/loopback IP: {ip}")
        except ValueError as e:
            if "does not appear to be an IPv4 or IPv6 address" in str(e):
                # Hostname (DNS) - acceptable
                pass
            else:
                raise

        # Rule 3: Port must be 443 (HTTPS default)
        if parsed.port and parsed.port != 443:
            raise ValueError("Webhook HTTPS must use port 443")

        # Rule 4: No authentication in URL
        if parsed.username or parsed.password:
            raise ValueError("Do not embed credentials in webhook URLs")

        return True

    except Exception as e:
        logger.warning(f"URL validation failed: {url} - {e}")
        return False

# Usage in webhook delivery
async def send_webhook(delivery_id: int, webhook_url: str, payload: dict):
    if not validate_webhook_url(webhook_url):
        raise ValueError(f"Invalid webhook URL: {webhook_url}")

    # Continue with delivery...
```

### 1.2 HTTPS Configuration

```yaml
# docker-compose.yml updates for production
services:
  webhook-worker-1:
    environment:
      # Enable HTTPS enforcement
      HTTPS_ONLY: "true"

      # Certificate pinning (optional, for critical webhooks)
      CERT_PIN_HASHES: "sha256/..."

      # Minimum TLS version
      TLS_MIN_VERSION: "1.2"
```

### 1.3 Certificate Pinning (Optional)

For critical webhook endpoints, implement certificate pinning:

```python
import ssl
import certifi

async def create_ssl_context():
    """Create SSL context with certificate pinning"""

    context = ssl.create_default_context(cafile=certifi.where())
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_3

    # Add certificate pinning for critical endpoints
    # Pinned SHA-256 hashes of expected certificates
    PINNED_CERTS = {
        'api.critical-webhook.com': {
            'pins': ['sha256/abcd1234...', 'sha256/efgh5678...'],
            'backup_pins': ['sha256/ijkl9012...']
        }
    }

    return context, PINNED_CERTS

# Usage in aiohttp session
async def send_webhook_with_pinning(url: str, payload: dict):
    ssl_context, pinned_certs = await create_ssl_context()

    async with aiohttp.ClientSession(connector=aiohttp.TCPConnector(
        ssl=ssl_context
    )) as session:
        async with session.post(url, json=payload) as resp:
            return await resp.json()
```

## 2. Request Signing (HMAC-SHA256)

### 2.1 Database Schema for Signing

Add to Phase 8 schema:

```sql
-- Enhanced webhook_health_metrics with signing keys
ALTER TABLE pggit.webhook_health_metrics ADD COLUMN (
    signing_key_id BIGINT,
    signing_key_hash TEXT,  -- SHA256(signing_key), never store plaintext
    signature_algorithm TEXT DEFAULT 'hmac-sha256'
);

-- Table for webhook signing credentials (encrypted in database)
CREATE TABLE IF NOT EXISTS pggit.webhook_signing_keys (
    key_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),

    -- Encrypted key material (AES-256-GCM)
    encrypted_key_material BYTEA NOT NULL,
    key_hash TEXT NOT NULL,  -- SHA256 of plaintext key for verification

    -- Key rotation tracking
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rotated_at TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,

    -- Audit trail
    created_by TEXT,
    rotation_reason TEXT,

    CONSTRAINT valid_key_length CHECK (octet_length(encrypted_key_material) > 0),
    CONSTRAINT unique_active_key UNIQUE (webhook_id) WHERE is_active = TRUE
);

CREATE INDEX idx_webhook_signing_keys ON pggit.webhook_signing_keys(webhook_id, is_active);
```

### 2.2 Signature Generation and Verification

```python
import hmac
import hashlib
import json
from datetime import datetime

class WebhookSigner:
    """HMAC-SHA256 request signer"""

    @staticmethod
    def create_signature(payload: dict, secret_key: str) -> str:
        """Create HMAC-SHA256 signature for webhook payload"""

        # Serialize payload deterministically
        payload_json = json.dumps(payload, sort_keys=True, separators=(',', ':'))

        # Create HMAC-SHA256 signature
        signature = hmac.new(
            secret_key.encode(),
            payload_json.encode(),
            hashlib.sha256
        ).hexdigest()

        return signature

    @staticmethod
    def verify_signature(payload: dict, signature: str, secret_key: str) -> bool:
        """Verify webhook signature (for receiving webhooks from pgGit)"""

        expected_signature = WebhookSigner.create_signature(payload, secret_key)

        # Constant-time comparison to prevent timing attacks
        return hmac.compare_digest(expected_signature, signature)

    @staticmethod
    def create_signed_delivery_header(payload: dict, secret_key: str) -> dict:
        """Create complete signature header for webhook delivery"""

        timestamp = datetime.utcnow().isoformat() + 'Z'
        signature = WebhookSigner.create_signature(payload, secret_key)

        return {
            'X-pgGit-Timestamp': timestamp,
            'X-pgGit-Signature': f'sha256={signature}',
            'X-pgGit-Delivery-ID': str(uuid4())
        }

# Usage in webhook_worker.py
async def deliver_webhook_with_signature(
    delivery_id: int,
    webhook_url: str,
    payload: dict,
    signing_key: str
):
    """Deliver webhook with HMAC-SHA256 signature"""

    headers = WebhookSigner.create_signed_delivery_header(payload, signing_key)

    async with aiohttp.ClientSession() as session:
        async with session.post(
            webhook_url,
            json=payload,
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=5.0)
        ) as resp:
            return resp.status
```

### 2.3 Signature Verification (For Recipients)

```python
# Example code for webhook recipients to verify signatures
def verify_pgGit_webhook(request_body: bytes, request_headers: dict, secret_key: str) -> bool:
    """
    Verify webhook signature from pgGit

    Usage:
        @app.post('/webhooks/pggit')
        async def receive_pggit_webhook(request):
            body = await request.body()
            headers = request.headers

            if not verify_pgGit_webhook(body, headers, PGGIT_SECRET_KEY):
                return Response(status=401, text='Signature verification failed')

            # Process webhook...
            return Response(status=200)
    """

    signature_header = request_headers.get('X-pgGit-Signature', '')
    timestamp_header = request_headers.get('X-pgGit-Timestamp', '')

    if not signature_header or not timestamp_header:
        return False

    # Verify timestamp is recent (prevent replay attacks)
    try:
        timestamp = datetime.fromisoformat(timestamp_header.replace('Z', '+00:00'))
        age_seconds = (datetime.now(timezone.utc) - timestamp).total_seconds()

        if abs(age_seconds) > 300:  # 5 minute window
            logger.warning(f"Webhook timestamp too old: {age_seconds}s")
            return False
    except ValueError:
        return False

    # Parse expected signature
    if not signature_header.startswith('sha256='):
        return False

    expected_signature = signature_header[7:]  # Remove 'sha256=' prefix

    # Calculate actual signature
    payload_json = json.dumps(json.loads(request_body), sort_keys=True)
    actual_signature = hmac.new(
        secret_key.encode(),
        payload_json.encode(),
        hashlib.sha256
    ).hexdigest()

    # Constant-time comparison
    return hmac.compare_digest(expected_signature, actual_signature)
```

## 3. Data Encryption (AES-256-GCM)

### 3.1 Webhook URL Encryption in Database

```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2
import os
import base64

class WebhookEncryption:
    """AES-256-GCM encryption for webhook URLs and secrets"""

    @staticmethod
    def derive_key(master_key: str, salt: bytes) -> bytes:
        """Derive encryption key from master key + salt"""

        kdf = PBKDF2(
            algorithm=hashes.SHA256(),
            length=32,  # 256-bit key for AES-256
            salt=salt,
            iterations=100000
        )

        return kdf.derive(master_key.encode())

    @staticmethod
    def encrypt_webhook_url(url: str, master_key: str) -> dict:
        """Encrypt webhook URL for storage"""

        # Generate random salt and nonce
        salt = os.urandom(16)
        nonce = os.urandom(12)

        # Derive encryption key
        key = WebhookEncryption.derive_key(master_key, salt)

        # Encrypt with AES-256-GCM
        cipher = AESGCM(key)
        ciphertext = cipher.encrypt(nonce, url.encode(), None)

        # Return all components needed for decryption
        return {
            'salt': base64.b64encode(salt).decode(),
            'nonce': base64.b64encode(nonce).decode(),
            'ciphertext': base64.b64encode(ciphertext).decode(),
            'algorithm': 'aes-256-gcm'
        }

    @staticmethod
    def decrypt_webhook_url(encrypted_data: dict, master_key: str) -> str:
        """Decrypt webhook URL from storage"""

        try:
            salt = base64.b64decode(encrypted_data['salt'])
            nonce = base64.b64decode(encrypted_data['nonce'])
            ciphertext = base64.b64decode(encrypted_data['ciphertext'])

            # Derive same key
            key = WebhookEncryption.derive_key(master_key, salt)

            # Decrypt
            cipher = AESGCM(key)
            plaintext = cipher.decrypt(nonce, ciphertext, None)

            return plaintext.decode()

        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            raise ValueError("Failed to decrypt webhook URL")

# Database function for encrypted storage
CREATE OR REPLACE FUNCTION pggit.get_webhook_decrypted(
    p_webhook_id BIGINT
) RETURNS TEXT AS $$
DECLARE
    v_master_key TEXT;
    v_encrypted_data JSONB;
BEGIN
    -- Get master key from environment/secrets manager
    v_master_key := current_setting('pggit.encryption_master_key', true);

    IF v_master_key IS NULL THEN
        RAISE EXCEPTION 'Encryption master key not configured';
    END IF;

    -- Get encrypted URL from webhook table
    SELECT encrypted_webhook_url INTO v_encrypted_data
    FROM pggit.webhook_health_metrics
    WHERE webhook_id = p_webhook_id;

    -- Decrypt using Python function (via plpython3u)
    -- For PostgreSQL without plpython, return encrypted data and decrypt in application
    RETURN v_encrypted_data::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## 4. Secret Rotation

### 4.1 Rotation Strategy

```sql
-- Rotate signing keys periodically
CREATE OR REPLACE FUNCTION pggit.rotate_webhook_signing_keys()
RETURNS TABLE (
    webhook_id BIGINT,
    old_key_id BIGINT,
    new_key_id BIGINT,
    rotated_at TIMESTAMP
) AS $$
BEGIN
    -- Mark old active keys as expired
    UPDATE pggit.webhook_signing_keys
    SET
        is_active = FALSE,
        rotated_at = CURRENT_TIMESTAMP,
        rotation_reason = 'Scheduled rotation'
    WHERE
        is_active = TRUE
        AND created_at < CURRENT_TIMESTAMP - INTERVAL '90 days';

    -- Return rotation results
    RETURN QUERY
    SELECT
        webhook_id,
        key_id,
        NULL::BIGINT,  -- new_key_id would be generated by application
        rotated_at
    FROM pggit.webhook_signing_keys
    WHERE rotated_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Schedule rotation (runs daily)
SELECT cron.schedule('rotate-webhook-keys', '0 2 * * *', 'SELECT pggit.rotate_webhook_signing_keys()');
```

### 4.2 Key Derivation for Rotation

```python
import secrets

class KeyRotationManager:
    """Manages webhook signing key rotation"""

    @staticmethod
    def generate_signing_key() -> str:
        """Generate cryptographically strong signing key"""
        return secrets.token_urlsafe(32)  # 256-bit key

    @staticmethod
    def rotate_key(webhook_id: int, db_connection) -> dict:
        """
        Rotate signing key for a webhook

        1. Generate new key
        2. Mark old key as inactive
        3. Store encrypted new key
        4. Keep old key for grace period (7 days)
        """

        new_key = KeyRotationManager.generate_signing_key()

        # Database operations
        async with db_connection.transaction():
            # Deactivate old key
            await db_connection.execute('''
                UPDATE pggit.webhook_signing_keys
                SET is_active = FALSE
                WHERE webhook_id = $1 AND is_active = TRUE
            ''', webhook_id)

            # Create new key
            result = await db_connection.fetchrow('''
                INSERT INTO pggit.webhook_signing_keys (
                    webhook_id, encrypted_key_material, key_hash,
                    created_at, created_by
                ) VALUES ($1, $2, $3, CURRENT_TIMESTAMP, $4)
                RETURNING key_id, created_at
            ''', webhook_id, encrypt(new_key), hash_key(new_key), 'system')

            return {
                'key_id': result['key_id'],
                'rotated_at': result['created_at']
            }
```

## 5. Access Control & Authentication

### 5.1 Bearer Token Authentication

```python
# Add to webhook_worker.py for securing webhook endpoints

class WebhookAuthentication:
    """Bearer token authentication for webhook API"""

    @staticmethod
    def create_bearer_token(webhook_id: int, secret: str) -> str:
        """Create JWT Bearer token for webhook access"""

        import jwt
        from datetime import datetime, timedelta

        payload = {
            'sub': f'webhook:{webhook_id}',
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(days=1),
            'scope': 'webhook:deliver'
        }

        token = jwt.encode(payload, secret, algorithm='HS256')
        return token

    @staticmethod
    def verify_bearer_token(token: str, secret: str) -> bool:
        """Verify JWT Bearer token"""

        try:
            jwt.decode(token, secret, algorithms=['HS256'])
            return True
        except jwt.InvalidTokenError:
            return False
```

### 5.2 Rate Limiting by Authentication

```python
# Enhanced rate limiting per webhook + per requester
async def apply_rate_limit(webhook_id: int, requester_id: str = None) -> bool:
    """
    Rate limit with per-webhook and per-requester tracking

    Limits:
    - Global: 1000 req/sec per webhook
    - Per requester: 100 req/sec per webhook
    """

    # Check global limit for webhook
    global_key = f"webhook:{webhook_id}:ratelimit"
    global_count = await redis.incr(global_key)

    if global_count == 1:
        await redis.expire(global_key, 1)

    if global_count > 1000:
        return False

    # Check per-requester limit if authenticated
    if requester_id:
        requester_key = f"webhook:{webhook_id}:requester:{requester_id}:ratelimit"
        requester_count = await redis.incr(requester_key)

        if requester_count == 1:
            await redis.expire(requester_key, 1)

        if requester_count > 100:
            return False

    return True
```

## 6. Audit Logging

### 6.1 Webhook Delivery Audit Trail

```sql
-- Audit table for webhook operations
CREATE TABLE IF NOT EXISTS pggit.webhook_audit_log (
    audit_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL,
    delivery_id BIGINT,

    -- Operation type
    operation VARCHAR(50),  -- 'delivered', 'failed', 'retried', 'signature_verified'
    status_code INT,
    error_message TEXT,

    -- Security details
    signature_verified BOOLEAN,
    encryption_algorithm TEXT,
    ip_address INET,

    -- Timestamps
    occurred_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Compliance
    user_id TEXT,
    request_id UUID,

    CONSTRAINT valid_operation CHECK (
        operation IN ('delivered', 'failed', 'retried', 'signature_verified',
                     'key_rotated', 'url_decrypted', 'authentication_failed')
    )
);

CREATE INDEX idx_webhook_audit ON pggit.webhook_audit_log(webhook_id, occurred_at DESC);
CREATE INDEX idx_audit_operation ON pggit.webhook_audit_log(operation, occurred_at DESC);

-- Log webhook delivery
CREATE OR REPLACE FUNCTION pggit.log_webhook_delivery(
    p_webhook_id BIGINT,
    p_delivery_id BIGINT,
    p_status_code INT,
    p_signature_verified BOOLEAN DEFAULT FALSE
) RETURNS BIGINT AS $$
BEGIN
    INSERT INTO pggit.webhook_audit_log (
        webhook_id, delivery_id, operation, status_code,
        signature_verified
    ) VALUES (
        p_webhook_id, p_delivery_id,
        CASE WHEN p_status_code >= 200 AND p_status_code < 300 THEN 'delivered' ELSE 'failed' END,
        p_status_code,
        p_signature_verified
    );

    RETURN LASTVAL();
END;
$$ LANGUAGE plpgsql;
```

## 7. Configuration & Environment Variables

### 7.1 Production Environment Setup

```bash
# .env.production - Secure configuration

# Encryption keys (should come from secrets manager)
ENCRYPTION_MASTER_KEY=<from-vault>
WEBHOOK_SIGNING_SECRET=<from-vault>

# Security settings
HTTPS_ONLY=true
MIN_TLS_VERSION=1.2
CERTIFICATE_PIN_HASHES=sha256/...

# Authentication
JWT_SECRET=<from-vault>
BEARER_TOKEN_EXPIRY_HOURS=24

# Rate limiting
RATE_LIMIT_GLOBAL_RPS=1000
RATE_LIMIT_PER_REQUESTER_RPS=100

# Audit & Compliance
AUDIT_LOG_ENABLED=true
AUDIT_LOG_RETENTION_DAYS=365

# Key rotation
KEY_ROTATION_INTERVAL_DAYS=90
KEY_ROTATION_GRACE_PERIOD_DAYS=7
```

## 8. Security Checklist

### Before Production Deployment

- [ ] All webhook URLs validated for HTTPS + no private IPs
- [ ] HMAC-SHA256 signatures implemented and tested
- [ ] AES-256-GCM encryption enabled for URLs and secrets
- [ ] Signing keys generated and stored encrypted
- [ ] Bearer token authentication configured
- [ ] Rate limiting per webhook + per requester
- [ ] Audit logging enabled and tested
- [ ] Key rotation scheduled (90-day interval)
- [ ] TLS 1.2+ enforced (no TLS 1.0/1.1)
- [ ] Secrets manager integrated (Vault/AWS Secrets)
- [ ] Sensitive data never logged in plaintext
- [ ] Certificate pinning implemented for critical endpoints
- [ ] Webhook recipients have verification code
- [ ] All credentials rotated since development
- [ ] Security scanning (OWASP ZAP, Trivy) passed

## 9. Webhook Recipient Integration

### 9.1 Example: Verifying pgGit Webhooks

```python
# Example recipient implementation
from fastapi import FastAPI, Request, Response, HTTPException
import json
import hmac
import hashlib
from datetime import datetime, timezone

app = FastAPI()

PGGIT_WEBHOOK_SECRET = "your-webhook-secret-from-pggit"

def verify_pggit_signature(request_body: bytes, headers: dict) -> bool:
    """Verify webhook signature from pgGit"""

    signature_header = headers.get('X-pgGit-Signature', '')
    timestamp_header = headers.get('X-pgGit-Timestamp', '')

    # Verify timestamp (prevent replay attacks)
    try:
        timestamp = datetime.fromisoformat(timestamp_header.replace('Z', '+00:00'))
        age = (datetime.now(timezone.utc) - timestamp).total_seconds()

        if abs(age) > 300:  # 5 minute window
            return False
    except:
        return False

    # Verify signature
    if not signature_header.startswith('sha256='):
        return False

    expected = signature_header[7:]
    actual = hmac.new(
        PGGIT_WEBHOOK_SECRET.encode(),
        request_body,
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(expected, actual)

@app.post("/webhooks/pggit")
async def receive_pggit_webhook(request: Request):
    body = await request.body()

    if not verify_pggit_signature(body, dict(request.headers)):
        raise HTTPException(status_code=401, detail="Signature verification failed")

    payload = json.loads(body)

    # Process webhook...
    print(f"Received webhook: {payload}")

    return Response(status_code=200)
```

## References

- **OWASP Webhook Security**: https://owasp.org/www-community/attacks/WebhookAttacks
- **HMAC Authentication**: https://developer.github.com/webhooks/securing/
- **AES-256-GCM**: https://csrc.nist.gov/publications/detail/sp/800-38d/final
- **JWT Tokens**: https://tools.ietf.org/html/rfc7519
- **TLS Best Practices**: https://wiki.mozilla.org/Security/Server_Side_TLS

