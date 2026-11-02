from sqlalchemy.exc import IntegrityError

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.equipment import Equipment
from app.repositories.base import Page
from app.repositories.equipment import EquipmentContext, EquipmentRepository
from app.schemas.equipment import (
    CustodianBrief,
    CustodianCandidate,
    EquipmentCreate,
    EquipmentCustodyAssignRequest,
    EquipmentLocationAssignRequest,
    EquipmentResponse,
    EquipmentSummaryResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
    LastMaintenance,
    LocationBrief,
    LocationCreate,
    LocationResponse,
)
from app.services.audit import AuditService


class EquipmentService:
    def __init__(self, repository: EquipmentRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    async def list_equipment(
        self,
        *,
        status: str | None = None,
        equipment_type_id: int | None = None,
        location_id: int | None = None,
        brand: str | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[EquipmentResponse]:
        page = await self.repository.list_equipment(
            status=status,
            equipment_type_id=equipment_type_id,
            location_id=location_id,
            brand=brand,
            search=search,
            params=params,
        )
        contexts = await self.repository.current_context([e.id for e in page.items])
        return page.map(lambda item: self._response(item, contexts.get(item.id)))

    async def summary(self) -> EquipmentSummaryResponse:
        counts = await self.repository.status_counts()
        return EquipmentSummaryResponse(total=sum(counts.values()), by_status=counts)

    async def custodian_candidates(
        self, search: str | None = None
    ) -> list[CustodianCandidate]:
        users = await self.repository.search_active_users(search)
        return [CustodianCandidate.model_validate(user) for user in users]

    async def list_types(self) -> list[EquipmentTypeResponse]:
        return [
            EquipmentTypeResponse.model_validate(item)
            for item in await self.repository.list_types()
        ]

    async def get(self, equipment_id: int) -> EquipmentResponse:
        return await self._present(equipment_id)

    async def create(
        self, payload: EquipmentCreate, actor: AuthContext
    ) -> EquipmentResponse:
        if await self.repository.get_type(payload.equipment_type_id) is None:
            raise NotFoundError("equipment type not found")
        try:
            equipment = await self.repository.create(payload)
            self.repository.record_status_change(
                equipment_id=equipment.id,
                from_status=None,
                to_status=equipment.status,
                changed_by_user_id=actor.id,
                reason="equipment registered",
            )
            self.audit.record(
                user_id=actor.id,
                action="equipment.created",
                entity_type="equipment",
                entity_id=equipment.id,
                new_values={
                    "asset_tag": equipment.asset_tag,
                    "status": equipment.status,
                },
            )
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("asset_tag or serial_number already exists") from exc
        return await self._present(equipment.id)

    async def update(
        self, equipment_id: int, payload: EquipmentUpdate, actor: AuthContext
    ) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        if equipment is None:
            raise NotFoundError("equipment not found")
        if (
            payload.equipment_type_id is not None
            and await self.repository.get_type(payload.equipment_type_id) is None
        ):
            raise NotFoundError("equipment type not found")

        self._validate_warranty_dates(equipment, payload)

        previous_status = equipment.status
        try:
            await self.repository.update(equipment, payload)
            changes = payload.model_dump(exclude_unset=True)
            if "status" in changes and changes["status"] != previous_status:
                self.repository.record_status_change(
                    equipment_id=equipment.id,
                    from_status=previous_status,
                    to_status=changes["status"],
                    changed_by_user_id=actor.id,
                    reason=None,
                )
            if changes:
                self.audit.record(
                    user_id=actor.id,
                    action="equipment.updated",
                    entity_type="equipment",
                    entity_id=equipment.id,
                    old_values={"status": previous_status},
                    new_values=changes,
                )
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("serial_number already exists") from exc
        return await self._present(equipment_id)

    @staticmethod
    def _validate_warranty_dates(
        equipment: Equipment, payload: EquipmentUpdate
    ) -> None:
        """`EquipmentUpdate`'s validator only checks the two dates when both are
        sent in the same PATCH; compare against the stored value too so a
        single-field PATCH can't silently produce an inconsistent pair."""
        start = (
            payload.warranty_start_date
            if payload.warranty_start_date is not None
            else equipment.warranty_start_date
        )
        end = (
            payload.warranty_end_date
            if payload.warranty_end_date is not None
            else equipment.warranty_end_date
        )
        if start and end and end < start:
            raise ConflictError("warranty_end_date cannot precede warranty_start_date")

    async def assign_location(
        self,
        equipment_id: int,
        payload: EquipmentLocationAssignRequest,
        actor: AuthContext,
    ) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        if equipment is None:
            raise NotFoundError("equipment not found")
        if await self.repository.get_location(payload.location_id) is None:
            raise NotFoundError("location not found")
        await self.repository.assign_location(
            equipment_id=equipment_id,
            location_id=payload.location_id,
            moved_by_user_id=actor.id,
            notes=payload.notes,
        )
        self.audit.record(
            user_id=actor.id,
            action="equipment.location_assigned",
            entity_type="equipment",
            entity_id=equipment_id,
            new_values={"location_id": payload.location_id},
        )
        await self.repository.commit()
        return await self._present(equipment_id)

    async def assign_custody(
        self,
        equipment_id: int,
        payload: EquipmentCustodyAssignRequest,
        actor: AuthContext,
    ) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        if equipment is None:
            raise NotFoundError("equipment not found")
        if await self.repository.get_active_user(payload.assigned_to_user_id) is None:
            raise NotFoundError("active user not found")
        await self.repository.assign_custody(
            equipment_id=equipment_id,
            assigned_to_user_id=payload.assigned_to_user_id,
            assigned_by_user_id=actor.id,
            notes=payload.notes,
        )
        self.audit.record(
            user_id=actor.id,
            action="equipment.custody_assigned",
            entity_type="equipment",
            entity_id=equipment_id,
            new_values={"assigned_to_user_id": payload.assigned_to_user_id},
        )
        await self.repository.commit()
        return await self._present(equipment_id)

    async def list_locations(
        self, *, search: str | None = None, params: PageParams = DEFAULT_PAGE
    ) -> Page[LocationResponse]:
        page = await self.repository.list_locations(search=search, params=params)
        return page.map(LocationResponse.model_validate)

    async def create_location(
        self, payload: LocationCreate, actor: AuthContext
    ) -> LocationResponse:
        try:
            location = await self.repository.create_location(payload)
            self.audit.record(
                user_id=actor.id,
                action="location.created",
                entity_type="location",
                entity_id=location.id,
                new_values={"code": payload.code, "name": payload.name},
            )
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("location code or name already exists") from exc
        return LocationResponse.model_validate(location)

    async def _present(self, equipment_id: int) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        contexts = await self.repository.current_context([equipment_id])
        return self._response(equipment, contexts.get(equipment_id))

    @staticmethod
    def _response(
        equipment: Equipment | None, context: EquipmentContext | None = None
    ) -> EquipmentResponse:
        if equipment is None:
            raise NotFoundError("equipment not found")
        response = EquipmentResponse.model_validate(equipment)
        if context is None:
            return response
        if context.location is not None:
            location_id, code, name = context.location
            response.current_location = LocationBrief(
                id=location_id, code=code, name=name
            )
        if context.custodian is not None:
            user_id, full_name, email = context.custodian
            response.current_custodian = CustodianBrief(
                id=user_id, full_name=full_name, email=email
            )
        if context.last_maintenance is not None:
            performed_at, work_type, result, technician = context.last_maintenance
            response.last_maintenance = LastMaintenance(
                performed_at=performed_at,
                work_type=work_type,
                result=result,
                technician_name=technician,
            )
        return response
