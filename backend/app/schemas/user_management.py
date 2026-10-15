"""Schemas of the Users screen (`/admin/users`): list, create, edit, roles, password, summary."""

import re
from datetime import datetime
from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    field_validator,
)

from app.core.text import collapse

_PHONE = re.compile(r"^\+?[0-9][0-9 ()-]{5,24}$")
_CODE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,49}$")
MIN_PASSWORD = 10


class UserRoleRef(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str


class UserListItem(BaseModel):
    id: int
    email: str
    full_name: str
    phone: str | None
    employee_code: str | None
    is_active: bool
    roles: list[UserRoleRef]
    created_at: datetime
    last_login_at: datetime | None = Field(
        description="Start of the latest session; null if the person never signed in"
    )
    linked: bool = Field(
        description="The person already signed in once (their sign-in account is linked)"
    )


class _Editable(BaseModel):
    """Text rules shared by creation and edition."""

    @field_validator("full_name", check_fields=False, mode="before")
    @classmethod
    def _name(cls, value: str | None) -> str | None:
        return collapse(value) if isinstance(value, str) else value

    @field_validator("phone", "employee_code", check_fields=False, mode="before")
    @classmethod
    def _optional(cls, value: str | None) -> str | None:
        return (collapse(value) or None) if isinstance(value, str) else value

    @field_validator("phone", check_fields=False)
    @classmethod
    def _phone_format(cls, value: str | None) -> str | None:
        if value is not None and not _PHONE.fullmatch(value):
            raise ValueError("el teléfono solo admite números, espacios, +, ( ) y -")
        return value

    @field_validator("employee_code", check_fields=False)
    @classmethod
    def _code_format(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not _CODE.fullmatch(value):
            raise ValueError("el código solo admite letras, números, . _ - (2 a 50)")
        return value.upper()


class UserCreate(_Editable):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "email": "ana.perez@empresa.co",
                "full_name": "Ana Pérez",
                "phone": "+57 300 123 4567",
                "employee_code": "EMP-014",
                "role_ids": [3],
            }
        }
    )

    email: EmailStr
    full_name: str = Field(min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=25)
    employee_code: str | None = Field(default=None, max_length=50)
    role_ids: list[Annotated[int, Field(ge=1)]] = Field(min_length=1, max_length=10)

    @field_validator("email")
    @classmethod
    def _lower(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator("role_ids")
    @classmethod
    def _unique(cls, value: list[int]) -> list[int]:
        return list(dict.fromkeys(value))


class UserUpdate(_Editable):
    """Partial update. The name is not here: each person edits it from their own profile.

    The e-mail can change only while the person has not signed in yet."""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=25)
    employee_code: str | None = Field(default=None, max_length=50)

    @field_validator("email")
    @classmethod
    def _lower(cls, value: str | None) -> str | None:
        return value.strip().lower() if value else value


class RolesReplace(BaseModel):
    role_ids: list[Annotated[int, Field(ge=1)]] = Field(min_length=1, max_length=10)

    @field_validator("role_ids")
    @classmethod
    def _unique(cls, value: list[int]) -> list[int]:
        return list(dict.fromkeys(value))


class PasswordReset(BaseModel):
    """A new password set by an administrator (the sign-in service stores it; Mantix never does)."""

    model_config = ConfigDict(
        json_schema_extra={"example": {"password": "Cambio-2026-Seguro"}}
    )

    password: str = Field(min_length=MIN_PASSWORD, max_length=128, repr=False)

    @field_validator("password")
    @classmethod
    def _policy(cls, value: str) -> str:
        if value != value.strip() or " " in value:
            raise ValueError("la contraseña no puede contener espacios")
        if not (
            re.search(r"[a-z]", value)
            and re.search(r"[A-Z]", value)
            and re.search(r"[0-9]", value)
        ):
            raise ValueError(
                "la contraseña debe tener mayúsculas, minúsculas y números"
            )
        return value


class RoleCount(BaseModel):
    code: str
    name: str
    count: int


class RecentAccess(BaseModel):
    id: int
    full_name: str
    email: str
    last_login_at: datetime


class UsersSummary(BaseModel):
    """Indicators of the Users screen (not repeated from the dashboard)."""

    total: int
    active: int
    inactive: int
    never_signed_in: int = Field(description="Registered but never signed in")
    without_role: int = Field(description="Active users with no role yet")
    by_role: list[RoleCount]
    recent_access: list[RecentAccess]
