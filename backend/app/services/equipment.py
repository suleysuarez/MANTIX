from sqlalchemy.exc import IntegrityError

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.models.equipment import Equipment
from app.repositories.equipment import EquipmentRepository
from app.schemas.equipment import (
    EquipmentCreate,
    EquipmentCustodyAssignRequest,
    EquipmentLocationAssignRequest,
    EquipmentResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
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
        search: str | None = None,
        limit: int = 200,
        offset: int = 0,
    ) -> list[EquipmentResponse]:
        items = await self.repository.list_equipment(
            status=status,
            equipment_type_id=equipment_type_id,
            search=search,
            limit=min(limit, 500),
            offset=offset,
        )
        return [EquipmentResponse.model_validate(item) for item in items]

    async def list_types(self) -> list[EquipmentTypeResponse]:
        return [
            EquipmentTypeResponse.model_validate(item)
            for item in await self.repository.list_types()
        ]

    async def get(self, equipment_id: int) -> EquipmentResponse:
        return self._response(await self.repository.get(equipment_id))

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
        equipment = await self.repository.get(equipment.id)
        return self._response(equipment)

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
        updated = await self.repository.get(equipment_id)
        return self._response(updated)

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
        return self._response(await self.repository.get(equipment_id))

    async def assign_custody(
        self,
        equipment_id: int,
        payload: EquipmentCustodyAssignRequest,
        actor: AuthContext,
    ) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        if equipment is None:
            raise NotFoundError("equipment not found")
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
        return self._response(await self.repository.get(equipment_id))

    async def list_locations(self) -> list[LocationResponse]:
        return [
            LocationResponse.model_validate(item)
            for item in await self.repository.list_locations()
        ]

    async def create_location(self, payload: LocationCreate) -> LocationResponse:
        try:
            location = await self.repository.create_location(payload)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("location code or name already exists") from exc
        return LocationResponse.model_validate(location)

    @staticmethod
    def _response(equipment: Equipment | None) -> EquipmentResponse:
        if equipment is None:
            raise NotFoundError("equipment not found")
        return EquipmentResponse.model_validate(equipment)
