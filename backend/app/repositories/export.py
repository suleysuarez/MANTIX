"""Rows behind the document exports (PDF and Excel). Ticket rows carry every field the
documents show, straight from the database: equipment, type, category, priority and SLA,
technician, dates and the costs recorded on the ticket's maintenance records."""

from typing import Any, cast

from sqlalchemy import Select, and_, func, select
from sqlalchemy.orm import aliased

from app.models.auth import User
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
