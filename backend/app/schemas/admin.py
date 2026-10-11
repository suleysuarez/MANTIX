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
