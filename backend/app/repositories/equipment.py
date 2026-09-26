from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.equipment import Equipment, EquipmentType
from app.schemas.equipment import EquipmentCreate, EquipmentUpdate


class EquipmentRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    @staticmethod
    def _equipment_query():
        return select(Equipment).options(selectinload(Equipment.equipment_type))

    async def list_equipment(self) -> list[Equipment]:
        result = await self.session.execute(
            self._equipment_query().order_by(Equipment.asset_tag)
        )
        return list(result.scalars().all())

    async def list_types(self) -> list[EquipmentType]:
        result = await self.session.execute(
            select(EquipmentType)
            .where(EquipmentType.is_active.is_(True))
            .order_by(EquipmentType.name)
        )
        return list(result.scalars().all())

    async def get(self, equipment_id: int) -> Equipment | None:
        result = await self.session.execute(
            self._equipment_query().where(Equipment.id == equipment_id)
        )
        return result.scalar_one_or_none()

    async def get_type(self, equipment_type_id: int) -> EquipmentType | None:
        result = await self.session.execute(
            select(EquipmentType).where(
                EquipmentType.id == equipment_type_id,
                EquipmentType.is_active.is_(True),
            )
        )
        return result.scalar_one_or_none()

    async def create(self, payload: EquipmentCreate) -> Equipment:
        equipment = Equipment(**payload.model_dump())
        self.session.add(equipment)
        await self.session.flush()
        return equipment

    async def update(self, equipment: Equipment, payload: EquipmentUpdate) -> Equipment:
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(equipment, field, value)
        await self.session.flush()
        return equipment

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
