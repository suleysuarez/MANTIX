from functools import lru_cache
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):
    app_env: str = "development"
    database_url: str = Field(default="", validation_alias="DATABASE_URL")
    cors_origins: str = Field(
        default="http://localhost:4200", validation_alias="CORS_ORIGINS"
    )
    backend_port: int = Field(default=8000, validation_alias="BACKEND_PORT")
    jwt_secret_key: str = Field(default="", validation_alias="JWT_SECRET_KEY")
    jwt_algorithm: str = Field(default="HS256", validation_alias="JWT_ALGORITHM")
    access_token_expire_minutes: int = Field(
        default=15, validation_alias="ACCESS_TOKEN_EXPIRE_MINUTES"
    )
    refresh_token_expire_days: int = Field(
        default=30, validation_alias="REFRESH_TOKEN_EXPIRE_DAYS"
    )
    password_reset_expire_minutes: int = Field(
        default=30, validation_alias="PASSWORD_RESET_EXPIRE_MINUTES"
    )

    model_config = SettingsConfigDict(
        env_file=(BASE_DIR / ".env", ".env"),
        extra="ignore",
    )

    @field_validator("database_url", mode="after")
    @classmethod
    def assemble_async_db_connection(cls, v: str) -> str:
        if not v:
            return v
        if v.startswith("postgresql://"):
            v = v.replace("postgresql://", "postgresql+asyncpg://", 1)
        if v.startswith("postgresql+asyncpg://"):
            parsed = urlparse(v)
            if parsed.query:
                qs = parse_qs(parsed.query)
                new_qs = {}
                if "sslmode" in qs or "ssl" in qs:
                    new_qs["ssl"] = "require"
                for k, val in qs.items():
                    if k not in ("sslmode", "channel_binding", "ssl"):
                        new_qs[k] = val[0]
                v = urlunparse(
                    (
                        parsed.scheme,
                        parsed.netloc,
                        parsed.path,
                        parsed.params,
                        urlencode(new_qs),
                        parsed.fragment,
                    )
                )
        return v

    @property
    def cors_origin_list(self) -> list[str]:
        return [
            origin.strip() for origin in self.cors_origins.split(",") if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
