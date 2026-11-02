from datetime import UTC, datetime, timedelta

from sqlalchemy.exc import IntegrityError

from app.core.clerk import ClerkProfile, VerifiedClerkIdentity, get_clerk_profile
from app.core.config import Settings
from app.core.exceptions import AppError, ConflictError, ForbiddenError
from app.core.rbac import effective_permission_objects
from app.models.auth import User
from app.repositories.auth import AuthRepository
from app.schemas.auth import PermissionResponse, RoleResponse, UserResponse
from app.services.audit import AuditService

#: A new session is recorded when the previous one started longer ago than this.
SESSION_GAP = timedelta(minutes=30)


class ClerkAuthService:
    def __init__(
        self,
        repository: AuthRepository,
        settings: Settings,
        audit: AuditService | None = None,
    ):
        self.repository = repository
        self.settings = settings
        self.audit = audit

    async def _touch_login(self, user: User) -> None:
        """Note the start of a session (at most once per `SESSION_GAP`), with an audit entry."""
        now = datetime.now(UTC)
        if user.last_login_at is not None and now - user.last_login_at < SESSION_GAP:
            return
        user.last_login_at = now
        if self.audit is not None:
            self.audit.record(
                user_id=user.id,
                action="auth.login",
                entity_type="user",
                entity_id=user.id,
            )
        await self.repository.commit()

    async def resolve_local_user(self, identity: VerifiedClerkIdentity) -> User:
        user = await self.repository.get_user_by_clerk_id(identity.user_id)
        if user is not None:
            user = self._require_active(user)
            await self._touch_login(user)
            if not user.roles:
                assigned = await self._assign_bootstrap_admin(user)
                if assigned:
                    await self.repository.commit()
                    # `roles` was already loaded (empty); reload it after the grant.
                    self.repository.expire(user, ["roles", "user_roles"])
                    return (
                        await self.repository.get_user_by_clerk_id(identity.user_id)
                    ) or user
            return user

        profile = await get_clerk_profile(identity, self.settings)
        existing_by_email = await self.repository.get_user_by_email(profile.email)
        if existing_by_email is not None:
            if existing_by_email.clerk_user_id is None:
                # Pre-registered by an administrator: the first sign-in with that e-mail links it.
                existing_by_email.clerk_user_id = identity.user_id
                await self.repository.commit()
            elif existing_by_email.clerk_user_id != identity.user_id:
                raise ConflictError(
                    "local email is already linked to another Clerk user"
                )
            user = self._require_active(existing_by_email)
            await self._touch_login(user)
            return user

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
    # Own permissions of each role plus those inherited from its ancestors.
    permissions = {
        code: PermissionResponse(code=code, name=permission.name)
        for code, permission in effective_permission_objects(
            role for role in user.roles if role.is_active
        ).items()
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
