"""Schemas of the person's own profile (`/profile`): data, photo, password, history."""

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.text import collapse
from app.schemas.auth import RoleResponse

_PHONE = re.compile(r"^\+?[0-9][0-9 ()-]{5,24}$")
MIN_PASSWORD = 10

HistoryKind = Literal["session", "profile", "security", "activity"]


class ProfileResponse(BaseModel):
    id: int
    email: str = Field(description="Read only: it is the sign-in identity")
    full_name: str
    phone: str | None
    employee_code: str | None = Field(description="Assigned by an administrator")
    roles: list[RoleResponse]
    has_avatar: bool
    avatar_version: int | None = Field(
        description="Changes with every new photo (cache-buster); null without photo"
    )
    last_login_at: datetime | None
    created_at: datetime


class ProfileUpdate(BaseModel):
    """Editable personal data. The e-mail is listed only to be refused with a clear message."""

    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {"full_name": "Ana Pérez", "phone": "+57 300 123 4567"}
        },
    )

    full_name: str | None = Field(default=None, min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=25)
    email: str | None = Field(
        default=None, description="Not editable: any value is a 403"
    )

    @field_validator("full_name", mode="before")
    @classmethod
    def _name(cls, value: object) -> object:
        return collapse(value) if isinstance(value, str) else value

    @field_validator("phone", mode="before")
    @classmethod
    def _phone_clean(cls, value: object) -> object:
        return (collapse(value) or None) if isinstance(value, str) else value

    @field_validator("phone")
    @classmethod
    def _phone_format(cls, value: str | None) -> str | None:
        if value is not None and not _PHONE.fullmatch(value):
            raise ValueError("el teléfono solo admite números, espacios, +, ( ) y -")
        return value


class PasswordChange(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "current_password": "Actual-2026",
                "new_password": "Nueva-2026-Segura",
            }
        }
    )

    current_password: str = Field(min_length=1, max_length=128, repr=False)
    new_password: str = Field(min_length=MIN_PASSWORD, max_length=128, repr=False)

    @field_validator("new_password")
    @classmethod
    def _policy(cls, value: str) -> str:
        if re.search(r"\s", value):
            raise ValueError("la contraseña no puede contener espacios")
        if not (
            re.search(r"[a-z]", value)
            and re.search(r"[A-Z]", value)
            and re.search(r"[0-9]", value)
        ):
            raise ValueError(
                "la contraseña debe combinar mayúsculas, minúsculas y números"
            )
        return value


class HistoryEntry(BaseModel):
    id: int
    action: str = Field(examples=["auth.login"])
    kind: HistoryKind
    entity_type: str
    entity_id: int | None
    actor_name: str | None = Field(
        description="Who did it when it was somebody else (e.g. an administrator); null if you"
    )
    ip_address: str | None
    created_at: datetime
