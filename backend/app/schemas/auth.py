from pydantic import BaseModel, ConfigDict, EmailStr


class RoleResponse(BaseModel):
    code: str
    name: str


class PermissionResponse(BaseModel):
    code: str
    name: str


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    full_name: str
    employee_code: str | None
    is_active: bool
    roles: list[RoleResponse]
    permissions: list[PermissionResponse]
