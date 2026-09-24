from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clerk import ClerkProfile, VerifiedClerkIdentity, get_clerk_profile
from app.core.config import Settings
from app.models.auth import User
from app.repositories.auth import AuthRepository
from app.schemas.auth import PermissionResponse, RoleResponse, UserResponse


class ClerkAuthService:
    def __init__(self, session: AsyncSession, settings: Settings):
        self.repository = AuthRepository(session)
        self.settings = settings

    async def resolve_local_user(self, identity: VerifiedClerkIdentity) -> User:
        user = await self.repository.get_user_by_clerk_id(identity.user_id)
        if user is not None:
            return self._require_active(user)

        profile = await get_clerk_profile(identity, self.settings)
        existing_by_email = await self.repository.get_user_by_email(profile.email)
        if existing_by_email is not None:
            if existing_by_email.clerk_user_id != identity.user_id:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="local email is already linked to another Clerk user",
                )
            return self._require_active(existing_by_email)

        return await self._provision_employee(profile)

    async def _provision_employee(self, profile: ClerkProfile) -> User:
        employee_role = await self.repository.get_employee_role()
        if employee_role is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="default EMPLOYEE role is not configured",
            )
        try:
            user = await self.repository.create_user(profile)
            await self.repository.assign_role(user, employee_role)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            existing = await self.repository.get_user_by_clerk_id(profile.clerk_user_id)
            if existing is not None:
                return self._require_active(existing)
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Clerk user could not be linked to a local profile",
            ) from exc
        provisioned = await self.repository.get_user_by_clerk_id(profile.clerk_user_id)
        if provisioned is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="provisioned local user could not be reloaded",
            )
        return provisioned

    @staticmethod
    def _require_active(user: User) -> User:
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="local user is inactive",
            )
        return user


def user_response(user: User) -> UserResponse:
    roles = [
        RoleResponse(code=role.code, name=role.name)
        for role in sorted(user.roles, key=lambda item: item.code)
        if role.is_active
    ]
    permissions = {
        permission.code: PermissionResponse(code=permission.code, name=permission.name)
        for role in user.roles
        if role.is_active
        for permission in role.permissions
        if permission.is_active
    }
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        employee_code=user.employee_code,
        is_active=user.is_active,
        roles=roles,
        permissions=sorted(permissions.values(), key=lambda item: item.code),
    )
