"""User list export (PDF and Excel). Only for those who manage users (`users.manage`)."""

from collections import Counter
from typing import Any

from app.exports.base import ExportContext, ExportDefinition, Scope
from app.exports.meta import meta_items, report_code
from app.exports.model import (
    ExportColumn,
    ReportExport,
    SummaryGroup,
    SummaryLine,
)
from app.exports.tickets import describe_period
from app.repositories.export import ExportRepository
from app.schemas.export import ExportFilters

ACTIVE = "Activo"
INACTIVE = "Inactivo"
NO_ROLE = "Sin rol"
COLUMNS = (
    ExportColumn("full_name", "Usuario", width=26, total="count"),
    ExportColumn("email", "Correo", width=32),
    ExportColumn("employee_code", "Código", width=12),
    ExportColumn("roles", "Roles", width=26),
    ExportColumn("status", "Estado", width=11, align="center", pill=True),
    ExportColumn("last_login_at", "Último acceso", "datetime", width=17),
    ExportColumn("created_at", "Alta", "date", width=12),
)
PDF_DEFAULT = ("full_name", "email", "roles", "status", "last_login_at", "created_at")


def prepare(raw: dict[str, Any]) -> dict[str, Any]:
    row = dict(raw)
    row["status"] = ACTIVE if row["is_active"] else INACTIVE
    row["roles"] = row.get("roles") or NO_ROLE
    return row


def describe_filters(filters: ExportFilters, role_name: str | None = None) -> str:
    parts = []
    if filters.search:
        parts.append(f"Búsqueda: {filters.search}")
    if filters.role:
        parts.append(f"Rol: {role_name or filters.role}")
    if filters.is_active is not None:
        parts.append("Estado: " + (ACTIVE if filters.is_active else INACTIVE))
    return " · ".join(parts) or "Sin filtros"


class UsersExport(ExportDefinition):
    key = "users"
    title = "Usuarios"
    columns = COLUMNS
    pdf_default = PDF_DEFAULT
    permission = "usuarios:ver"

    async def count(
        self, repo: ExportRepository, filters: ExportFilters, scope: Scope
    ) -> int:
        return await repo.count_users(filters)

    async def rows(
        self,
        repo: ExportRepository,
        filters: ExportFilters,
        scope: Scope,
        limit: int,
    ) -> list[dict[str, Any]]:
        return await repo.export_users(filters, limit=limit)

    def build(self, rows: list[dict[str, Any]], context: ExportContext) -> ReportExport:
        data = [prepare(row) for row in rows]
        meta = meta_items(
            code=report_code("USR", context.generated_at),
            generated_by=context.generated_by,
            generated_at=context.generated_at,
            records=len(data),
            period=describe_period(context.filters),
            filters=describe_filters(context.filters),
        )
        active = sum(1 for row in data if row["is_active"])
        never = sum(1 for row in data if row["last_login_at"] is None)
        by_status = Counter(row["status"] for row in data)
        return ReportExport(
            key=self.key,
            title=self.title.upper(),
            section="Listado de usuarios",
            columns=self.columns,
            rows=data,
            sheet_name="Detalle",
            subtitle="Cuentas, roles y accesos",
            meta_left=meta[0],
            meta_right=meta[1],
            summary=[
                SummaryGroup(
                    "Por estado",
                    [SummaryLine(k, n, str(n)) for k, n in by_status.most_common()],
                    chart="pie",
                ),
                SummaryGroup(
                    "Indicadores",
                    [
                        SummaryLine(
                            "Total de usuarios",
                            len(data),
                            str(len(data)),
                            "Cuentas del reporte",
                        ),
                        SummaryLine(
                            "Activos",
                            active,
                            str(active),
                            "Pueden iniciar sesión",
                            "good",
                        ),
                        SummaryLine(
                            "Inactivos",
                            len(data) - active,
                            str(len(data) - active),
                            "Cuentas desactivadas",
                            "neutral",
                        ),
                        SummaryLine(
                            "Nunca iniciaron sesión",
                            never,
                            str(never),
                            "Registrados sin acceso",
                            "warn",
                        ),
                    ],
                    kpi=True,
                ),
            ],
        )
