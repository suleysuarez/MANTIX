"""Rows behind the document exports (PDF and Excel). Ticket rows carry every field the
documents show, straight from the database: equipment, type, category, priority and SLA,
technician, dates and the costs recorded on the ticket's maintenance records."""

from typing import Any, cast

from sqlalchemy import Select, and_, func, select
from sqlalchemy.orm import aliased

from app.models.auth import Role, User, UserRole
from app.models.category import RequestCategory
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import (
    MaintenanceRecord,
    MaintenanceRequest,
    TicketAssignment,
)
from app.models.organization import OrganizationSettings
from app.models.priority import Priority
from app.models.technician import Technician
from app.repositories.report import MAX_EXPORT_ROWS
from app.repositories.report_builder import ReportBuilderRepository
from app.schemas.export import ExportFilters

#: Ticket statuses that count as open work / as finished work for a technician's load.
OPEN_STATUSES = ("assigned", "in_progress", "waiting")
DONE_STATUSES = ("resolved", "closed")


class ExportRepository(ReportBuilderRepository):
    async def organization(self) -> OrganizationSettings | None:
        return await self.session.get(OrganizationSettings, 1)

    async def technician_id_of(self, user_id: int) -> int | None:
        row = await self.session.execute(
            select(Technician.id).where(Technician.user_id == user_id)
        )
        return row.scalar_one_or_none()

    def _tickets(
        self,
        filters: ExportFilters,
        *,
        requester_id: int | None,
        technician_id: int | None,
    ) -> Select[Any]:
        requester = aliased(User)
        tech_user = aliased(User)
        costs = (
            select(
                MaintenanceRecord.request_id.label("request_id"),
                func.coalesce(func.sum(MaintenanceRecord.labor_cost), 0).label("labor"),
                func.coalesce(func.sum(MaintenanceRecord.parts_cost), 0).label("parts"),
            )
            .where(MaintenanceRecord.request_id.is_not(None))
            .group_by(MaintenanceRecord.request_id)
            .subquery("costs")
        )
        request = MaintenanceRequest
        query: Any = (
            select(
                request.id,
                request.ticket_number,
                request.title,
                request.status,
                request.priority.label("priority_code"),
                Priority.name.label("priority"),
                Priority.sla_hours,
                request.category.label("category_code"),
                RequestCategory.name.label("category"),
                Equipment.asset_tag.label("equipment"),
                Equipment.serial_number.label("serial"),
                EquipmentType.name.label("equipment_type"),
                requester.full_name.label("requested_by"),
                Technician.id.label("technician_id"),
                tech_user.full_name.label("technician"),
                request.created_at,
                request.resolved_at,
                func.coalesce(costs.c.labor, 0).label("labor_cost"),
                func.coalesce(costs.c.parts, 0).label("parts_cost"),
            )
            .join(Equipment, Equipment.id == request.equipment_id)
            .join(EquipmentType, EquipmentType.id == Equipment.equipment_type_id)
            .join(requester, requester.id == request.requested_by_user_id)
            .outerjoin(Priority, Priority.code == request.priority)
            .outerjoin(RequestCategory, RequestCategory.code == request.category)
            .outerjoin(
                TicketAssignment,
                and_(
                    TicketAssignment.request_id == request.id,
                    TicketAssignment.unassigned_at.is_(None),
                ),
            )
            .outerjoin(Technician, Technician.id == TicketAssignment.technician_id)
            .outerjoin(tech_user, tech_user.id == Technician.user_id)
            .outerjoin(costs, costs.c.request_id == request.id)
        )
        if requester_id is not None:
            query = query.where(request.requested_by_user_id == requester_id)
        if technician_id is not None:
            query = query.where(Technician.id == technician_id)
        if filters.statuses:
            query = query.where(request.status.in_(filters.statuses))
        if filters.priorities:
            query = query.where(request.priority.in_(filters.priorities))
        if filters.categories:
            query = query.where(request.category.in_(filters.categories))
        if filters.technician_ids:
            query = query.where(Technician.id.in_(filters.technician_ids))
        if filters.date_from is not None:
            query = query.where(request.created_at >= filters.date_from)
        if filters.date_to is not None:
            query = query.where(request.created_at <= filters.date_to)
        return cast("Select[Any]", query)

    def _technicians(self, filters: ExportFilters) -> Select[Any]:
        """Roster rows: the person, their profile and how many tickets they hold or closed."""
        open_tickets = (
            select(
                TicketAssignment.technician_id.label("technician_id"),
                func.count(MaintenanceRequest.id).label("open_tickets"),
            )
            .join(
                MaintenanceRequest, MaintenanceRequest.id == TicketAssignment.request_id
            )
            .where(
                TicketAssignment.unassigned_at.is_(None),
                MaintenanceRequest.status.in_(OPEN_STATUSES),
            )
            .group_by(TicketAssignment.technician_id)
            .subquery("open_load")
        )
        resolved = (
            select(
                TicketAssignment.technician_id.label("technician_id"),
                func.count(func.distinct(MaintenanceRequest.id)).label("resolved"),
            )
            .join(
                MaintenanceRequest, MaintenanceRequest.id == TicketAssignment.request_id
            )
            .where(MaintenanceRequest.status.in_(DONE_STATUSES))
            .group_by(TicketAssignment.technician_id)
            .subquery("done_load")
        )
        open_count = func.coalesce(open_tickets.c.open_tickets, 0)
        query: Any = (
            select(
                Technician.id,
                User.full_name,
                User.employee_code,
                User.email,
                Technician.specialization,
                User.is_active,
                Technician.is_available,
                Technician.hourly_rate,
                Technician.created_at,
                open_count.label("open_tickets"),
                func.coalesce(resolved.c.resolved, 0).label("resolved"),
            )
            .join(User, User.id == Technician.user_id)
            .outerjoin(open_tickets, open_tickets.c.technician_id == Technician.id)
            .outerjoin(resolved, resolved.c.technician_id == Technician.id)
        )
        if filters.is_active is not None:
            query = query.where(User.is_active.is_(filters.is_active))
        if filters.is_available is not None:
            query = query.where(Technician.is_available.is_(filters.is_available))
        if filters.specialty:
            query = query.where(
                func.lower(Technician.specialization).contains(
                    filters.specialty.lower()
                )
            )
        if filters.load == "none":
            query = query.where(open_count == 0)
        elif filters.load == "low":
            query = query.where(open_count.between(1, 2))
        elif filters.load == "high":
            query = query.where(open_count >= 3)
        if filters.search:
            term = f"%{filters.search.lower()}%"
            query = query.where(
                func.lower(
                    func.concat_ws(
                        " ",
                        User.full_name,
                        User.email,
                        User.employee_code,
                        Technician.specialization,
                    )
                ).like(term)
            )
        return cast("Select[Any]", query)

    async def count_technicians(self, filters: ExportFilters) -> int:
        result = await self.session.execute(
            select(func.count()).select_from(self._technicians(filters).subquery())
        )
        return int(result.scalar_one())

    async def export_technicians(
        self, filters: ExportFilters, *, limit: int = MAX_EXPORT_ROWS
    ) -> list[dict[str, Any]]:
        query = (
            self._technicians(filters)
            .order_by(User.full_name, Technician.id)
            .limit(limit)
        )
        return [dict(row._mapping) for row in await self.session.execute(query)]

    def _users(self, filters: ExportFilters) -> Select[Any]:
        """Accounts with their role names, filtered like the Users screen."""
        roles = (
            select(func.string_agg(Role.name, ", "))
            .select_from(UserRole)
            .join(Role, Role.id == UserRole.role_id)
            .where(UserRole.user_id == User.id)
            .scalar_subquery()
        )
        query: Any = select(
            User.id,
            User.full_name,
            User.email,
            User.employee_code,
            User.phone,
            User.is_active,
            User.last_login_at,
            User.created_at,
            roles.label("roles"),
        )
        if filters.is_active is not None:
            query = query.where(User.is_active.is_(filters.is_active))
        if filters.role:
            query = query.where(
                User.user_roles.any(UserRole.role.has(Role.code == filters.role))
            )
        if filters.date_from is not None:
            query = query.where(User.created_at >= filters.date_from)
        if filters.date_to is not None:
            query = query.where(User.created_at <= filters.date_to)
        if filters.search:
            term = f"%{filters.search.lower()}%"
            query = query.where(
                func.lower(
                    func.concat_ws(" ", User.full_name, User.email, User.employee_code)
                ).like(term)
            )
        return cast("Select[Any]", query)

    async def count_users(self, filters: ExportFilters) -> int:
        result = await self.session.execute(
            select(func.count()).select_from(self._users(filters).subquery())
        )
        return int(result.scalar_one())

    async def export_users(
        self, filters: ExportFilters, *, limit: int = MAX_EXPORT_ROWS
    ) -> list[dict[str, Any]]:
        query = self._users(filters).order_by(User.full_name, User.id).limit(limit)
        return [dict(row._mapping) for row in await self.session.execute(query)]

    async def count_tickets(
        self,
        filters: ExportFilters,
        *,
        requester_id: int | None = None,
        technician_id: int | None = None,
    ) -> int:
        query = self._tickets(
            filters, requester_id=requester_id, technician_id=technician_id
        )
        result = await self.session.execute(
            select(func.count()).select_from(query.subquery())
        )
        return int(result.scalar_one())

    async def export_tickets(
        self,
        filters: ExportFilters,
        *,
        requester_id: int | None = None,
        technician_id: int | None = None,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        query = (
            self._tickets(
                filters, requester_id=requester_id, technician_id=technician_id
            )
            .order_by(
                MaintenanceRequest.created_at.desc(), MaintenanceRequest.id.desc()
            )
            .limit(limit)
        )
        return [dict(row._mapping) for row in await self.session.execute(query)]
