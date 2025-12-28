# ============================================================================
# Dockerfile: PGGIT FastAPI Application
# ============================================================================
# Purpose: Production-ready container image for PGGIT API
# Base: Python 3.12 slim (lightweight, security updates)
# Features:
#   - Multi-stage build for minimal image size
#   - Non-root user for security
#   - Health checks for orchestration
#   - Optimized layer caching
# ============================================================================

# ============================================================================
# Stage 1: Builder - Install dependencies
# ============================================================================
FROM python:3.12-slim AS builder

WORKDIR /app

# Install system dependencies for building Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install uv package manager
RUN pip install --no-cache-dir uv

# Create virtual environment and install dependencies
RUN uv venv /app/.venv && \
    /app/.venv/bin/pip install --no-cache-dir -e ".[api,dev]"

# ============================================================================
# Stage 2: Runtime - Final lightweight image
# ============================================================================
FROM python:3.12-slim

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY api/ /app/api/
COPY services/ /app/services/
COPY src/ /app/src/

# Create non-root user for security
RUN useradd -m -u 1000 pggit && \
    chown -R pggit:pggit /app

USER pggit

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Health check: API /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=5)" || exit 1

# Expose API port
EXPOSE 8000

# Run FastAPI application
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
