from datetime import UTC, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.exceptions import UnprocessableError
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.inventory import InventoryItem, InventoryMovement
from app.models.schedule import MaintenanceSchedule, ScheduleRun
from app.models.technician import Technician
from app.repositories.report_builder import ReportBuilderRepository, RunRow
from app.schemas.report_builder import (
    ReportFilters,
    ReportGenerateRequest,
    ReportPreviewRequest,
)
from app.services.report_builder import ReportBuilderService
from tests.support import expand, perm_objects

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
ACTOR = AuthContext(
    user=SimpleNamespace(id=1, full_name="Ana"),
    roles=frozenset({"SUPERVISOR"}),
    permissions=expand("reports.read"),
)


def aware(day: int, month: int = 9, year: int = 2026) -> str:
    return f"{year}-{month:02d}-{day:02d}T00:00:00Z"


# -- filters --------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "filters",
    [
        {"date_from": aware(10), "date_to": aware(9)},  # inverted
        {"date_from": aware(1, 1, 2025), "date_to": aware(1, 3, 2026)},  # over 366 days
        {"date_from": "2026-09-01T00:00:00"},  # naive
        {"statuses": ["Bad Value"]},
        {"statuses": ["a1"]},
        {"statuses": [f"s{i}x" for i in range(21)]},
        {"equipment_type_ids": [0]},
        {"equipment_type_ids": [-3]},
        {"days": 0},
        {"days": 366},
        {"nonsense": ["x"]},  # unknown filter
    ],
)
def test_filters_reject_incoherent_values(filters):
    with pytest.raises(ValidationError):
        ReportFilters(**filters)


def test_filters_accept_the_boundary_and_normalise_lists():
    exact = ReportFilters(
        date_from=aware(1, 1, 2026), date_to=aware(2, 1, 2027)
    )  # 366 days
    assert exact.date_to - exact.date_from == timedelta(days=366)
    filters = ReportFilters(statuses=["closed", "resolved", "closed"], priorities=[])
    assert filters.statuses == ["closed", "resolved"] and filters.priorities is None
    assert ReportFilters(date_from=aware(5), date_to=aware(5)).date_from == datetime(
        2026, 9, 5, tzinfo=UTC
    )


def test_generate_request_takes_format_under_its_wire_name():
    request = ReportGenerateRequest.model_validate(
        {"report": "tickets", "format": "pdf"}
    )
    assert request.export_format == "pdf"
    with pytest.raises(ValidationError):
        ReportGenerateRequest.model_validate({"report": "tickets", "format": "docx"})
    with pytest.raises(ValidationError):
        ReportGenerateRequest.model_validate({"report": "unknown"})


# -- service (fake repository) -------------------------------------------------------------------


class FakeBuilderRepository:
    def __init__(self, rows=None):
        self.rows = rows
        self.calls = []
        self.runs = []
        self.committed = 0
        self.overview = {}

    def _rows(self, name, kwargs, default):
        self.calls.append((name, kwargs))
        rows = self.rows if self.rows is not None else default
        return rows(kwargs) if callable(rows) else rows

    async def equipment_rows(self, **kwargs):
        return self._rows(
            "equipment",
            kwargs,
            [
                {
                    "asset_tag": "LT-1",
                    "status": "in_repair",
                    "brand": "Dell",
                    "purchase_cost": Decimal("1200.5"),
                }
            ],
        )

    async def ticket_rows(self, **kwargs):
        return self._rows(
            "tickets",
            kwargs,
            [
                {
                    "ticket_number": "T-1",
                    "title": "=cmd|calc",
                    "priority": "high",
                    "status": "in_progress",
                    "created_at": NOW,
                }
            ],
        )

    async def plan_rows(self, **kwargs):
        return self._rows(
            "plans", kwargs, [{"title": "Limpieza", "status": "overdue", "runs": 2}]
        )

    async def item_rows(self, **kwargs):
        return self._rows(
            "items",
            kwargs,
            [{"sku": "SSD-1", "category": "spare_part", "status": "low", "stock": 2}],
        )

    async def movement_rows(self, **kwargs):
        return self._rows(
            "movements",
            kwargs,
            [{"sku": "SSD-1", "kind": "out", "quantity": -2, "created_at": NOW}],
        )

    async def equipment_type_options(self):
        return [(1, "Laptop"), (2, "Servidor")]

    def record_run(self, **kwargs):
        run = SimpleNamespace(id=len(self.runs) + 1, **kwargs)
        self.runs.append(run)
        return run

    async def flush(self):
        pass

    async def commit(self):
        self.committed += 1

    async def runs_in(self, start, end):
        return self.overview.setdefault("runs", [12, 8]).pop(0)

    async def people_in(self, start, end):
        return 3

    async def most_used(self, start, end, *, limit):
        return [("tickets", 7), ("equipment", 5)]

    async def by_format(self, start, end):
        return {"xlsx": 9, "pdf": 3}

    async def last_run(self):
        return RunRow(9, "tickets", "pdf", 120, {}, "Ana", NOW)

    async def count_runs(self):
        return 25

    async def recent_runs(self, *, limit, offset):
        return [RunRow(9, "tickets", "pdf", 120, {"statuses": ["closed"]}, "Ana", NOW)]


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeDashboard:
    async def summary(self, actor, *, days):
        by = lambda key, count: SimpleNamespace(key=key, count=count)
        return SimpleNamespace(
            tickets=SimpleNamespace(
                total=10,
                open=4,
                overdue=1,
                by_status=[by("closed", 6)],
                open_by_priority=[by("high", 2)],
            ),
            equipment_by_status=[by("assigned", 8)],
        )

    async def resolution_times(self, actor, *, days):
        timing = SimpleNamespace(priority="high", avg_hours=5.0)
        return SimpleNamespace(
            overall=SimpleNamespace(resolved_count=6, avg_hours=4.0, median_hours=3.0),
            by_priority=[timing],
        )

    async def top_failing_equipment(self, *, days, limit):
        return SimpleNamespace(equipment=[SimpleNamespace(asset_tag="LT-1", tickets=3)])


def service(rows=None):
    return ReportBuilderService(
        FakeBuilderRepository(rows), FakeDashboard(), FakeAudit()
    )


def preview(report, compare=False, **filters):
    return ReportPreviewRequest(
        report=report, compare=compare, filters=ReportFilters(**filters)
    )


async def test_catalog_lists_every_report_with_the_filters_it_takes():
    catalog = await service().catalog()
    keys = [r.key for r in catalog.reports]
    assert keys == [
        "equipment",
        "tickets",
        "summary",
        "maintenance_plans",
        "inventory_items",
        "inventory_movements",
    ]
    assert (
        catalog.max_rows == 10_000
        and catalog.max_range_days == 366
        and "pdf" in catalog.formats
    )
    equipment = catalog.reports[0]
    types = next(f for f in equipment.filters if f.key == "equipment_type_ids")
    assert [(o.value, o.label) for o in types.options] == [
        ("1", "Laptop"),
        ("2", "Servidor"),
    ]
    assert (
        catalog.reports[1].supports_compare and not catalog.reports[0].supports_compare
    )
    assert [f.kind for f in catalog.reports[1].filters] == [
        "multiselect",
        "multiselect",
        "dates",
    ]


async def test_preview_translates_codes_and_formats_cells():
    result = await service().preview(ACTOR, preview("equipment"), now=NOW)
    assert (
        result.title == "Inventario de equipos"
        and result.total_rows == 1
        and result.truncated is False
    )
    assert result.rows[0]["status"] == "En mantenimiento"
    assert result.rows[0]["purchase_cost"] == "1200.50"
    assert result.rows[0]["serial_number"] == ""
    assert [c.header for c in result.columns][:3] == [
        "Código de activo",
        "Serie",
        "Tipo",
    ]
    tickets = await service().preview(ACTOR, preview("tickets"), now=NOW)
    assert (tickets.rows[0]["priority"], tickets.rows[0]["status"]) == (
        "Alta",
        "En curso",
    )
    assert tickets.rows[0]["created_at"] == "2026-10-14 12:00"


async def test_preview_shows_only_the_first_rows_but_counts_all():
    many = [
        {"ticket_number": f"T-{i}", "priority": "low", "status": "closed"}
        for i in range(40)
    ]
    result = await service(many).preview(ACTOR, preview("tickets"), now=NOW)
    assert len(result.rows) == 15 and result.total_rows == 40


async def test_preview_flags_a_result_beyond_the_export_limit():
    huge = [{"ticket_number": "T", "priority": "low", "status": "closed"}] * 10_001
    result = await service(huge).preview(ACTOR, preview("tickets"), now=NOW)
    assert result.truncated is True and result.total_rows == 10_000


async def test_filters_reach_the_repository_as_lists():
    svc = service()
    await svc.preview(
        ACTOR,
        preview(
            "tickets",
            statuses=["closed", "resolved"],
            priorities=["high"],
            date_from=aware(1),
            date_to=aware(30),
        ),
        now=NOW,
    )
    _, kwargs = svc.repository.calls[-1]
    assert kwargs["statuses"] == ["closed", "resolved"] and kwargs["priorities"] == [
        "high"
    ]
    assert (
        kwargs["date_from"] == datetime(2026, 9, 1, tzinfo=UTC)
        and kwargs["limit"] == 10_001
    )


@pytest.mark.parametrize(
    ("report", "filters", "message"),
    [
        ("equipment", {"priorities": ["high"]}, "does not accept: priorities"),
        ("equipment", {"date_from": aware(1)}, "does not accept: date_from"),
        ("summary", {"statuses": ["closed"]}, "does not accept"),
        ("inventory_items", {"kinds": ["in"]}, "does not accept: kinds"),
        ("tickets", {"statuses": ["flying"]}, "unknown statuses for 'tickets': flying"),
        ("equipment", {"statuses": ["closed"]}, "unknown statuses"),
        ("inventory_items", {"categories": ["furniture"]}, "unknown categories"),
        ("inventory_movements", {"kinds": ["steal"]}, "unknown kinds"),
        ("maintenance_plans", {"statuses": ["closed"]}, "unknown statuses"),
        ("summary", {"days": 45}, "days must be one of"),
    ],
)
async def test_filters_a_report_does_not_take_or_values_it_does_not_know_are_a_422(
    report, filters, message
):
    with pytest.raises(UnprocessableError, match=message):
        await service().preview(ACTOR, preview(report, **filters), now=NOW)


async def test_comparison_counts_the_previous_period_of_equal_length():
    def rows(kwargs):
        # current window (Sept 11-20, 10 days): 6 rows; the 10 days before: 4 rows
        return [{"ticket_number": "T", "priority": "low", "status": "closed"}] * (
            6 if kwargs["date_from"].day == 11 else 4
        )

    svc = service(rows)
    result = await svc.preview(
        ACTOR,
        preview("tickets", compare=True, date_from=aware(11), date_to=aware(20)),
        now=NOW,
    )
    comparison = result.comparison
    assert (
        comparison.current_total,
        comparison.previous_total,
        comparison.change_pct,
    ) == (6, 4, 50.0)
    assert comparison.previous_to == datetime(2026, 9, 11, tzinfo=UTC) - timedelta(
        microseconds=1
    )
    assert comparison.previous_from == comparison.previous_to - timedelta(days=9)
    previous_call = svc.repository.calls[-1][1]
    assert previous_call["date_to"] == comparison.previous_to


async def test_comparison_without_a_previous_period_has_no_percentage():
    svc = service(
        lambda kwargs: (
            [{"ticket_number": "T", "priority": "low", "status": "closed"}]
            * (3 if kwargs["date_from"].day == 11 else 0)
        )
    )
    result = await svc.preview(
        ACTOR,
        preview("tickets", compare=True, date_from=aware(11), date_to=aware(20)),
        now=NOW,
    )
    assert (
        result.comparison.previous_total == 0 and result.comparison.change_pct is None
    )


@pytest.mark.parametrize(
    ("report", "filters", "message"),
    [
        ("tickets", {"date_from": aware(1)}, "both date_from and date_to"),
        ("tickets", {}, "both date_from and date_to"),
        ("equipment", {}, "cannot be compared"),
        ("summary", {"days": 30}, "cannot be compared"),
    ],
)
async def test_comparing_needs_dates_and_a_comparable_report(report, filters, message):
    with pytest.raises(UnprocessableError, match=message):
        await service().preview(
            ACTOR, preview(report, compare=True, **filters), now=NOW
        )


async def test_summary_report_has_spanish_sections_and_honours_the_days():
    result = await service().preview(ACTOR, preview("summary", days=90), now=NOW)
    sections = {row["section"] for row in result.rows}
    assert "Tickets" in sections and "Resolución" in sections
    assert result.total_rows >= len(result.rows) > 0


# -- generate ---------------------------------------------------------------------------------


def generate(report, fmt="csv", **filters):
    return ReportGenerateRequest(
        report=report, format=fmt, filters=ReportFilters(**filters)
    )


async def test_generating_logs_the_run_and_the_audit_trail():
    svc = service()
    file = await svc.generate(
        ACTOR, generate("tickets", "csv", statuses=["in_progress"]), now=NOW
    )
    assert file.filename == "tickets-20261014-1200.csv" and file.media_type.startswith(
        "text/csv"
    )
    (run,) = svc.repository.runs
    assert (run.report_key, run.export_format, run.row_count, run.user_id) == (
        "tickets",
        "csv",
        1,
        1,
    )
    assert run.filters == {"statuses": ["in_progress"]}
    assert svc.audit.records[0]["action"] == "report.generated"
    assert svc.audit.records[0]["new_values"] == {
        "report": "tickets",
        "format": "csv",
        "rows": 1,
    }
    assert svc.repository.committed == 1


async def test_the_file_has_spanish_headers_translated_values_and_a_filter_summary():
    text = (
        await service().generate(
            ACTOR,
            generate("tickets", "csv", statuses=["in_progress"], priorities=["high"]),
            now=NOW,
        )
    ).content.decode("utf-8-sig")
    assert text.splitlines()[0].startswith("Ticket,Título,Prioridad,Estado")
    assert "Alta" in text and "En curso" in text


async def test_spreadsheet_formulas_in_the_data_are_neutralised():
    text = (
        await service().generate(ACTOR, generate("tickets"), now=NOW)
    ).content.decode("utf-8-sig")
    assert "'=cmd|calc" in text


@pytest.mark.parametrize(("fmt", "magic"), [("xlsx", b"PK"), ("pdf", b"%PDF")])
async def test_binary_formats_render(fmt, magic):
    file = await service().generate(ACTOR, generate("inventory_items", fmt), now=NOW)
    assert file.content.startswith(magic) and file.filename.endswith(f".{fmt}")


async def test_an_oversized_report_asks_for_narrower_filters_instead_of_truncating():
    huge = [{"ticket_number": "T", "priority": "low", "status": "closed"}] * 10_001
    svc = service(huge)
    with pytest.raises(UnprocessableError, match="narrow the filters"):
        await svc.generate(ACTOR, generate("tickets"), now=NOW)
    assert svc.repository.runs == []  # nothing was generated, so nothing is logged


async def test_invalid_filters_log_nothing():
    svc = service()
    with pytest.raises(UnprocessableError):
        await svc.generate(
            ACTOR, generate("equipment", "xlsx", priorities=["high"]), now=NOW
        )
    assert svc.repository.runs == [] and svc.audit.records == []


# -- activity ---------------------------------------------------------------------------------


async def test_overview_reports_generated_reports_against_the_previous_period():
    result = await service().overview(period="30d", now=NOW)
    assert (result.generated, result.previous, result.change_pct) == (12, 8, 50.0)
    assert result.low_sample is False and result.people == 3
    assert (
        result.most_used[0].report,
        result.most_used[0].title,
        result.most_used[0].count,
    ) == (
        "tickets",
        "Tickets de mantenimiento",
        7,
    )
    assert result.by_format == {"xlsx": 9, "pdf": 3}
    assert (
        result.last_export.title,
        result.last_export.by,
        result.last_export.row_count,
    ) == ("Tickets de mantenimiento", "Ana", 120)


async def test_overview_without_activity_has_no_percentage_and_flags_few_runs():
    svc = service()
    svc.repository.overview = {"runs": [0, 0]}
    quiet = await svc.overview(period="7d", now=NOW)
    assert quiet.change_pct is None and quiet.low_sample is False
    svc.repository.overview = {"runs": [3, 0]}
    assert (await svc.overview(period="7d", now=NOW)).low_sample is True


async def test_history_pages_through_the_runs():
    page = await service().history(page=2, size=10)
    assert page.total == 25 and page.page == 2
    assert page.items[0].title == "Tickets de mantenimiento" and page.items[
        0
    ].filters == {"statuses": ["closed"]}


async def test_history_reads_the_exports_that_are_not_builder_reports():
    """The technician roster and the user list export too; their runs must not break the history."""
    svc = service()
    svc.repository.recent_runs = lambda **_: _runs(
        [
            RunRow(1, "technicians", "pdf", 3, {}, "Ana", NOW),
            RunRow(2, "users", "xlsx", 13, {}, "Ana", NOW),
        ]
    )
    page = await svc.history(page=1, size=10)
    assert [(item.report, item.title) for item in page.items] == [
        ("technicians", "Técnicos"),
        ("users", "Usuarios"),
    ]


async def _runs(rows):
    return rows


# -- HTTP -----------------------------------------------------------------------------------


class StubBuilder(ReportBuilderService):
    def __init__(self):
        super().__init__(FakeBuilderRepository(), FakeDashboard(), FakeAudit())
        self.calls = []

    async def preview(self, actor, request, *, now=None):
        self.calls.append(("preview", request.report))
        return await super().preview(actor, request, now=NOW)

    async def generate(self, actor, request, *, now=None):
        self.calls.append(("generate", request.report, request.export_format))
        return await super().generate(actor, request, now=NOW)


def build_client(permissions):
    stub = StubBuilder()
    user = SimpleNamespace(
        id=1,
        full_name="Ana",
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=perm_objects(*permissions),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_report_builder_service] = lambda: stub
    return stub


@pytest.fixture
def client():
    stub = build_client(["reports.read"])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def forbidden():
    build_client([])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_catalog_endpoint(client):
    body = client.get("/reports/catalog").json()
    assert len(body["reports"]) == 6 and body["max_range_days"] == 366


def test_preview_endpoint_validates_the_whole_body(client):
    ok = client.post(
        "/reports/preview",
        json={"report": "tickets", "filters": {"statuses": ["closed"]}},
    )
    assert ok.status_code == 200 and ok.json()["total_rows"] == 1
    bad_bodies = [
        {"report": "nope"},
        {
            "report": "tickets",
            "filters": {
                "date_from": "2026-09-10T00:00:00Z",
                "date_to": "2026-09-01T00:00:00Z",
            },
        },
        {
            "report": "tickets",
            "filters": {
                "date_from": "2024-01-01T00:00:00Z",
                "date_to": "2026-01-01T00:00:00Z",
            },
        },
        {"report": "tickets", "filters": {"date_from": "2026-09-01T00:00:00"}},
        {"report": "tickets", "filters": {"statuses": ["BAD"]}},
        {"report": "tickets", "filters": {"mystery": 1}},
        {"report": "tickets", "filters": {"statuses": "closed"}},
    ]
    for body in bad_bodies:
        response = client.post("/reports/preview", json=body)
        assert response.status_code == 422, body
        assert response.json()["errors"], body
    assert (
        client.post(
            "/reports/preview",
            json={"report": "equipment", "filters": {"priorities": ["high"]}},
        ).json()["code"]
        == "unprocessable"
    )


def test_generate_endpoint_returns_an_attachment_and_exposes_its_name(client):
    response = client.post(
        "/reports/generate", json={"report": "tickets", "format": "xlsx"}
    )
    assert response.status_code == 200
    assert (
        response.headers["content-disposition"]
        == 'attachment; filename="tickets-20261014-1200.xlsx"'
    )
    assert "Content-Disposition" in response.headers["access-control-expose-headers"]
    assert (
        response.headers["cache-control"] == "no-store"
        and response.content[:2] == b"PK"
    )
    assert (
        client.post(
            "/reports/generate", json={"report": "tickets", "format": "docx"}
        ).status_code
        == 422
    )
    assert (
        client.stub.calls[-1] == ("generate", "tickets", "xlsx")
        or client.stub.calls[-1][0] == "generate"
    )


def test_overview_and_history_endpoints(client):
    assert client.get("/reports/overview?period=12m").json()["generated"] == 12
    assert client.get("/reports/overview?period=1d").status_code == 422
    history = client.get("/reports/history?page=1&size=5")
    assert history.status_code == 200 and history.headers["x-total-count"] == "25"
    assert client.get("/reports/history?size=500").status_code == 422
    assert client.get("/reports/history?page=0").status_code == 422


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/reports/catalog"),
        ("post", "/reports/preview"),
        ("post", "/reports/generate"),
        ("get", "/reports/overview"),
        ("get", "/reports/history"),
    ],
)
def test_every_report_endpoint_needs_the_reports_permission(forbidden, method, path):
    kwargs = {"json": {"report": "tickets"}} if method == "post" else {}
    assert getattr(forbidden, method)(path, **kwargs).status_code == 403


# -- real-database datasets (need TEST_DATABASE_URL) ----------------------------------------------


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
    plans = [
        MaintenanceSchedule(
            equipment_id=laptop.id,
            technician_id=tech.id,
            title="vencido",
            interval_days=30,
            next_due_at=NOW - timedelta(days=3),
            is_active=True,
        ),
        MaintenanceSchedule(
            equipment_id=laptop.id,
            title="programado",
            interval_days=30,
            next_due_at=NOW + timedelta(days=5),
            is_active=True,
        ),
        MaintenanceSchedule(
            equipment_id=laptop.id,
            title="inactivo",
            interval_days=30,
            next_due_at=NOW + timedelta(days=9),
            is_active=False,
        ),
    ]
    items = [
        InventoryItem(
            sku="OK-1",
            name="Item ok",
            category="spare_part",
            unit="unidad",
            unit_cost=Decimal(10),
            stock=20,
            min_stock=5,
        ),
        InventoryItem(
            sku="LOW-1",
            name="Item low",
            category="tool",
            unit="unidad",
            unit_cost=Decimal(5),
            stock=3,
            min_stock=5,
        ),
        InventoryItem(
            sku="OUT-1",
            name="Item out",
            category="tool",
            unit="unidad",
            unit_cost=Decimal(5),
            stock=0,
            min_stock=2,
        ),
        InventoryItem(
            sku="OFF-1",
            name="Item off",
            category="other",
            unit="unidad",
            unit_cost=Decimal(1),
            stock=1,
            min_stock=0,
            is_active=False,
        ),
    ]
    session.add_all([*plans, *items])
    await session.flush()
    session.add_all(
        [
            ScheduleRun(
                schedule_id=plans[0].id,
                due_at=NOW - timedelta(days=40),
                completed_at=NOW - timedelta(days=39),
            ),
            ScheduleRun(
                schedule_id=plans[0].id,
                due_at=NOW - timedelta(days=10),
                completed_at=NOW - timedelta(days=9),
            ),
            InventoryMovement(
                item_id=items[0].id,
                kind="in",
                quantity=20,
                stock_after=20,
                created_at=NOW - timedelta(days=20),
            ),
            InventoryMovement(
                item_id=items[0].id,
                kind="out",
                quantity=-2,
                stock_after=18,
                created_at=NOW - timedelta(days=2),
                created_by_user_id=user.id,
            ),
        ]
    )
    await session.flush()
    return user


async def test_plan_rows_classify_filter_and_count_services(db_session):
    await seed(db_session)
    repo = ReportBuilderRepository(db_session)
    rows = await repo.plan_rows(statuses=None, date_from=None, date_to=None, now=NOW)
    assert [(r["title"], r["status"]) for r in rows] == [
        ("vencido", "overdue"),
        ("programado", "scheduled"),
        ("inactivo", "inactive"),
    ]
    assert (
        rows[0]["runs"] == 2
        and rows[0]["last_done"] == NOW - timedelta(days=9)
        and rows[1]["runs"] == 0
    )
    only = await repo.plan_rows(
        statuses=["overdue", "inactive"], date_from=None, date_to=None, now=NOW
    )
    assert [r["title"] for r in only] == ["vencido", "inactivo"]
    ranged = await repo.plan_rows(
        statuses=None, date_from=NOW, date_to=NOW + timedelta(days=6), now=NOW
    )
    assert [r["title"] for r in ranged] == ["programado"]


async def test_item_rows_filter_by_category_and_computed_status(db_session):
    await seed(db_session)
    repo = ReportBuilderRepository(db_session)
    rows = await repo.item_rows(categories=None, statuses=None)
    assert {r["sku"]: r["status"] for r in rows} == {
        "OK-1": "ok",
        "LOW-1": "low",
        "OUT-1": "out",
        "OFF-1": "inactive",
    }
    assert next(r for r in rows if r["sku"] == "OK-1")["stock_value"] == Decimal(200)
    assert sorted(
        r["sku"]
        for r in await repo.item_rows(categories=["tool"], statuses=["low", "out"])
    ) == ["LOW-1", "OUT-1"]


async def test_movement_rows_filter_by_kind_and_dates_newest_first(db_session):
    await seed(db_session)
    repo = ReportBuilderRepository(db_session)
    rows = await repo.movement_rows(kinds=None, date_from=None, date_to=None)
    assert [r["kind"] for r in rows] == ["out", "in"] and rows[0][
        "registered_by"
    ] == "Luis"
    assert [
        r["kind"]
        for r in await repo.movement_rows(kinds=["in"], date_from=None, date_to=None)
    ] == ["in"]
    recent = await repo.movement_rows(
        kinds=None, date_from=NOW - timedelta(days=5), date_to=NOW
    )
    assert [r["kind"] for r in recent] == ["out"]


async def test_the_activity_log_counts_runs_in_a_window(db_session):
    user = await seed(db_session)
    repo = ReportBuilderRepository(db_session)
    for key, fmt, days_ago in (
        ("tickets", "pdf", 1),
        ("tickets", "xlsx", 2),
        ("equipment", "csv", 40),
    ):
        run = repo.record_run(
            report_key=key, export_format=fmt, filters={}, row_count=5, user_id=user.id
        )
        run.created_at = NOW - timedelta(days=days_ago)
    await db_session.flush()
    start, end = NOW - timedelta(days=30), NOW + timedelta(days=1)
    assert (
        await repo.runs_in(start, end) == 2
        and await repo.runs_in(NOW - timedelta(days=60), start) == 1
    )
    assert await repo.people_in(start, end) == 1
    assert await repo.most_used(start, end, limit=5) == [("tickets", 2)]
    assert await repo.by_format(start, end) == {"pdf": 1, "xlsx": 1}
    last = await repo.last_run()
    assert (last.report_key, last.export_format, last.by) == ("tickets", "pdf", "Luis")
    assert await repo.count_runs() == 3
    page = await repo.recent_runs(limit=2, offset=1)
    assert [r.export_format for r in page] == ["xlsx", "csv"]
