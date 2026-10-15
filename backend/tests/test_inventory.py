from datetime import UTC, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.exceptions import (
    BusinessRuleError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
)
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.inventory import InventoryItem, InventoryMovement
from app.models.maintenance import MaintenanceRecord
from app.models.technician import Technician
from app.repositories.base import Page
from app.repositories.inventory import (
    ConsumptionRow,
    InventoryRepository,
    ItemUnits,
    MonthRow,
    ReorderRow,
    StaleRow,
)
from app.schemas.inventory import ItemCreate, ItemUpdate, MovementCreate
from app.services.inventory import InventoryService
from tests.support import expand, perm_objects

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
MANAGER = AuthContext(
    user=SimpleNamespace(id=1, full_name="Ana"),
    roles=frozenset({"SUPERVISOR"}),
    permissions=expand("inventory.read", "inventory.manage", "inventory.consume"),
)
TECHNICIAN = AuthContext(
    user=SimpleNamespace(id=2, full_name="Luis"),
    roles=frozenset({"TECHNICIAN"}),
    permissions=expand("inventory.read", "inventory.consume"),
)


def item_payload(**overrides):
    data = {
        "sku": "ssd-512",
        "name": "SSD 512 GB",
        "unit_cost": "64.90",
        "min_stock": 5,
        "max_stock": 40,
    }
    return {**data, **overrides}


# -- payload validation -----------------------------------------------------------------


@pytest.mark.parametrize(
    "overrides",
    [
        {"sku": "ab"},  # too short
        {"sku": "x" * 41},
        {"sku": "SSD 512"},  # space
        {"sku": "SSD/512"},
        {"sku": "-SSD"},  # must start with a letter or digit
        {"sku": "   "},
        {"name": "ab"},
        {"name": "   "},
        {"name": "x" * 201},
        {"unit_cost": "-0.01"},
        {"unit_cost": "1.234"},  # more than 2 decimals
        {"unit_cost": "1000000.01"},
        {"min_stock": -1},
        {"max_stock": -1},
        {"min_stock": 1_000_001},
        {"initial_stock": -3},
        {"initial_stock": 1_000_001},
        {"min_stock": 10, "max_stock": 5},  # max below min
        {"unit": ""},
        {"unit": "u@"},
        {"category": "Not A Code"},  # a code is lower-case letters, digits and _
        {"description": "x" * 2001},
        {"min_stock": 1.5},
    ],
)
def test_item_payload_rejects_bad_values(overrides):
    with pytest.raises(ValidationError):
        ItemCreate(**item_payload(**overrides))


def test_item_payload_normalises_what_it_accepts():
    item = ItemCreate(
        **item_payload(
            sku="  ssd-512 ",
            name="  SSD  ",
            description="   ",
            location=" Estante A ",
            unit_cost="64.9",
        )
    )
    assert item.sku == "SSD-512" and item.name == "SSD" and item.description is None
    assert item.location == "Estante A" and item.unit_cost == Decimal("64.9")
    assert (
        ItemCreate(**item_payload(min_stock=5, max_stock=5)).max_stock == 5
    )  # equal is fine


@pytest.mark.parametrize(
    "payload",
    [
        {"kind": "in", "quantity": 0},
        {"kind": "in", "quantity": -3},
        {"kind": "out", "quantity": -1},
        {"kind": "adjust", "quantity": 0},
        {"kind": "out", "quantity": 1, "unit_cost": "5.00"},  # cost only for entries
        {"kind": "in", "quantity": 1, "record_id": 4},  # links only for consumption
        {"kind": "adjust", "quantity": 1, "request_id": 4},
        {"kind": "in", "quantity": 1, "unit_cost": "-1"},
        {"kind": "in", "quantity": 1_000_001},
        {"kind": "move", "quantity": 1},
        {"kind": "in", "quantity": 1, "notes": "x" * 301},
    ],
)
def test_movement_payload_rejects_incoherent_values(payload):
    with pytest.raises(ValidationError):
        MovementCreate(**payload)


def test_movement_payload_accepts_signed_adjustments_and_trims_notes():
    assert MovementCreate(kind="adjust", quantity=-4).quantity == -4
    assert (
        MovementCreate(kind="out", quantity=2, record_id=9, notes="  cambio  ").notes
        == "cambio"
    )


def test_update_payload_trims_and_allows_clearing_optional_fields():
    update = ItemUpdate(name="  Nuevo nombre ", location="  ")
    assert update.name == "Nuevo Nombre" and update.location is None
    with pytest.raises(ValidationError):
        ItemUpdate(unit_cost="-1")


# -- service (fake repository) ----------------------------------------------------------------


class FakeInventoryRepository:
    def __init__(self):
        self.items: dict[int, SimpleNamespace] = {}
        self.movements: list[SimpleNamespace] = []
        self.records = {7}
        self.requests = {3}
        self.committed = 0
        self.deleted = []
        self.overview = {}

    async def find_skus(self, skus):
        return {i.sku for i in self.items.values() if i.sku in skus}

    # drop-down options: the five built-in categories are there from the start
    options = None

    def _options(self):
        if self.options is None:
            self.options = [
                SimpleNamespace(
                    id=n, kind="category", value=code, label=label, key=label.lower()
                )
                for n, (code, label) in enumerate(
                    [
                        ("spare_part", "Repuesto"),
                        ("consumable", "Consumible"),
                        ("accessory", "Accesorio"),
                        ("tool", "Herramienta"),
                        ("other", "Otro"),
                    ],
                    start=1,
                )
            ]
        return self.options

    async def list_options(self, kind=None):
        return [o for o in self._options() if kind in (None, o.kind)]

    async def option_by_key(self, kind, key):
        return next(
            (o for o in self._options() if (o.kind, o.key) == (kind, key)), None
        )

    async def add_option(self, *, kind, value, label, key):
        option = SimpleNamespace(
            id=len(self._options()) + 1, kind=kind, value=value, label=label, key=key
        )
        self.options.append(option)
        return option

    async def add_and_flush(self, item):
        item.id = len(self.items) + 1
        item.created_at = item.updated_at = NOW
        for field, default in (
            ("description", None),
            ("location", None),
            ("supplier", None),
            ("max_stock", None),
        ):
            if not hasattr(item, field) or getattr(item, field, None) is None:
                setattr(item, field, getattr(item, field, default))
        self.items[item.id] = item
        return item

    def add_movement(self, **kwargs):
        movement = SimpleNamespace(
            id=len(self.movements) + 1,
            created_at=NOW,
            created_by=None,
            **{k: v for k, v in kwargs.items() if k != "user_id"},
        )
        self.movements.append(movement)
        return movement

    async def update_fields(self, item, values):
        for key, value in values.items():
            setattr(item, key, value)
        return item

    async def get(self, item_id):
        return self.items.get(item_id)

    get_for_update = get

    async def has_movements(self, item_id):
        return any(m.item_id == item_id for m in self.movements)

    async def delete_item(self, item):
        self.deleted.append(item.id)
        del self.items[item.id]

    async def last_movements(self, ids):
        return {m.item_id: m.created_at for m in self.movements if m.item_id in ids}

    async def search(self, **kwargs):
        self.search_kwargs = kwargs
        return Page(
            items=list(self.items.values()), total=len(self.items), page=1, size=20
        )

    async def list_movements(self, item_id, *, params):
        rows = [m for m in self.movements if m.item_id == item_id][::-1]
        return Page(items=rows, total=len(rows), page=1, size=20)

    async def record_exists(self, record_id):
        return record_id in self.records

    async def request_exists(self, request_id):
        return request_id in self.requests

    async def flush(self):
        pass

    async def commit(self):
        self.committed += 1

    # aggregates for the overview
    async def stock_value_at(self, at):
        return self.overview.setdefault(
            "values", [(Decimal(1000), 8), (Decimal(800), 8), (Decimal(500), 8)]
        ).pop(0)

    async def consumption(self, *, start, end):
        return self.overview.setdefault(
            "consumption",
            [
                ConsumptionRow(30, Decimal(300), 6),
                ConsumptionRow(20, Decimal(100), 4),
            ],
        ).pop(0)

    async def monthly_consumption(self, *, start, end):
        return self.overview.get(
            "monthly",
            [
                MonthRow(datetime(2026, 9, 1, tzinfo=UTC), 12),
                MonthRow(datetime(2026, 10, 1, tzinfo=UTC), 18),
            ],
        )

    async def counts(self):
        return 3, 1

    async def stale(self, now, *, limit):
        return 2, [StaleRow(5, "OLD-1", "Cable viejo", 9, None)]

    async def most_used(self, *, start, end, limit):
        return [ItemUnits(1, "SSD-512", "SSD 512 GB", 7)]

    async def reorder(self, *, limit):
        return [
            ReorderRow(1, "SSD-512", "SSD", 0, 5, 40),
            ReorderRow(2, "RAM-8", "RAM", 2, 4, None),
        ]


def service():
    return InventoryService(FakeInventoryRepository(), FakeAudit())


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


async def stocked(stock=10, **overrides):
    svc = service()
    created = await svc.create(
        ItemCreate(**item_payload(initial_stock=stock, **overrides)), MANAGER
    )
    return svc, created


async def test_create_normalises_the_sku_and_records_the_initial_stock_in_the_ledger():
    svc, created = await stocked(12)
    assert created.sku == "SSD-512" and created.stock == 12 and created.status == "ok"
    (entry,) = svc.repository.movements
    assert (entry.kind, entry.quantity, entry.stock_after, entry.notes) == (
        "in",
        12,
        12,
        "Carga inicial",
    )
    assert "inventory.item_created" in [r["action"] for r in svc.audit.records]


async def test_create_without_initial_stock_leaves_the_ledger_empty():
    svc, created = await stocked(0)
    assert created.status == "out" and svc.repository.movements == []


async def test_a_duplicate_sku_is_a_409_with_a_clear_message():
    svc, _ = await stocked()
    with pytest.raises(ConflictError, match="SSD-512"):
        await svc.create(ItemCreate(**item_payload(sku="Ssd-512")), MANAGER)


async def test_item_status_and_level_follow_the_stock():
    svc, item = await stocked(40)
    assert (item.status, item.level_pct, item.stock_value) == (
        "ok",
        100.0,
        Decimal("2596.00"),
    )
    low = (
        await svc.move(item.id, MovementCreate(kind="out", quantity=35), MANAGER)
    ).stock_after
    assert low == 5
    assert (await svc.get(item.id)).status == "low"  # at the minimum counts as low
    await svc.move(item.id, MovementCreate(kind="out", quantity=5), MANAGER)
    assert (await svc.get(item.id)).status == "out"


async def test_level_uses_twice_the_minimum_when_there_is_no_maximum():
    _, item = await stocked(5, min_stock=10, max_stock=None)
    assert item.level_pct == 25.0  # 5 of 20


async def test_update_checks_the_maximum_against_the_stored_minimum():
    svc, item = await stocked(min_stock=5, max_stock=40)
    with pytest.raises(UnprocessableError, match="stock máximo"):
        await svc.update(item.id, ItemUpdate(max_stock=3), MANAGER)
    with pytest.raises(UnprocessableError, match="stock máximo"):
        await svc.update(item.id, ItemUpdate(min_stock=50), MANAGER)
    updated = await svc.update(
        item.id, ItemUpdate(min_stock=8, max_stock=None, name="Nuevo nombre"), MANAGER
    )
    assert updated.min_stock == 8 and updated.max_stock is None
    assert svc.audit.records[-1]["old_values"]["min_stock"] == 5


@pytest.mark.parametrize(
    "field", ["name", "category", "unit", "unit_cost", "min_stock"]
)
async def test_update_rejects_null_for_required_fields(field):
    svc, item = await stocked()
    with pytest.raises(UnprocessableError, match="cannot be null"):
        await svc.update(
            item.id,
            ItemUpdate.model_construct(_fields_set={field}, **{field: None}),
            MANAGER,
        )


async def test_an_item_that_moved_cannot_be_deleted_but_a_fresh_one_can():
    svc, item = await stocked(5)
    with pytest.raises(ConflictError, match="deactivate"):
        await svc.delete(item.id, MANAGER)
    fresh = await svc.create(ItemCreate(**item_payload(sku="NEW-1")), MANAGER)
    await svc.delete(fresh.id, MANAGER)
    assert svc.repository.deleted == [fresh.id]
    assert svc.audit.records[-1]["action"] == "inventory.item_deleted"
    with pytest.raises(NotFoundError):
        await svc.get(fresh.id)


# -- movements ------------------------------------------------------------------------------


async def test_consumption_reduces_stock_and_is_stored_negative():
    svc, item = await stocked(10)
    moved = await svc.move(
        item.id,
        MovementCreate(kind="out", quantity=4, record_id=7, notes="Cambio de SSD"),
        TECHNICIAN,
    )
    assert (moved.kind, moved.quantity, moved.stock_after, moved.record_id) == (
        "out",
        -4,
        6,
        7,
    )
    assert moved.created_by == "Luis"
    assert (await svc.get(item.id)).stock == 6
    assert svc.audit.records[-1]["new_values"] == {
        "stock": 6,
        "kind": "out",
        "quantity": -4,
    }


async def test_consuming_all_the_stock_is_allowed_but_one_more_unit_is_not():
    svc, item = await stocked(3)
    with pytest.raises(BusinessRuleError, match="3 available, 4 requested"):
        await svc.move(item.id, MovementCreate(kind="out", quantity=4), TECHNICIAN)
    assert (await svc.get(item.id)).stock == 3  # untouched by the failed attempt
    assert len(svc.repository.movements) == 1
    await svc.move(item.id, MovementCreate(kind="out", quantity=3), TECHNICIAN)
    assert (await svc.get(item.id)).stock == 0
    with pytest.raises(BusinessRuleError, match="0 available"):
        await svc.move(item.id, MovementCreate(kind="out", quantity=1), TECHNICIAN)


async def test_an_adjustment_cannot_drive_the_stock_negative():
    svc, item = await stocked(3)
    with pytest.raises(BusinessRuleError, match="insufficient"):
        await svc.move(item.id, MovementCreate(kind="adjust", quantity=-4), MANAGER)
    assert (
        await svc.move(item.id, MovementCreate(kind="adjust", quantity=-3), MANAGER)
    ).stock_after == 0
    assert (
        await svc.move(item.id, MovementCreate(kind="adjust", quantity=7), MANAGER)
    ).stock_after == 7


@pytest.mark.parametrize("kind", ["in", "adjust"])
async def test_only_managers_register_entries_and_adjustments(kind):
    svc, item = await stocked(3)
    with pytest.raises(ForbiddenError):
        await svc.move(item.id, MovementCreate(kind=kind, quantity=1), TECHNICIAN)
    assert (await svc.get(item.id)).stock == 3


async def test_entries_with_a_cost_update_the_weighted_average():
    svc, item = await stocked(10, unit_cost="10.00")
    await svc.move(
        item.id, MovementCreate(kind="in", quantity=10, unit_cost="20.00"), MANAGER
    )
    refreshed = await svc.get(item.id)
    assert refreshed.stock == 20 and refreshed.unit_cost == Decimal("15.00")


async def test_entries_without_a_cost_keep_the_current_cost():
    svc, item = await stocked(10, unit_cost="10.00")
    await svc.move(item.id, MovementCreate(kind="in", quantity=5), MANAGER)
    assert (await svc.get(item.id)).unit_cost == Decimal("10.00")


async def test_stock_cannot_exceed_the_system_limit():
    svc, item = await stocked(999_999)
    with pytest.raises(UnprocessableError, match="cannot exceed"):
        await svc.move(item.id, MovementCreate(kind="in", quantity=2), MANAGER)


async def test_an_inactive_item_cannot_move():
    svc, item = await stocked(3)
    await svc.update(item.id, ItemUpdate(is_active=False), MANAGER)
    with pytest.raises(BusinessRuleError, match="inactive"):
        await svc.move(item.id, MovementCreate(kind="out", quantity=1), TECHNICIAN)


async def test_consumption_links_must_point_to_real_records_and_tickets():
    svc, item = await stocked(3)
    with pytest.raises(NotFoundError, match="record"):
        await svc.move(
            item.id, MovementCreate(kind="out", quantity=1, record_id=99), TECHNICIAN
        )
    with pytest.raises(NotFoundError, match="request"):
        await svc.move(
            item.id, MovementCreate(kind="out", quantity=1, request_id=99), TECHNICIAN
        )
    ok = await svc.move(
        item.id, MovementCreate(kind="out", quantity=1, request_id=3), TECHNICIAN
    )
    assert ok.request_id == 3


async def test_moving_a_missing_item_is_a_404():
    with pytest.raises(NotFoundError):
        await service().move(404, MovementCreate(kind="out", quantity=1), TECHNICIAN)


async def test_history_lists_newest_first():
    svc, item = await stocked(5)
    await svc.move(item.id, MovementCreate(kind="out", quantity=1), TECHNICIAN)
    page = await svc.movements(item.id)
    assert [m.kind for m in page.items] == ["out", "in"]


# -- overview ------------------------------------------------------------------------------


async def test_overview_reports_value_consumption_and_rotation_against_the_previous_period():
    svc = service()
    result = await svc.overview(period="30d", now=NOW)
    assert result.stock_value.total == Decimal(
        "1000.00"
    ) and result.stock_value.previous == Decimal("800.00")
    assert result.stock_value.change_pct == 25.0
    assert (result.low_stock, result.out_of_stock) == (3, 1)
    assert (
        result.consumption.units,
        result.consumption.previous_units,
        result.consumption.change_pct,
    ) == (30, 20, 50.0)
    assert result.consumption.movements == 6 and result.consumption.low_sample is False
    assert result.rotation.value == 0.38  # 300 / 800
    assert result.rotation.previous == 0.2  # 100 / 500
    assert [(m.units) for m in result.monthly_consumption][-4:] == [0, 0, 12, 18]
    assert len(result.monthly_consumption) == 12
    assert result.stale_count == 2 and result.most_used[0].units == 7
    assert [(r.sku, r.suggested_order) for r in result.reorder] == [
        ("SSD-512", 40),
        ("RAM-8", 6),
    ]


async def test_overview_has_no_values_instead_of_zeros_without_a_base():
    svc = service()
    svc.repository.overview = {
        "values": [(Decimal(0), 0), (Decimal(0), 0), (Decimal(0), 0)],
        "consumption": [
            ConsumptionRow(0, Decimal(0), 0),
            ConsumptionRow(0, Decimal(0), 0),
        ],
        "monthly": [],
    }
    result = await svc.overview(period="7d", now=NOW)
    assert result.rotation.value is None and result.rotation.change_pct is None
    assert (
        result.stock_value.change_pct is None and result.consumption.change_pct is None
    )
    assert all(m.units == 0 for m in result.monthly_consumption)


@pytest.mark.parametrize(("n", "low"), [(1, True), (4, True), (5, False)])
async def test_few_consumption_movements_are_flagged(n, low):
    svc = service()
    svc.repository.overview = {
        "consumption": [
            ConsumptionRow(3, Decimal(9), n),
            ConsumptionRow(0, Decimal(0), 0),
        ]
    }
    assert (await svc.overview(period="30d", now=NOW)).consumption.low_sample is low


# -- import ---------------------------------------------------------------------------------


def csv_rows(*rows):
    return [dict(row) for row in rows]


GOOD = {
    "sku": "ram-8",
    "name": "RAM 8 GB",
    "unit_cost": "30.5",
    "stock": "10",
    "min_stock": "4",
    "max_stock": "20",
}


async def test_import_creates_every_row_and_records_the_initial_stock():
    svc = service()
    result = await svc.import_items(
        csv_rows(GOOD, {**GOOD, "sku": "RAM-16"}), MANAGER, dry_run=False
    )
    assert (result.success, result.created, result.total_rows) == (True, 2, 2)
    assert sorted(i.sku for i in svc.repository.items.values()) == ["RAM-16", "RAM-8"]
    assert len(svc.repository.movements) == 2 and svc.repository.committed == 1


async def test_a_dry_run_validates_without_writing():
    svc = service()
    result = await svc.import_items(csv_rows(GOOD), MANAGER, dry_run=True)
    assert result.success and result.created == 0 and svc.repository.items == {}


async def test_import_is_all_or_nothing_and_reports_each_error_with_its_row():
    svc = service()
    rows = csv_rows(
        GOOD,
        {**GOOD, "sku": "BAD-1", "unit_cost": "-5"},
        {**GOOD, "sku": "BAD-2", "min_stock": "30"},  # above the maximum
        {**GOOD, "sku": "BAD-3", "stock": "1.5"},
        {**GOOD, "sku": "ram-8"},  # repeated in the file
    )
    result = await svc.import_items(rows, MANAGER, dry_run=False)
    assert (
        result.success is False and result.created == 0 and svc.repository.items == {}
    )
    by_row = {(e.row, e.field) for e in result.errors}
    assert (3, "unit_cost") in by_row and (5, "stock") in by_row
    assert any(
        e.row == 6 and e.field == "sku" and "repetido" in e.message
        for e in result.errors
    )
    assert any(e.row == 4 for e in result.errors)


async def test_import_rejects_skus_that_already_exist_and_missing_columns():
    svc, _ = await stocked()
    result = await svc.import_items(
        csv_rows({**GOOD, "sku": "ssd-512"}), MANAGER, dry_run=False
    )
    assert any("ya existe" in e.message for e in result.errors)
    missing = await svc.import_items(csv_rows({"sku": "A-1"}), MANAGER, dry_run=False)
    assert "name" in missing.errors[0].message


# -- HTTP -----------------------------------------------------------------------------------


class StubInventoryService:
    def __init__(self):
        self.calls = []

    async def list_items(self, **kwargs):
        self.calls.append(("list", kwargs))
        return Page(items=[], total=0, page=1, size=20)

    async def create(self, payload, actor):
        self.calls.append(("create", payload.sku))
        _, item = await stocked(1)
        return item

    async def move(self, item_id, payload, actor):
        self.calls.append(("move", item_id, payload.kind, payload.quantity))
        svc, item = await stocked(5)
        return await svc.move(item.id, MovementCreate(kind="in", quantity=1), MANAGER)

    async def overview(self, *, period):
        self.calls.append(("overview", period))
        return await service().overview(period=period, now=NOW)

    async def import_items(self, rows, actor, *, dry_run, skip_invalid=False):
        self.calls.append(("import", len(rows), dry_run))
        return await service().import_items(rows, actor, dry_run=True)


def build_client(permissions):
    stub = StubInventoryService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="TECHNICIAN",
                is_active=True,
                permissions=perm_objects(*permissions),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_inventory_service] = lambda: stub
    return stub


@pytest.fixture
def client():
    stub = build_client(["inventory.read", "inventory.manage", "inventory.consume"])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def reader():
    build_client(["inventory.read"])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_list_endpoint_forwards_filters_and_rejects_unknown_ones(client):
    assert (
        client.get(
            "/inventory/items?search=ssd&category=spare_part&status=low&sort=-stock"
        ).status_code
        == 200
    )
    _, kwargs = client.stub.calls[-1]
    assert (
        kwargs["search"] == "ssd"
        and kwargs["category"] == "spare_part"
        and kwargs["status"] == "low"
    )
    assert client.get("/inventory/items?status=broken").status_code == 422
    assert client.get("/inventory/items?category=Bad%20Code").status_code == 422


def test_create_endpoint_returns_201_and_validates_numbers(client):
    created = client.post("/inventory/items", json=item_payload())
    assert created.status_code == 201 and created.json()["sku"] == "SSD-512"
    for bad in (
        {"unit_cost": "-1"},
        {"min_stock": -2},
        {"min_stock": 9, "max_stock": 3},
        {"sku": "a"},
        {"name": ""},
    ):
        response = client.post("/inventory/items", json=item_payload(**bad))
        assert response.status_code == 422, bad
        assert response.json()["errors"], bad


def test_movement_endpoint_validates_quantities(client):
    assert (
        client.post(
            "/inventory/items/1/movements", json={"kind": "in", "quantity": 2}
        ).status_code
        == 201
    )
    for bad in (
        {"kind": "in", "quantity": 0},
        {"kind": "out", "quantity": -1},
        {"kind": "in", "quantity": 2_000_000},
        {"kind": "x", "quantity": 1},
    ):
        assert (
            client.post("/inventory/items/1/movements", json=bad).status_code == 422
        ), bad


def test_overview_endpoint_shape_and_period(client):
    body = client.get("/inventory/overview?period=12m").json()
    assert set(body) == {
        "generated_at",
        "period",
        "window_start",
        "window_end",
        "stock_value",
        "low_stock",
        "out_of_stock",
        "consumption",
        "rotation",
        "monthly_consumption",
        "stale_count",
        "stale_items",
        "most_used",
        "reorder",
    }
    assert client.get("/inventory/overview?period=1d").status_code == 422


def test_a_reader_cannot_change_anything(reader):
    assert reader.get("/inventory/items").status_code == 200
    assert reader.post("/inventory/items", json=item_payload()).status_code == 403
    assert (
        reader.patch("/inventory/items/1", json={"name": "Nuevo nombre"}).status_code
        == 403
    )
    assert reader.delete("/inventory/items/1").status_code == 403
    assert (
        reader.post(
            "/inventory/items/1/movements", json={"kind": "out", "quantity": 1}
        ).status_code
        == 403
    )
    assert (
        reader.post(
            "/inventory/import",
            files={"file": ("a.csv", b"sku,name\nA-1,Algo", "text/csv")},
        ).status_code
        == 403
    )


def test_import_endpoint_checks_the_file_before_parsing_it(client):
    csv = b"sku,name,stock\nA-100,Cable HDMI,5\n"
    ok = client.post(
        "/inventory/import?dry_run=true", files={"file": ("items.csv", csv, "text/csv")}
    )
    assert ok.status_code == 200 and ok.json()["total_rows"] == 1
    assert (
        client.post(
            "/inventory/import",
            files={"file": ("items.exe", b"MZ", "application/octet-stream")},
        ).status_code
        == 415
    )
    too_big = client.post(
        "/inventory/import",
        files={"file": ("big.csv", b"sku,name\n" + b"A-1,x\n" * 1_000_000, "text/csv")},
    )
    assert too_big.status_code == 413


# -- real-database aggregates (need TEST_DATABASE_URL) -----------------------------------------------


async def seed(session):
    user = User(clerk_user_id="c1", email="u@x.co", full_name="Luis", is_active=True)
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    session.add_all([user, etype])
    await session.flush()
    laptop = Equipment(
        asset_tag="LT-1",
        equipment_type_id=etype.id,
        brand="Dell",
        model="X",
        status="assigned",
    )
    tech = Technician(user_id=user.id, is_available=True)
    session.add_all([laptop, tech])
    await session.flush()
    record = MaintenanceRecord(
        equipment_id=laptop.id,
        technician_id=tech.id,
        work_type="corrective",
        started_at=NOW - timedelta(days=3),
        completed_at=NOW - timedelta(days=3, hours=-1),
        diagnosis="d",
        actions_taken="a",
        result="ok",
    )

    def item(sku, stock, minimum, cost, created_days_ago=200, **extra):
        return InventoryItem(
            sku=sku,
            name=f"Item {sku}",
            category="spare_part",
            unit="unidad",
            unit_cost=Decimal(cost),
            stock=stock,
            min_stock=minimum,
            created_at=NOW - timedelta(days=created_days_ago),
            **extra,
        )

    items = [
        item("OK-1", 20, 5, "10.00"),
        item("LOW-1", 3, 5, "20.00"),
        item("OUT-1", 0, 2, "5.00"),
        item("OLD-1", 9, 2, "1.00", created_days_ago=400),
        item("OFF-1", 0, 0, "1.00", is_active=False),
    ]
    session.add_all([record, *items])
    await session.flush()
    ok, low, *_ = items

    def move(target, kind, quantity, days_ago, **links):
        return InventoryMovement(
            item_id=target.id,
            kind=kind,
            quantity=quantity,
            stock_after=max(target.stock, 0),
            created_at=NOW - timedelta(days=days_ago),
            **links,
        )

    session.add_all(
        [
            move(ok, "in", 25, 100),
            move(ok, "out", -5, 3, record_id=record.id),
            move(ok, "out", -2, 40),
            move(low, "out", -4, 2, record_id=record.id),
            move(low, "in", 7, 80),
        ]
    )
    await session.flush()
    return items


async def test_search_filters_by_status_text_and_orders_on_the_server(db_session):
    await seed(db_session)
    repo = InventoryRepository(db_session)
    now = NOW

    async def skus(**kwargs):
        from app.core.pagination import PageParams

        page = await repo.search(
            now=now,
            params=PageParams(page=1, size=50, sort=kwargs.pop("sort", None)),
            **kwargs,
        )
        return [i.sku for i in page.items]

    assert await skus(status="low") == ["LOW-1"]
    assert await skus(status="out") == ["OUT-1"]  # the inactive one is not counted
    assert sorted(await skus(status="ok")) == ["OK-1", "OLD-1"]
    assert await skus(status="stale") == [
        "OLD-1"
    ]  # in stock, no movement, created > 90 days ago
    assert await skus(status="inactive") == ["OFF-1"]
    assert await skus(search="low") == ["LOW-1"]
    assert (await skus(sort="-stock"))[0] == "OK-1"
    assert (await skus(sort="stock_value"))[0] in {"OUT-1", "OFF-1"}


async def test_has_movements_and_last_movement(db_session):
    items = await seed(db_session)
    repo = InventoryRepository(db_session)
    assert await repo.has_movements(items[0].id) is True
    assert await repo.has_movements(items[2].id) is False
    last = await repo.last_movements([items[0].id, items[2].id])
    assert last == {items[0].id: NOW - timedelta(days=3)}


async def test_stock_value_is_rebuilt_for_a_past_date(db_session):
    await seed(db_session)
    repo = InventoryRepository(db_session)
    now_value, count = await repo.stock_value_at(NOW)
    assert now_value == Decimal(20) * 10 + 3 * 20 + 9 * 1 and count == 4
    # 10 days ago: OK-1 had 20 + 5 consumed 3 days ago, LOW-1 had 3 + 4 consumed 2 days ago
    past, _ = await repo.stock_value_at(NOW - timedelta(days=10))
    assert past == Decimal(25) * 10 + 7 * 20 + 9 * 1


async def test_consumption_and_most_used_only_count_the_window_and_maintenance_links(
    db_session,
):
    await seed(db_session)
    repo = InventoryRepository(db_session)
    start, end = NOW - timedelta(days=30), NOW + timedelta(days=1)
    row = await repo.consumption(start=start, end=end)
    assert (row.units, row.movements) == (9, 2) and row.value == Decimal(
        5
    ) * 10 + 4 * 20
    used = await repo.most_used(start=start, end=end, limit=5)
    assert [(u.sku, u.units) for u in used] == [("OK-1", 5), ("LOW-1", 4)]
    wide = await repo.consumption(start=NOW - timedelta(days=60), end=end)
    assert wide.units == 11  # the 40-day-old consumption now counts
    months = await repo.monthly_consumption(start=NOW - timedelta(days=60), end=end)
    assert sum(m.units for m in months) == 11


async def test_counts_stale_and_reorder_alerts(db_session):
    await seed(db_session)
    repo = InventoryRepository(db_session)
    assert await repo.counts() == (1, 1)
    total, stale = await repo.stale(NOW, limit=5)
    assert total == 1 and stale[0].sku == "OLD-1"
    assert [r.sku for r in await repo.reorder(limit=10)] == [
        "OUT-1",
        "LOW-1",
    ]  # emptiest first
