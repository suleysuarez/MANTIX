"""Load demo data (about 40 tickets) so the dashboard KPIs can be judged on a realistic set.

Manual, never run on its own:

    python -m scripts.seed_demo --yes            # add the demo data
    python -m scripts.seed_demo --reset --yes    # remove it first, then add it again
    python -m scripts.seed_demo --remove --yes   # only remove it

Everything it creates carries a `DEMO` marker (ticket numbers `DEMO-T-*`, asset tags
`DEMO-*`, users `*@demo.mantix.local`), so removing it never touches real records.
It writes to whatever `DATABASE_URL` points at: the target host is printed and
nothing happens without `--yes`. Needs the priorities created by the migrations.
"""

import argparse
import asyncio
import random
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import session as db
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentStatusHistory, EquipmentType
from app.models.maintenance import (
    MaintenanceRequest,
    TicketAssignment,
    TicketStatusHistory,
)
from app.models.priority import Priority
from app.models.schedule import MaintenanceSchedule
from app.models.technician import Technician

TICKET_PREFIX = "DEMO-T-"
ASSET_PREFIX = "DEMO-"
EMAIL_DOMAIN = "@demo.mantix.local"
TICKET_COUNT = 40
SEED = 20261013

#: (hours to resolve relative to the priority SLA, weight): some on time, some late.
_RESOLUTION_FACTORS = (0.3, 0.6, 0.9, 1.4, 2.5)
_TITLES = (
    "No enciende",
    "Pantalla con líneas",
    "Lentitud al iniciar sesión",
    "Sin conexión de red",
    "Ruido en el ventilador",
    "Batería no carga",
    "Teclado con teclas fallando",
    "Error al imprimir",
)
_TECHNICIANS = (
    ("Ana Demo", "Redes"),
    ("Luis Demo", "Hardware"),
    ("Marta Demo", "Software"),
)


def _status_row(
    request: MaintenanceRequest, to_status: str, at: datetime
) -> TicketStatusHistory:
    return TicketStatusHistory(
        request_id=request.id, from_status=None, to_status=to_status, changed_at=at
    )


async def remove_demo(session: AsyncSession) -> None:
    demo_users = select(User.id).where(User.email.like(f"%{EMAIL_DOMAIN}"))
    await session.execute(
        delete(MaintenanceRequest).where(
            MaintenanceRequest.ticket_number.like(f"{TICKET_PREFIX}%")
        )
    )
    await session.execute(
        delete(Equipment).where(Equipment.asset_tag.like(f"{ASSET_PREFIX}%"))
    )
    await session.execute(delete(User).where(User.id.in_(demo_users)))
    await session.execute(delete(EquipmentType).where(EquipmentType.code == "DEMO"))


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

    etype = EquipmentType(code="DEMO", name="Demo laptop", is_active=True)
    requester = User(
        email=f"requester{EMAIL_DOMAIN}", full_name="Solicitante Demo", is_active=True
    )
    tech_users = [
        User(email=f"tech{i}{EMAIL_DOMAIN}", full_name=name, is_active=True)
        for i, (name, _) in enumerate(_TECHNICIANS)
    ]
    session.add_all([etype, requester, *tech_users])
    await session.flush()
    technicians = [
        Technician(user_id=user.id, specialization=spec, is_available=i != 2)
        for i, (user, (_, spec)) in enumerate(
            zip(tech_users, _TECHNICIANS, strict=True)
        )
    ]
    statuses = ["assigned"] * 6 + ["in_repair"] * 2 + ["lost"]
    equipment = [
        Equipment(
            asset_tag=f"{ASSET_PREFIX}{i:03d}",
            equipment_type_id=etype.id,
            brand=rng.choice(["Dell", "HP", "Lenovo"]),
            model=rng.choice(["Latitude 5420", "ProBook 450", "ThinkPad E14"]),
            status=statuses[i] if i < len(statuses) else "assigned",
        )
        for i in range(12)
    ]
    session.add_all([*technicians, *equipment])
    await session.flush()
    for item in equipment:
        if item.status in ("in_repair", "lost"):
            session.add(
                EquipmentStatusHistory(
                    equipment_id=item.id,
                    from_status="assigned",
                    to_status=item.status,
                    changed_at=now - timedelta(hours=rng.randint(6, 200)),
                )
            )

    created_tickets = 0
    for n in range(1, TICKET_COUNT + 1):
        # Two thirds of the tickets fall in the last 30 days, the rest in the last year.
        age_hours = (
            rng.uniform(1, 30 * 24)
            if rng.random() < 0.67
            else rng.uniform(30 * 24, 360 * 24)
        )
        created = now - timedelta(hours=age_hours)
        code = rng.choices(["low", "medium", "high", "critical"], weights=[3, 4, 3, 1])[
            0
        ]
        sla = priorities[code].sla_hours or 72
        fate = rng.random()
        resolved_at = None
        if age_hours > 24 * 8 or fate < 0.55:
            status = rng.choice(["resolved", "closed"])
            resolved_at = created + timedelta(
                hours=sla * rng.choice(_RESOLUTION_FACTORS)
            )
            resolved_at = min(resolved_at, now - timedelta(minutes=5))
        elif fate < 0.7:
            status = "submitted"
        else:
            status = rng.choice(["assigned", "in_progress", "waiting"])

        ticket = MaintenanceRequest(
            ticket_number=f"{TICKET_PREFIX}{n:04d}",
            equipment_id=rng.choice(equipment).id,
            requested_by_user_id=requester.id,
            title=rng.choice(_TITLES),
            description="Dato de demostración",
            priority=code,
            status=status,
            created_at=created,
            updated_at=resolved_at or created,
            resolved_at=resolved_at,
            closed_at=resolved_at if status == "closed" else None,
        )
        session.add(ticket)
        await session.flush()
        session.add(_status_row(ticket, "submitted", created))
        if status != "submitted":
            assigned_at = created + timedelta(hours=rng.uniform(0.2, 6))
            session.add(
                TicketAssignment(
                    request_id=ticket.id,
                    technician_id=rng.choice(technicians).id,
                    assigned_at=min(assigned_at, resolved_at or now),
                )
            )
        created_tickets += 1

    plans = [
        ("Limpieza interna", -9),
        ("Actualización de firmware", -2),
        ("Revisión de batería", 4),
        ("Inspección general", 20),
    ]
    for i, (title, due_in_days) in enumerate(plans):
        session.add(
            MaintenanceSchedule(
                equipment_id=equipment[i].id,
                technician_id=technicians[i % len(technicians)].id,
                title=title,
                interval_days=90,
                next_due_at=now + timedelta(days=due_in_days),
                is_active=True,
            )
        )
    return {
        "tickets": created_tickets,
        "equipment": len(equipment),
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
