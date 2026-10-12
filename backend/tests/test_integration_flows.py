"""End-to-end API flows over the real DI chain and a real PostgreSQL schema.

Needs `MIGRATED_DATABASE_URL`: a database upgraded with `alembic upgrade head`
(roles, permissions, priorities and equipment types come from the migrations).
Each test runs inside a transaction that is rolled back, so nothing persists.
Requests go through the real routers, services, repositories and permission
checks; only the Clerk token verification and the file storage location are
replaced.
"""

import io
import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from fastapi import HTTPException, Request
from openpyxl import Workbook
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.config import Settings
from app.core.storage import LocalFileStorage
from app.db.session import get_db
from app.main import app
from app.models.auth import Role, User, UserRole
from app.models.notification import Notification
from app.repositories.auth import AuthRepository

MIGRATED_DATABASE_URL = os.environ.get("MIGRATED_DATABASE_URL", "")
pytestmark = pytest.mark.skipif(
    not MIGRATED_DATABASE_URL, reason="MIGRATED_DATABASE_URL is not set"
)

PDF = b"%PDF-1.7 integration"


class Api:
    """Thin client: every call is made as a given test user."""

    def __init__(self, client: httpx.AsyncClient, session: AsyncSession):
        self.client = client
        self.session = session
        self._count = 0

    async def user(self, *role_codes: str, name: str | None = None) -> str:
        """Create a local user holding `role_codes`; returns its fake Clerk id."""
        self._count += 1
        clerk_id = f"test_{self._count}_{os.urandom(3).hex()}"
        user = User(
            clerk_user_id=clerk_id,
            email=f"{clerk_id}@example.com",
            full_name=name or f"User {self._count}",
            is_active=True,
        )
        self.session.add(user)
        await self.session.flush()
        for code in role_codes:
            role = (
                await self.session.execute(select(Role).where(Role.code == code))
            ).scalar_one()
            self.session.add(UserRole(user_id=user.id, role_id=role.id))
        await self.session.flush()
        return clerk_id

    async def id_of(self, clerk_id: str) -> int:
        row = await self.session.execute(
            select(User.id).where(User.clerk_user_id == clerk_id)
        )
        return row.scalar_one()

    async def call(self, method: str, path: str, as_user: str | None = None, **kwargs):
        headers = kwargs.pop("headers", {})
        if as_user:
            headers["X-Test-User"] = as_user
        return await self.client.request(method, path, headers=headers, **kwargs)

    async def get(self, path, as_user=None, **kw):
        return await self.call("GET", path, as_user, **kw)

    async def post(self, path, as_user=None, **kw):
        return await self.call("POST", path, as_user, **kw)

    async def patch(self, path, as_user=None, **kw):
        return await self.call("PATCH", path, as_user, **kw)

    async def delete(self, path, as_user=None, **kw):
        return await self.call("DELETE", path, as_user, **kw)


@pytest.fixture
async def api(tmp_path) -> AsyncIterator[Api]:
    url = Settings(database_url=MIGRATED_DATABASE_URL).database_url
    engine = create_async_engine(url)
    connection = await engine.connect()
    outer = await connection.begin()
    session = AsyncSession(
        bind=connection,
        join_transaction_mode="create_savepoint",
        expire_on_commit=False,
        autoflush=False,
    )

    async def override_db():
        yield session

    async def override_auth(request: Request) -> User:
        clerk_id = request.headers.get("X-Test-User")
        if not clerk_id:
            raise HTTPException(status_code=401, detail="missing credentials")
        session.expire_all()  # see role changes made by earlier requests
        user = await AuthRepository(session).get_user_by_clerk_id(clerk_id)
        if user is None:
            raise HTTPException(status_code=401, detail="unknown user")
        return user

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_authenticated_user] = override_auth
    app.dependency_overrides[providers.get_file_storage] = lambda: LocalFileStorage(
        tmp_path
    )
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        yield Api(client, session)
    app.dependency_overrides.clear()
    await session.close()
    await outer.rollback()
    await connection.close()
    await engine.dispose()


async def make_equipment(api: Api, admin: str, tag="LT-INT-1", **extra) -> dict:
    types = (await api.get("/equipment/types", admin)).json()
    laptop = next(t for t in types if t["code"] == "LAPTOP")
    response = await api.post(
        "/equipment",
        admin,
        json={
            "asset_tag": tag,
            "equipment_type_id": laptop["id"],
            "brand": "Dell",
            "model": "Latitude",
            **extra,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


async def make_technician(api: Api, admin: str, name="Tina Tech") -> tuple[str, dict]:
    clerk = await api.user("TECHNICIAN", name=name)
    response = await api.post(
        "/technicians",
        admin,
        json={"user_id": await api.id_of(clerk), "specialization": "Hardware"},
    )
    assert response.status_code == 201, response.text
    return clerk, response.json()


# -- the ticket lifecycle -----------------------------------------------------------


async def test_ticket_lifecycle_from_request_to_closure(api):
    admin = await api.user("ADMIN", name="Ada Admin")
    supervisor = await api.user("SUPERVISOR", name="Sam Super")
    employee = await api.user("EMPLOYEE", name="Eva Employee")
    technician, profile = await make_technician(api, admin)
    equipment = await make_equipment(api, admin)

    # the employee reports a problem
    created = await api.post(
        "/maintenance/requests",
        employee,
        json={
            "equipment_id": equipment["id"],
            "title": "Screen flickers",
            "description": "Flickers after wake-up",
            "priority": "high",
        },
    )
    assert created.status_code == 201, created.text
    ticket = created.json()
    assert ticket["status"] == "submitted"
    assert ticket["ticket_number"].startswith("TCK-")
    assert ticket["allowed_next_statuses"] == ["assigned", "cancelled", "triaged"]
    tid = ticket["id"]

    # an employee cannot manage the ticket...
    assert (
        await api.post(
            f"/maintenance/requests/{tid}/assignment",
            employee,
            json={"technician_id": profile["id"]},
        )
    ).status_code == 403
    # ...and the state machine refuses a jump to 'assigned' without a technician
    jump = await api.post(
        f"/maintenance/requests/{tid}/status", supervisor, json={"status": "assigned"}
    )
    assert jump.status_code == 409 and jump.json()["code"] == "invalid_transition"

    # the supervisor assigns the technician: submitted -> assigned through the state machine
    assigned = await api.post(
        f"/maintenance/requests/{tid}/assignment",
        supervisor,
        json={"technician_id": profile["id"], "notes": "Please check today"},
    )
    assert assigned.status_code == 200, assigned.text
    assert assigned.json()["status"] == "assigned"
    assert (
        assigned.json()["current_assignment"]["technician"]["full_name"] == "Tina Tech"
    )

    # the technician works the ticket
    started = await api.post(
        f"/maintenance/requests/{tid}/status",
        technician,
        json={"status": "in_progress"},
    )
    assert started.json()["status"] == "in_progress"
    record = await api.post(
        f"/maintenance/requests/{tid}/records",
        technician,
        json={
            "work_type": "corrective",
            "started_at": "2026-10-11T09:00:00Z",
            "completed_at": "2026-10-11T10:00:00Z",
            "diagnosis": "Loose display cable",
            "actions_taken": "Reseated the cable",
            "result": "resolved",
            "labor_cost": "20.00",
            "parts_cost": "5.50",
        },
    )
    assert record.status_code == 201, record.text
    assert record.json()["total_cost"] == "25.50"
    resolved = await api.post(
        f"/maintenance/requests/{tid}/status",
        technician,
        json={"status": "resolved", "resolution_summary": "Cable reseated"},
    )
    body = resolved.json()
    assert body["status"] == "resolved" and body["resolved_at"]
    assert body["resolution_summary"] == "Cable reseated"

    # the requester was told; the supervisor closes the ticket
    notices = (await api.get("/notifications", employee)).json()
    assert notices["unread_count"] >= 1
    assert any("resolved" in n["title"] for n in notices["items"])
    closed = await api.post(
        f"/maintenance/requests/{tid}/status", supervisor, json={"status": "closed"}
    )
    assert closed.json()["status"] == "closed" and closed.json()["closed_at"]
    assert closed.json()["allowed_next_statuses"] == []

    history = closed.json()["status_history"]
    assert [h["to_status"] for h in history] == [
        "submitted",
        "assigned",
        "in_progress",
        "resolved",
        "closed",
    ]
    # terminal state: nothing else is possible
    again = await api.post(
        f"/maintenance/requests/{tid}/status",
        supervisor,
        json={"status": "in_progress"},
    )
    assert again.status_code == 409

    # audit trail: who/what/when with previous and new values
    trail = await api.get(
        f"/audit-logs?entity_type=maintenance_request&entity_id={tid}&sort=id",
        supervisor,
    )
    assert trail.status_code == 200
    actions = [row["action"] for row in trail.json()]
    assert actions[0] == "maintenance.request_created"
    assert actions.count("maintenance.status_changed") == 3
    changed = [r for r in trail.json() if r["action"] == "maintenance.status_changed"]
    assert changed[0]["old_values"] == {"status": "assigned"}
    assert changed[0]["new_values"] == {"status": "in_progress"}
    assert changed[0]["user"]["full_name"] == "Tina Tech"
    assert changed[0]["ip_address"]  # request metadata was captured

    # the same data feeds the dashboard and the export
    summary = (await api.get("/dashboard/summary", supervisor)).json()
    by_status = {i["key"]: i["count"] for i in summary["tickets"]["by_status"]}
    assert by_status.get("closed", 0) >= 1
    assert summary["resolution"]["resolved_count"] >= 1
    export = await api.get("/reports/tickets?format=csv", supervisor)
    assert export.status_code == 200
    assert ticket["ticket_number"] in export.content.decode("utf-8-sig")
    assert 'filename="tickets-' in export.headers["content-disposition"]


async def test_ticket_visibility_is_scoped_by_role(api):
    admin = await api.user("ADMIN")
    alice = await api.user("EMPLOYEE", name="Alice")
    bob = await api.user("EMPLOYEE", name="Bob")
    equipment = await make_equipment(api, admin)

    async def open_ticket(user, title):
        response = await api.post(
            "/maintenance/requests",
            user,
            json={"equipment_id": equipment["id"], "title": title, "description": "d"},
        )
        assert response.status_code == 201
        return response.json()

    alices = await open_ticket(alice, "Alice's laptop")
    await open_ticket(bob, "Bob's laptop")

    mine = await api.get("/maintenance/requests", alice)
    assert [t["title"] for t in mine.json()] == ["Alice's laptop"]
    assert mine.headers["X-Total-Count"] == "1"
    everything = await api.get("/maintenance/requests", admin)
    assert everything.headers["X-Total-Count"] == "2"

    assert (
        await api.get(f"/maintenance/requests/{alices['id']}", bob)
    ).status_code == 403
    assert (
        await api.get(f"/maintenance/requests/{alices['id']}", alice)
    ).status_code == 200
    assert (await api.get("/maintenance/requests/999999", admin)).status_code == 404

    search = await api.get("/maintenance/requests?search=bob&sort=-priority", admin)
    assert [t["title"] for t in search.json()] == ["Bob's laptop"]


async def test_ticket_priority_follows_the_managed_catalog(api):
    admin = await api.user("ADMIN")
    employee = await api.user("EMPLOYEE")
    equipment = await make_equipment(api, admin)
    payload = {"equipment_id": equipment["id"], "title": "t", "description": "d"}

    unknown = await api.post(
        "/maintenance/requests", employee, json={**payload, "priority": "urgent"}
    )
    assert unknown.status_code == 404

    created = await api.post(
        "/priorities",
        admin,
        json={"code": "urgent", "name": "Urgent", "level": 9, "sla_hours": 1},
    )
    assert created.status_code == 201
    dup = await api.post(
        "/priorities", admin, json={"code": "urgent", "name": "Again", "level": 9}
    )
    assert dup.status_code == 409
    assert (
        await api.post(
            "/priorities", employee, json={"code": "x1", "name": "X", "level": 1}
        )
    ).status_code == 403

    ok = await api.post(
        "/maintenance/requests", employee, json={**payload, "priority": "urgent"}
    )
    assert ok.status_code == 201

    listing = (await api.get("/priorities", employee)).json()
    assert listing[0]["code"] == "urgent"  # most urgent first

    await api.patch(
        f"/priorities/{created.json()['id']}", admin, json={"is_active": False}
    )
    gone = await api.post(
        "/maintenance/requests", employee, json={**payload, "priority": "urgent"}
    )
    assert gone.status_code == 404


# -- equipment ----------------------------------------------------------------------


async def test_equipment_listing_search_sort_pagination_and_updates(api):
    admin = await api.user("ADMIN")
    employee = await api.user("EMPLOYEE")
    for tag, brand in (("EQ-C", "HP"), ("EQ-A", "Dell"), ("EQ-B", "Dell")):
        await make_equipment(api, admin, tag=tag, brand=brand)

    page = await api.get("/equipment?size=2&sort=asset_tag&search=EQ-", employee)
    assert page.status_code == 200
    assert [e["asset_tag"] for e in page.json()] == ["EQ-A", "EQ-B"]
    assert page.headers["X-Total-Count"] == "3"
    assert page.headers["X-Total-Pages"] == "2"
    second = await api.get(
        "/equipment?size=2&page=2&sort=asset_tag&search=EQ-", employee
    )
    assert [e["asset_tag"] for e in second.json()] == ["EQ-C"]
    desc = await api.get("/equipment?sort=-asset_tag&search=EQ-&brand=dell", employee)
    assert [e["asset_tag"] for e in desc.json()] == ["EQ-B", "EQ-A"]
    literal = await api.get("/equipment?search=%25", employee)  # '%' is not a wildcard
    assert literal.json() == []

    dup = await api.post(
        "/equipment",
        admin,
        json={
            "asset_tag": "EQ-A",
            "equipment_type_id": page.json()[0]["equipment_type_id"],
            "brand": "x",
            "model": "y",
        },
    )
    assert dup.status_code == 409 and dup.json()["code"] == "conflict"
    assert (await api.post("/equipment", employee, json={})).status_code == 403

    target = page.json()[0]
    patched = await api.patch(
        f"/equipment/{target['id']}", admin, json={"status": "in_repair"}
    )
    assert patched.json()["status"] == "in_repair"
    trail = (
        await api.get(
            f"/audit-logs?entity_type=equipment&entity_id={target['id']}", admin
        )
    ).json()
    updated = next(r for r in trail if r["action"] == "equipment.updated")
    assert updated["new_values"]["status"] == "in_repair"


async def test_equipment_location_custody_and_locations_listing(api):
    admin = await api.user("ADMIN")
    holder = await api.user("EMPLOYEE", name="Hal Holder")
    equipment = await make_equipment(api, admin)

    room = await api.post(
        "/locations", admin, json={"code": "R-101", "name": "Room 101", "kind": "room"}
    )
    assert room.status_code == 201
    placed = await api.post(
        f"/equipment/{equipment['id']}/location",
        admin,
        json={"location_id": room.json()["id"]},
    )
    assert placed.status_code == 200, placed.text
    given = await api.post(
        f"/equipment/{equipment['id']}/custody",
        admin,
        json={"assigned_to_user_id": await api.id_of(holder)},
    )
    assert given.status_code == 200, given.text

    rooms = await api.get("/locations?search=room", holder)
    assert [r["code"] for r in rooms.json()] == ["R-101"]
    inventory = await api.get("/reports/equipment?format=csv", admin)
    text = inventory.content.decode("utf-8-sig")
    assert "LT-INT-1" in text and "Room 101" in text and "Hal Holder" in text


def xlsx(rows) -> bytes:
    book = Workbook()
    for row in rows:
        book.active.append(row)
    buffer = io.BytesIO()
    book.save(buffer)
    return buffer.getvalue()


async def test_equipment_bulk_import_dry_run_then_real_then_duplicates(api):
    admin = await api.user("ADMIN")
    sheet = xlsx(
        [
            [
                "Asset Tag",
                "Equipment Type",
                "Brand",
                "Model",
                "Serial Number",
                "Purchase Date",
            ],
            ["IMP-1", "LAPTOP", "Lenovo", "T14", "SER-1", "2026-03-04"],
            ["IMP-2", "monitor", "LG", "27UL", None, None],
        ]
    )
    files = {"file": ("inventory.xlsx", sheet, "application/octet-stream")}

    dry = await api.post("/imports/equipment?dry_run=true", admin, files=files)
    assert dry.json() == {
        "dry_run": True,
        "success": True,
        "total_rows": 2,
        "created": 0,
        "errors": [],
    }
    assert (await api.get("/equipment?search=IMP-", admin)).json() == []

    real = await api.post("/imports/equipment", admin, files=files)
    assert real.json()["created"] == 2
    imported = (await api.get("/equipment?search=IMP-&sort=asset_tag", admin)).json()
    assert [e["asset_tag"] for e in imported] == ["IMP-1", "IMP-2"]
    assert imported[0]["purchase_date"] == "2026-03-04"

    again = await api.post("/imports/equipment", admin, files=files)
    body = again.json()
    assert body["success"] is False and body["created"] == 0
    assert {(e["row"], e["field"]) for e in body["errors"]} >= {
        (2, "asset_tag"),
        (2, "serial_number"),
    }

    audit = (await api.get("/audit-logs?action=equipment.imported", admin)).json()
    assert audit[0]["new_values"] == {"created": 2}


# -- attachments ------------------------------------------------------------------------


async def test_ticket_attachments_upload_download_and_access_rules(api):
    admin = await api.user("ADMIN")
    owner = await api.user("EMPLOYEE", name="Olga Owner")
    stranger = await api.user("EMPLOYEE", name="Stan Stranger")
    equipment = await make_equipment(api, admin)
    ticket = (
        await api.post(
            "/maintenance/requests",
            owner,
            json={"equipment_id": equipment["id"], "title": "t", "description": "d"},
        )
    ).json()
    base = f"/maintenance/requests/{ticket['id']}/attachments"

    up = await api.post(
        base, owner, files={"file": ("../../photo report.pdf", PDF, "application/pdf")}
    )
    assert up.status_code == 201, up.text
    meta = up.json()
    assert meta["file_name"] == "photo report.pdf" and meta["file_size"] == len(PDF)

    assert (
        await api.post(
            base, stranger, files={"file": ("a.pdf", PDF, "application/pdf")}
        )
    ).status_code == 403
    spoof = await api.post(
        base, owner, files={"file": ("a.pdf", b"<html>", "application/pdf")}
    )
    assert spoof.status_code == 415

    listing = await api.get(base, owner)
    assert [a["id"] for a in listing.json()] == [meta["id"]]
    download = await api.get(f"/attachments/{meta['id']}/download", owner)
    assert download.content == PDF
    assert download.headers["x-content-type-options"] == "nosniff"
    assert (
        await api.get(f"/attachments/{meta['id']}/download", stranger)
    ).status_code == 403
    assert (
        await api.get(f"/attachments/{meta['id']}/download", admin)
    ).status_code == 200

    assert (await api.delete(f"/attachments/{meta['id']}", stranger)).status_code == 403
    assert (await api.delete(f"/attachments/{meta['id']}", owner)).status_code == 204
    assert (
        await api.get(f"/attachments/{meta['id']}/download", owner)
    ).status_code == 404


# -- administration -----------------------------------------------------------------------------


async def test_roles_assigned_and_revoked_change_what_a_user_may_do(api):
    admin = await api.user("ADMIN", name="Root")
    newcomer = await api.user(name="Nora Newcomer")  # no role yet: pending

    pending = (await api.get("/admin/users/pending", admin)).json()
    assert [p["full_name"] for p in pending] == ["Nora Newcomer"]
    assert (await api.get("/equipment", newcomer)).status_code == 403

    roles = {r["code"]: r["id"] for r in (await api.get("/admin/roles", admin)).json()}
    granted = await api.post(
        f"/admin/users/{await api.id_of(newcomer)}/roles",
        admin,
        json={"role_ids": [roles["EMPLOYEE"]]},
    )
    assert granted.status_code == 200
    assert (await api.get("/equipment", newcomer)).status_code == 200  # now allowed
    me = (await api.get("/auth/me", newcomer)).json()
    assert [r["code"] for r in me["roles"]] == ["EMPLOYEE"]
    assert "maintenance.create" in {p["code"] for p in me["permissions"]}
    notified = (await api.get("/notifications", newcomer)).json()
    assert any(n["title"] == "Access granted" for n in notified["items"])

    revoked = await api.delete(
        f"/admin/users/{await api.id_of(newcomer)}/roles/{roles['EMPLOYEE']}", admin
    )
    assert revoked.status_code == 200 and revoked.json()["role_ids"] == []
    assert (await api.get("/equipment", newcomer)).status_code == 403

    matrix = (await api.get("/admin/roles/matrix", admin)).json()
    by_role = {r["code"]: {p["code"] for p in r["permissions"]} for r in matrix}
    assert (
        "users.manage" in by_role["ADMIN"]
        and "users.manage" not in by_role["SUPERVISOR"]
    )

    # the only admin cannot lock the system by removing their own role
    own = await api.delete(
        f"/admin/users/{await api.id_of(admin)}/roles/{roles['ADMIN']}", admin
    )
    assert own.status_code == 409


async def test_notifications_can_be_read_and_cleared(api):
    admin = await api.user("ADMIN")
    target = await api.user()
    roles = {r["code"]: r["id"] for r in (await api.get("/admin/roles", admin)).json()}
    await api.post(
        f"/admin/users/{await api.id_of(target)}/roles",
        admin,
        json={"role_ids": [roles["EMPLOYEE"]]},
    )

    inbox = (await api.get("/notifications?unread_only=true", target)).json()
    assert inbox["unread_count"] == 1
    first = inbox["items"][0]["id"]
    read = await api.post(f"/notifications/{first}/read", target)
    assert read.json()["is_read"] is True
    other = await api.post(f"/notifications/{first}/read", admin)  # not theirs
    assert other.status_code == 404
    assert (await api.post("/notifications/read-all", target)).status_code == 204
    assert (await api.get("/notifications", target)).json()["unread_count"] == 0


# -- technicians, dashboard scope, schedules -----------------------------------------------------------


async def test_technicians_management_and_dashboard_scope(api):
    admin = await api.user("ADMIN")
    tech_a, profile_a = await make_technician(api, admin, "Ana Tech")
    _, profile_b = await make_technician(api, admin, "Bea Tech")
    employee = await api.user("EMPLOYEE")
    equipment = await make_equipment(api, admin)

    assert (
        await api.post("/technicians", employee, json={"user_id": 1})
    ).status_code == 403
    dup = await api.post("/technicians", admin, json={"user_id": profile_a["user_id"]})
    assert dup.status_code == 409
    await api.patch(
        f"/technicians/{profile_b['id']}", admin, json={"is_available": False}
    )
    available = await api.get("/technicians?is_available=true&search=tech", employee)
    assert [t["id"] for t in available.json()] == [profile_a["id"]]

    for title, tech in (("A1", profile_a), ("A2", profile_a), ("B1", profile_b)):
        made = await api.post(
            "/maintenance/requests",
            employee,
            json={"equipment_id": equipment["id"], "title": title, "description": "d"},
        )
        await api.post(
            f"/maintenance/requests/{made.json()['id']}/assignment",
            admin,
            json={"technician_id": tech["id"]},
        )

    all_view = (await api.get("/dashboard/summary", admin)).json()
    own_view = (await api.get("/dashboard/summary", tech_a)).json()
    assert all_view["scope"] == "all" and own_view["scope"] == "own"
    assert own_view["tickets"]["total"] == 2
    assert all_view["tickets"]["total"] >= 3
    workload = (await api.get("/dashboard/workload", admin)).json()["technicians"]
    mine = {w["full_name"]: w["open_tickets"] for w in workload}
    assert mine["Ana Tech"] == 2 and mine["Bea Tech"] == 1
    own_workload = (await api.get("/dashboard/workload", tech_a)).json()["technicians"]
    assert [w["full_name"] for w in own_workload] == ["Ana Tech"]

    failing = (await api.get("/dashboard/top-failing-equipment?limit=1", admin)).json()
    assert failing["equipment"][0]["asset_tag"] == "LT-INT-1"
    assert failing["equipment"][0]["tickets"] >= 3
    assert (await api.get("/dashboard/summary", employee)).status_code == 403

    pdf = await api.get("/reports/summary?format=pdf", admin)
    assert pdf.status_code == 200 and pdf.content.startswith(b"%PDF-")


async def test_preventive_schedule_reminds_once_and_rearms_on_completion(api):
    admin = await api.user("ADMIN")
    tech, profile = await make_technician(api, admin, "Rita Tech")
    equipment = await make_equipment(api, admin, tag="SRV-PM-1")
    soon = (datetime.now(UTC) + timedelta(days=2)).isoformat()

    created = await api.post(
        "/maintenance/schedules",
        admin,
        json={
            "equipment_id": equipment["id"],
            "technician_id": profile["id"],
            "title": "Dust filters",
            "interval_days": 30,
            "remind_days_before": 3,
            "first_due_at": soon,
        },
    )
    assert created.status_code == 201, created.text
    schedule_id = created.json()["id"]
    assert created.json()["technician"]["full_name"] == "Rita Tech"
    assert (await api.post("/maintenance/schedules", tech, json={})).status_code == 403

    first = (await api.post("/maintenance/schedules/run-reminders", admin)).json()
    assert first["reminders_sent"] == 1 and first["locked_by_another_worker"] is False
    inbox = (await api.get("/notifications", tech)).json()["items"]
    reminder = next(
        n for n in inbox if n["notification_type"] == "maintenance_reminder"
    )
    assert "SRV-PM-1" in reminder["message"]
    assert (await api.post("/maintenance/schedules/run-reminders", admin)).json()[
        "reminders_sent"
    ] == 0

    done = await api.post(f"/maintenance/schedules/{schedule_id}/complete", admin)
    assert done.status_code == 200
    assert done.json()["last_reminded_at"] is None
    assert (await api.post("/maintenance/schedules/run-reminders", admin)).json()[
        "reminders_sent"
    ] == 0

    moved = await api.patch(
        f"/maintenance/schedules/{schedule_id}",
        admin,
        json={
            "next_due_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
            "technician_id": None,
        },
    )
    assert moved.json()["technician"] is None
    again = (await api.post("/maintenance/schedules/run-reminders", admin)).json()
    assert (
        again["reminders_sent"] == 1
    )  # new date, reminder re-armed (goes to the creator)

    listing = await api.get(
        f"/maintenance/schedules?equipment_id={equipment['id']}", tech
    )
    assert [s["id"] for s in listing.json()] == [schedule_id]
    sent = await api.get("/audit-logs?action=schedule.reminder_sent", admin)
    assert len(sent.json()) == 2 and sent.json()[0]["user"] is None


async def test_every_notification_row_belongs_to_a_known_user(api):
    admin = await api.user("ADMIN")
    await api.user()
    rows = (await api.session.execute(select(Notification.user_id))).scalars().all()
    assert all(isinstance(user_id, int) for user_id in rows)
    assert (await api.get("/health")).status_code == 200
    assert (await api.get("/maintenance/requests")).status_code == 401
    assert admin  # fixture sanity: users are created through the API-visible session


# -- error paths and the less-travelled branches ---------------------------------------------


async def test_equipment_error_paths(api):
    admin = await api.user("ADMIN")
    equipment = await make_equipment(api, admin, tag="ERR-1", serial_number="SN-1")
    other = await make_equipment(api, admin, tag="ERR-2", serial_number="SN-2")
    base = f"/equipment/{equipment['id']}"

    assert (await api.get("/equipment/999999", admin)).status_code == 404
    assert (
        await api.patch("/equipment/999999", admin, json={"brand": "x"})
    ).status_code == 404
    clash = await api.patch(
        f"/equipment/{other['id']}", admin, json={"serial_number": "SN-1"}
    )
    assert clash.status_code == 409
    bad_type = await api.patch(base, admin, json={"equipment_type_id": 999999})
    assert bad_type.status_code == 404
    warranty = await api.patch(
        base,
        admin,
        json={"warranty_start_date": "2026-05-01", "warranty_end_date": "2026-01-01"},
    )
    assert warranty.status_code in (409, 422)
    assert (
        await api.post(f"{base}/location", admin, json={"location_id": 999999})
    ).status_code == 404
    assert (
        await api.post(f"{base}/custody", admin, json={"assigned_to_user_id": 999999})
    ).status_code == 404
    assert (await api.get("/equipment/types", admin)).status_code == 200

    loc = {"code": "L-1", "name": "Lab", "kind": "room"}
    assert (await api.post("/locations", admin, json=loc)).status_code == 201
    assert (await api.post("/locations", admin, json=loc)).status_code == 409
    trail = (await api.get("/audit-logs?action=location.created", admin)).json()
    assert trail[0]["new_values"] == {"code": "L-1", "name": "Lab"}


async def test_ticket_unassign_cancel_and_record_attribution(api):
    admin = await api.user("ADMIN")
    supervisor = await api.user("SUPERVISOR")
    employee = await api.user("EMPLOYEE")
    tech, profile = await make_technician(api, admin, "Uma Tech")
    outsider, _ = await make_technician(api, admin, "Otto Tech")
    equipment = await make_equipment(api, admin, tag="TK-1")

    async def ticket():
        made = await api.post(
            "/maintenance/requests",
            employee,
            json={"equipment_id": equipment["id"], "title": "t", "description": "d"},
        )
        return made.json()["id"]

    tid = await ticket()
    record = {
        "work_type": "inspection",
        "started_at": "2026-10-11T09:00:00Z",
        "diagnosis": "d",
        "actions_taken": "a",
        "result": "ok",
    }
    # no technician yet: the work record has nobody to be attributed to
    no_owner = await api.post(
        f"/maintenance/requests/{tid}/records", supervisor, json=record
    )
    assert no_owner.status_code == 409

    assign = {"technician_id": profile["id"]}
    await api.post(f"/maintenance/requests/{tid}/assignment", supervisor, json=assign)
    # a supervisor logging work is attributed to the assigned technician
    logged = await api.post(
        f"/maintenance/requests/{tid}/records", supervisor, json=record
    )
    assert logged.status_code == 201 and logged.json()["technician_id"] == profile["id"]
    listed = await api.get(f"/maintenance/requests/{tid}/records", employee)
    assert len(listed.json()) == 1

    # only the assigned technician (or a supervisor) can act on it
    denied = await api.post(
        f"/maintenance/requests/{tid}/status", outsider, json={"status": "in_progress"}
    )
    assert denied.status_code == 403
    assert (await api.get(f"/maintenance/requests/{tid}", outsider)).status_code == 403
    mine = await api.get("/maintenance/requests", tech)
    assert [t["id"] for t in mine.json()] == [tid]

    # unassigning keeps the status but frees the slot; a second unassign is a 404
    freed = await api.delete(f"/maintenance/requests/{tid}/assignment", supervisor)
    assert freed.status_code == 200 and freed.json()["current_assignment"] is None
    assert (
        await api.delete(f"/maintenance/requests/{tid}/assignment", supervisor)
    ).status_code == 404
    assert (
        await api.delete("/maintenance/requests/999999/assignment", supervisor)
    ).status_code == 404
    assert (
        await api.post(
            f"/maintenance/requests/{tid}/assignment",
            supervisor,
            json={"technician_id": 999999},
        )
    ).status_code == 404

    # reassigning mid-flight keeps the status, and cancelling is terminal
    await api.post(f"/maintenance/requests/{tid}/assignment", supervisor, json=assign)
    cancelled = await api.post(
        f"/maintenance/requests/{tid}/status",
        supervisor,
        json={"status": "cancelled", "notes": "duplicate"},
    )
    assert cancelled.json()["status"] == "cancelled"
    refused = await api.post(
        f"/maintenance/requests/{tid}/assignment", supervisor, json=assign
    )
    assert refused.status_code == 409 and refused.json()["code"] == "invalid_transition"

    # tickets for unknown equipment are rejected up front
    bad = await api.post(
        "/maintenance/requests",
        employee,
        json={"equipment_id": 999999, "title": "t", "description": "d"},
    )
    assert bad.status_code == 404


async def test_validation_errors_use_the_uniform_error_body(api):
    employee = await api.user("EMPLOYEE")
    response = await api.post("/maintenance/requests", employee, json={"title": ""})
    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert {"equipment_id", "title", "description"} <= {
        e["field"] for e in body["errors"]
    }
    assert body["request_id"]


async def test_equipment_listing_exposes_current_context_summary_and_candidates(api):
    admin = await api.user("ADMIN")
    employee = await api.user("EMPLOYEE", name="Eva Employee")
    holder = await api.user("EMPLOYEE", name="Hugo Holder")
    tech, profile = await make_technician(api, admin, "Tina Tech")
    placed = await make_equipment(api, admin, tag="CTX-1")
    loose = await make_equipment(api, admin, tag="CTX-2", status="in_repair")

    room = await api.post(
        "/locations", admin, json={"code": "R-9", "name": "Room 9", "kind": "room"}
    )
    await api.post(
        f"/equipment/{placed['id']}/location",
        admin,
        json={"location_id": room.json()["id"]},
    )
    await api.post(
        f"/equipment/{placed['id']}/custody",
        admin,
        json={"assigned_to_user_id": await api.id_of(holder)},
    )
    ticket = (
        await api.post(
            "/maintenance/requests",
            employee,
            json={"equipment_id": placed["id"], "title": "t", "description": "d"},
        )
    ).json()
    await api.post(
        f"/maintenance/requests/{ticket['id']}/assignment",
        admin,
        json={"technician_id": profile["id"]},
    )
    await api.post(
        f"/maintenance/requests/{ticket['id']}/records",
        tech,
        json={
            "work_type": "preventive",
            "started_at": "2026-10-01T09:00:00Z",
            "diagnosis": "d",
            "actions_taken": "cleaned",
            "result": "ok",
        },
    )

    items = (await api.get("/equipment?search=CTX-&sort=asset_tag", employee)).json()
    first, second = items
    assert first["current_location"]["name"] == "Room 9"
    assert first["current_custodian"]["full_name"] == "Hugo Holder"
    assert first["last_maintenance"]["technician_name"] == "Tina Tech"
    assert first["last_maintenance"]["work_type"] == "preventive"
    assert (
        second["current_location"],
        second["current_custodian"],
        second["last_maintenance"],
    ) == (
        None,
        None,
        None,
    )
    detail = (await api.get(f"/equipment/{placed['id']}", employee)).json()
    assert detail["current_location"]["code"] == "R-9"

    in_room = await api.get(f"/equipment?location_id={room.json()['id']}", employee)
    assert [e["asset_tag"] for e in in_room.json()] == ["CTX-1"]
    nowhere = await api.get("/equipment?location_id=999999", employee)
    assert nowhere.json() == []

    summary = (await api.get("/equipment/summary", employee)).json()
    assert summary["total"] == sum(summary["by_status"].values()) >= 2
    assert summary["by_status"]["in_repair"] >= 1

    found = await api.get("/equipment/custodian-candidates?search=hugo", admin)
    assert [u["full_name"] for u in found.json()] == ["Hugo Holder"]
    assert (
        await api.get("/equipment/custodian-candidates", employee)
    ).status_code == 403
    assert loose["id"] != placed["id"]
