import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Status = Literal["ok", "warning", "error", "disabled"]


class UserCounts(BaseModel):
    total: int
    active: int
    inactive: int
    without_role: int = Field(description="Signed up but not approved yet")


class RoleHealth(BaseModel):
    id: int
    code: str
    name: str
    is_active: bool
    users: int = Field(description="Active users holding the role")
    permissions: int


class AuditEntry(BaseModel):
    id: int
    action: str
    entity_type: str
    entity_id: int | None
    by: str | None
    at: datetime


class AuditHealth(BaseModel):
    last_24h: int
    recent: list[AuditEntry]


class JobHealth(BaseModel):
    id: str
    name: str
    running: bool = Field(description="The scheduler is up and the job is registered")
    interval_minutes: int | None
    next_run_at: datetime | None
    last_run_at: datetime | None = Field(description="Since the server started")
    last_status: Literal["ok", "error", "never"]
    last_detail: str | None


class IntegrationHealth(BaseModel):
    key: str
    name: str
    status: Status
    detail: str
    latency_ms: float | None = None


class EnvironmentInfo(BaseModel):
    """Read-only runtime parameters (set through environment variables, never secrets)."""

    name: str
    version: str
    rate_limit_per_minute: int
    max_upload_mb: int
    reminder_interval_minutes: int
    log_level: str
    scheduler_enabled: bool


class SystemHealth(BaseModel):
    generated_at: datetime
    overall: Literal["ok", "warning", "error"]
    environment: EnvironmentInfo
    users: UserCounts
    roles: list[RoleHealth]
    audit: AuditHealth
    jobs: list[JobHealth]
    integrations: list[IntegrationHealth]


# -- request categories -------------------------------------------------------------------


class CategoryAdmin(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str
    is_active: bool
    usage: int = Field(default=0, description="Requests that use it")
    created_at: datetime


class CategoryCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={"example": {"code": "printers", "name": "Impresoras"}}
    )

    code: str = Field(
        pattern=r"^[a-z][a-z_]{1,29}$",
        description="Stable identifier (lower case, `_` allowed); cannot change",
    )
    name: str = Field(min_length=3, max_length=100)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 3:
            raise ValueError("the name must have at least 3 characters")
        return value


class CategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=100)
    is_active: bool | None = None

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip()
        if len(value) < 3:
            raise ValueError("the name must have at least 3 characters")
        return value


# -- organization (report header) ---------------------------------------------------------

DEFAULT_COMPANY = "Mantix"


class OrganizationResponse(BaseModel):
    company_name: str
    legal_name: str | None
    tax_id: str | None
    configured: bool = Field(description="False while the defaults are in use")
    updated_at: datetime | None


class OrganizationUpdate(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "company_name": "Mantix",
                "legal_name": "Mantix S.A.S.",
                "tax_id": "900.123.456-7",
            }
        },
    )

    company_name: str = Field(min_length=2, max_length=150)
    legal_name: str | None = Field(default=None, max_length=200)
    tax_id: str | None = Field(
        default=None,
        max_length=30,
        description="Tax id (NIT): digits, letters, dots and hyphens",
    )

    @field_validator("company_name", "legal_name", "tax_id")
    @classmethod
    def _trim(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("company_name")
    @classmethod
    def _company_required(cls, value: str | None) -> str:
        if value is None or len(value) < 2:
            raise ValueError("the company name must have at least 2 characters")
        return value

    @field_validator("tax_id")
    @classmethod
    def _tax_id_format(cls, value: str | None) -> str | None:
        if value is not None and not re.fullmatch(r"[0-9A-Za-z.\-]{5,30}", value):
            raise ValueError(
                "the tax id must have 5 to 30 digits, letters, dots or hyphens"
            )
        return value
