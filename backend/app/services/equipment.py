from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.equipment import Equipment
from app.repositories.equipment import EquipmentRepository
from app.schemas.equipment import (
    EquipmentCreate,
    EquipmentResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
)


class EquipmentService:
    def __init__(self, session: AsyncSession):
        self.repository = EquipmentRepository(session)

    async def list_equipment(self) -> list[EquipmentResponse]:
        return [
            EquipmentResponse.model_validate(item)
            for item in await self.repository.list_equipment()
        ]

    async def list_types(self) -> list[EquipmentTypeResponse]:
        return [
            EquipmentTypeResponse.model_validate(item)
            for item in await self.repository.list_types()
        ]

    async def create(self, payload: EquipmentCreate) -> EquipmentResponse:
        if await self.repository.get_type(payload.equipment_type_id) is None:
            raise HTTPException(status_code=404, detail="equipment type not found")
        try:
            equipment = await self.repository.create(payload)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise HTTPException(
                status_code=409,
                detail="asset_tag or serial_number already exists",
            ) from exc
        equipment = await self.repository.get(equipment.id)
        return self._response(equipment)

    async def update(
        self, equipment_id: int, payload: EquipmentUpdate
    ) -> EquipmentResponse:
        equipment = await self.repository.get(equipment_id)
        if equipment is None:
            raise HTTPException(status_code=404, detail="equipment not found")
        if (
            payload.equipment_type_id is not None
            and await self.repository.get_type(payload.equipment_type_id) is None
        ):
            raise HTTPException(status_code=404, detail="equipment type not found")
        try:
            await self.repository.update(equipment, payload)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise HTTPException(
                status_code=409,
                detail="serial_number already exists",
            ) from exc
        updated = await self.repository.get(equipment_id)
        return self._response(updated)

    @staticmethod
    def _response(equipment: Equipment | None) -> EquipmentResponse:
        if equipment is None:
            raise HTTPException(status_code=404, detail="equipment not found")
        return EquipmentResponse.model_validate(equipment)
