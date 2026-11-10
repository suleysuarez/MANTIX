"""Códigos de error estables (`code` en el cuerpo de error de la API).

Cada código es un contrato con la app móvil: **no se renombra ni se reutiliza**
para otro significado. Si un caso cambia, se añade un código nuevo.

Dos niveles:

* **Genéricos**: uno por estado HTTP (`not_found`, `conflict`…). Se usan cuando
  no hay un caso concreto y son el respaldo para cualquier error no listado abajo.
* **Específicos**: un caso de negocio concreto (`ticket_not_found`,
  `user_email_taken`…). Pasan como `code=` al lanzar el error de dominio.

`ERROR_CODES` es la fuente de la tabla de `docs/error-codes.md`; un test comprueba
que el código, el registro y el documento coinciden. Para regenerar el documento:
`python scripts/export_error_codes.py`.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class ErrorCodeInfo:
    status: int
    meaning: str
    #: Genérico (respaldo por estado HTTP) o específico de un caso de negocio.
    generic: bool = False


def _group(status: int, codes: dict[str, str]) -> dict[str, ErrorCodeInfo]:
    return {code: ErrorCodeInfo(status, meaning) for code, meaning in codes.items()}


def _generic(status: int, codes: dict[str, str]) -> dict[str, ErrorCodeInfo]:
    return {
        code: ErrorCodeInfo(status, meaning, generic=True)
        for code, meaning in codes.items()
    }


ERROR_CODES: dict[str, ErrorCodeInfo] = {
    # --- Genéricos (uno por estado HTTP) -----------------------------------------------
    **_generic(400, {"bad_request": "Petición mal formada."}),
    **_generic(401, {"unauthorized": "Sin sesión válida o sesión caducada."}),
    **_generic(403, {"forbidden": "No tienes permiso para esta acción."}),
    **_generic(404, {"not_found": "El recurso no existe."}),
    **_generic(405, {"method_not_allowed": "Método HTTP no permitido en esta ruta."}),
    **_generic(
        409,
        {
            "conflict": "Choca con el estado actual o con datos existentes.",
            "business_rule_violation": "La petición es válida pero incumple una regla de negocio.",
            "invalid_transition": "El cambio de estado del ticket no está permitido.",
        },
    ),
    **_generic(413, {"payload_too_large": "El archivo supera el tamaño máximo."}),
    **_generic(
        415, {"unsupported_media_type": "Tipo de archivo o formato no admitido."}
    ),
    **_generic(
        422,
        {
            "validation_error": "Algún campo no es válido (ver `errors`).",
            "unprocessable": "El contenido no se puede procesar (por ejemplo, un archivo dañado).",
        },
    ),
    **_group(
        422,
        {
            "invalid_date_range": "La fecha «desde» no puede ser posterior a la fecha «hasta».",
            "filter_too_many_values": "Un filtro admite como máximo 20 valores.",
        },
    ),
    **_generic(429, {"rate_limited": "Demasiadas peticiones; espera un momento."}),
    **_generic(500, {"internal_error": "Error interno del servidor."}),
    # --- No encontrado (404) -----------------------------------------------------------
    **_group(
        404,
        {
            "ticket_not_found": "El ticket no existe.",
            "equipment_not_found": "El equipo no existe.",
            "equipment_type_not_found": "El tipo de equipo no existe.",
            "technician_not_found": "El técnico no existe.",
            "maintenance_record_not_found": "El registro de trabajo no existe.",
            "schedule_not_found": "El plan de mantenimiento no existe.",
            "inventory_item_not_found": "El ítem de inventario no existe.",
            "location_not_found": "La ubicación no existe.",
            "category_not_found": "La categoría no existe o está inactiva.",
            "priority_not_found": "La prioridad no existe o está inactiva.",
            "user_not_found": "El usuario no existe o está inactivo.",
            "role_not_found": "El rol no existe o está inactivo.",
            "permission_not_found": "Algún permiso indicado no existe.",
            "user_role_not_assigned": "El usuario no tiene ese rol.",
            "attachment_not_found": "El adjunto no existe.",
            "attachment_file_missing": "El adjunto existe pero su archivo no está en el almacenamiento.",
            "notification_not_found": "La notificación no existe.",
            "profile_photo_not_found": "El usuario no tiene foto de perfil.",
            "no_active_assignment": "El ticket no tiene un técnico asignado.",
        },
    ),
    # --- Conflicto (409) ---------------------------------------------------------------
    **_group(
        409,
        {
            "ticket_requires_technician": "No se puede avanzar el ticket sin técnico asignado.",
            "ticket_assign_wrong_status": "En el estado actual del ticket no se puede asignar técnico.",
            "ticket_classify_wrong_status": "Solo se clasifican las solicitudes que esperan triaje.",
            "ticket_reject_wrong_status": "Solo se rechazan las solicitudes que aún no empezaron.",
            "ticket_status_unknown": "El estado indicado no existe en el flujo.",
            "ticket_record_without_technician": "No se puede registrar trabajo: el ticket no tiene técnico asignado.",
            "technician_inactive": "No se puede asignar un ticket a un técnico inactivo.",
            "technician_profile_exists": "El usuario ya tiene perfil de técnico.",
            "schedule_equipment_unavailable": "No se programa mantenimiento para un equipo en ese estado.",
            "schedule_technician_inactive": "No se asigna un plan a un técnico inactivo.",
            "equipment_identifier_taken": "Ya existe un equipo con esa etiqueta o número de serie.",
            "equipment_type_name_taken": "Ya existe una categoría de equipo con ese nombre.",
            "equipment_serial_taken": "Ya existe un equipo con ese número de serie.",
            "warranty_dates_invalid": "El fin de garantía no puede ser anterior al inicio.",
            "location_taken": "Ya existe una ubicación con ese código o nombre.",
            "inventory_item_inactive": "Un ítem inactivo no admite movimientos; reactívalo primero.",
            "inventory_insufficient_stock": "No hay stock suficiente para el movimiento.",
            "inventory_item_has_movements": "El ítem tiene movimientos y no se elimina; desactívalo.",
            "inventory_sku_taken": "Ya existe un ítem con ese código.",
            "list_value_taken": "Ya existe ese valor en la lista.",
            "priority_code_taken": "Ya existe una prioridad con ese código.",
            "category_code_taken": "Ya existe una categoría con ese código.",
            "category_in_use": "La categoría está en uso por solicitudes y no se elimina.",
            "attachment_limit_reached": "Se alcanzó el máximo de adjuntos.",
            "user_email_taken": "Ya existe un usuario con ese correo.",
            "user_employee_code_taken": "Ya existe un usuario con ese código de empleado.",
            "user_account_disabled": "La cuenta está desactivada.",
            "cannot_deactivate_self": "No puedes desactivar tu propia cuenta.",
            "cannot_revoke_own_admin": "No puedes quitarte tu propio rol de administrador.",
            "last_admin_protected": "No se puede dejar al sistema sin administradores activos.",
            "use_profile_to_change_password": "La contraseña propia se cambia desde el perfil.",
            "password_reset_unavailable": "La persona aún no inició sesión: no hay contraseña que restablecer.",
            "account_email_linked_to_other": "Ese correo ya está enlazado a otra cuenta de acceso.",
            "account_provisioning_failed": "No se pudo enlazar la cuenta de acceso con un perfil local.",
            "auth_service_not_configured": "El servicio de acceso no está configurado.",
            "auth_service_rejected": "El servicio de acceso rechazó la operación o no está disponible.",
            "role_name_taken": "Ya existe un rol con ese nombre.",
            "role_name_too_short": "El nombre del rol es demasiado corto.",
            "role_base_protected": "Los roles base no se eliminan, no se desactivan y su jerarquía no cambia.",
            "role_admin_immutable": "El rol Administrador siempre tiene todos los permisos y no se edita.",
            "role_has_users": "El rol tiene usuarios asignados; reasígnalos primero.",
            "role_is_parent": "El rol es padre de otros roles; cambia primero su jerarquía.",
            "role_hierarchy_cycle": "Ese padre crearía un ciclo en la jerarquía de roles.",
            "role_hierarchy_too_deep": "La jerarquía supera el máximo de niveles de herencia.",
        },
    ),
    # --- Prohibido (403) ---------------------------------------------------------------
    **_group(
        403,
        {
            "ticket_view_forbidden": "No puedes ver este ticket.",
            "ticket_act_forbidden": "Solo el técnico asignado o un supervisor puede actuar sobre el ticket.",
            "attachment_equipment_forbidden": "No puedes adjuntar archivos a equipos.",
            "attachment_delete_forbidden": "Solo quien subió el archivo o un supervisor puede eliminarlo.",
            "attachment_access_forbidden": "No tienes acceso a este archivo.",
            "inventory_manage_forbidden": "Solo quien gestiona inventario registra entradas y ajustes.",
            "export_forbidden": "No tienes permiso para exportar esto.",
            "cannot_change_own_roles": "No puedes cambiar tus propios roles.",
            "role_escalation_forbidden": "No puedes conceder ni quitar permisos o roles que tú no tienes.",
            "profile_email_locked": "El correo no se modifica desde el perfil.",
            "user_inactive": "El usuario local está inactivo.",
            "auth_email_not_verified": "El correo debe verificarse antes de iniciar sesión.",
            "auth_email_already_verified": "El correo ya fue verificado.",
            "auth_code_invalid": "El código no es válido o ha vencido.",
            "auth_code_attempts_exceeded": "Se superó el número de intentos del código.",
            "auth_invalid_credentials": "El correo o la contraseña no son correctos.",
        },
    ),
}
