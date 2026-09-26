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
    clerk_secret_key: str = Field(default="", validation_alias="CLERK_SECRET_KEY")
    clerk_publishable_key: str = Field(
        default="", validation_alias="CLERK_PUBLISHABLE_KEY"
    )
    clerk_authorized_parties: str = Field(
        default="http://localhost:4200", validation_alias="CLERK_AUTHORIZED_PARTIES"
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

    @property
    def clerk_authorized_party_list(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.clerk_authorized_parties.split(",")
            if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
