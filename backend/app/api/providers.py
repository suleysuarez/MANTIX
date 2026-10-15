"""Composition root: FastAPI `Depends` providers for repositories and services.

Wiring is one chain per request -- `get_db` (session) -> `get_*_repository`
-> `get_*_service` -- so every collaborator shares the same `AsyncSession` (and
therefore one transaction). Services never build repositories themselves, and
routes depend on service providers only. Tests can swap any link with
`app.dependency_overrides`, or build a service directly from fakes.
"""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.storage import FileStorage, LocalFileStorage
from app.db.session import get_db
from app.repositories.admin import AdminRepository
from app.repositories.attachment import AttachmentRepository
from app.repositories.audit import AuditRepository
from app.repositories.auth import AuthRepository
from app.repositories.dashboard_kpis import DashboardKpiRepository
from app.repositories.equipment import EquipmentRepository
from app.repositories.export import ExportRepository
from app.repositories.inventory import InventoryRepository
from app.repositories.maintenance import MaintenanceRepository
from app.repositories.maintenance_overview import MaintenanceOverviewRepository
from app.repositories.notification import NotificationRepository
from app.repositories.priority import PriorityRepository
from app.repositories.queue import QueueRepository
from app.repositories.report import ReportRepository
from app.repositories.report_builder import ReportBuilderRepository
from app.repositories.schedule import ScheduleRepository
from app.repositories.settings import SettingsRepository
from app.repositories.technician import TechnicianRepository
from app.services.admin import AdminUserService
from app.services.attachment import AttachmentService
from app.services.audit import AuditService
from app.services.auth import ClerkAuthService
from app.services.dashboard_kpis import DashboardKpiService
from app.services.data_import import EquipmentImportService
from app.services.equipment import EquipmentService
from app.services.export import ExportService
from app.services.inventory import InventoryService
from app.services.maintenance import MaintenanceService
from app.services.maintenance_overview import MaintenanceOverviewService
from app.services.notification import NotificationService
from app.services.notification_inbox import NotificationInboxService
from app.services.priority import PriorityService
from app.services.queue import QueueService
from app.services.reminders import ReminderService
from app.services.report import ReportService
from app.services.report_builder import ReportBuilderService
from app.services.schedule import ScheduleService
from app.services.settings import SystemSettingsService
from app.services.technician import TechnicianService

Session = Depends(get_db)


# -- Repositories ----------------------------------------------------------


def get_audit_repository(session: AsyncSession = Session) -> AuditRepository:
    return AuditRepository(session)


def get_auth_repository(session: AsyncSession = Session) -> AuthRepository:
    return AuthRepository(session)


def get_notification_repository(
    session: AsyncSession = Session,
) -> NotificationRepository:
    return NotificationRepository(session)


def get_priority_repository(session: AsyncSession = Session) -> PriorityRepository:
    return PriorityRepository(session)


def get_dashboard_repository(session: AsyncSession = Session) -> DashboardKpiRepository:
    return DashboardKpiRepository(session)


def get_report_repository(session: AsyncSession = Session) -> ReportRepository:
    return ReportRepository(session)


def get_attachment_repository(
    session: AsyncSession = Session,
) -> AttachmentRepository:
    return AttachmentRepository(session)


def get_schedule_repository(session: AsyncSession = Session) -> ScheduleRepository:
    return ScheduleRepository(session)


def get_maintenance_repository(
    session: AsyncSession = Session,
) -> MaintenanceRepository:
    return MaintenanceRepository(session)


def get_maintenance_overview_repository(
    session: AsyncSession = Session,
) -> MaintenanceOverviewRepository:
    return MaintenanceOverviewRepository(session)


def get_inventory_repository(session: AsyncSession = Session) -> InventoryRepository:
    return InventoryRepository(session)


def get_report_builder_repository(
    session: AsyncSession = Session,
) -> ReportBuilderRepository:
    return ReportBuilderRepository(session)


def get_settings_repository(session: AsyncSession = Session) -> SettingsRepository:
    return SettingsRepository(session)


def get_queue_repository(session: AsyncSession = Session) -> QueueRepository:
    return QueueRepository(session)


def get_equipment_repository(session: AsyncSession = Session) -> EquipmentRepository:
    return EquipmentRepository(session)


def get_technician_repository(
    session: AsyncSession = Session,
) -> TechnicianRepository:
    return TechnicianRepository(session)


def get_admin_repository(session: AsyncSession = Session) -> AdminRepository:
    return AdminRepository(session)


# -- Services --------------------------------------------------------------


def get_audit_service(
    repository: Annotated[AuditRepository, Depends(get_audit_repository)],
) -> AuditService:
    return AuditService(repository)


def get_notification_service(
    repository: Annotated[NotificationRepository, Depends(get_notification_repository)],
) -> NotificationService:
    return NotificationService(repository)


def get_auth_service(
    repository: Annotated[AuthRepository, Depends(get_auth_repository)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ClerkAuthService:
    return ClerkAuthService(repository, settings)


def get_notification_inbox_service(
    repository: Annotated[NotificationRepository, Depends(get_notification_repository)],
) -> NotificationInboxService:
    return NotificationInboxService(repository)


def get_maintenance_service(
    repository: Annotated[MaintenanceRepository, Depends(get_maintenance_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    notifications: Annotated[NotificationService, Depends(get_notification_service)],
) -> MaintenanceService:
    return MaintenanceService(repository, audit, notifications)


def get_maintenance_overview_service(
    repository: Annotated[
        MaintenanceOverviewRepository, Depends(get_maintenance_overview_repository)
    ],
) -> MaintenanceOverviewService:
    return MaintenanceOverviewService(repository)


def get_inventory_service(
    repository: Annotated[InventoryRepository, Depends(get_inventory_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> InventoryService:
    return InventoryService(repository, audit)


def get_system_settings_service(
    repository: Annotated[SettingsRepository, Depends(get_settings_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> SystemSettingsService:
    return SystemSettingsService(repository, audit, settings)


def get_queue_service(
    repository: Annotated[QueueRepository, Depends(get_queue_repository)],
) -> QueueService:
    return QueueService(repository)


def get_equipment_service(
    repository: Annotated[EquipmentRepository, Depends(get_equipment_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> EquipmentService:
    return EquipmentService(repository, audit)


def get_technician_service(
    repository: Annotated[TechnicianRepository, Depends(get_technician_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> TechnicianService:
    return TechnicianService(repository, audit)


def get_admin_user_service(
    repository: Annotated[AdminRepository, Depends(get_admin_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    notifications: Annotated[NotificationService, Depends(get_notification_service)],
) -> AdminUserService:
    return AdminUserService(repository, audit, notifications)


def get_priority_service(
    repository: Annotated[PriorityRepository, Depends(get_priority_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> PriorityService:
    return PriorityService(repository, audit)


def get_dashboard_service(
    repository: Annotated[DashboardKpiRepository, Depends(get_dashboard_repository)],
) -> DashboardKpiService:
    return DashboardKpiService(repository)


def get_report_service(
    repository: Annotated[ReportRepository, Depends(get_report_repository)],
    dashboard: Annotated[DashboardKpiService, Depends(get_dashboard_service)],
) -> ReportService:
    return ReportService(repository, dashboard)


def get_report_builder_service(
    repository: Annotated[
        ReportBuilderRepository, Depends(get_report_builder_repository)
    ],
    dashboard: Annotated[DashboardKpiService, Depends(get_dashboard_service)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> ReportBuilderService:
    return ReportBuilderService(repository, dashboard, audit)


def get_export_repository(session: AsyncSession = Session) -> ExportRepository:
    return ExportRepository(session)


def get_export_service(
    repository: Annotated[ExportRepository, Depends(get_export_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> ExportService:
    return ExportService(repository, audit)


def get_equipment_import_service(
    repository: Annotated[EquipmentRepository, Depends(get_equipment_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> EquipmentImportService:
    return EquipmentImportService(repository, audit)


def get_file_storage(
    settings: Annotated[Settings, Depends(get_settings)],
) -> FileStorage:
    return LocalFileStorage(settings.upload_dir)


def get_attachment_service(
    repository: Annotated[AttachmentRepository, Depends(get_attachment_repository)],
    storage: Annotated[FileStorage, Depends(get_file_storage)],
    maintenance: Annotated[MaintenanceService, Depends(get_maintenance_service)],
    equipment: Annotated[EquipmentRepository, Depends(get_equipment_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AttachmentService:
    return AttachmentService(
        repository,
        storage,
        maintenance,
        equipment,
        audit,
        max_bytes=settings.max_upload_mb * 1024 * 1024,
    )


def get_schedule_service(
    repository: Annotated[ScheduleRepository, Depends(get_schedule_repository)],
    equipment: Annotated[EquipmentRepository, Depends(get_equipment_repository)],
    technicians: Annotated[TechnicianRepository, Depends(get_technician_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> ScheduleService:
    return ScheduleService(repository, equipment, technicians, audit)


def get_reminder_service(
    repository: Annotated[ScheduleRepository, Depends(get_schedule_repository)],
    notifications: Annotated[NotificationService, Depends(get_notification_service)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> ReminderService:
    return ReminderService(repository, notifications, audit)
