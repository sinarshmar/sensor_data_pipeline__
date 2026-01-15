"""
Application configuration using Pydantic Settings.

Reads from environment variables and .env file.
Validates all config values on startup.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    postgres_user: str = "postgres"
    postgres_password: str = "postgres"
    postgres_db: str = "sensor_data"
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    db_pool_min: int = 2
    db_pool_max: int = 10

    @property
    def database_url(self) -> str:
        return (
            f"postgresql://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    api_host: str = "0.0.0.0"
    api_port: int = 5001
    api_debug: bool = False

    # dbt schema names (for querying dbt-managed tables)
    silver_schema: str = "silver"
    gold_schema: str = "gold"


@lru_cache
def get_settings() -> Settings:
    return Settings()