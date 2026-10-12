from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.equipment import (
    Equipment,
    EquipmentCustodyHistory,
    EquipmentLocationHistory,
    EquipmentStatusHistory,
    EquipmentType,
    Location,
)
from app.repositories.base import BaseRepository, Page, escape_like
from app.schemas.equipment import EquipmentCreate, EquipmentUpdate, LocationCreate

EQUIPMENT_SORT_FIELDS = {
    "asset_tag": Equipment.asset_tag,
    "brand": Equipment.brand,
    "model": Equipment.model,
    "status": Equipment.status,
    "purchase_date": Equipment.purchase_date,
    "created_at": Equipment.created_at,
    "id": Equipment.id,
}


class EquipmentRepository(BaseRepository[Equipment]):
    model = Equipment

    @staticmethod
    def _equipment_query():
        return select(Equipment).options(selectinload(Equipment.equipment_type))

    async def list_equipment(
        self,
        *,
        status: str | None = None,
        equipment_type_id: int | None = None,
        brand: str | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[Equipment]:
        query = self._equipment_query()
        if status is not None:
            query = query.where(Equipment.status == status)
        if equipment_type_id is not None:
            query = query.where(Equipment.equipment_type_id == equipment_type_id)
        if brand:
            query = query.where(Equipment.brand.ilike(escape_like(brand), escape="\\"))
        query = self.apply_search(
            query,
            search,
            [
                Equipment.asset_tag,
                Equipment.serial_number,
                Equipment.brand,
                Equipment.model,
            ],
        )
        query = self.apply_ordering(
            query,
            params.sort,
            EQUIPMENT_SORT_FIELDS,
            default=(Equipment.asset_tag, Equipment.id),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

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

    async def active_type_ids_by_code(self) -> dict[str, int]:
        result = await self.session.execute(
            select(EquipmentType.code, EquipmentType.id).where(
                EquipmentType.is_active.is_(True)
            )
        )
        return {code.upper(): type_id for code, type_id in result.all()}

    async def find_existing_identifiers(
        self, asset_tags: set[str], serial_numbers: set[str]
    ) -> tuple[set[str], set[str]]:
        """Which of the given asset tags / serial numbers are already registered."""
        tags: set[str] = set()
        serials: set[str] = set()
        if asset_tags:
            result = await self.session.execute(
                select(Equipment.asset_tag).where(Equipment.asset_tag.in_(asset_tags))
            )
            tags = set(result.scalars().all())
        if serial_numbers:
            result = await self.session.execute(
                select(Equipment.serial_number).where(
                    Equipment.serial_number.in_(serial_numbers)
                )
            )
            serials = set(result.scalars().all())
        return tags, serials

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

    def record_status_change(
        self,
        *,
        equipment_id: int,
        from_status: str | None,
        to_status: str,
        changed_by_user_id: int | None,
        reason: str | None,
    ) -> None:
        self.session.add(
            EquipmentStatusHistory(
                equipment_id=equipment_id,
                from_status=from_status,
                to_status=to_status,
                changed_by_user_id=changed_by_user_id,
                reason=reason,
            )
        )

    # -- Locations -----------------------------------------------------

    async def list_locations(
        self, *, search: str | None = None, params: PageParams = DEFAULT_PAGE
    ) -> Page[Location]:
        query = select(Location).where(Location.is_active.is_(True))
        query = self.apply_search(query, search, [Location.name])
        query = self.apply_ordering(
            query,
            params.sort,
            {"name": Location.name, "id": Location.id},
            default=(Location.name, Location.id),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def get_location(self, location_id: int) -> Location | None:
        result = await self.session.execute(
            select(Location).where(
                Location.id == location_id, Location.is_active.is_(True)
            )
        )
        return result.scalar_one_or_none()

    async def create_location(self, payload: LocationCreate) -> Location:
        location = Location(**payload.model_dump())
        self.session.add(location)
        await self.session.flush()
        return location

    async def get_active_location(
        self, equipment_id: int
    ) -> EquipmentLocationHistory | None:
        result = await self.session.execute(
            select(EquipmentLocationHistory).where(
                EquipmentLocationHistory.equipment_id == equipment_id,
                EquipmentLocationHistory.ended_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    async def assign_location(
        self,
        *,
        equipment_id: int,
        location_id: int,
        moved_by_user_id: int | None,
        notes: str | None,
    ) -> EquipmentLocationHistory:
        active = await self.get_active_location(equipment_id)
        now = datetime.now(UTC)
        if active is not None:
            active.ended_at = now
        entry = EquipmentLocationHistory(
            equipment_id=equipment_id,
            location_id=location_id,
            moved_by_user_id=moved_by_user_id,
            notes=notes,
        )
        self.session.add(entry)
        await self.session.flush()
        return entry

    # -- Custody ---------------------------------------------------------

    async def get_active_custody(
        self, equipment_id: int
    ) -> EquipmentCustodyHistory | None:
        result = await self.session.execute(
            select(EquipmentCustodyHistory).where(
                EquipmentCustodyHistory.equipment_id == equipment_id,
                EquipmentCustodyHistory.returned_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    async def assign_custody(
        self,
        *,
        equipment_id: int,
        assigned_to_user_id: int,
        assigned_by_user_id: int | None,
        notes: str | None,
    ) -> EquipmentCustodyHistory:
        active = await self.get_active_custody(equipment_id)
        now = datetime.now(UTC)
        if active is not None:
            active.returned_at = now
        entry = EquipmentCustodyHistory(
            equipment_id=equipment_id,
            assigned_to_user_id=assigned_to_user_id,
            assigned_by_user_id=assigned_by_user_id,
            notes=notes,
        )
        self.session.add(entry)
        await self.session.flush()
        return entry
