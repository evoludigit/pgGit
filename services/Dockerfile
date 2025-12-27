# ============================================================================
# Dockerfile: Webhook Delivery Worker
# ============================================================================
# Purpose: Production-ready container image for external webhook worker
# Base: Python 3.12 slim (lightweight, security updates)
# ============================================================================

FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Install system dependencies (minimal for security)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (for Docker layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY webhook_worker.py .

# Create non-root user for security
RUN useradd -m -u 1000 worker && chown -R worker:worker /app
USER worker

# Health check: can we connect to metrics endpoint?
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import socket; socket.create_connection(('localhost', 8000), timeout=2)" || exit 1

# Expose Prometheus metrics port
EXPOSE 8000

# Run worker
CMD ["python", "webhook_worker.py"]
