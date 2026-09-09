import os
from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-driven configuration. Reads from process env, then `.env`
    (the `.env` file is skipped under tests so they stay hermetic)."""

    model_config = SettingsConfigDict(
        env_file=None if os.getenv("AI_RECEIPT_TEST") else ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # App
    environment: str = "local"
    log_level: str = "INFO"
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])
    auto_create_tables: bool = True

    # Auth — Auth0 (issues the access tokens; we verify them via JWKS)
    auth0_domain: str = ""  # e.g. your-tenant.us.auth0.com
    auth0_audience: str = ""  # the Auth0 API identifier for this backend

    # Anonymous (not-signed-in) extraction: free scans per device before sign-in.
    anon_scan_limit: int = 15

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

    @property
    def auth_configured(self) -> bool:
        return bool(self.auth0_domain and self.auth0_audience)

    @property
    def auth0_issuer(self) -> str:
        return f"https://{self.auth0_domain}/"

    @property
    def auth0_jwks_url(self) -> str:
        return f"https://{self.auth0_domain}/.well-known/jwks.json"

    @property
    def auth0_userinfo_url(self) -> str:
        return f"https://{self.auth0_domain}/userinfo"


@lru_cache
def get_settings() -> Settings:
    return Settings()
