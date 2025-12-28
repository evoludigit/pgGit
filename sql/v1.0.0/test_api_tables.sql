-- Minimal API tables for integration testing
-- These are simplified versions without complex constraints

CREATE SCHEMA IF NOT EXISTS pggit;

-- Webhooks table for API testing
CREATE TABLE IF NOT EXISTS pggit.webhooks (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    events TEXT[] DEFAULT ARRAY['*'],
    active BOOLEAN DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Webhook health metrics for API testing
CREATE TABLE IF NOT EXISTS pggit.webhook_health_metrics (
    webhook_id INTEGER PRIMARY KEY REFERENCES pggit.webhooks(id) ON DELETE CASCADE,
    health_status TEXT DEFAULT 'UNKNOWN',
    total_deliveries INTEGER DEFAULT 0,
    successful_deliveries INTEGER DEFAULT 0,
    last_delivery_at TIMESTAMP,
    last_failure_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Alerts table for API testing
CREATE TABLE IF NOT EXISTS pggit.alerts (
    id SERIAL PRIMARY KEY,
    alert_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_at TIMESTAMP,
    acknowledged_by TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_webhooks_active ON pggit.webhooks(active);
CREATE INDEX IF NOT EXISTS idx_alerts_acknowledged ON pggit.alerts(acknowledged);
CREATE INDEX IF NOT EXISTS idx_alerts_created_at ON pggit.alerts(created_at DESC);
