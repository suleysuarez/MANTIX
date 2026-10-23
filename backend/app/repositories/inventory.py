"""Stock items, the movement ledger and the aggregates behind the Inventory screen."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import Select, and_, case, func, or_, select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.inventory import InventoryItem, InventoryMovement, InventoryOption
from app.models.maintenance import MaintenanceRecord, MaintenanceRequest
from app.repositories.base import BaseRepository, Page

#: Days without movement after which in-stock items count as stale.
STALE_DAYS = 90

_STOCK_VALUE = InventoryItem.stock * InventoryItem.unit_cost
_LAST_MOVEMENT = (
    select(func.max(InventoryMovement.created_at))
    .where(InventoryMovement.item_id == InventoryItem.id)
    .scalar_subquery()
)

SORTABLE = {
    "name": InventoryItem.name,
    "sku": InventoryItem.sku,
    "stock": InventoryItem.stock,
    "unit_cost": InventoryItem.unit_cost,
    "stock_value": _STOCK_VALUE,
    "updated_at": InventoryItem.updated_at,
    "created_at": InventoryItem.created_at,
    "id": InventoryItem.id,
}


@dataclass(frozen=True, slots=True)
class ConsumptionRow:
    units: int
    value: Decimal
    movements: int


@dataclass(frozen=True, slots=True)
class MonthRow:
    month: datetime
    units: int


@dataclass(frozen=True, slots=True)
class ItemUnits:
    item_id: int
    sku: str
    name: str
    units: int


@dataclass(frozen=True, slots=True)
class StaleRow:
    item_id: int
    sku: str
    name: str
    stock: int
    last_movement_at: datetime | None


@dataclass(frozen=True, slots=True)
class ReorderRow:
    item_id: int
    sku: str
    name: str
    stock: int
    min_stock: int
    max_stock: int | None


@dataclass(frozen=True, slots=True)
class ItemRanges:
    """Optional bounds for the item list; every pair is inclusive and may be one-sided."""

    stock_min: int | None = None
    stock_max: int | None = None
    cost_min: Decimal | None = None
    cost_max: Decimal | None = None
    created_from: datetime | None = None
    created_to: datetime | None = None
    moved_from: datetime | None = None
    moved_to: datetime | None = None


class InventoryRepository(BaseRepository[InventoryItem]):
    model = InventoryItem

    # -- drop-down options -------------------------------------------------------------

    async def list_options(self, kind: str | None = None) -> list[InventoryOption]:
        query = select(InventoryOption).order_by(
            InventoryOption.kind, InventoryOption.label
        )
        if kind:
            query = query.where(InventoryOption.kind == kind)
        return list((await self.session.execute(query)).scalars().all())

    async def option_by_key(self, kind: str, key: str) -> InventoryOption | None:
        result = await self.session.execute(
            select(InventoryOption).where(
                InventoryOption.kind == kind, InventoryOption.key == key
            )
        )
        found: InventoryOption | None = result.scalar_one_or_none()
        return found

    async def add_option(
        self, *, kind: str, value: str, label: str, key: str
    ) -> InventoryOption:
        option = InventoryOption(kind=kind, value=value, label=label, key=key)
        self.session.add(option)
        await self.session.flush()
        return option

    # -- items -------------------------------------------------------------------------

    async def get(self, item_id: int) -> InventoryItem | None:
        result = await self.session.execute(
            select(InventoryItem).where(InventoryItem.id == item_id)
        )
        item: InventoryItem | None = result.scalar_one_or_none()
        return item

    async def get_for_update(self, item_id: int) -> InventoryItem | None:
        """Row-locked read: concurrent movements on one item queue up, so stock can
        never be consumed twice or driven below zero by a race."""
        result = await self.session.execute(
            select(InventoryItem)
            .where(InventoryItem.id == item_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        item: InventoryItem | None = result.scalar_one_or_none()
        return item

    async def find_skus(self, skus: set[str]) -> set[str]:
        if not skus:
            return set()
        rows = await self.session.execute(
            select(InventoryItem.sku).where(InventoryItem.sku.in_(skus))
        )
        return {row[0] for row in rows.all()}

    async def has_movements(self, item_id: int) -> bool:
        row = await self.session.execute(
            select(InventoryMovement.id)
            .where(InventoryMovement.item_id == item_id)
            .limit(1)
        )
        return row.first() is not None

    async def delete_item(self, item: InventoryItem) -> None:
        await self.session.delete(item)
        await self.session.flush()

    async def search(
        self,
        *,
        search: str | None = None,
        category: str | None = None,
        status: str | None = None,
        now: datetime,
        params: PageParams = DEFAULT_PAGE,
        ranges: "ItemRanges | None" = None,
    ) -> Page[InventoryItem]:
        query: Select[Any] = select(InventoryItem)
        if category:
            query = query.where(InventoryItem.category == category)
        if ranges is not None:
            query = self._apply_ranges(query, ranges)
        stale_before = now - timedelta(days=STALE_DAYS)
        filters = {
            "out": and_(InventoryItem.is_active.is_(True), InventoryItem.stock == 0),
            "low": and_(
                InventoryItem.is_active.is_(True),
                InventoryItem.stock > 0,
                InventoryItem.stock <= InventoryItem.min_stock,
            ),
            "ok": and_(
                InventoryItem.is_active.is_(True),
                InventoryItem.stock > InventoryItem.min_stock,
            ),
            "stale": and_(
                InventoryItem.is_active.is_(True),
                InventoryItem.stock > 0,
                func.coalesce(_LAST_MOVEMENT, InventoryItem.created_at) < stale_before,
            ),
            "active": InventoryItem.is_active.is_(True),
            "inactive": InventoryItem.is_active.is_(False),
        }
        if status in filters:
            query = query.where(filters[status])
        query = self.apply_search(
            query,
            search,
            [
                InventoryItem.sku,
                InventoryItem.name,
                InventoryItem.supplier,
                InventoryItem.location,
            ],
        )
        query = self.apply_ordering(
            query,
            params.sort,
            SORTABLE,
            default=(InventoryItem.name.asc(), InventoryItem.id),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    @staticmethod
    def _apply_ranges(query: Select[Any], r: "ItemRanges") -> Select[Any]:
        """Stock and unit-cost ranges, and the dates an item was added / last moved."""
        bounds = (
            (InventoryItem.stock, r.stock_min, r.stock_max),
            (InventoryItem.unit_cost, r.cost_min, r.cost_max),
            (InventoryItem.created_at, r.created_from, r.created_to),
            (_LAST_MOVEMENT, r.moved_from, r.moved_to),
        )
        for column, low, high in bounds:
            if low is not None:
                query = query.where(column >= low)
            if high is not None:
                query = query.where(column <= high)
        return query

    async def last_movements(self, item_ids: list[int]) -> dict[int, datetime]:
        if not item_ids:
            return {}
        rows = await self.session.execute(
            select(InventoryMovement.item_id, func.max(InventoryMovement.created_at))
            .where(InventoryMovement.item_id.in_(item_ids))
            .group_by(InventoryMovement.item_id)
        )
        return {row[0]: row[1] for row in rows.all()}

    # -- movements ---------------------------------------------------------------------

    def add_movement(
        self,
        *,
        item_id: int,
        kind: str,
        quantity: int,
        stock_after: int,
        unit_cost: Decimal | None,
        notes: str | None,
        record_id: int | None,
        request_id: int | None,
        user_id: int | None,
    ) -> InventoryMovement:
        movement = InventoryMovement(
            item_id=item_id,
            kind=kind,
            quantity=quantity,
            stock_after=stock_after,
            unit_cost=unit_cost,
            notes=notes,
            record_id=record_id,
            request_id=request_id,
            created_by_user_id=user_id,
        )
        self.session.add(movement)
        return movement

    async def list_movements(
        self, item_id: int, *, params: PageParams = DEFAULT_PAGE
    ) -> Page[InventoryMovement]:
        query = (
            select(InventoryMovement)
            .options(selectinload(InventoryMovement.created_by))
            .where(InventoryMovement.item_id == item_id)
            .order_by(InventoryMovement.created_at.desc(), InventoryMovement.id.desc())
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def record_exists(self, record_id: int) -> bool:
        row = await self.session.execute(
            select(MaintenanceRecord.id).where(MaintenanceRecord.id == record_id)
        )
        return row.first() is not None

    async def request_exists(self, request_id: int) -> bool:
        row = await self.session.execute(
            select(MaintenanceRequest.id).where(MaintenanceRequest.id == request_id)
        )
        return row.first() is not None

    # -- aggregates --------------------------------------------------------------------

    async def stock_value_at(self, at: datetime) -> tuple[Decimal, int]:
        """Value and item count of the active items as of `at`, at current unit costs.

        Stock back then is today's stock minus the movements made since.
        """
        item = InventoryItem
        moved_since = (
            select(func.coalesce(func.sum(InventoryMovement.quantity), 0))
            .where(
                InventoryMovement.item_id == item.id, InventoryMovement.created_at > at
            )
            .correlate(item)
            .scalar_subquery()
        )
        stock_then = func.greatest(item.stock - moved_since, 0)
        row = (
            await self.session.execute(
                select(
                    func.coalesce(func.sum(stock_then * item.unit_cost), 0),
                    func.count(),
                ).where(item.is_active.is_(True), item.created_at <= at)
            )
        ).one()
        return Decimal(row[0]), int(row[1])

    async def consumption(self, *, start: datetime, end: datetime) -> ConsumptionRow:
        move = InventoryMovement
        row = (
            await self.session.execute(
                select(
                    func.coalesce(func.sum(-move.quantity), 0),
                    func.coalesce(
                        func.sum(-move.quantity * InventoryItem.unit_cost), 0
                    ),
                    func.count(),
                )
                .join(InventoryItem, InventoryItem.id == move.item_id)
                .where(
                    move.kind == "out", move.created_at >= start, move.created_at < end
                )
            )
        ).one()
        return ConsumptionRow(
            units=int(row[0]), value=Decimal(row[1]), movements=row[2]
        )

    async def monthly_consumption(
        self, *, start: datetime, end: datetime
    ) -> list[MonthRow]:
        move = InventoryMovement
        month = func.date_trunc("month", move.created_at, "UTC")
        rows = (
            await self.session.execute(
                select(month, func.sum(-move.quantity))
                .where(
                    move.kind == "out", move.created_at >= start, move.created_at < end
                )
                .group_by(month)
                .order_by(month)
            )
        ).all()
        return [MonthRow(month=row[0], units=int(row[1])) for row in rows]

    async def counts(self) -> tuple[int, int]:
        """(low, out) among active items, now."""
        item = InventoryItem
        row = (
            await self.session.execute(
                select(
                    func.count().filter(
                        and_(item.stock > 0, item.stock <= item.min_stock)
                    ),
                    func.count().filter(item.stock == 0),
                ).where(item.is_active.is_(True))
            )
        ).one()
        return int(row[0]), int(row[1])

    async def stale(self, now: datetime, *, limit: int) -> tuple[int, list[StaleRow]]:
        item = InventoryItem
        last = func.coalesce(_LAST_MOVEMENT, item.created_at)
        condition = and_(
            item.is_active.is_(True),
            item.stock > 0,
            last < now - timedelta(days=STALE_DAYS),
        )
        total = (
            await self.session.execute(select(func.count()).where(condition))
        ).scalar_one()
        rows = (
            await self.session.execute(
                select(item.id, item.sku, item.name, item.stock, _LAST_MOVEMENT)
                .where(condition)
                .order_by(last.asc())
                .limit(limit)
            )
        ).all()
        return int(total), [StaleRow(*row) for row in rows]

    async def most_used(
        self, *, start: datetime, end: datetime, limit: int
    ) -> list[ItemUnits]:
        """Items consumed in maintenance work (linked to a record or a ticket)."""
        move = InventoryMovement
        units = func.sum(-move.quantity)
        rows = (
            await self.session.execute(
                select(InventoryItem.id, InventoryItem.sku, InventoryItem.name, units)
                .join(InventoryItem, InventoryItem.id == move.item_id)
                .where(
                    move.kind == "out",
                    move.created_at >= start,
                    move.created_at < end,
                    or_(move.record_id.is_not(None), move.request_id.is_not(None)),
                )
                .group_by(InventoryItem.id)
                .order_by(units.desc(), InventoryItem.sku)
                .limit(limit)
            )
        ).all()
        return [ItemUnits(row[0], row[1], row[2], int(row[3])) for row in rows]

    async def reorder(self, *, limit: int) -> list[ReorderRow]:
        """Active items at or below their minimum (or out of stock), emptiest first."""
        item = InventoryItem
        ratio = case((item.min_stock > 0, item.stock * 1.0 / item.min_stock), else_=0.0)
        rows = (
            await self.session.execute(
                select(
                    item.id,
                    item.sku,
                    item.name,
                    item.stock,
                    item.min_stock,
                    item.max_stock,
                )
                .where(
                    item.is_active.is_(True),
                    or_(item.stock == 0, item.stock <= item.min_stock),
                )
                .order_by(ratio.asc(), item.sku)
                .limit(limit)
            )
        ).all()
        return [ReorderRow(*row) for row in rows]
