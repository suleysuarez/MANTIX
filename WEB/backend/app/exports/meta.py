"""The metadata block every report shows under its title: code, date, period, author, records, filters.

Laid out row by row in three columns (PDF) or as two blocks (Excel), so the order is:
`Reporte · Fecha de generación · Periodo` then `Generado por · Registros · Filtros`.
"""

from datetime import datetime

from app.exports.formatting import local
from app.exports.model import MetaItem
from app.exports.theme import DATETIME_FORMAT


def report_code(prefix: str, generated_at: datetime) -> str:
    """`TICK-20261015-1205`: the report's short name and the minute it was generated."""
    return f"{prefix.upper()}-{local(generated_at):%Y%m%d-%H%M}"


def meta_items(
    *,
    code: str,
    generated_by: str,
    generated_at: datetime,
    records: int,
    period: str = "Todo el historial",
    filters: str = "Sin filtros",
) -> tuple[list[MetaItem], list[MetaItem]]:
    """`(first row, second row)` of the metadata block. Company name, tax id and legal name are
    deliberately not part of it."""
    return (
        [
            MetaItem("Reporte", code),
            MetaItem(
                "Fecha de generación", local(generated_at).strftime(DATETIME_FORMAT)
            ),
            MetaItem("Periodo", period),
        ],
        [
            MetaItem("Generado por", generated_by),
            MetaItem("Registros", str(records)),
            MetaItem("Filtros", filters),
        ],
    )
