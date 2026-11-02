"""Read models for the system-health panel and the category catalog."""

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import func, select, text

from app.models.audit import AuditLog
from app.models.auth import Role, RolePermission, User, UserRole
from app.models.category import RequestCategory
from app.models.maintenance import MaintenanceRequest
from app.models.organization import OrganizationSettings
from app.repositories.base import BaseRepository


@dataclass(frozen=True, slots=True)
class UserCountRow:
    total: int
    active: int
    without_role: int


@dataclass(frozen=True, slots=True)
class RoleRow:
    id: int
    code: str
    name: str
    is_active: bool
    users: int
    permissions: int


@dataclass(frozen=True, slots=True)
class AuditRow:
    id: int
    action: str
    entity_type: str
    entity_id: int | None
    by: str | None
    at: datetime


class SettingsRepository(BaseRepository[RequestCategory]):
    model = RequestCategory

    # -- health ------------------------------------------------------------------------

    async def ping(self) -> None:
        await self.session.execute(text("SELECT 1"))

    async def user_counts(self) -> UserCountRow:
        has_role = select(UserRole.user_id).where(UserRole.user_id == User.id).exists()
        row = (
            await self.session.execute(
                select(
                    func.count(),
                    func.count().filter(User.is_active.is_(True)),
                    func.count().filter(~has_role),
                )
            )
        ).one()
        return UserCountRow(total=row[0], active=row[1], without_role=row[2])

    async def role_rows(self) -> list[RoleRow]:
        holders = (
            select(
                UserRole.role_id, func.count(func.distinct(UserRole.user_id)).label("n")
            )
            .join(User, User.id == UserRole.user_id)
            .where(User.is_active.is_(True))
            .group_by(UserRole.role_id)
            .subquery("holders")
        )
        grants = (
            select(RolePermission.role_id, func.count().label("n"))
            .group_by(RolePermission.role_id)
            .subquery("grants")
        )
        rows = await self.session.execute(
            select(
                Role.id,
                Role.code,
                Role.name,
                Role.is_active,
                func.coalesce(holders.c.n, 0),
                func.coalesce(grants.c.n, 0),
            )
            .outerjoin(holders, holders.c.role_id == Role.id)
            .outerjoin(grants, grants.c.role_id == Role.id)
            .order_by(Role.code)
        )
        return [RoleRow(*row) for row in rows.all()]

    async def audit_recent(self, limit: int) -> list[AuditRow]:
        rows = await self.session.execute(
            select(
                AuditLog.id,
                AuditLog.action,
                AuditLog.entity_type,
                AuditLog.entity_id,
                User.full_name,
                AuditLog.created_at,
            )
            .outerjoin(User, User.id == AuditLog.user_id)
            .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
            .limit(limit)
        )
        return [AuditRow(*row) for row in rows.all()]

    async def audit_since(self, since: datetime) -> int:
        row = await self.session.execute(
            select(func.count()).where(AuditLog.created_at >= since)
        )
        return int(row.scalar_one())

    # -- request categories ------------------------------------------------------------------

    async def list_categories(self) -> list[tuple[RequestCategory, int]]:
        usage = func.count(MaintenanceRequest.id)
        rows = await self.session.execute(
            select(RequestCategory, usage)
            .outerjoin(
                MaintenanceRequest, MaintenanceRequest.category == RequestCategory.code
            )
            .group_by(RequestCategory.id)
            .order_by(RequestCategory.name)
        )
        return [(row[0], int(row[1])) for row in rows.all()]

    async def get_category(self, category_id: int) -> RequestCategory | None:
        row = await self.session.execute(
            select(RequestCategory).where(RequestCategory.id == category_id)
        )
        return row.scalar_one_or_none()

    async def get_category_by_code(self, code: str) -> RequestCategory | None:
        row = await self.session.execute(
            select(RequestCategory).where(RequestCategory.code == code)
        )
        return row.scalar_one_or_none()

    async def category_usage(self, code: str) -> int:
        row = await self.session.execute(
            select(func.count()).where(MaintenanceRequest.category == code)
        )
        return int(row.scalar_one())

    async def delete_category(self, category: RequestCategory) -> None:
        await self.session.delete(category)
        await self.session.flush()

    # -- organization ------------------------------------------------------------------------

    async def get_organization(self) -> OrganizationSettings | None:
        return await self.session.get(OrganizationSettings, 1)

    async def save_organization(
        self,
        *,
        company_name: str,
        user_id: int | None,
    ) -> OrganizationSettings:
        row = await self.get_organization()
        if row is None:
            row = OrganizationSettings(id=1, company_name=company_name)
            self.session.add(row)
        row.company_name = company_name
        row.updated_by_user_id = user_id
        await self.session.flush()
        await self.session.refresh(row)
        return row
