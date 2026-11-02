"""Load demo data for every screen (users per role, equipment, tickets, costs, inventory, ...).

Manual, never run on its own:

    python -m scripts.seed_demo --yes            # add the demo data
    python -m scripts.seed_demo --reset --yes    # remove it first, then add it again
    python -m scripts.seed_demo --remove --yes   # only remove it

What it creates, so the dashboard, reports and every list have something real to show:

* people of every role (administrator, supervisors, technicians, requesters, an auditor),
* locations, ~36 pieces of equipment (costs, warranties, custody, location history),
* ~90 tickets over the last year with their whole history, assignments, work records and costs,
* an inventory of ~24 items with a year of movements (some consumed by tickets, some low or out),
* maintenance plans with completed runs, audit trail, recent exports and notifications.

Everything carries a `DEMO` marker (ticket numbers `DEMO-T-*`, asset tags `DEMO-*`, SKUs
`DEMO-INV-*`, locations `DEMO-*`, users `*@demo.mantix.co`), so removing it never touches
real records. It writes to whatever `DATABASE_URL` points at: the target host is printed and
nothing happens without `--yes`. Needs the roles, priorities, categories and equipment types
created by the migrations. The demo people have no sign-in account: they fill lists and metrics
(sign in with your own accounts to try each role).
"""

import argparse
import asyncio
import random
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from urllib.parse import urlparse

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.text import fold
from app.db import session as db
from app.models.audit import AuditLog
from app.models.auth import Role, User, UserRole
from app.models.equipment import (
    Equipment,
    EquipmentCustodyHistory,
    EquipmentLocationHistory,
    EquipmentStatusHistory,
    EquipmentType,
    Location,
)
from app.models.inventory import InventoryItem, InventoryMovement, InventoryOption
from app.models.maintenance import (
    MaintenanceRecord,
    MaintenanceRequest,
    TicketAssignment,
    TicketStatusHistory,
)
from app.models.notification import Notification
from app.models.priority import Priority
from app.models.report_run import ReportRun
from app.models.schedule import MaintenanceSchedule, ScheduleRun
from app.models.technician import Technician

TICKET_PREFIX = "DEMO-T-"
ASSET_PREFIX = "DEMO-"
SKU_PREFIX = "DEMO-INV-"
LOCATION_PREFIX = "DEMO-"
EMAIL_DOMAIN = "@demo.mantix.co"
TICKET_COUNT = 90
SEED = 20261013

_TITLES = {
    "network": ("Sin conexión de red", "Wi-Fi intermitente", "No obtiene dirección IP"),
    "peripherals": (
        "Teclado con teclas fallando",
        "Mouse no responde",
        "Monitor sin señal",
    ),
    "software": (
        "Lentitud al iniciar sesión",
        "Error al abrir el sistema",
        "Actualización fallida",
    ),
    "access": ("No puede iniciar sesión", "Cuenta bloqueada", "Permisos de carpeta"),
    "other": (
        "No enciende",
        "Ruido en el ventilador",
        "Batería no carga",
        "Error al imprimir",
    ),
}
_TECHNICIANS = (
    ("Ana Demo", "Redes"),
    ("Luis Demo", "Hardware"),
    ("Marta Demo", "Software"),
)
_REQUESTERS = (
    "Carlos Pérez",
    "Laura Gómez",
    "Jorge Ramírez",
    "Sofía Torres",
    "Andrés Molina",
    "Paula Rojas",
)
_SUPERVISORS = ("Valeria Supervisora", "Mateo Supervisor")
_LOCATIONS = (
    ("DEMO-OFI-1", "Oficina principal", "office"),
    ("DEMO-OFI-2", "Oficina sur", "office"),
    ("DEMO-SRV", "Sala de servidores", "room"),
    ("DEMO-BOD", "Bodega de TI", "warehouse"),
    ("DEMO-REC", "Recepción", "office"),
)
#: type code -> (brand/model pairs, cost range, how many pieces)
_EQUIPMENT_PLAN = {
    "LAPTOP": (
        (("Dell", "Latitude 5420"), ("HP", "ProBook 450"), ("Lenovo", "ThinkPad E14")),
        (1800, 3400),
        12,
    ),
    "DESKTOP": ((("Dell", "OptiPlex 3080"), ("HP", "ProDesk 400")), (1400, 2600), 6),
    "MONITOR": (
        (("LG", "24MK600"), ("Samsung", "S24R350"), ("Dell", "P2422H")),
        (400, 900),
        6,
    ),
    "PRINTER": ((("HP", "LaserJet M404"), ("Epson", "L3250")), (600, 1800), 4),
    "NETWORK_EQUIPMENT": (
        (("Cisco", "SG350"), ("TP-Link", "TL-SG1024")),
        (500, 2200),
        4,
    ),
    "SERVER": ((("Dell", "PowerEdge T150"), ("HP", "ProLiant ML30")), (6500, 9800), 2),
    "MOBILE_DEVICE": (
        (("Samsung", "Galaxy A54"), ("Apple", "iPhone 12")),
        (1200, 2800),
        2,
    ),
}
_ITEMS = (
    # sku suffix, name, category, unit, cost, min, max, supplier
    ("001", "Memoria RAM DDR4 8 GB", "spare_part", "unidad", 95, 4, 20, "Tecnomega"),
    ("002", "Disco SSD 480 GB", "spare_part", "unidad", 140, 4, 16, "Tecnomega"),
    (
        "003",
        "Batería de portátil universal",
        "spare_part",
        "unidad",
        120,
        3,
        12,
        "Compuparts",
    ),
    ("004", "Fuente de poder 500 W", "spare_part", "unidad", 110, 2, 8, "Compuparts"),
    ("005", "Ventilador de CPU", "spare_part", "unidad", 35, 3, 12, "Compuparts"),
    (
        "006",
        'Pantalla portátil 15.6"',
        "spare_part",
        "unidad",
        310,
        1,
        5,
        "Pantallas SAS",
    ),
    ("007", "Teclado USB", "accessory", "unidad", 28, 5, 25, "Office Depot"),
    ("008", "Mouse óptico USB", "accessory", "unidad", 15, 5, 30, "Office Depot"),
    ("009", "Cargador portátil 65 W", "accessory", "unidad", 55, 3, 15, "Compuparts"),
    ("010", "Cable HDMI 2 m", "accessory", "unidad", 12, 6, 30, "Office Depot"),
    (
        "011",
        "Cable de red Cat6",
        "consumable",
        "metro",
        1.2,
        100,
        500,
        "Redes y Cables",
    ),
    ("012", "Conectores RJ45", "consumable", "caja", 18, 4, 20, "Redes y Cables"),
    (
        "013",
        "Tóner HP 58A negro",
        "consumable",
        "unidad",
        135,
        3,
        12,
        "Suministros del Norte",
    ),
    (
        "014",
        "Tinta Epson 544 negra",
        "consumable",
        "unidad",
        22,
        6,
        30,
        "Suministros del Norte",
    ),
    ("015", "Pasta térmica", "consumable", "unidad", 9, 5, 25, "Compuparts"),
    (
        "016",
        "Alcohol isopropílico 1 L",
        "consumable",
        "unidad",
        14,
        4,
        16,
        "Suministros del Norte",
    ),
    (
        "017",
        "Paños de limpieza",
        "consumable",
        "caja",
        8,
        5,
        20,
        "Suministros del Norte",
    ),
    (
        "018",
        "Aire comprimido",
        "consumable",
        "unidad",
        11,
        4,
        18,
        "Suministros del Norte",
    ),
    (
        "019",
        "Juego de destornilladores",
        "tool",
        "unidad",
        45,
        1,
        4,
        "Ferretería Central",
    ),
    ("020", "Pulsera antiestática", "tool", "unidad", 10, 2, 8, "Ferretería Central"),
    ("021", "Probador de cable de red", "tool", "unidad", 38, 1, 3, "Redes y Cables"),
    ("022", "Switch 8 puertos", "spare_part", "unidad", 85, 1, 5, "Redes y Cables"),
    ("023", "Adaptador USB-C a HDMI", "accessory", "unidad", 32, 3, 12, "Office Depot"),
    (
        "024",
        "Etiquetas de inventario",
        "consumable",
        "caja",
        6,
        3,
        10,
        "Suministros del Norte",
    ),
)
_WORK_RESULTS = (
    "Reparado",
    "Componente reemplazado",
    "Configuración corregida",
    "Sin falla encontrada",
)
_NOTIFICATIONS = (
    (
        "Tu solicitud avanzó",
        "Un técnico ya trabaja en tu solicitud.",
        "maintenance_status",
    ),
    (
        "Ticket resuelto",
        "Tu equipo fue reparado: revisa y confirma.",
        "maintenance_status",
    ),
    (
        "Nuevo ticket asignado",
        "Se te asignó un ticket de mantenimiento.",
        "ticket_assigned",
    ),
)


@dataclass
class Plan:
    """Rows collected while building the data, flushed in dependency order."""

    movements: list[
        tuple[
            datetime,
            InventoryItem,
            str,
            int,
            Decimal | None,
            str,
            MaintenanceRecord | None,
            MaintenanceRequest | None,
            int | None,
        ]
    ] = field(default_factory=list)


def _d(value: float) -> Decimal:
    return Decimal(f"{value:.2f}")


def _history(
    request: MaintenanceRequest, steps: list[tuple[str, datetime]], actor: int | None
) -> list[TicketStatusHistory]:
    rows, previous = [], None
    for status, at in steps:
        rows.append(
            TicketStatusHistory(
                request_id=request.id,
                from_status=previous,
                to_status=status,
                changed_at=at,
                changed_by_user_id=actor,
            )
        )
        previous = status
    return rows


async def remove_demo(session: AsyncSession) -> None:
    demo_users = select(User.id).where(User.email.like(f"%{EMAIL_DOMAIN}"))
    demo_equipment = select(Equipment.id).where(
        Equipment.asset_tag.like(f"{ASSET_PREFIX}%")
    )
    demo_items = select(InventoryItem.id).where(
        InventoryItem.sku.like(f"{SKU_PREFIX}%")
    )
    await session.execute(delete(ReportRun).where(ReportRun.user_id.in_(demo_users)))
    await session.execute(delete(AuditLog).where(AuditLog.user_id.in_(demo_users)))
    await session.execute(
        delete(InventoryMovement).where(InventoryMovement.item_id.in_(demo_items))
    )
    await session.execute(
        delete(InventoryItem).where(InventoryItem.sku.like(f"{SKU_PREFIX}%"))
    )
    await session.execute(
        delete(InventoryOption).where(
            InventoryOption.kind == "supplier",
            InventoryOption.value.in_({row[7] for row in _ITEMS}),
        )
    )
    await session.execute(
        delete(MaintenanceRecord).where(
            MaintenanceRecord.equipment_id.in_(demo_equipment)
        )
    )
    await session.execute(
        delete(MaintenanceRequest).where(
            MaintenanceRequest.ticket_number.like(f"{TICKET_PREFIX}%")
        )
    )
    await session.execute(
        delete(MaintenanceSchedule).where(
            MaintenanceSchedule.equipment_id.in_(demo_equipment)
        )
    )
    await session.execute(
        delete(Equipment).where(Equipment.asset_tag.like(f"{ASSET_PREFIX}%"))
    )
    await session.execute(
        delete(Location).where(Location.code.like(f"{LOCATION_PREFIX}%"))
    )
    await session.execute(delete(User).where(User.id.in_(demo_users)))
    await session.execute(delete(EquipmentType).where(EquipmentType.code == "DEMO"))


async def _people(
    session: AsyncSession, rng: random.Random, now: datetime
) -> dict[str, list[User]]:
    roles = {r.code: r for r in (await session.execute(select(Role))).scalars().all()}
    missing = {"ADMIN", "SUPERVISOR", "TECHNICIAN", "EMPLOYEE"} - roles.keys()
    if missing:
        raise SystemExit(f"Missing roles {sorted(missing)}: run the migrations first.")

    def person(
        email: str, name: str, code: str, active: bool = True
    ) -> tuple[User, str]:
        user = User(
            email=f"{email}{EMAIL_DOMAIN}",
            full_name=name,
            is_active=active,
            last_login_at=now - timedelta(hours=rng.uniform(1, 24 * 12))
            if active
            else None,
            created_at=now - timedelta(days=rng.randint(60, 330)),
        )
        return user, code

    made = [person("admin", "Admin Demo", "ADMIN")]
    made += [
        person(f"super{i}", name, "SUPERVISOR") for i, name in enumerate(_SUPERVISORS)
    ]
    made += [
        person(f"tech{i}", name, "TECHNICIAN")
        for i, (name, _) in enumerate(_TECHNICIANS)
    ]
    made += [
        person(f"req{i}", name, "EMPLOYEE", active=i != 5)
        for i, name in enumerate(_REQUESTERS)
    ]
    if "AUDITOR" in roles:
        made.append(person("auditor", "Auditor Demo", "AUDITOR"))
    session.add_all([user for user, _ in made])
    await session.flush()
    for user, code in made:
        session.add(UserRole(user_id=user.id, role_id=roles[code].id))
    groups: dict[str, list[User]] = {}
    for user, code in made:
        groups.setdefault(code, []).append(user)
    return groups


async def add_demo(
    session: AsyncSession, rng: random.Random, now: datetime
) -> dict[str, int]:
    priorities = {
        p.code: p for p in (await session.execute(select(Priority))).scalars().all()
    }
    missing = {"low", "medium", "high", "critical"} - priorities.keys()
    if missing:
        raise SystemExit(
            f"Missing priorities {sorted(missing)}: run the migrations first."
        )
    types = {
        t.code: t
        for t in (await session.execute(select(EquipmentType))).scalars().all()
    }
    if not set(_EQUIPMENT_PLAN) <= types.keys():
        raise SystemExit("Missing equipment types: run the migrations first.")
    from app.models.category import RequestCategory

    categories = [
        c.code
        for c in (
            await session.execute(
                select(RequestCategory).where(RequestCategory.is_active.is_(True))
            )
        )
        .scalars()
        .all()
    ]
    categories = [c for c in categories if c in _TITLES] or ["other"]

    people = await _people(session, rng, now)
    admin, supervisors = people["ADMIN"][0], people["SUPERVISOR"]
    requesters = people["EMPLOYEE"]
    tech_users = people["TECHNICIAN"]
    technicians = [
        Technician(
            user_id=user.id,
            specialization=spec,
            is_available=i != 2,
            hourly_rate=_d(rng.choice([28, 35, 42])),
        )
        for i, (user, (_, spec)) in enumerate(
            zip(tech_users, _TECHNICIANS, strict=True)
        )
    ]
    locations = [
        Location(code=code, name=name, kind=kind, is_active=True)
        for code, name, kind in _LOCATIONS
    ]
    session.add_all([*technicians, *locations])
    await session.flush()

    # -- equipment ---------------------------------------------------------------------
    equipment: list[Equipment] = []
    statuses = (
        ["assigned"] * 22
        + ["in_storage"] * 6
        + ["in_repair"] * 3
        + ["retired"] * 2
        + ["lost", "disposed"]
    )
    rng.shuffle(statuses)
    n = 0
    for code, (models, (low, high), count) in _EQUIPMENT_PLAN.items():
        for _ in range(count):
            brand, model = rng.choice(models)
            bought = now.date() - timedelta(days=rng.randint(60, 4 * 365))
            warranty_end = bought + timedelta(days=rng.choice([365, 730, 1095]))
            if n % 9 == 4:  # a few warranties about to expire, to feed the alerts
                warranty_end = now.date() + timedelta(days=rng.randint(5, 45))
            n += 1
            equipment.append(
                Equipment(
                    asset_tag=f"{ASSET_PREFIX}{n:03d}",
                    serial_number=f"DEMO-SN-{rng.randint(100000, 999999)}",
                    equipment_type_id=types[code].id,
                    brand=brand,
                    model=model,
                    description="Equipo de demostración",
                    status=statuses[(n - 1) % len(statuses)],
                    purchase_date=bought,
                    purchase_cost=_d(rng.uniform(low, high)),
                    warranty_start_date=bought,
                    warranty_end_date=max(warranty_end, bought),
                    created_at=datetime.combine(
                        bought, datetime.min.time(), tzinfo=UTC
                    ),
                )
            )
    session.add_all(equipment)
    await session.flush()
    for item in equipment:
        placed = item.created_at + timedelta(days=1)
        where = (
            locations[3]
            if item.status in ("in_storage", "retired", "disposed")
            else rng.choice(locations[:3] + locations[4:])
        )
        session.add(
            EquipmentStatusHistory(
                equipment_id=item.id,
                from_status=None,
                to_status="in_storage",
                changed_at=item.created_at,
                reason="Registro inicial",
            )
        )
        session.add(
            EquipmentLocationHistory(
                equipment_id=item.id, location_id=where.id, started_at=placed
            )
        )
        if item.status != "in_storage":
            session.add(
                EquipmentStatusHistory(
                    equipment_id=item.id,
                    from_status="in_storage",
                    to_status=item.status,
                    changed_at=min(placed, now - timedelta(hours=1)),
                )
            )
        if item.status in ("assigned", "in_repair"):
            session.add(
                EquipmentCustodyHistory(
                    equipment_id=item.id,
                    assigned_to_user_id=rng.choice(requesters[:5]).id,
                    assigned_at=placed,
                    assigned_by_user_id=admin.id,
                )
            )

    # -- inventory ---------------------------------------------------------------------
    start = now - timedelta(days=345)
    for value in sorted({row[7] for row in _ITEMS}):
        session.add(
            InventoryOption(kind="supplier", value=value, label=value, key=fold(value))
        )
    for value in sorted({row[3] for row in _ITEMS}):
        exists = await session.scalar(
            select(InventoryOption.id).where(
                InventoryOption.kind == "unit", InventoryOption.key == fold(value)
            )
        )
        if not exists:
            session.add(
                InventoryOption(kind="unit", value=value, label=value, key=fold(value))
            )
    items: list[InventoryItem] = []
    plan = Plan()
    for suffix, name, category, unit, cost, minimum, maximum, supplier in _ITEMS:
        item = InventoryItem(
            sku=f"{SKU_PREFIX}{suffix}",
            name=name,
            description="Ítem de demostración",
            category=category,
            unit=unit,
            unit_cost=_d(cost),
            stock=0,
            min_stock=minimum,
            max_stock=maximum,
            location="Bodega de TI",
            supplier=supplier,
            is_active=True,
            created_at=start,
        )
        items.append(item)
    session.add_all(items)
    await session.flush()
    for item in items:
        first = item.max_stock or 10
        plan.movements.append(
            (
                start + timedelta(hours=1),
                item,
                "in",
                int(first * 0.8),
                item.unit_cost,
                "Stock inicial",
                None,
                None,
                admin.id,
            )
        )
        for month in range(1, 12):  # a restock every few months for what is used often
            if rng.random() < 0.35:
                plan.movements.append(
                    (
                        start + timedelta(days=month * 29 + rng.randint(0, 5)),
                        item,
                        "in",
                        rng.randint(3, 10),
                        item.unit_cost,
                        "Reposición",
                        None,
                        None,
                        admin.id,
                    )
                )

    # -- tickets, history, work records ------------------------------------------------
    created_tickets = 0
    records: list[MaintenanceRecord] = []
    for number in range(1, TICKET_COUNT + 1):
        age_hours = (
            rng.uniform(1, 30 * 24)
            if rng.random() < 0.62
            else rng.uniform(30 * 24, 350 * 24)
        )
        created = now - timedelta(hours=age_hours)
        priority = rng.choices(
            ["low", "medium", "high", "critical"], weights=[3, 4, 3, 1]
        )[0]
        sla = priorities[priority].sla_hours or 72
        category = rng.choice(categories)
        fate = rng.random()
        if fate < 0.05:
            status = "cancelled"
        elif age_hours > 24 * 9 or fate < 0.55:
            status = rng.choices(["resolved", "closed"], weights=[1, 3])[0]
        elif fate < 0.68:
            status = "submitted"
        elif fate < 0.76:
            status = "triaged"
        else:
            status = rng.choice(["assigned", "in_progress", "waiting"])

        resolved_at = None
        if status in ("resolved", "closed"):
            resolved_at = min(
                created + timedelta(hours=sla * rng.choice((0.3, 0.6, 0.9, 1.4, 2.5))),
                now - timedelta(minutes=5),
            )
        requester = rng.choice(requesters[:5])
        target = rng.choice(equipment)
        ticket = MaintenanceRequest(
            ticket_number=f"{TICKET_PREFIX}{number:04d}",
            equipment_id=target.id,
            requested_by_user_id=requester.id,
            title=rng.choice(_TITLES[category]),
            description="Dato de demostración: el usuario reporta el problema desde su puesto.",
            priority=priority,
            category=None if status == "submitted" else category,
            status=status,
            resolution_summary=rng.choice(_WORK_RESULTS) if resolved_at else None,
            created_at=created,
            updated_at=resolved_at or created,
            resolved_at=resolved_at,
            closed_at=(resolved_at + timedelta(hours=rng.uniform(1, 30)))
            if status == "closed" and resolved_at
            else None,
        )
        if ticket.closed_at and ticket.closed_at > now:
            ticket.closed_at = now - timedelta(minutes=1)
        session.add(ticket)
        await session.flush()

        # one step per state, spread between creation and the last milestone
        path = {
            "submitted": ["submitted"],
            "cancelled": ["submitted", "cancelled"],
            "triaged": ["submitted", "triaged"],
            "assigned": ["submitted", "triaged", "assigned"],
            "in_progress": ["submitted", "triaged", "assigned", "in_progress"],
            "waiting": ["submitted", "triaged", "assigned", "in_progress", "waiting"],
            "resolved": ["submitted", "triaged", "assigned", "in_progress", "resolved"],
            "closed": [
                "submitted",
                "triaged",
                "assigned",
                "in_progress",
                "resolved",
                "closed",
            ],
        }[status]
        if resolved_at:
            # everything before "resolved" happens between the creation and the resolution
            before = [step for step in path if step not in ("resolved", "closed")]
            span = (resolved_at - created).total_seconds()
            fractions = sorted(rng.uniform(0.02, 0.9) for _ in before[1:])
            times = [
                created,
                *[created + timedelta(seconds=span * f) for f in fractions],
                resolved_at,
            ]
            if status == "closed" and ticket.closed_at:
                times.append(ticket.closed_at)
        else:
            end = min(
                now - timedelta(minutes=2),
                created + timedelta(hours=rng.uniform(2, 60)),
            )
            span = max((end - created).total_seconds(), 60)
            fractions = sorted(rng.uniform(0.05, 1.0) for _ in path[1:])
            times = [
                created,
                *[created + timedelta(seconds=span * f) for f in fractions],
            ]
        steps = list(zip(path, times, strict=True))
        for row in _history(ticket, steps, supervisors[0].id):
            session.add(row)

        technician = None
        if "assigned" in path:
            technician = rng.choice(
                technicians[:2] if rng.random() < 0.8 else technicians
            )
            at = times[path.index("assigned")]
            session.add(
                TicketAssignment(
                    request_id=ticket.id,
                    technician_id=technician.id,
                    assigned_at=at,
                    assigned_by_user_id=supervisors[0].id,
                )
            )
        if technician and resolved_at:
            started = times[path.index("in_progress")]
            labor = _d(rng.uniform(0.5, 4) * float(technician.hourly_rate or 30))
            record = MaintenanceRecord(
                equipment_id=target.id,
                request_id=ticket.id,
                technician_id=technician.id,
                work_type=rng.choices(
                    ["corrective", "preventive", "inspection", "installation"],
                    weights=[6, 2, 2, 1],
                )[0],
                started_at=started,
                completed_at=resolved_at,
                diagnosis="Diagnóstico de demostración",
                actions_taken="Acciones de demostración realizadas por el técnico",
                result=rng.choice(_WORK_RESULTS),
                labor_cost=labor,
                parts_cost=Decimal("0.00"),
                total_cost=labor,
            )
            records.append(record)
            session.add(record)
            await session.flush()
            if rng.random() < 0.4:  # the repair used stock
                item = rng.choice(items)
                qty = rng.randint(1, 3)
                plan.movements.append(
                    (
                        resolved_at - timedelta(minutes=30),
                        item,
                        "out",
                        -qty,
                        item.unit_cost,
                        f"Consumo en {ticket.ticket_number}",
                        record,
                        ticket,
                        technician.user_id,
                    )
                )
        created_tickets += 1

    # -- apply the stock movements in time order so stock_after is always right ---------
    stock = {item.id: 0 for item in items}
    spent: dict[int, Decimal] = {}
    for at, item, kind, quantity, cost, notes, record, request, user_id in sorted(
        plan.movements, key=lambda m: m[0]
    ):
        current = stock[item.id]
        if kind == "out":
            quantity = -min(-quantity, current)
            if quantity == 0:
                continue
        after = current + quantity
        stock[item.id] = after
        session.add(
            InventoryMovement(
                item_id=item.id,
                kind=kind,
                quantity=quantity,
                stock_after=after,
                unit_cost=cost,
                notes=notes,
                record_id=record.id if record else None,
                request_id=request.id if request else None,
                created_by_user_id=user_id,
                created_at=at,
            )
        )
        if record is not None and kind == "out" and cost is not None:
            spent[record.id] = spent.get(record.id, Decimal(0)) + cost * -quantity
    # a few items end low or out of stock, and one adjustment, so the alerts have content
    for index, item in enumerate(items):
        if index % 6 == 2 and stock[item.id] > 0:  # low
            drop = max(stock[item.id] - max(item.min_stock - 1, 0), 0)
            if drop:
                stock[item.id] -= drop
                session.add(
                    InventoryMovement(
                        item_id=item.id,
                        kind="out",
                        quantity=-drop,
                        stock_after=stock[item.id],
                        unit_cost=item.unit_cost,
                        notes="Entrega a sucursal",
                        created_by_user_id=tech_users[0].id,
                        created_at=now - timedelta(days=3),
                    )
                )
        if index % 11 == 5 and stock[item.id] > 0:  # out
            drop = stock[item.id]
            stock[item.id] = 0
            session.add(
                InventoryMovement(
                    item_id=item.id,
                    kind="out",
                    quantity=-drop,
                    stock_after=0,
                    unit_cost=item.unit_cost,
                    notes="Consumo del mes",
                    created_by_user_id=tech_users[1].id,
                    created_at=now - timedelta(days=2),
                )
            )
        if index == 7 and stock[item.id] > 2:
            stock[item.id] -= 1
            session.add(
                InventoryMovement(
                    item_id=item.id,
                    kind="adjust",
                    quantity=-1,
                    stock_after=stock[item.id],
                    notes="Ajuste por conteo físico",
                    created_by_user_id=admin.id,
                    created_at=now - timedelta(days=5),
                )
            )
    for item in items:
        item.stock = stock[item.id]
        item.updated_at = now
    for record in records:
        parts = spent.get(record.id)
        if parts:
            record.parts_cost = parts.quantize(Decimal("0.01"))
            record.total_cost = (record.labor_cost or Decimal(0)) + record.parts_cost

    # -- maintenance plans with completed runs --------------------------------------------
    plans = [
        ("Limpieza interna", -9, 90),
        ("Actualización de firmware", -2, 120),
        ("Revisión de batería", 4, 90),
        ("Inspección general", 20, 180),
        ("Cambio de pasta térmica", 33, 365),
        ("Respaldo de configuración", 12, 30),
        ("Revisión de UPS", -20, 60),
        ("Limpieza de impresora", 7, 45),
    ]
    for i, (title, due_in_days, interval) in enumerate(plans):
        schedule = MaintenanceSchedule(
            equipment_id=equipment[i * 3 % len(equipment)].id,
            technician_id=technicians[i % len(technicians)].id,
            title=title,
            description="Plan de demostración",
            interval_days=interval,
            estimated_hours=_d(rng.uniform(0.5, 3)),
            remind_days_before=7,
            next_due_at=now + timedelta(days=due_in_days),
            is_active=True,
            created_by_user_id=supervisors[0].id,
            created_at=now - timedelta(days=400),
        )
        session.add(schedule)
        await session.flush()
        for run in range(1, 4):
            due = schedule.next_due_at - timedelta(days=interval * run)
            session.add(
                ScheduleRun(
                    schedule_id=schedule.id,
                    due_at=due,
                    completed_at=due + timedelta(days=rng.randint(0, 3)),
                    actual_hours=_d(rng.uniform(0.5, 3)),
                    completed_by_user_id=tech_users[i % 3].id,
                )
            )

    # -- activity: audit trail, exports, notifications --------------------------------------
    everyone = [admin, *supervisors, *tech_users, *requesters[:5]]
    for _ in range(36):
        user = rng.choice(everyone)
        session.add(
            AuditLog(
                user_id=user.id,
                action="auth.login",
                entity_type="user",
                entity_id=user.id,
                ip_address=f"203.0.113.{rng.randint(2, 60)}",
                created_at=now - timedelta(hours=rng.uniform(1, 24 * 14)),
            )
        )
    for action, entity, who in (
        ("equipment.created", "equipment", admin),
        ("equipment.updated", "equipment", admin),
        ("inventory.item_created", "inventory_item", supervisors[0]),
        ("maintenance.status_changed", "maintenance_request", tech_users[0]),
        ("user.updated", "user", admin),
        ("roles.replaced", "user", admin),
        ("priority.updated", "priority", admin),
    ):
        for _ in range(3):
            session.add(
                AuditLog(
                    user_id=who.id,
                    action=action,
                    entity_type=entity,
                    entity_id=rng.randint(1, 30),
                    created_at=now - timedelta(hours=rng.uniform(1, 24 * 10)),
                )
            )
    for key, fmt, rows in (
        ("tickets", "pdf", 64),
        ("equipment", "xlsx", 36),
        ("inventory_items", "xlsx", 24),
        ("summary", "pdf", 1),
        ("technicians", "pdf", 3),
        ("tickets", "xlsx", 90),
    ):
        session.add(
            ReportRun(
                report_key=key,
                export_format=fmt,
                filters={},
                row_count=rows,
                user_id=admin.id,
                created_at=now - timedelta(hours=rng.uniform(1, 24 * 9)),
            )
        )
    for user in [*requesters[:5], *tech_users]:
        for title, message, kind in rng.sample(_NOTIFICATIONS, 2):
            read = rng.random() < 0.5
            session.add(
                Notification(
                    user_id=user.id,
                    title=title,
                    message=message,
                    notification_type=kind,
                    is_read=read,
                    read_at=now - timedelta(hours=2) if read else None,
                    created_at=now - timedelta(hours=rng.uniform(1, 72)),
                )
            )

    return {
        "users": sum(len(group) for group in people.values()),
        "equipment": len(equipment),
        "locations": len(locations),
        "tickets": created_tickets,
        "work records": len(records),
        "inventory items": len(items),
        "movements": len(plan.movements),
        "schedules": len(plans),
    }


async def main(args: argparse.Namespace) -> None:
    if db.async_session_maker is None or db.engine is None:
        raise SystemExit("DATABASE_URL is not configured.")
    host = urlparse(
        str(db.engine.url.render_as_string(hide_password=True)).replace("+asyncpg", "")
    ).hostname
    print(f"Target database host: {host}")
    if not args.yes:
        raise SystemExit("Nothing done. Re-run with --yes to write to that database.")
    async with db.async_session_maker() as session, session.begin():
        if args.reset or args.remove:
            await remove_demo(session)
            print("Removed previous demo data.")
        if not args.remove:
            exists = await session.scalar(
                select(MaintenanceRequest.id)
                .where(MaintenanceRequest.ticket_number.like(f"{TICKET_PREFIX}%"))
                .limit(1)
            )
            if exists:
                raise SystemExit(
                    "Demo data already present: use --reset to replace it."
                )
            added = await add_demo(session, random.Random(SEED), datetime.now(UTC))
            print(
                "Added:", ", ".join(f"{count} {name}" for name, count in added.items())
            )
    await db.engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--yes", action="store_true", help="confirm writing to DATABASE_URL"
    )
    parser.add_argument(
        "--reset", action="store_true", help="remove demo data, then add it"
    )
    parser.add_argument("--remove", action="store_true", help="only remove demo data")
    asyncio.run(main(parser.parse_args()))
