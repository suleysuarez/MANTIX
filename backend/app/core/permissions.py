"""Canonical role -> permission matrix.

The database is the runtime source of truth (roles and permissions are rows
seeded by migrations and editable by administrators). This module records the
*intended* default matrix so that:

* tests can assert the seeded rows match it (`MIGRATED_DATABASE_URL`),
* tests can assert every endpoint enforces what the matrix says,
* the README/docs matrix has one place to be generated from.

Changing a default grant means: new migration + update this file.
"""

from types import MappingProxyType

from app.core.authz import ADMIN, EMPLOYEE, SUPERVISOR, TECHNICIAN

# Permission codes (the strings stored in `permissions.code`).
EQUIPMENT_READ = "equipment.read"
EQUIPMENT_MANAGE = "equipment.manage"
MAINTENANCE_READ = "maintenance.read"
MAINTENANCE_CREATE = "maintenance.create"
MAINTENANCE_MANAGE = "maintenance.manage"
TECHNICIANS_MANAGE = "technicians.manage"
USERS_MANAGE = "users.manage"
PRIORITIES_MANAGE = "priorities.manage"
DASHBOARD_READ = "dashboard.read"
REPORTS_READ = "reports.read"
AUDIT_READ = "audit.read"
ATTACHMENTS_WRITE = "attachments.write"
SCHEDULES_MANAGE = "schedules.manage"

ALL_PERMISSIONS = frozenset(
    {
        EQUIPMENT_READ,
        EQUIPMENT_MANAGE,
        MAINTENANCE_READ,
        MAINTENANCE_CREATE,
        MAINTENANCE_MANAGE,
        TECHNICIANS_MANAGE,
        USERS_MANAGE,
        PRIORITIES_MANAGE,
        DASHBOARD_READ,
        REPORTS_READ,
        AUDIT_READ,
        ATTACHMENTS_WRITE,
        SCHEDULES_MANAGE,
    }
)

#: `maintenance.manage` for a TECHNICIAN only applies to tickets assigned to
#: them; that scoping is enforced in `MaintenanceService`, not by this grant.
ROLE_PERMISSIONS = MappingProxyType(
    {
        ADMIN: ALL_PERMISSIONS,
        SUPERVISOR: frozenset(
            {
                EQUIPMENT_READ,
                EQUIPMENT_MANAGE,
                MAINTENANCE_READ,
                MAINTENANCE_CREATE,
                MAINTENANCE_MANAGE,
                TECHNICIANS_MANAGE,
                DASHBOARD_READ,
                REPORTS_READ,
                AUDIT_READ,
                ATTACHMENTS_WRITE,
                SCHEDULES_MANAGE,
            }
        ),
        TECHNICIAN: frozenset(
            {
                EQUIPMENT_READ,
                MAINTENANCE_READ,
                MAINTENANCE_MANAGE,
                DASHBOARD_READ,
                ATTACHMENTS_WRITE,
            }
        ),
        EMPLOYEE: frozenset(
            {
                EQUIPMENT_READ,
                MAINTENANCE_READ,
                MAINTENANCE_CREATE,
                ATTACHMENTS_WRITE,
            }
        ),
    }
)
