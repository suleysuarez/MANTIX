"""Flat, joined read models for exports. No ORM entities leave this module."""

from datetime import datetime
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.orm import aliased

from app.models.auth import User
from app.models.equipment import (
    Equipment,
    EquipmentCustodyHistory,
    EquipmentLocationHistory,
    EquipmentType,
    Location,
)
from app.models.maintenance import MaintenanceRequest, TicketAssignment
from app.models.technician import Technician
from app.repositories.base import BaseRepository

#: Hard ceiling so one export cannot exhaust memory.
MAX_EXPORT_ROWS = 10_000


class ReportRepository(BaseRepository[MaintenanceRequest]):
    model = MaintenanceRequest

    async def equipment_rows(
        self,
        *,
        status: str | None = None,
        equipment_type_id: int | None = None,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        holder = aliased(User)
        query = (
            select(
                Equipment.asset_tag,
                Equipment.serial_number,
                EquipmentType.code.label("equipment_type"),
                Equipment.brand,
                Equipment.model,
                Equipment.status,
                Location.name.label("location"),
                holder.full_name.label("custodian"),
                Equipment.purchase_date,
                Equipment.purchase_cost,
                Equipment.warranty_end_date,
            )
            .join(EquipmentType, EquipmentType.id == Equipment.equipment_type_id)
            .outerjoin(
                EquipmentLocationHistory,
                and_(
                    EquipmentLocationHistory.equipment_id == Equipment.id,
                    EquipmentLocationHistory.ended_at.is_(None),
                ),
            )
            .outerjoin(Location, Location.id == EquipmentLocationHistory.location_id)
            .outerjoin(
                EquipmentCustodyHistory,
                and_(
                    EquipmentCustodyHistory.equipment_id == Equipment.id,
                    EquipmentCustodyHistory.returned_at.is_(None),
                ),
            )
            .outerjoin(holder, holder.id == EquipmentCustodyHistory.assigned_to_user_id)
            .order_by(Equipment.asset_tag)
            .limit(limit)
        )
        if status is not None:
            query = query.where(Equipment.status == status)
        if equipment_type_id is not None:
            query = query.where(Equipment.equipment_type_id == equipment_type_id)
        return [dict(row._mapping) for row in await self.session.execute(query)]

    async def ticket_rows(
        self,
        *,
        status: str | None = None,
        priority: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        requester = aliased(User)
        tech_user = aliased(User)
        hours_to_resolve = (
            func.extract(
                "epoch", MaintenanceRequest.resolved_at - MaintenanceRequest.created_at
            )
            / 3600
        )
        query = (
            select(
                MaintenanceRequest.ticket_number,
                MaintenanceRequest.title,
                MaintenanceRequest.priority,
                MaintenanceRequest.status,
                Equipment.asset_tag,
                requester.full_name.label("requested_by"),
                tech_user.full_name.label("technician"),
                MaintenanceRequest.created_at,
                MaintenanceRequest.resolved_at,
                MaintenanceRequest.closed_at,
                func.round(hours_to_resolve, 1).label("hours_to_resolve"),
            )
            .join(Equipment, Equipment.id == MaintenanceRequest.equipment_id)
            .join(requester, requester.id == MaintenanceRequest.requested_by_user_id)
            .outerjoin(
                TicketAssignment,
                and_(
                    TicketAssignment.request_id == MaintenanceRequest.id,
                    TicketAssignment.unassigned_at.is_(None),
                ),
            )
            .outerjoin(Technician, Technician.id == TicketAssignment.technician_id)
            .outerjoin(tech_user, tech_user.id == Technician.user_id)
            .order_by(
                MaintenanceRequest.created_at.desc(), MaintenanceRequest.id.desc()
            )
            .limit(limit)
        )
        if status is not None:
            query = query.where(MaintenanceRequest.status == status)
        if priority is not None:
            query = query.where(MaintenanceRequest.priority == priority)
        if date_from is not None:
            query = query.where(MaintenanceRequest.created_at >= date_from)
        if date_to is not None:
            query = query.where(MaintenanceRequest.created_at <= date_to)
        return [dict(row._mapping) for row in await self.session.execute(query)]
