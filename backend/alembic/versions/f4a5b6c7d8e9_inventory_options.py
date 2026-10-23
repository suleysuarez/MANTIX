"""inventory options: user-extensible categories, units, locations and suppliers

* `inventory_options` holds the values of the four item drop-downs; `key` (the folded
  label) is unique per kind, so a value cannot be added twice with another case.
* The fixed category list (`category_allowed`) is dropped: categories are now rows of the
  table. The five built-in ones are seeded, and so is every unit, location and supplier
  already in use (collapsed whitespace, one canonical spelling per folded value).
* SKUs are stored in capitals (`sku_upper_case`), which makes the existing unique index
  case-insensitive. Existing SKUs are upper-cased first; a collision fails the migration
  and has to be resolved by hand.

Text normalisation of names, suppliers and locations is NOT done here: it is a reviewable
script (`scripts/normalize_inventory.py`) that shows what it would change before writing.

Revision ID: f4a5b6c7d8e9
Revises: e3b4c5d6e7f8
Create Date: 2026-10-15 12:00:00.000000

"""

import re
import unicodedata
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "f4a5b6c7d8e9"
down_revision: Union[str, None] = "e3b4c5d6e7f8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

BUILT_IN = [
    ("spare_part", "Repuesto"),
    ("consumable", "Consumible"),
    ("accessory", "Accesorio"),
    ("tool", "Herramienta"),
    ("other", "Otro"),
]


def _collapse(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _fold(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", _collapse(value))
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def upgrade() -> None:
    op.create_table(
        "inventory_options",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("kind", sa.String(length=12), nullable=False),
        sa.Column("value", sa.String(length=150), nullable=False),
        sa.Column("label", sa.String(length=150), nullable=False),
        sa.Column("key", sa.String(length=150), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "kind IN ('category', 'unit', 'location', 'supplier')",
            name=op.f("ck_inventory_options_kind_allowed"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_inventory_options")),
        sa.UniqueConstraint("kind", "key", name="uq_inventory_options_kind_key"),
    )

    bind = op.get_bind()
    options = sa.table(
        "inventory_options",
        sa.column("kind", sa.String),
        sa.column("value", sa.String),
        sa.column("label", sa.String),
        sa.column("key", sa.String),
    )
    rows = [
        {"kind": "category", "value": code, "label": label, "key": _fold(label)}
        for code, label in BUILT_IN
    ]
    # Categories already in use that are not built in keep working as options.
    known = {code for code, _ in BUILT_IN}
    for (code,) in bind.execute(
        sa.text("SELECT DISTINCT category FROM inventory_items")
    ):
        if code and code not in known:
            rows.append(
                {
                    "kind": "category",
                    "value": code,
                    "label": code.replace("_", " ").title(),
                    "key": _fold(code.replace("_", " ")),
                }
            )
    for kind, column in (
        ("unit", "unit"),
        ("location", "location"),
        ("supplier", "supplier"),
    ):
        seen: dict[str, str] = {}
        for (value,) in bind.execute(
            sa.text(f"SELECT {column} FROM inventory_items WHERE {column} IS NOT NULL")
        ):
            text = _collapse(value)
            if text:
                seen.setdefault(_fold(text), text)
        rows += [
            {"kind": kind, "value": text, "label": text, "key": key}
            for key, text in seen.items()
        ]
    op.bulk_insert(options, rows)

    op.execute("UPDATE inventory_items SET sku = upper(sku) WHERE sku <> upper(sku)")
    op.drop_constraint(
        op.f("ck_inventory_items_category_allowed"), "inventory_items", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_inventory_items_sku_upper_case"), "inventory_items", "sku = upper(sku)"
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_inventory_items_sku_upper_case"), "inventory_items", type_="check"
    )
    # Items in a category added after this migration go back to «other» so the old
    # fixed list holds again.
    op.execute(
        "UPDATE inventory_items SET category = 'other' "
        "WHERE category NOT IN ('spare_part', 'consumable', 'accessory', 'tool', 'other')"
    )
    op.create_check_constraint(
        op.f("ck_inventory_items_category_allowed"),
        "inventory_items",
        "category IN ('spare_part', 'consumable', 'accessory', 'tool', 'other')",
    )
    op.drop_table("inventory_options")
