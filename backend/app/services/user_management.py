"""Users screen: list, create (pre-register), edit, activate/deactivate, roles, password reset.

Accounts are never deleted (they carry history); they are deactivated. The sign-in service owns
passwords, so a new person is pre-registered here with a role and linked at their first sign-in
by e-mail; an administrator can set a new password through the sign-in service.
"""

from collections.abc import Awaitable, Callable
from datetime import datetime
from typing import Any

from app.core.authz import ADMIN, AuthContext
from app.core.exceptions import ConflictError, NotFoundError, UnprocessableError
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.auth import User
from app.repositories.base import Page
from app.repositories.user_management import UserManagementRepository
from app.schemas.user_management import (
    RecentAccess,
    RoleCount,
    UserCreate,
    UserListItem,
    UserRoleRef,
    UsersSummary,
    UserUpdate,
)
from app.services.audit import AuditService
from app.services.notification import NotificationService

PasswordSetter = Callable[[str, str], Awaitable[None]]


def to_item(user: User) -> UserListItem:
    roles = sorted(
        (link.role for link in user.user_roles if link.role.is_active),
        key=lambda role: role.code,
    )
    return UserListItem(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone=user.phone,
        employee_code=user.employee_code,
        is_active=user.is_active,
        roles=[UserRoleRef.model_validate(role) for role in roles],
        created_at=user.created_at,
        last_login_at=user.last_login_at,
        linked=user.clerk_user_id is not None,
    )


class UserManagementService:
    def __init__(
        self,
        repository: UserManagementRepository,
        audit: AuditService,
        notifications: NotificationService,
        set_password: PasswordSetter,
    ):
        self.repository = repository
        self.audit = audit
        self.notifications = notifications
        self.set_password = set_password

    # -- reads -------------------------------------------------------------------------

    async def list_users(
        self,
        *,
        search: str | None = None,
        role: str | None = None,
        is_active: bool | None = None,
        created_from: datetime | None = None,
        created_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[UserListItem]:
        if created_from and created_to and created_to < created_from:
            raise UnprocessableError(
                "el rango de fecha de creación no es válido: la final es anterior a la inicial"
            )
        page = await self.repository.search(
            search=search,
            role_code=role,
            is_active=is_active,
            created_from=created_from,
            created_to=created_to,
            params=params,
        )
        return page.map(to_item)

    async def get(self, user_id: int) -> UserListItem:
        return to_item(await self._require(user_id))

    async def summary(self) -> UsersSummary:
        total, active, never, without_role = await self.repository.totals()
        return UsersSummary(
            total=total,
            active=active,
            inactive=total - active,
            never_signed_in=never,
            without_role=without_role,
            by_role=[
                RoleCount(code=code, name=name, count=count)
                for code, name, count in await self.repository.count_by_role()
            ],
            recent_access=[
                RecentAccess(
                    id=u.id,
                    full_name=u.full_name,
                    email=u.email,
                    last_login_at=u.last_login_at,  # type: ignore[arg-type]
                )
                for u in await self.repository.recent_access()
            ],
        )

    # -- writes ------------------------------------------------------------------------

    async def create(self, payload: UserCreate, actor: AuthContext) -> UserListItem:
        if await self.repository.email_taken(payload.email):
            raise ConflictError(f"ya existe un usuario con el correo '{payload.email}'")
        if payload.employee_code and await self.repository.code_taken(
            payload.employee_code
        ):
            raise ConflictError(
                f"ya existe un usuario con el código '{payload.employee_code}'"
            )
        roles = await self._roles(payload.role_ids)
        user = await self.repository.create(
            email=payload.email,
            full_name=payload.full_name,
            phone=payload.phone,
            employee_code=payload.employee_code,
            roles=roles,
            assigned_by=actor.id,
        )
        self.audit.record(
            user_id=actor.id,
            action="user.created",
            entity_type="user",
            entity_id=user.id,
            new_values={
                "email": payload.email,
                "full_name": payload.full_name,
                "role_codes": sorted(role.code for role in roles),
            },
        )
        await self.repository.commit()
        return await self.get(user.id)

    async def update(
        self, user_id: int, payload: UserUpdate, actor: AuthContext
    ) -> UserListItem:
        user = await self._require(user_id)
        changes = payload.model_dump(exclude_unset=True)
        if changes.get("email") is None:
            changes.pop("email", None)
        if "email" in changes and changes["email"] != user.email:
            if user.clerk_user_id is not None:
                raise UnprocessableError(
                    "el correo de una cuenta que ya inició sesión no se puede cambiar"
                )
            if await self.repository.email_taken(changes["email"], excluding=user.id):
                raise ConflictError(
                    f"ya existe un usuario con el correo '{changes['email']}'"
                )
        code = changes.get("employee_code")
        if code and await self.repository.code_taken(code, excluding=user.id):
            raise ConflictError(f"ya existe un usuario con el código '{code}'")
        old = {field: getattr(user, field) for field in changes}
        for field, value in changes.items():
            setattr(user, field, value)
        if changes:
            self.audit.record(
                user_id=actor.id,
                action="user.updated",
                entity_type="user",
                entity_id=user.id,
                old_values=old,
                new_values=changes,
            )
        await self.repository.commit()
        return await self.get(user_id)

    async def set_active(
        self, user_id: int, active: bool, actor: AuthContext
    ) -> UserListItem:
        user = await self._require(user_id)
        if user.is_active == active:
            return to_item(user)
        if not active:
            if user.id == actor.id:
                raise ConflictError("no puedes desactivar tu propia cuenta")
            if (
                self._is_admin(user)
                and await self.repository.count_active_admins() <= 1
            ):
                raise ConflictError(
                    "no se puede desactivar al último administrador activo"
                )
        user.is_active = active
        self.audit.record(
            user_id=actor.id,
            action="user.activated" if active else "user.deactivated",
            entity_type="user",
            entity_id=user.id,
            old_values={"is_active": not active},
            new_values={"is_active": active},
        )
        await self.repository.commit()
        return await self.get(user_id)

    async def replace_roles(
        self, user_id: int, role_ids: list[int], actor: AuthContext
    ) -> UserListItem:
        user = await self._require(user_id)
        roles = await self._roles(role_ids)
        was_admin = self._is_admin(user)
        will_be_admin = any(role.code == ADMIN for role in roles)
        if was_admin and not will_be_admin:
            if user.id == actor.id:
                raise ConflictError("no puedes quitarte tu propio rol de administrador")
            if user.is_active and await self.repository.count_active_admins() <= 1:
                raise ConflictError("no se puede dejar al sistema sin administradores")
        old = sorted(link.role.code for link in user.user_roles)
        await self.repository.replace_roles(user, roles, actor.id)
        new = sorted(role.code for role in roles)
        if old != new:
            self.audit.record(
                user_id=actor.id,
                action="roles.replaced",
                entity_type="user",
                entity_id=user.id,
                old_values={"role_codes": old},
                new_values={"role_codes": new},
            )
            self.notifications.notify(
                user_id=user.id,
                title="Tus roles cambiaron",
                message="Tus roles ahora son: " + ", ".join(r.name for r in roles),
                notification_type="role_assigned",
            )
        await self.repository.commit()
        return await self.get(user_id)

    async def reset_password(
        self, user_id: int, password: str, actor: AuthContext
    ) -> None:
        """Set a new password through the sign-in service; it is never stored or logged here."""
        user = await self._require(user_id)
        if user.id == actor.id:
            raise ConflictError("cambia tu propia contraseña desde tu perfil")
        if not user.is_active:
            raise ConflictError("la cuenta está desactivada")
        if user.clerk_user_id is None:
            raise ConflictError(
                "la persona aún no ha iniciado sesión: no tiene contraseña que restablecer"
            )
        await self.set_password(user.clerk_user_id, password)
        self.audit.record(
            user_id=actor.id,
            action="user.password_reset",
            entity_type="user",
            entity_id=user.id,
        )
        self.notifications.notify(
            user_id=user.id,
            title="Tu contraseña fue restablecida",
            message="Un administrador cambió tu contraseña. Inicia sesión con la nueva.",
            notification_type="password_reset",
        )
        await self.repository.commit()

    # -- internals ---------------------------------------------------------------------

    @staticmethod
    def _is_admin(user: User) -> bool:
        return any(link.role.code == ADMIN for link in user.user_roles)

    async def _require(self, user_id: int) -> User:
        user = await self.repository.get(user_id)
        if user is None:
            raise NotFoundError("usuario no encontrado")
        return user

    async def _roles(self, role_ids: list[int]) -> list[Any]:
        roles = await self.repository.roles_by_ids(role_ids)
        if len(roles) != len(set(role_ids)):
            raise NotFoundError("uno o más roles no existen o están inactivos")
        return roles
