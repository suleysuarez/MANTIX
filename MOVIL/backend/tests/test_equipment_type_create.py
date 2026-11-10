"""`POST /equipment/types`: create an equipment category."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_equipment_service
from app.core.authz import AuthContext
from app.core.exceptions import ConflictError
from app.main import app
from app.models.equipment import EquipmentType
from app.repositories.equipment import EquipmentRepository
from app.schemas.equipment import EquipmentTypeCreate
from app.services.equipment import EquipmentService, _type_code_base

ACTOR = AuthContext.for_roles(SimpleNamespace(id=7), "ADMIN")


class FakeAudit:
    def __init__(self):
        self.records: list[dict] = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeRepository:
    def __init__(
        self,
        existing: list[SimpleNamespace] | None = None,
        *,
        fail_with_integrity_error: bool = False,
    ):
        self.types = list(existing or [])
        self.fail = fail_with_integrity_error
        self.committed = False
        self.rolled_back = False

    async def find_type_by_name(self, name):
        return next((t for t in self.types if t.name.lower() == name.lower()), None)

    async def type_code_exists(self, code):
        return any(t.code == code for t in self.types)

    async def create_type(self, *, code, name):
        if self.fail:
            raise IntegrityError("duplicate", {}, None)
        item = SimpleNamespace(
            id=len(self.types) + 1, code=code, name=name, is_active=True
        )
        self.types.append(item)
        return item

    async def commit(self):
        self.committed = True

    async def rollback(self):
        self.rolled_back = True


def make_type(name: str, code: str, type_id: int = 1) -> SimpleNamespace:
    return SimpleNamespace(id=type_id, code=code, name=name, is_active=True)


def service(repository, audit=None) -> EquipmentService:
    return EquipmentService(repository, audit or FakeAudit())


# -- the name -----------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "clean"),
    [
        ("Proyector", "Proyector"),
        ("  Proyector  ", "Proyector"),
        ("Cámara   de\tseguridad\n", "Cámara de seguridad"),
        ("A" * 100, "A" * 100),
        ("ab", "ab"),
    ],
)
def test_the_name_is_trimmed_and_its_inner_spaces_collapsed(raw, clean):
    assert EquipmentTypeCreate(name=raw).name == clean


@pytest.mark.parametrize(
    "raw", ["", "   ", "\t\n", "a", "  x  ", "A" * 101, "---", " ... ", "¿?"]
)
def test_empty_too_short_too_long_or_symbols_only_names_are_rejected(raw):
    with pytest.raises(ValidationError):
        EquipmentTypeCreate(name=raw)


def test_the_code_is_derived_from_the_name():
    assert _type_code_base("Proyector") == "PROYECTOR"
    assert _type_code_base("Cámara de seguridad") == "CAMARA_DE_SEGURIDAD"
    assert _type_code_base("  Router / Switch (red)  ") == "ROUTER_SWITCH_RED"
    assert _type_code_base("電腦") == "TYPE", (
        "nothing ASCII left falls back to a neutral base"
    )
    assert len(_type_code_base("x" * 100)) <= 44, "room is left for a numeric suffix"


# -- service ------------------------------------------------------------------------------------


async def test_it_creates_the_category_audits_it_and_commits():
    repository, audit = FakeRepository(), FakeAudit()
    created = await service(repository, audit).create_type(
        EquipmentTypeCreate(name="  Cámara   de seguridad "), ACTOR
    )

    assert (created.name, created.code) == (
        "Cámara de seguridad",
        "CAMARA_DE_SEGURIDAD",
    )
    assert repository.committed is True
    assert audit.records == [
        {
            "user_id": 7,
            "action": "equipment_type.created",
            "entity_type": "equipment_type",
            "entity_id": created.id,
            "new_values": {
                "code": "CAMARA_DE_SEGURIDAD",
                "name": "Cámara de seguridad",
            },
        }
    ]


async def test_a_name_that_differs_only_in_case_is_a_409_naming_the_existing_one():
    repository, audit = FakeRepository([make_type("Laptop", "LAPTOP")]), FakeAudit()
    with pytest.raises(ConflictError) as error:
        await service(repository, audit).create_type(
            EquipmentTypeCreate(name="  LAPTOP "), ACTOR
        )

    assert error.value.code == "equipment_type_name_taken"
    assert "'Laptop'" in error.value.detail
    assert len(repository.types) == 1, "no duplicate is created"
    assert audit.records == []
    assert repository.committed is False


async def test_two_different_names_with_the_same_slug_get_different_codes():
    repository = FakeRepository([make_type("Cámara", "CAMARA")])
    first = await service(repository).create_type(
        EquipmentTypeCreate(name="Camara!"), ACTOR
    )
    second = await service(repository).create_type(
        EquipmentTypeCreate(name="CAMARA?"), ACTOR
    )

    assert first.code == "CAMARA_2"
    assert second.code == "CAMARA_3"


async def test_losing_a_race_for_the_same_name_is_the_same_409_and_rolls_back():
    repository = FakeRepository(fail_with_integrity_error=True)
    with pytest.raises(ConflictError) as error:
        await service(repository).create_type(
            EquipmentTypeCreate(name="Proyector"), ACTOR
        )

    assert error.value.code == "equipment_type_name_taken"
    assert repository.rolled_back is True


# -- route --------------------------------------------------------------------------------------


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def serve(repository: FakeRepository, audit: FakeAudit, *codes: str) -> None:
    permissions = [SimpleNamespace(code=c, name=c, is_active=True) for c in codes]
    user = SimpleNamespace(
        id=7, roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)]
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[get_equipment_service] = lambda: service(repository, audit)


def test_without_a_session_it_is_a_401(client):
    assert (
        client.post("/equipment/types", json={"name": "Proyector"}).status_code == 401
    )


def test_seeing_the_catalog_is_not_enough_it_is_a_403_and_nothing_is_created(client):
    repository, audit = FakeRepository(), FakeAudit()
    serve(repository, audit, "equipos:ver")
    response = client.post("/equipment/types", json={"name": "Proyector"})

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"
    assert repository.types == []


def test_with_the_permission_it_is_a_201_with_the_id_code_and_name(client):
    repository, audit = FakeRepository(), FakeAudit()
    serve(repository, audit, "equipos:crear")
    response = client.post("/equipment/types", json={"name": "  Proyector   HD "})

    assert response.status_code == 201
    assert response.json() == {"id": 1, "code": "PROYECTOR_HD", "name": "Proyector HD"}
    assert [record["action"] for record in audit.records] == ["equipment_type.created"]


def test_a_duplicate_with_other_casing_is_a_409_with_the_specific_code(client):
    repository, audit = FakeRepository([make_type("Laptop", "LAPTOP")]), FakeAudit()
    serve(repository, audit, "equipos:crear")
    response = client.post("/equipment/types", json={"name": "lAPTOP"})

    assert response.status_code == 409
    body = response.json()
    assert body["code"] == "equipment_type_name_taken"
    assert "Laptop" in body["detail"]
    assert set(body) >= {"detail", "code", "errors", "request_id"}
    assert len(repository.types) == 1


@pytest.mark.parametrize(
    "payload",
    [
        {"name": ""},
        {"name": "   "},
        {"name": "x"},
        {"name": "A" * 101},
        {"name": "!!!"},
        {},
        {"name": None},
        {"name": 5},
    ],
)
def test_an_invalid_name_is_a_422_that_names_the_field(client, payload):
    repository, audit = FakeRepository(), FakeAudit()
    serve(repository, audit, "equipos:crear")
    response = client.post("/equipment/types", json=payload)

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert any(error["field"].endswith("name") for error in body["errors"])
    assert repository.types == []
    assert audit.records == []


# -- repository and service together (real PostgreSQL) ------------------------------------------


async def test_the_repository_finds_names_ignoring_case_and_including_inactive_ones(
    db_session,
):
    repo = EquipmentRepository(db_session)
    db_session.add_all(
        [
            EquipmentType(code="LAPTOP", name="Laptop", is_active=True),
            EquipmentType(code="OLD", name="Equipo Antiguo", is_active=False),
            EquipmentType(code="NANDU", name="Ñandú", is_active=True),
        ]
    )
    await db_session.flush()

    assert (await repo.find_type_by_name("lAPTOP")).code == "LAPTOP"
    assert (await repo.find_type_by_name("EQUIPO ANTIGUO")).code == "OLD"
    assert (await repo.find_type_by_name("ñandú")) is not None
    assert await repo.find_type_by_name("Impresora") is None
    assert await repo.type_code_exists("LAPTOP") is True
    assert await repo.type_code_exists("PRINTER") is False


async def test_creating_through_the_service_persists_it_and_the_listing_returns_it(
    db_session,
):
    audit = FakeAudit()
    svc = EquipmentService(EquipmentRepository(db_session), audit)

    created = await svc.create_type(
        EquipmentTypeCreate(name="  Proyector   HD "), ACTOR
    )

    assert (created.name, created.code) == ("Proyector HD", "PROYECTOR_HD")
    assert [t.name for t in await svc.list_types()] == ["Proyector HD"]
    assert audit.records[0]["entity_id"] == created.id


async def test_a_duplicate_is_refused_and_no_second_row_exists(db_session):
    svc = EquipmentService(EquipmentRepository(db_session), FakeAudit())
    await svc.create_type(EquipmentTypeCreate(name="Laptop"), ACTOR)

    with pytest.raises(ConflictError) as error:
        await svc.create_type(EquipmentTypeCreate(name="  LAPTOP"), ACTOR)

    assert error.value.code == "equipment_type_name_taken"
    assert len(await svc.list_types()) == 1


async def test_the_database_constraint_is_the_last_line_of_defense(db_session):
    repo = EquipmentRepository(db_session)
    await repo.create_type(code="LAPTOP", name="Laptop")
    with pytest.raises(IntegrityError):
        await repo.create_type(code="LAPTOP_2", name="Laptop")


async def test_names_with_the_same_slug_get_numbered_codes_in_the_database(db_session):
    svc = EquipmentService(EquipmentRepository(db_session), FakeAudit())
    first = await svc.create_type(EquipmentTypeCreate(name="Cámara"), ACTOR)
    second = await svc.create_type(EquipmentTypeCreate(name="Camara!"), ACTOR)

    assert (first.code, second.code) == ("CAMARA", "CAMARA_2")
