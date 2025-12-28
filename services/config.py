"""
Phase 8 Configuration Management
================================

Handles all application configuration from environment variables.
CRITICAL FIX #1: Moves hardcoded secrets to environment variables.

Security Notes:
- All secrets are loaded from environment variables only
- No secrets should appear in code or logs
- Configuration is read-only after application startup
- Secrets should be injected via CI/CD pipeline
"""

import os
from functools import lru_cache
from typing import Literal
from dataclasses import dataclass
from pathlib import Path


@dataclass
class DatabaseConfig:
    """Database connection configuration"""
    host: str
    port: int
    database: str
    user: str
    password: str

    @property
    def url(self) -> str:
        """PostgreSQL connection URL"""
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}"


@dataclass
class JWTConfig:
    """JWT authentication configuration"""
    secret_key: str
    algorithm: str
    expire_minutes: int


@dataclass
class WebhookConfig:
    """Webhook security configuration"""
    encryption_key: str  # 32-character hex string
    signing_secret: str


@dataclass
class RedisConfig:
    """Redis cache configuration"""
    host: str
    port: int
    password: str | None

    @property
    def url(self) -> str:
        """Redis connection URL"""
        if self.password:
            return f"redis://:{self.password}@{self.host}:{self.port}"
        return f"redis://{self.host}:{self.port}"


@dataclass
class CacheConfig:
    """Cache layer configuration"""
    type: Literal["in-memory", "redis", "hybrid"]
    max_size_memory: int  # Max items in memory cache
    ttl_seconds: int
    redis_url: str | None = None


@dataclass
class APIConfig:
    """API server configuration"""
    host: str
    port: int
    workers: int
    log_level: str


@dataclass
class ReplicationConfig:
    """Multi-region replication configuration"""
    enabled: bool
    primary_database_url: str | None
    replica_enabled_regions: list[str]


@dataclass
class TLSConfig:
    """TLS/SSL configuration"""
    enabled: bool
    cert_path: str | None
    key_path: str | None
    ca_path: str | None


@dataclass
class CORSConfig:
    """CORS configuration"""
    origins: list[str]
    allow_credentials: bool = True
    allow_methods: list[str] | None = None
    allow_headers: list[str] | None = None

    def __post_init__(self):
        if self.allow_methods is None:
            self.allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
        if self.allow_headers is None:
            self.allow_headers = ["*"]


@dataclass
class FeatureFlagsConfig:
    """Feature flags for Phase 8 enhancements"""
    enable_websocket: bool
    enable_multi_region: bool
    enable_ml_predictions: bool


class Settings:
    """
    Application settings loaded from environment variables.
    All configuration is loaded at startup and cached.
    """

    def __init__(self):
        """Load all configuration from environment"""
        # Load environment first (used by other loaders)
        self.environment = os.getenv("ENVIRONMENT", "production")

        self._load_database()
        self._load_jwt()
        self._load_webhook()
        self._load_redis()
        self._load_cache()
        self._load_api()
        self._load_replication()
        self._load_tls()
        self._load_cors()
        self._load_feature_flags()

    def _load_database(self):
        """Load database configuration"""
        # Allow empty password for local development/testing with trust auth
        password = os.getenv("DATABASE_PASSWORD", "")
        if not password and os.getenv("ENVIRONMENT") not in ("test", "development"):
            raise ValueError("DATABASE_PASSWORD is required in production environments")

        self.database = DatabaseConfig(
            host=os.getenv("DATABASE_HOST", "localhost"),
            port=int(os.getenv("DATABASE_PORT", "5432")),
            database=os.getenv("DATABASE_NAME", "pggit"),
            user=os.getenv("DATABASE_USER", "postgres"),
            password=password,
        )

    def _load_jwt(self):
        """Load JWT configuration"""
        self.jwt = JWTConfig(
            secret_key=self._require_env("JWT_SECRET_KEY", "JWT secret key"),
            algorithm=os.getenv("JWT_ALGORITHM", "HS256"),
            expire_minutes=int(os.getenv("JWT_EXPIRE_MINUTES", "1440")),
        )

    def _load_webhook(self):
        """Load webhook security configuration"""
        encryption_key = self._require_env("WEBHOOK_ENCRYPTION_KEY", "Webhook encryption key")
        signing_secret = self._require_env("WEBHOOK_SIGNING_SECRET", "Webhook signing secret")

        # Validate encryption key length (should be 32 chars for AES-256)
        if len(encryption_key) != 32:
            raise ValueError(
                f"WEBHOOK_ENCRYPTION_KEY must be exactly 32 characters (hex), got {len(encryption_key)}"
            )

        self.webhook = WebhookConfig(
            encryption_key=encryption_key,
            signing_secret=signing_secret,
        )

    def _load_redis(self):
        """Load Redis configuration"""
        self.redis = RedisConfig(
            host=os.getenv("REDIS_HOST", "localhost"),
            port=int(os.getenv("REDIS_PORT", "6379")),
            password=os.getenv("REDIS_PASSWORD"),
        )

    def _load_cache(self):
        """Load cache configuration"""
        self.cache = CacheConfig(
            type=os.getenv("CACHE_TYPE", "hybrid"),
            max_size_memory=int(os.getenv("CACHE_MAX_SIZE_MEMORY", "10000")),
            ttl_seconds=int(os.getenv("CACHE_TTL_SECONDS", "60")),
            redis_url=os.getenv("CACHE_REDIS_URL", self.redis.url),
        )

    def _load_api(self):
        """Load API configuration"""
        self.api = APIConfig(
            host=os.getenv("API_HOST", "0.0.0.0"),
            port=int(os.getenv("API_PORT", "8080")),
            workers=int(os.getenv("API_WORKERS", "4")),
            log_level=os.getenv("LOG_LEVEL", "INFO"),
        )

    def _load_replication(self):
        """Load replication configuration"""
        replica_regions = os.getenv("REPLICA_ENABLED_REGIONS", "")
        self.replication = ReplicationConfig(
            enabled=os.getenv("REPLICATION_ENABLED", "false").lower() == "true",
            primary_database_url=os.getenv("PRIMARY_DATABASE_URL"),
            replica_enabled_regions=replica_regions.split(",") if replica_regions else [],
        )

    def _load_tls(self):
        """Load TLS configuration"""
        enabled = os.getenv("TLS_ENABLED", "false").lower() == "true"
        self.tls = TLSConfig(
            enabled=enabled,
            cert_path=os.getenv("TLS_CERT_PATH") if enabled else None,
            key_path=os.getenv("TLS_KEY_PATH") if enabled else None,
            ca_path=os.getenv("TLS_CA_PATH") if enabled else None,
        )

    def _load_cors(self):
        """Load CORS configuration"""
        origins = os.getenv("CORS_ORIGINS", "")
        self.cors = CORSConfig(
            origins=origins.split(",") if origins else [],
        )

    def _load_feature_flags(self):
        """Load feature flags"""
        self.features = FeatureFlagsConfig(
            enable_websocket=os.getenv("ENABLE_WEBSOCKET", "true").lower() == "true",
            enable_multi_region=os.getenv("ENABLE_MULTI_REGION", "false").lower() == "true",
            enable_ml_predictions=os.getenv("ENABLE_ML_PREDICTIONS", "true").lower() == "true",
        )

    @staticmethod
    def _require_env(var_name: str, description: str) -> str:
        """
        Get required environment variable.

        Args:
            var_name: Environment variable name
            description: Human-readable description for error message

        Returns:
            Environment variable value

        Raises:
            ValueError: If environment variable is not set
        """
        value = os.getenv(var_name)
        if not value:
            raise ValueError(f"Missing required environment variable: {var_name} ({description})")
        return value

    def validate(self) -> bool:
        """
        Validate all configuration is properly set.
        Called at application startup.
        """
        # Check database connectivity is possible (basic validation)
        # Allow empty password in test/development for trust auth
        if not self.database.password and os.getenv("ENVIRONMENT") not in ("test", "development"):
            raise ValueError("Database password not set in production environment")

        # Check JWT secret is strong enough
        if len(self.jwt.secret_key) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters")

        # Check webhook encryption key format
        try:
            bytes.fromhex(self.webhook.encryption_key)
        except ValueError:
            raise ValueError("WEBHOOK_ENCRYPTION_KEY must be a valid hex string")

        # Check cache configuration
        if self.cache.type == "redis" and not self.cache.redis_url:
            raise ValueError("Redis URL required for Redis cache type")

        if self.cache.max_size_memory <= 0:
            raise ValueError("CACHE_MAX_SIZE_MEMORY must be positive")

        return True


# Global settings instance
@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """
    Get application settings.
    Settings are loaded once and cached for the lifetime of the application.

    Returns:
        Cached Settings instance

    Raises:
        ValueError: If any required configuration is missing or invalid
    """
    settings = Settings()
    settings.validate()
    return settings


# For testing: allow override
def get_test_settings(**overrides) -> Settings:
    """
    Create settings instance for testing with overrides.

    Args:
        **overrides: Configuration values to override (dot-notation supported)

    Returns:
        Settings instance with overridden values
    """
    # Set required env vars for testing if not present
    required_vars = {
        "DATABASE_PASSWORD": "test-password",
        "JWT_SECRET_KEY": "test-secret-key-at-least-32-chars!!",
        "WEBHOOK_ENCRYPTION_KEY": "a" * 32,  # 32 hex chars
        "WEBHOOK_SIGNING_SECRET": "test-signing-secret",
    }

    for var, default in required_vars.items():
        if var not in os.environ:
            os.environ[var] = default

    return Settings()
