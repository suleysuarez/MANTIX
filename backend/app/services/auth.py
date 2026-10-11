from sqlalchemy.exc import IntegrityError

from app.core.clerk import ClerkProfile, VerifiedClerkIdentity, get_clerk_profile
from app.core.config import Settings
from app.core.exceptions import AppError, ConflictError, ForbiddenError
from app.models.auth import User
from app.repositories.auth import AuthRepository
from app.schemas.auth import PermissionResponse, RoleResponse, UserResponse


class ClerkAuthService:
    def __init__(self, repository: AuthRepository, settings: Settings):
        self.repository = repository
        self.settings = settings

    async def resolve_local_user(self, identity: VerifiedClerkIdentity) -> User:
        user = await self.repository.get_user_by_clerk_id(identity.user_id)
        if user is not None:
            user = self._require_active(user)
            if not user.roles:
                assigned = await self._assign_bootstrap_admin(user)
                if assigned:
                    await self.repository.commit()
                    return (
                        await self.repository.get_user_by_clerk_id(identity.user_id)
                    ) or user
            return user

        profile = await get_clerk_profile(identity, self.settings)
        existing_by_email = await self.repository.get_user_by_email(profile.email)
        if existing_by_email is not None:
            if existing_by_email.clerk_user_id != identity.user_id:
                raise ConflictError(
                    "local email is already linked to another Clerk user"
                )
            return self._require_active(existing_by_email)

        return await self._provision_first_or_pending(profile)

    async def _provision_first_or_pending(self, profile: ClerkProfile) -> User:
        try:
            user = await self.repository.create_user(profile)
            await self._assign_bootstrap_admin(user)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            existing = await self.repository.get_user_by_clerk_id(profile.clerk_user_id)
            if existing is not None:
                return self._require_active(existing)
            raise ConflictError(
                "Clerk user could not be linked to a local profile"
            ) from exc
        provisioned = await self.repository.get_user_by_clerk_id(profile.clerk_user_id)
        if provisioned is None:
            raise AppError("provisioned local user could not be reloaded")
        return provisioned

    async def _assign_bootstrap_admin(self, user: User) -> bool:
        await self.repository.lock_admin_bootstrap()
        if await self.repository.has_assigned_application_role():
            return False
        admin_role = await self.repository.get_admin_role()
        if admin_role is None:
            await self.repository.rollback()
            raise AppError("bootstrap ADMIN role is not configured")
        await self.repository.assign_role(user, admin_role)
        return True

    @staticmethod
    def _require_active(user: User) -> User:
        if not user.is_active:
            raise ForbiddenError("local user is inactive")
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
