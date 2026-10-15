"""One export definition per report (Strategy), sharing a template: the service counts
and loads rows, the definition turns them into a `ReportExport`, the renderers do the rest."""

from abc import ABC, abstractmethod
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from app.exports.model import ExportColumn, ReportExport
from app.repositories.export import ExportRepository
from app.schemas.export import ExportFilters


@dataclass(frozen=True, slots=True)
class Scope:
    """What the caller may see: everything, their assigned tickets, or only their own."""

    requester_id: int | None = None
    technician_id: int | None = None


@dataclass(frozen=True, slots=True)
class ExportContext:
    company: str
    legal_name: str | None
    tax_id: str | None
    generated_by: str
    generated_at: datetime
    filters: ExportFilters


class ExportDefinition(ABC):
    key: str
    title: str
    #: Columns the user can pick, in print order.
    columns: Sequence[ExportColumn]
    #: Compact set for the PDF (the page is only so wide).
    pdf_default: Sequence[str]

    @abstractmethod
    async def count(
        self, repo: ExportRepository, filters: ExportFilters, scope: Scope
    ) -> int: ...

    @abstractmethod
    async def rows(
        self, repo: ExportRepository, filters: ExportFilters, scope: Scope, limit: int
    ) -> list[dict[str, Any]]: ...

    @abstractmethod
    def build(
        self, rows: list[dict[str, Any]], context: ExportContext
    ) -> ReportExport: ...
