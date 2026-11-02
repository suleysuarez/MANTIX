"""Datasets and activity log behind the Reports screen."""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import case, func, select
from sqlalchemy.orm import aliased

from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.inventory import InventoryItem, InventoryMovement
from app.models.report_run import ReportRun
from app.models.schedule import MaintenanceSchedule, ScheduleRun
from app.models.technician import Technician
from app.repositories.report import MAX_EXPORT_ROWS, ReportRepository


@dataclass(frozen=True, slots=True)
class RunRow:
    id: int
    report_key: str
    export_format: str
    row_count: int
    filters: dict[str, Any]
    by: str | None
    at: datetime


class ReportBuilderRepository(ReportRepository):
    # -- datasets (flat dict rows, raw values; the service formats them) --------------------

    async def plan_rows(
        self,
        *,
        statuses: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        now: datetime,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        """Preventive plans with their last completion and how many times they were done."""
        plan = MaintenanceSchedule
        tech_user = aliased(User)
        status = case(
            (plan.is_active.is_(False), "inactive"),
            (plan.next_due_at < now, "overdue"),
            else_="scheduled",
        )
        done = (
            select(
                ScheduleRun.schedule_id.label("schedule_id"),
                func.count().label("runs"),
                func.max(ScheduleRun.completed_at).label("last_done"),
            )
            .group_by(ScheduleRun.schedule_id)
            .subquery("done")
        )
        query = (
            select(
                plan.title,
                Equipment.asset_tag,
                tech_user.full_name.label("technician"),
                plan.interval_days,
                plan.estimated_hours,
                plan.next_due_at,
                status.label("status"),
                done.c.last_done.label("last_done"),
                func.coalesce(done.c.runs, 0).label("runs"),
            )
            .join(Equipment, Equipment.id == plan.equipment_id)
            .outerjoin(Technician, Technician.id == plan.technician_id)
            .outerjoin(tech_user, tech_user.id == Technician.user_id)
            .outerjoin(done, done.c.schedule_id == plan.id)
            .order_by(plan.next_due_at, plan.id)
            .limit(limit)
        )
        if statuses:
            query = query.where(status.in_(statuses))
        if date_from is not None:
            query = query.where(plan.next_due_at >= date_from)
        if date_to is not None:
            query = query.where(plan.next_due_at <= date_to)
        return [dict(row._mapping) for row in await self.session.execute(query)]

    async def item_rows(
        self,
        *,
        categories: list[str] | None,
        statuses: list[str] | None,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        item = InventoryItem
        status = case(
            (item.is_active.is_(False), "inactive"),
            (item.stock == 0, "out"),
            (item.stock <= item.min_stock, "low"),
            else_="ok",
        )
        query = (
            select(
                item.sku,
                item.name,
                item.category,
                item.unit,
                item.unit_cost,
                item.stock,
                item.min_stock,
                item.max_stock,
                (item.stock * item.unit_cost).label("stock_value"),
                status.label("status"),
                item.location,
                item.supplier,
            )
            .order_by(item.name, item.id)
            .limit(limit)
        )
        if categories:
            query = query.where(item.category.in_(categories))
        if statuses:
            query = query.where(status.in_(statuses))
        return [dict(row._mapping) for row in await self.session.execute(query)]

    async def movement_rows(
        self,
        *,
        kinds: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int = MAX_EXPORT_ROWS,
    ) -> list[dict[str, Any]]:
        move = InventoryMovement
        query = (
            select(
                move.created_at,
                InventoryItem.sku,
                InventoryItem.name,
                move.kind,
                move.quantity,
                move.stock_after,
                User.full_name.label("registered_by"),
                move.notes,
            )
            .join(InventoryItem, InventoryItem.id == move.item_id)
            .outerjoin(User, User.id == move.created_by_user_id)
            .order_by(move.created_at.desc(), move.id.desc())
            .limit(limit)
        )
        if kinds:
            query = query.where(move.kind.in_(kinds))
        if date_from is not None:
            query = query.where(move.created_at >= date_from)
        if date_to is not None:
            query = query.where(move.created_at <= date_to)
        return [dict(row._mapping) for row in await self.session.execute(query)]

    async def equipment_type_options(self) -> list[tuple[int, str]]:
        rows = await self.session.execute(
            select(EquipmentType.id, EquipmentType.name)
            .where(EquipmentType.is_active.is_(True))
            .order_by(EquipmentType.name)
        )
        return [(row[0], row[1]) for row in rows.all()]

    # -- activity log ------------------------------------------------------------------------

    def record_run(
        self,
        *,
        report_key: str,
        export_format: str,
        filters: dict[str, Any],
        row_count: int,
        user_id: int | None,
    ) -> ReportRun:
        run = ReportRun(
            report_key=report_key,
            export_format=export_format,
            filters=filters,
            row_count=row_count,
            user_id=user_id,
        )
        self.session.add(run)
        return run

    async def runs_in(self, start: datetime, end: datetime) -> int:
        row = await self.session.execute(
            select(func.count()).where(
                ReportRun.created_at >= start, ReportRun.created_at < end
            )
        )
        return int(row.scalar_one())

    async def people_in(self, start: datetime, end: datetime) -> int:
        row = await self.session.execute(
            select(func.count(func.distinct(ReportRun.user_id))).where(
                ReportRun.created_at >= start, ReportRun.created_at < end
            )
        )
        return int(row.scalar_one())

    async def most_used(
        self, start: datetime, end: datetime, *, limit: int
    ) -> list[tuple[str, int]]:
        count = func.count()
        rows = await self.session.execute(
            select(ReportRun.report_key, count)
            .where(ReportRun.created_at >= start, ReportRun.created_at < end)
            .group_by(ReportRun.report_key)
            .order_by(count.desc(), ReportRun.report_key)
            .limit(limit)
        )
        return [(row[0], int(row[1])) for row in rows.all()]

    async def by_format(self, start: datetime, end: datetime) -> dict[str, int]:
        rows = await self.session.execute(
            select(ReportRun.export_format, func.count())
            .where(ReportRun.created_at >= start, ReportRun.created_at < end)
            .group_by(ReportRun.export_format)
        )
        return {row[0]: int(row[1]) for row in rows.all()}

    async def last_run(self) -> RunRow | None:
        rows = await self.recent_runs(limit=1, offset=0)
        return rows[0] if rows else None

    async def count_runs(self) -> int:
        row = await self.session.execute(select(func.count()).select_from(ReportRun))
        return int(row.scalar_one())

    async def recent_runs(self, *, limit: int, offset: int) -> list[RunRow]:
        """Newest first."""
        rows = await self.session.execute(
            select(
                ReportRun.id,
                ReportRun.report_key,
                ReportRun.export_format,
                ReportRun.row_count,
                ReportRun.filters,
                User.full_name,
                ReportRun.created_at,
            )
            .outerjoin(User, User.id == ReportRun.user_id)
            .order_by(ReportRun.created_at.desc(), ReportRun.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return [
            RunRow(
                id=r[0],
                report_key=r[1],
                export_format=r[2],
                row_count=r[3],
                filters=r[4],
                by=r[5],
                at=r[6],
            )
            for r in rows.all()
        ]
