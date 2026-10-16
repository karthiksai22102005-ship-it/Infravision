from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class ConfigError(RuntimeError):
    """Raised when the service cannot start with its current configuration."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # SQL Server in production, e.g.
    # mssql+pyodbc://USER:PASS@HOST,1433/DB?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes
    database_url: str = "sqlite:///./citizen_dev.db"
    jwt_secret: str = "CHANGE_ME"
    jwt_minutes: int = 60 * 24
    db_schema: str = "dbo"
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_connect_timeout_s: int = 10
    evidence_dir: str = "./evidence_store"
    max_evidence_bytes: int = 8 * 1024 * 1024
    max_evidence_per_complaint: int = 7
    max_video_evidence_bytes: int = 50 * 1024 * 1024
    inspector_api_key: str = "CHANGE_ME_INSPECTOR"
    environment: str = "development"
    ai_api_key: str | None = None
    ai_provider: str = "openai-compatible"
    ai_base_url: str | None = None
    ai_model: str | None = None

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")

    def inspector_key_map(self) -> dict[str, str]:
        # Keep the existing single-key contract and give it a stable principal name.
        key = self.inspector_api_key.strip()
        return {"default": key} if key else {}


def enforce_settings(settings: Settings) -> None:
    """Validate required service settings without exposing configured secrets."""
    if not settings.database_url.strip():
        raise ConfigError("DATABASE_URL is not set")
    if len(settings.jwt_secret) < 32:
        raise ConfigError("JWT_SECRET must contain at least 32 characters")
    if settings.environment.lower() == "production":
        if settings.jwt_secret == "CHANGE_ME" or settings.inspector_api_key == "CHANGE_ME_INSPECTOR":
            raise ConfigError("Production secrets must be changed from their development defaults")
        if settings.is_sqlite:
            raise ConfigError("Production DATABASE_URL must use a server database")


@lru_cache
def get_settings() -> Settings:
    return Settings()
