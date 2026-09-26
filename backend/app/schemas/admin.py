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
