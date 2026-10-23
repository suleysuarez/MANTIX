"""The signed-in person's own data and their history (audit entries about them or by them)."""

from datetime import datetime
from typing import Any

from sqlalchemy import Select, and_, not_, or_, select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.audit import AuditLog
from app.models.auth import User, UserRole
from app.repositories.base import BaseRepository, Page

#: Actions that change who can do what or how the person signs in.
SECURITY_ACTIONS = (
    "profile.password_changed",
    "user.password_reset",
    "roles.replaced",
    "roles.assigned",
    "roles.revoked",
    "user.activated",
    "user.deactivated",
)


def _kind_filter(kind: str) -> Any:
    session = AuditLog.action.like("auth.%")
    security = AuditLog.action.in_(SECURITY_ACTIONS)
    profile = AuditLog.action.like("profile.%")
    if kind == "session":
        return session
    if kind == "security":
        return security
    if kind == "profile":
        return and_(profile, not_(security))
    return not_(or_(session, security, profile))


class ProfileRepository(BaseRepository[User]):
    model = User

    async def get(self, user_id: int) -> User | None:
        result = await self.session.execute(
            select(User)
            .options(selectinload(User.user_roles).selectinload(UserRole.role))
            .where(User.id == user_id)
            .execution_options(populate_existing=True)
        )
        user: User | None = result.scalar_one_or_none()
        return user

    async def history(
        self,
        user_id: int,
        *,
        kind: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[AuditLog]:
        """What the person did, plus what others did to their account, newest first."""
        query: Select[Any] = (
            select(AuditLog)
            .options(selectinload(AuditLog.user))
            .where(
                or_(
                    AuditLog.user_id == user_id,
                    and_(AuditLog.entity_type == "user", AuditLog.entity_id == user_id),
                )
            )
        )
        if kind:
            query = query.where(_kind_filter(kind))
        if date_from is not None:
            query = query.where(AuditLog.created_at >= date_from)
        if date_to is not None:
            query = query.where(AuditLog.created_at <= date_to)
        query = query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )
