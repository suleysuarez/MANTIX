from app.core.authz import AuthContext
from app.core.exceptions import NotFoundError
from app.repositories.admin import AdminRepository
from app.schemas.admin import (
    AdminRoleResponse,
    ManagedUserResponse,
    PendingUserResponse,
)
from app.services.audit import AuditService
from app.services.notification import NotificationService


class AdminUserService:
    def __init__(
        self,
        repository: AdminRepository,
        audit: AuditService,
        notifications: NotificationService,
    ):
        self.repository = repository
        self.audit = audit
        self.notifications = notifications

    async def list_pending_users(self) -> list[PendingUserResponse]:
        users = await self.repository.list_pending_users()
        return [PendingUserResponse.model_validate(user) for user in users]

    async def list_roles(self) -> list[AdminRoleResponse]:
        roles = await self.repository.list_active_roles()
        return [AdminRoleResponse.model_validate(role) for role in roles]

    async def assign_roles(
        self, user_id: int, role_ids: list[int], assigned_by: AuthContext
    ) -> ManagedUserResponse:
        user = await self.repository.get_active_user(user_id)
        if user is None:
            raise NotFoundError("active target user not found")

        unique_role_ids = list(dict.fromkeys(role_ids))
        roles = await self.repository.get_active_roles_by_ids(unique_role_ids)
        if len(roles) != len(unique_role_ids):
            raise NotFoundError("one or more active roles not found")

        existing_role_ids = {user_role.role_id for user_role in user.user_roles}
        newly_added = [role for role in roles if role.id not in existing_role_ids]

        await self.repository.add_missing_roles(user, roles, assigned_by.id)
        if newly_added:
            self.audit.record(
                user_id=assigned_by.id,
                action="roles.assigned",
                entity_type="user",
                entity_id=user.id,
                new_values={"role_codes": [role.code for role in newly_added]},
            )
            self.notifications.notify(
                user_id=user.id,
                title="Access granted",
                message="You were granted the role(s): "
                + ", ".join(role.name for role in newly_added),
                notification_type="role_assigned",
            )
        await self.repository.commit()
        updated = await self.repository.reload_user(user_id)
        if updated is None:
            raise NotFoundError("active target user not found")
        return ManagedUserResponse(
            id=updated.id,
            email=updated.email,
            full_name=updated.full_name,
            role_ids=sorted(user_role.role_id for user_role in updated.user_roles),
        )
