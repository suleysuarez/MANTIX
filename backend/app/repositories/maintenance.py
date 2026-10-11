from datetime import datetime, timezone

from sqlalchemy import select, text
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.equipment import Equipment
from app.models.maintenance import (
    MaintenanceRecord,
    MaintenanceRequest,
    TicketAssignment,
    TicketStatusHistory,
)
from app.models.priority import Priority
from app.models.technician import Technician
from app.repositories.base import BaseRepository, Page
from app.schemas.maintenance import MaintenanceRecordCreate

#: Priority is sorted by its catalog `level`, not alphabetically by code.
_PRIORITY_LEVEL = (
    select(Priority.level)
    .where(Priority.code == MaintenanceRequest.priority)
    .scalar_subquery()
)

REQUEST_SORT_FIELDS = {
    "created_at": MaintenanceRequest.created_at,
    "updated_at": MaintenanceRequest.updated_at,
    "status": MaintenanceRequest.status,
    "priority": _PRIORITY_LEVEL,
    "ticket_number": MaintenanceRequest.ticket_number,
    "id": MaintenanceRequest.id,
}


class MaintenanceRepository(BaseRepository[MaintenanceRequest]):
    model = MaintenanceRequest

    @staticmethod
    def _request_query():
        return select(MaintenanceRequest).options(
            selectinload(MaintenanceRequest.equipment),
            selectinload(MaintenanceRequest.requested_by_user),
            selectinload(MaintenanceRequest.ticket_assignments)
            .selectinload(TicketAssignment.technician)
            .selectinload(Technician.user),
            selectinload(MaintenanceRequest.status_history),
        )

    def expire_mutable_collections(self, request: MaintenanceRequest) -> None:
        """Force `ticket_assignments`/`status_history` to be re-fetched on
        the next query for this specific object.

        The service reloads the same request within one session after
        mutating those two collections (new assignment, new status-history
        row) — by default SQLAlchemy would hand back the same identity-mapped
        Python object with its *already loaded* collections left stale.

        This must stay scoped to exactly these two attributes on this one
        object. `session.execute(..., execution_options={"populate_existing":
        True})` looks like the obvious alternative, but it resets *every*
        attribute not covered by the query's own load options - including
        ones eagerly loaded elsewhere, like `requested_by_user.roles`. If the
        actor happens to be the ticket's own requester (an admin managing
        their own ticket, say), that wipes the *actor's* already-loaded roles
        out from under it via the identity map, and the very next permission
        check crashes with a lazy-load `MissingGreenlet` in async SQLAlchemy.
        `session.expire(obj, [...])` only targets the named attributes on
        `obj` itself, so it can't cross-contaminate unrelated objects.
        """
        self.session.expire(request, ["ticket_assignments", "status_history"])

    async def next_ticket_number(self) -> str:
        result = await self.session.execute(
            text("SELECT nextval('maintenance_ticket_number_seq')")
        )
        sequence_value = result.scalar_one()
        year = datetime.now(timezone.utc).year
        return f"TCK-{year}-{sequence_value:06d}"

    async def get_equipment(self, equipment_id: int) -> Equipment | None:
        result = await self.session.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        return result.scalar_one_or_none()

    async def get_active_priority(self, code: str) -> Priority | None:
        result = await self.session.execute(
            select(Priority).where(Priority.code == code, Priority.is_active.is_(True))
        )
        return result.scalar_one_or_none()

    async def get(self, request_id: int) -> MaintenanceRequest | None:
        result = await self.session.execute(
            self._request_query().where(MaintenanceRequest.id == request_id)
        )
        return result.scalar_one_or_none()

    async def list_requests(
        self,
        *,
        status: str | None = None,
        priority: str | None = None,
        equipment_id: int | None = None,
        requested_by_user_id: int | None = None,
        technician_id: int | None = None,
        search: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[MaintenanceRequest]:
        query = select(MaintenanceRequest)
        if status is not None:
            query = query.where(MaintenanceRequest.status == status)
        if priority is not None:
            query = query.where(MaintenanceRequest.priority == priority)
        if equipment_id is not None:
            query = query.where(MaintenanceRequest.equipment_id == equipment_id)
        if requested_by_user_id is not None:
            query = query.where(
                MaintenanceRequest.requested_by_user_id == requested_by_user_id
            )
        if technician_id is not None:
            query = query.where(
                MaintenanceRequest.ticket_assignments.any(
                    TicketAssignment.technician_id == technician_id,
                    TicketAssignment.unassigned_at.is_(None),
                )
            )
        if date_from is not None:
            query = query.where(MaintenanceRequest.created_at >= date_from)
        if date_to is not None:
            query = query.where(MaintenanceRequest.created_at <= date_to)
        query = self.apply_search(
            query,
            search,
            [
                MaintenanceRequest.ticket_number,
                MaintenanceRequest.title,
                MaintenanceRequest.description,
            ],
        )
        query = self.apply_ordering(
            query,
            params.sort,
            REQUEST_SORT_FIELDS,
            default=(
                MaintenanceRequest.created_at.desc(),
                MaintenanceRequest.id.desc(),
            ),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def create_request(
        self,
        *,
        ticket_number: str,
        equipment_id: int,
        requested_by_user_id: int,
        title: str,
        description: str,
        priority: str,
    ) -> MaintenanceRequest:
        request = MaintenanceRequest(
            ticket_number=ticket_number,
            equipment_id=equipment_id,
            requested_by_user_id=requested_by_user_id,
            title=title,
            description=description,
            priority=priority,
            status="submitted",
        )
        self.session.add(request)
        await self.session.flush()
        return request

    def append_status_history(
        self,
        *,
        request_id: int,
        from_status: str | None,
        to_status: str,
        changed_by_user_id: int | None,
        notes: str | None,
    ) -> None:
        self.session.add(
            TicketStatusHistory(
                request_id=request_id,
                from_status=from_status,
                to_status=to_status,
                changed_by_user_id=changed_by_user_id,
                notes=notes,
            )
        )

    async def get_technician(self, technician_id: int) -> Technician | None:
        result = await self.session.execute(
            select(Technician)
            .options(selectinload(Technician.user))
            .where(Technician.id == technician_id)
        )
        return result.scalar_one_or_none()

    async def get_technician_by_user_id(self, user_id: int) -> Technician | None:
        result = await self.session.execute(
            select(Technician).where(Technician.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def get_active_assignment(self, request_id: int) -> TicketAssignment | None:
        result = await self.session.execute(
            select(TicketAssignment)
            .options(selectinload(TicketAssignment.technician))
            .where(
                TicketAssignment.request_id == request_id,
                TicketAssignment.unassigned_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    async def assign_technician(
        self,
        *,
        request_id: int,
        technician_id: int,
        assigned_by_user_id: int | None,
        notes: str | None,
    ) -> TicketAssignment:
        active = await self.get_active_assignment(request_id)
        if active is not None:
            active.unassigned_at = datetime.now(timezone.utc)
        assignment = TicketAssignment(
            request_id=request_id,
            technician_id=technician_id,
            assigned_by_user_id=assigned_by_user_id,
            notes=notes,
        )
        self.session.add(assignment)
        await self.session.flush()
        return assignment

    async def unassign_active(self, request_id: int) -> TicketAssignment | None:
        active = await self.get_active_assignment(request_id)
        if active is None:
            return None
        active.unassigned_at = datetime.now(timezone.utc)
        await self.session.flush()
        return active

    async def create_record(
        self,
        *,
        equipment_id: int,
        request_id: int | None,
        technician_id: int,
        payload: MaintenanceRecordCreate,
    ) -> MaintenanceRecord:
        labor_cost = payload.labor_cost or 0
        parts_cost = payload.parts_cost or 0
        record = MaintenanceRecord(
            equipment_id=equipment_id,
            request_id=request_id,
            technician_id=technician_id,
            work_type=payload.work_type,
            started_at=payload.started_at,
            completed_at=payload.completed_at,
            diagnosis=payload.diagnosis,
            actions_taken=payload.actions_taken,
            result=payload.result,
            labor_cost=labor_cost,
            parts_cost=parts_cost,
            total_cost=labor_cost + parts_cost,
            notes=payload.notes,
        )
        self.session.add(record)
        await self.session.flush()
        return record

    async def list_records(self, request_id: int) -> list[MaintenanceRecord]:
        result = await self.session.execute(
            select(MaintenanceRecord)
            .where(MaintenanceRecord.request_id == request_id)
            .order_by(MaintenanceRecord.started_at.desc())
        )
        return list(result.scalars().all())
