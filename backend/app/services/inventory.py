from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from pydantic import ValidationError

from app.core.authz import AuthContext
from app.core.exceptions import (
    BusinessRuleError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
)
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.inventory import InventoryItem, InventoryMovement
from app.repositories.base import Page
from app.repositories.inventory import InventoryRepository
from app.schemas.dashboard import Period
from app.schemas.inventory import (
    MAX_QUANTITY,
    Consumption,
    InventoryOverview,
    ItemCreate,
    ItemResponse,
    ItemUpdate,
    MonthlyConsumption,
    MovementCreate,
    MovementResponse,
    ReorderAlert,
    Rotation,
    StaleItem,
    StockValue,
    UsedItem,
)
from app.schemas.report import ImportResult, ImportRowError
from app.services.audit import AuditService
from app.services.dashboard_kpis import (
    MIN_SAMPLE,
    change_pct,
    period_window,
    previous_window,
)

MANAGE = "inventory.manage"
_CENT = Decimal("0.01")
_NOT_NULL = ("name", "category", "unit", "unit_cost", "min_stock")


def _money(value: Decimal) -> Decimal:
    return value.quantize(_CENT)


def _jsonable(values: dict[str, Any]) -> dict[str, Any]:
    return {k: str(v) if isinstance(v, Decimal) else v for k, v in values.items()}


def _level(item: InventoryItem) -> float:
    reference = item.max_stock or max(item.min_stock * 2, item.stock, 1)
    return round(min(item.stock / reference * 100, 100), 1)


def _status(item: InventoryItem) -> str:
    if item.stock == 0:
        return "out"
    return "low" if item.stock <= item.min_stock else "ok"


def _suggested(max_stock: int | None, min_stock: int, stock: int) -> int:
    return max((max_stock or min_stock * 2) - stock, 1)


class InventoryService:
    """Stock items and their ledger. Movements are the only way stock changes."""

    def __init__(self, repository: InventoryRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    # -- items -------------------------------------------------------------------------

    async def list_items(
        self,
        *,
        search: str | None = None,
        category: str | None = None,
        status: str | None = None,
        params: PageParams = DEFAULT_PAGE,
        now: datetime | None = None,
    ) -> Page[ItemResponse]:
        page = await self.repository.search(
            search=search,
            category=category,
            status=status,
            now=now or datetime.now(UTC),
            params=params,
        )
        last = await self.repository.last_movements([item.id for item in page.items])
        return page.map(lambda item: self._response(item, last.get(item.id)))

    async def get(self, item_id: int) -> ItemResponse:
        item = await self._require(item_id)
        last = await self.repository.last_movements([item.id])
        return self._response(item, last.get(item.id))

    async def create(self, payload: ItemCreate, actor: AuthContext) -> ItemResponse:
        if await self.repository.find_skus({payload.sku}):
            raise ConflictError(f"an item with SKU '{payload.sku}' already exists")
        item = await self._add(payload, actor)
        await self.repository.commit()
        return await self.get(item.id)

    async def update(
        self, item_id: int, payload: ItemUpdate, actor: AuthContext
    ) -> ItemResponse:
        item = await self._require(item_id)
        changes = payload.model_dump(exclude_unset=True)
        for field in _NOT_NULL:
            if field in changes and changes[field] is None:
                raise UnprocessableError(f"{field} cannot be null")
        if "is_active" in changes and changes["is_active"] is None:
            raise UnprocessableError("is_active cannot be null")
        minimum = changes.get("min_stock", item.min_stock)
        maximum = changes.get("max_stock", item.max_stock)
        if maximum is not None and maximum < minimum:
            raise UnprocessableError("max_stock cannot be below min_stock")
        old = {field: getattr(item, field) for field in changes}
        await self.repository.update_fields(item, changes)
        self.audit.record(
            user_id=actor.id,
            action="inventory.item_updated",
            entity_type="inventory_item",
            entity_id=item_id,
            old_values=_jsonable(old),
            new_values=_jsonable(changes),
        )
        await self.repository.commit()
        return await self.get(item_id)

    async def delete(self, item_id: int, actor: AuthContext) -> None:
        item = await self._require(item_id)
        if await self.repository.has_movements(item_id):
            raise ConflictError(
                "the item has stock movements and cannot be deleted; deactivate it instead"
            )
        self.audit.record(
            user_id=actor.id,
            action="inventory.item_deleted",
            entity_type="inventory_item",
            entity_id=item_id,
            old_values={"sku": item.sku, "name": item.name},
        )
        await self.repository.delete_item(item)
        await self.repository.commit()

    # -- movements ---------------------------------------------------------------------

    async def move(
        self, item_id: int, payload: MovementCreate, actor: AuthContext
    ) -> MovementResponse:
        if payload.kind != "out" and MANAGE not in actor.permissions:
            raise ForbiddenError(
                "only inventory managers can register entries and adjustments"
            )
        item = await self.repository.get_for_update(item_id)
        if item is None:
            raise NotFoundError("inventory item not found")
        if not item.is_active:
            raise BusinessRuleError("an inactive item cannot move; reactivate it first")
        if payload.record_id and not await self.repository.record_exists(
            payload.record_id
        ):
            raise NotFoundError("maintenance record not found")
        if payload.request_id and not await self.repository.request_exists(
            payload.request_id
        ):
            raise NotFoundError("maintenance request not found")

        delta = -payload.quantity if payload.kind == "out" else payload.quantity
        new_stock = item.stock + delta
        if new_stock < 0:
            raise BusinessRuleError(
                f"insufficient stock: {item.stock} available, {abs(delta)} requested"
            )
        if new_stock > MAX_QUANTITY:
            raise UnprocessableError(f"stock cannot exceed {MAX_QUANTITY} units")

        old_stock = item.stock
        if payload.kind == "in" and payload.unit_cost is not None:
            item.unit_cost = _money(
                (item.stock * item.unit_cost + payload.quantity * payload.unit_cost)
                / (item.stock + payload.quantity)
            )
        item.stock = new_stock
        movement = self.repository.add_movement(
            item_id=item_id,
            kind=payload.kind,
            quantity=delta,
            stock_after=new_stock,
            unit_cost=payload.unit_cost,
            notes=payload.notes,
            record_id=payload.record_id,
            request_id=payload.request_id,
            user_id=actor.id,
        )
        await self.repository.flush()
        self.audit.record(
            user_id=actor.id,
            action="inventory.stock_moved",
            entity_type="inventory_item",
            entity_id=item_id,
            old_values={"stock": old_stock},
            new_values={"stock": new_stock, "kind": payload.kind, "quantity": delta},
        )
        await self.repository.commit()
        return self._movement(movement, actor.user.full_name)

    async def movements(
        self, item_id: int, *, params: PageParams = DEFAULT_PAGE
    ) -> Page[MovementResponse]:
        await self._require(item_id)
        page = await self.repository.list_movements(item_id, params=params)
        return page.map(
            lambda m: self._movement(
                m, m.created_by.full_name if m.created_by else None
            )
        )

    # -- overview ----------------------------------------------------------------------

    async def overview(
        self, *, period: Period, now: datetime | None = None
    ) -> InventoryOverview:
        now = now or datetime.now(UTC)
        start, end = period_window(period, now)
        prev_start, prev_end = previous_window(period, start, end)
        repo = self.repository

        value_now, items = await repo.stock_value_at(now)
        value_start, _ = await repo.stock_value_at(start)
        value_prev_start, _ = await repo.stock_value_at(prev_start)
        current = await repo.consumption(start=start, end=end)
        previous = await repo.consumption(start=prev_start, end=prev_end)
        low, out = await repo.counts()
        year_start, year_end = period_window("12m", now)
        stale_count, stale = await repo.stale(now, limit=5)

        return InventoryOverview(
            generated_at=now,
            period=period,
            window_start=start,
            window_end=end,
            stock_value=StockValue(
                total=_money(value_now),
                previous=_money(value_start),
                change_pct=change_pct(float(value_now), float(value_start)),
                items=items,
            ),
            low_stock=low,
            out_of_stock=out,
            consumption=Consumption(
                units=current.units,
                value=_money(current.value),
                previous_units=previous.units,
                change_pct=change_pct(float(current.units), float(previous.units)),
                movements=current.movements,
                low_sample=0 < current.movements < MIN_SAMPLE,
            ),
            rotation=self._rotation(
                current.value, value_start, previous.value, value_prev_start
            ),
            monthly_consumption=await self._monthly(year_start, year_end),
            stale_count=stale_count,
            stale_items=[
                StaleItem(
                    item_id=s.item_id,
                    sku=s.sku,
                    name=s.name,
                    stock=s.stock,
                    last_movement_at=s.last_movement_at,
                )
                for s in stale
            ],
            most_used=[
                UsedItem(item_id=u.item_id, sku=u.sku, name=u.name, units=u.units)
                for u in await repo.most_used(start=start, end=end, limit=5)
            ],
            reorder=[
                ReorderAlert(
                    item_id=r.item_id,
                    sku=r.sku,
                    name=r.name,
                    stock=r.stock,
                    min_stock=r.min_stock,
                    suggested_order=_suggested(r.max_stock, r.min_stock, r.stock),
                )
                for r in await repo.reorder(limit=10)
            ],
        )

    @staticmethod
    def _rotation(
        consumed: Decimal, base: Decimal, prev_consumed: Decimal, prev_base: Decimal
    ) -> Rotation:
        value = round(float(consumed / base), 2) if base > 0 else None
        before = round(float(prev_consumed / prev_base), 2) if prev_base > 0 else None
        return Rotation(
            value=value, previous=before, change_pct=change_pct(value, before)
        )

    async def _monthly(
        self, start: datetime, end: datetime
    ) -> list[MonthlyConsumption]:
        rows = {
            r.month.astimezone(UTC): r.units
            for r in await self.repository.monthly_consumption(start=start, end=end)
        }
        months: list[MonthlyConsumption] = []
        month = start
        while month < end:
            months.append(MonthlyConsumption(month=month, units=rows.get(month, 0)))
            month = (month.replace(day=28) + timedelta(days=4)).replace(day=1)
        return months

    # -- import ------------------------------------------------------------------------

    async def import_items(
        self, rows: list[dict[str, str]], actor: AuthContext, *, dry_run: bool
    ) -> ImportResult:
        """All-or-nothing bulk creation. A fixed file can simply be uploaded again."""
        errors: list[ImportRowError] = []
        missing = [c for c in ("sku", "name") if rows and c not in rows[0]]
        if missing:
            errors.append(
                ImportRowError(
                    row=1,
                    field=None,
                    message="missing required column(s): " + ", ".join(missing),
                )
            )
            return ImportResult(
                dry_run=dry_run,
                success=False,
                total_rows=len(rows),
                created=0,
                errors=errors,
            )

        taken = await self.repository.find_skus(
            {r.get("sku", "").strip().upper() for r in rows} - {""}
        )
        seen: dict[str, int] = {}
        payloads: list[ItemCreate] = []
        for index, row in enumerate(rows, start=2):
            payload = self._parse_row(index, row, taken, seen, errors)
            if payload is not None:
                payloads.append(payload)
        if not errors and not dry_run:
            for payload in payloads:
                await self._add(payload, actor)
            await self.repository.commit()
        return ImportResult(
            dry_run=dry_run,
            success=not errors,
            total_rows=len(rows),
            created=0 if errors or dry_run else len(payloads),
            errors=errors,
        )

    @staticmethod
    def _parse_row(
        index: int,
        row: dict[str, str],
        taken: set[str],
        seen: dict[str, int],
        errors: list[ImportRowError],
    ) -> ItemCreate | None:
        data: dict[str, Any] = {
            k: v.strip() for k, v in row.items() if v is not None and v.strip() != ""
        }
        if "stock" in data:
            data["initial_stock"] = data.pop("stock")
        known = set(ItemCreate.model_fields)
        data = {k: v for k, v in data.items() if k in known}
        try:
            payload = ItemCreate(**data)
        except ValidationError as error:
            for item in error.errors():
                field = ".".join(str(p) for p in item["loc"]) or None
                errors.append(
                    ImportRowError(row=index, field=field, message=str(item["msg"]))
                )
            return None
        if payload.sku in taken:
            errors.append(
                ImportRowError(
                    row=index,
                    field="sku",
                    message=f"SKU '{payload.sku}' already exists",
                )
            )
            return None
        if payload.sku in seen:
            errors.append(
                ImportRowError(
                    row=index,
                    field="sku",
                    message=f"duplicate SKU '{payload.sku}' (first seen in row {seen[payload.sku]})",
                )
            )
            return None
        seen[payload.sku] = index
        return payload

    # -- internals ---------------------------------------------------------------------

    async def _add(self, payload: ItemCreate, actor: AuthContext) -> InventoryItem:
        fields = payload.model_dump(exclude={"initial_stock"})
        item = await self.repository.add_and_flush(
            InventoryItem(**fields, stock=payload.initial_stock, is_active=True)
        )
        if payload.initial_stock > 0:
            self.repository.add_movement(
                item_id=item.id,
                kind="in",
                quantity=payload.initial_stock,
                stock_after=payload.initial_stock,
                unit_cost=payload.unit_cost,
                notes="Carga inicial",
                record_id=None,
                request_id=None,
                user_id=actor.id,
            )
        self.audit.record(
            user_id=actor.id,
            action="inventory.item_created",
            entity_type="inventory_item",
            entity_id=item.id,
            new_values=_jsonable(
                {
                    "sku": payload.sku,
                    "name": payload.name,
                    "stock": payload.initial_stock,
                }
            ),
        )
        return item

    async def _require(self, item_id: int) -> InventoryItem:
        item = await self.repository.get(item_id)
        if item is None:
            raise NotFoundError("inventory item not found")
        return item

    @staticmethod
    def _response(
        item: InventoryItem, last_movement_at: datetime | None
    ) -> ItemResponse:
        return ItemResponse(
            id=item.id,
            sku=item.sku,
            name=item.name,
            description=item.description,
            category=item.category,  # type: ignore[arg-type]
            unit=item.unit,
            unit_cost=item.unit_cost,
            stock=item.stock,
            min_stock=item.min_stock,
            max_stock=item.max_stock,
            location=item.location,
            supplier=item.supplier,
            is_active=item.is_active,
            status=_status(item),  # type: ignore[arg-type]
            stock_value=_money(item.stock * item.unit_cost),
            level_pct=_level(item),
            last_movement_at=last_movement_at,
            created_at=item.created_at,
            updated_at=item.updated_at,
        )

    @staticmethod
    def _movement(
        movement: InventoryMovement, created_by: str | None
    ) -> MovementResponse:
        return MovementResponse(
            id=movement.id,
            item_id=movement.item_id,
            kind=movement.kind,  # type: ignore[arg-type]
            quantity=movement.quantity,
            stock_after=movement.stock_after,
            unit_cost=movement.unit_cost,
            notes=movement.notes,
            record_id=movement.record_id,
            request_id=movement.request_id,
            created_by=created_by,
            created_at=movement.created_at,
        )
