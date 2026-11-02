from pydantic import BaseModel, ConfigDict, Field


class PendingUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    full_name: str


class AdminRoleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str


class AssignRolesRequest(BaseModel):
    role_ids: list[int] = Field(min_length=1)


class ManagedUserResponse(PendingUserResponse):
    role_ids: list[int]


class PermissionDetail(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    code: str
    name: str
    module: str
    description: str | None
    resource: str | None = None
    action: str | None = None


class RoleDetailResponse(BaseModel):
    """A role with the permissions it grants (one row of the role matrix)."""

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "id": 3,
                "code": "TECHNICIAN",
                "name": "Technician",
                "description": "Performs assigned maintenance work",
                "permissions": [
                    {
                        "code": "maintenance.read",
                        "name": "View maintenance requests",
                        "module": "maintenance",
                        "description": "View maintenance tickets and their history",
                    }
                ],
            }
        },
    )

    id: int
    code: str
    name: str
    description: str | None
    permissions: list[PermissionDetail]


# -- Roles administration (Phase 4) -------------------------------------------------------


class EffectivePermission(BaseModel):
    """A permission a role ends up with, and which role in its lineage grants it."""

    code: str
    source_role_id: int
    source_role_name: str
    inherited: bool


class RoleAdminResponse(BaseModel):
    """One column of the roles matrix: the role, its place in the hierarchy and its grants."""

    id: int
    code: str
    name: str
    description: str | None
    is_active: bool
    is_system: bool
    parent_role_id: int | None
    parent_name: str | None
    depth: int
    user_count: int
    children_count: int
    own_permissions: list[str]
    effective: list[EffectivePermission]


class RoleCreateRequest(BaseModel):
    name: str = Field(min_length=3, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    parent_role_id: int | None = None
    permissions: list[str] = Field(default_factory=list, max_length=200)


class RoleUpdateRequest(BaseModel):
    """Only the fields sent change; `parent_role_id: null` makes the role a root."""

    name: str | None = Field(default=None, min_length=3, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    parent_role_id: int | None = None
    is_active: bool | None = None


class RolePermissionsRequest(BaseModel):
    permissions: list[str] = Field(max_length=200)
