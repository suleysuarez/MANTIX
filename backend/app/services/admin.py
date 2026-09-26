from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.auth import User
from app.repositories.admin import AdminRepository
from app.schemas.admin import (
    AdminRoleResponse,
    ManagedUserResponse,
    PendingUserResponse,
)


class AdminUserService:
    def __init__(self, session: AsyncSession):
        self.repository = AdminRepository(session)

    async def list_pending_users(self) -> list[PendingUserResponse]:
        users = await self.repository.list_pending_users()
        return [PendingUserResponse.model_validate(user) for user in users]

    async def list_roles(self) -> list[AdminRoleResponse]:
        roles = await self.repository.list_active_roles()
        return [AdminRoleResponse.model_validate(role) for role in roles]

    async def assign_roles(
        self, user_id: int, role_ids: list[int], assigned_by: User
    ) -> ManagedUserResponse:
        user = await self.repository.get_active_user(user_id)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="active target user not found",
            )

        unique_role_ids = list(dict.fromkeys(role_ids))
        roles = await self.repository.get_active_roles_by_ids(unique_role_ids)
        if len(roles) != len(unique_role_ids):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="one or more active roles not found",
            )

        await self.repository.add_missing_roles(user, roles, assigned_by.id)
        await self.repository.commit()
        updated = await self.repository.reload_user(user_id)
        if updated is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="active target user not found",
            )
        return ManagedUserResponse(
            id=updated.id,
            email=updated.email,
            full_name=updated.full_name,
            role_ids=sorted(user_role.role_id for user_role in updated.user_roles),
        )
