"""Normalise the text already stored in the inventory (reviewable; nothing is written by default).

    python -m scripts.normalize_inventory             # show what would change
    python -m scripts.normalize_inventory --apply     # write it (one transaction)

The criterion is the same one the API applies to new data:

* SKU: capitals, no spaces around it.
* Name: collapsed spaces, written as a title («cable  de RED» -> «Cable de Red»); digits and
  short acronyms are kept (SSD 512 GB).
* Supplier and location: collapsed spaces, title case, ONE spelling per value: «bodega a»,
  «BODEGA A» and «Bodega  A» all become the one registered in `inventory_options`.
* Unit: lower case.

Every changed item gets a line in the audit log (`inventory.item_normalised`) with the old
and new values. Items whose new SKU would collide with another one are reported and skipped:
they need a person to decide which one stays.
"""

import argparse
import asyncio
from collections import defaultdict
from typing import Any

from sqlalchemy import select

from app.core.text import collapse, fold, normalise_unit, title_case
from app.db import session as db
from app.models.audit import AuditLog
from app.models.inventory import InventoryItem, InventoryOption

FIELDS = ("sku", "name", "unit", "location", "supplier")


def normalised(
    item: InventoryItem, canonical: dict[tuple[str, str], str]
) -> dict[str, Any]:
    """The values the item should have; only the ones that differ from what is stored."""
    wanted: dict[str, Any] = {
        "sku": collapse(item.sku).upper(),
        "name": title_case(item.name),
        "unit": normalise_unit(item.unit),
    }
    for field in ("location", "supplier"):
        text = getattr(item, field)
        wanted[field] = title_case(text) or None if text else None
    # One spelling per value: the first one seen (or the registered option) wins.
    for field in ("unit", "location", "supplier"):
        value = wanted[field]
        if value:
            wanted[field] = canonical.setdefault((field, fold(value)), value)
    return {k: v for k, v in wanted.items() if v != getattr(item, k)}


async def main(apply: bool) -> None:
    if db.async_session_maker is None or db.engine is None:
        raise SystemExit("DATABASE_URL is not configured.")
    async with db.async_session_maker() as session, session.begin():
        options = (await session.execute(select(InventoryOption))).scalars().all()
        canonical = {(o.kind, o.key): o.value for o in options}
        items = (
            (await session.execute(select(InventoryItem).order_by(InventoryItem.id)))
            .scalars()
            .all()
        )
        taken = {i.sku for i in items}
        changes: list[tuple[InventoryItem, dict[str, Any]]] = []
        skipped: list[str] = []
        for item in items:
            diff = normalised(item, canonical)
            new_sku = diff.get("sku")
            if new_sku and new_sku in taken - {item.sku}:
                skipped.append(
                    f"#{item.id} {item.sku!r} -> {new_sku!r} (ya existe otro ítem con ese código)"
                )
                diff.pop("sku")
            if diff:
                changes.append((item, diff))
                if new_sku and "sku" in diff:
                    taken.discard(item.sku)
                    taken.add(new_sku)

        per_field: dict[str, int] = defaultdict(int)
        for item, diff in changes:
            print(f"#{item.id} {item.sku}")
            for field, new in diff.items():
                per_field[field] += 1
                print(f"    {field}: {getattr(item, field)!r} -> {new!r}")
        print(
            f"\n{len(changes)} de {len(items)} ítems cambiarían "
            f"({', '.join(f'{k}: {v}' for k, v in sorted(per_field.items())) or 'nada'})."
        )
        for line in skipped:
            print("OMITIDO:", line)

        if not apply:
            print(
                "\nNo se escribió nada. Revisa el listado y vuelve a ejecutar con --apply."
            )
            session.sync_session.rollback()
            return
        for item, diff in changes:
            old = {field: getattr(item, field) for field in diff}
            for field, value in diff.items():
                setattr(item, field, value)
            session.add(
                AuditLog(
                    user_id=None,
                    action="inventory.item_normalised",
                    entity_type="inventory_item",
                    entity_id=item.id,
                    old_values=old,
                    new_values=diff,
                )
            )
        print(
            f"\nAplicado: {len(changes)} ítems normalizados y registrados en la auditoría."
        )
    await db.engine.dispose()


def run() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write the changes (default: only show them)",
    )
    asyncio.run(main(parser.parse_args().apply))


if __name__ == "__main__":
    run()
