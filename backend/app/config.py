from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-driven configuration. Reads from process env, then `.env`."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App
    environment: str = "local"
    log_level: str = "INFO"
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])
    auto_create_tables: bool = True

    # Auth
    jwt_secret: str = "dev-only-change-me"
    jwt_algorithm: str = "HS256"
    access_token_ttl_minutes: int = 60 * 24 * 7

    # Database
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/ai_receipt"

    # Azure OpenAI
    azure_openai_endpoint: str = ""
    azure_openai_api_key: str = ""
    azure_openai_api_version: str = "2025-04-01-preview"
    azure_openai_deployment: str = "gpt-5-mini"

    # Azure Blob Storage
    azure_storage_connection_string: str = ""
    azure_storage_container: str = "receipts"

    # Monitoring
    applicationinsights_connection_string: str = ""

    @property
    def azure_openai_configured(self) -> bool:
        return bool(self.azure_openai_endpoint and self.azure_openai_api_key)

    @property
    def blob_configured(self) -> bool:
        return bool(self.azure_storage_connection_string)


@lru_cache
def get_settings() -> Settings:
    return Settings()
