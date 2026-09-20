from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    database_url: str = Field(default="", validation_alias="DATABASE_URL")
    cors_origins: str = Field(
        default="http://localhost:4200", validation_alias="CORS_ORIGINS"
    )
    backend_port: int = Field(default=8000, validation_alias="BACKEND_PORT")

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        return [
            origin.strip() for origin in self.cors_origins.split(",") if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
