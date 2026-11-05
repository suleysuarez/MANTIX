# Códigos de error de la API

> Generado por `python -m scripts.error_codes_doc`. No lo edites a mano: cámbialo en
> `backend/app/core/error_codes.py` y regenera.

Toda respuesta de error tiene el mismo cuerpo:

```json
{ "detail": "mensaje legible", "code": "ticket_not_found", "errors": null, "request_id": "3f2c9d1e0b7a4c58" }
```

- `code` es un contrato: **no se renombra ni se reutiliza** para otro significado. Un caso nuevo recibe un código nuevo.
- `errors` solo viene en los 422 (`validation_error`): lista de `{field, message, type}`.
- `request_id` identifica la petición en los logs del servidor; el soporte lo pide.
- `detail` es para mostrar, pero puede estar en español o en inglés: la app decide por `code`, no por el texto.

## Cómo debe usarlos un cliente

1. Si el `code` es uno de los **específicos**, usar el mensaje o la acción propia de ese caso.
2. Si el `code` no está en la tabla (por ejemplo, uno añadido por un servidor más nuevo), decidir por el **estado HTTP** con el significado del genérico de esa fila.
3. Nunca decidir por el texto de `detail`.

## Genéricos (respaldo por estado HTTP)

### 400 Petición mal formada

| Código | Significado |
| --- | --- |
| `bad_request` | Petición mal formada. |

### 401 Sin sesión

| Código | Significado |
| --- | --- |
| `unauthorized` | Sin sesión válida o sesión caducada. |

### 403 Prohibido

| Código | Significado |
| --- | --- |
| `forbidden` | No tienes permiso para esta acción. |

### 404 No encontrado

| Código | Significado |
| --- | --- |
| `not_found` | El recurso no existe. |

### 405 Método no permitido

| Código | Significado |
| --- | --- |
| `method_not_allowed` | Método HTTP no permitido en esta ruta. |

### 409 Conflicto

| Código | Significado |
| --- | --- |
| `business_rule_violation` | La petición es válida pero incumple una regla de negocio. |
| `conflict` | Choca con el estado actual o con datos existentes. |
| `invalid_transition` | El cambio de estado del ticket no está permitido. |

### 413 Archivo demasiado grande

| Código | Significado |
| --- | --- |
| `payload_too_large` | El archivo supera el tamaño máximo. |

### 415 Formato no admitido

| Código | Significado |
| --- | --- |
| `unsupported_media_type` | Tipo de archivo o formato no admitido. |

### 422 Datos no válidos

| Código | Significado |
| --- | --- |
| `unprocessable` | El contenido no se puede procesar (por ejemplo, un archivo dañado). |
| `validation_error` | Algún campo no es válido (ver `errors`). |

### 429 Demasiadas peticiones

| Código | Significado |
| --- | --- |
| `rate_limited` | Demasiadas peticiones; espera un momento. |

### 500 Error interno

| Código | Significado |
| --- | --- |
| `internal_error` | Error interno del servidor. |

## Específicos (un caso de negocio)

### 403 Prohibido

| Código | Significado |
| --- | --- |
| `auth_code_attempts_exceeded` | Se superó el número de intentos del código. |
| `auth_code_invalid` | El código no es válido o ha vencido. |
| `auth_email_not_verified` | El correo debe verificarse antes de iniciar sesión. |
| `auth_invalid_credentials` | El correo o la contraseña no son correctos. |
| `attachment_access_forbidden` | No tienes acceso a este archivo. |
| `attachment_delete_forbidden` | Solo quien subió el archivo o un supervisor puede eliminarlo. |
| `attachment_equipment_forbidden` | No puedes adjuntar archivos a equipos. |
| `cannot_change_own_roles` | No puedes cambiar tus propios roles. |
| `export_forbidden` | No tienes permiso para exportar esto. |
| `inventory_manage_forbidden` | Solo quien gestiona inventario registra entradas y ajustes. |
| `profile_email_locked` | El correo no se modifica desde el perfil. |
| `role_escalation_forbidden` | No puedes conceder ni quitar permisos o roles que tú no tienes. |
| `ticket_act_forbidden` | Solo el técnico asignado o un supervisor puede actuar sobre el ticket. |
| `ticket_view_forbidden` | No puedes ver este ticket. |
| `user_inactive` | El usuario local está inactivo. |

### 404 No encontrado

| Código | Significado |
| --- | --- |
| `attachment_file_missing` | El adjunto existe pero su archivo no está en el almacenamiento. |
| `attachment_not_found` | El adjunto no existe. |
| `category_not_found` | La categoría no existe o está inactiva. |
| `equipment_not_found` | El equipo no existe. |
| `equipment_type_not_found` | El tipo de equipo no existe. |
| `inventory_item_not_found` | El ítem de inventario no existe. |
| `location_not_found` | La ubicación no existe. |
| `maintenance_record_not_found` | El registro de trabajo no existe. |
| `no_active_assignment` | El ticket no tiene un técnico asignado. |
| `notification_not_found` | La notificación no existe. |
| `permission_not_found` | Algún permiso indicado no existe. |
| `priority_not_found` | La prioridad no existe o está inactiva. |
| `profile_photo_not_found` | El usuario no tiene foto de perfil. |
| `role_not_found` | El rol no existe o está inactivo. |
| `schedule_not_found` | El plan de mantenimiento no existe. |
| `technician_not_found` | El técnico no existe. |
| `ticket_not_found` | El ticket no existe. |
| `user_not_found` | El usuario no existe o está inactivo. |
| `user_role_not_assigned` | El usuario no tiene ese rol. |

### 409 Conflicto

| Código | Significado |
| --- | --- |
| `account_email_linked_to_other` | Ese correo ya está enlazado a otra cuenta de acceso. |
| `account_provisioning_failed` | No se pudo enlazar la cuenta de acceso con un perfil local. |
| `attachment_limit_reached` | Se alcanzó el máximo de adjuntos. |
| `auth_service_not_configured` | El servicio de acceso no está configurado. |
| `auth_service_rejected` | El servicio de acceso rechazó la operación o no está disponible. |
| `cannot_deactivate_self` | No puedes desactivar tu propia cuenta. |
| `cannot_revoke_own_admin` | No puedes quitarte tu propio rol de administrador. |
| `category_code_taken` | Ya existe una categoría con ese código. |
| `category_in_use` | La categoría está en uso por solicitudes y no se elimina. |
| `equipment_identifier_taken` | Ya existe un equipo con esa etiqueta o número de serie. |
| `equipment_serial_taken` | Ya existe un equipo con ese número de serie. |
| `inventory_insufficient_stock` | No hay stock suficiente para el movimiento. |
| `inventory_item_has_movements` | El ítem tiene movimientos y no se elimina; desactívalo. |
| `inventory_item_inactive` | Un ítem inactivo no admite movimientos; reactívalo primero. |
| `inventory_sku_taken` | Ya existe un ítem con ese código. |
| `last_admin_protected` | No se puede dejar al sistema sin administradores activos. |
| `list_value_taken` | Ya existe ese valor en la lista. |
| `location_taken` | Ya existe una ubicación con ese código o nombre. |
| `password_reset_unavailable` | La persona aún no inició sesión: no hay contraseña que restablecer. |
| `priority_code_taken` | Ya existe una prioridad con ese código. |
| `role_admin_immutable` | El rol Administrador siempre tiene todos los permisos y no se edita. |
| `role_base_protected` | Los roles base no se eliminan, no se desactivan y su jerarquía no cambia. |
| `role_has_users` | El rol tiene usuarios asignados; reasígnalos primero. |
| `role_hierarchy_cycle` | Ese padre crearía un ciclo en la jerarquía de roles. |
| `role_hierarchy_too_deep` | La jerarquía supera el máximo de niveles de herencia. |
| `role_is_parent` | El rol es padre de otros roles; cambia primero su jerarquía. |
| `role_name_taken` | Ya existe un rol con ese nombre. |
| `role_name_too_short` | El nombre del rol es demasiado corto. |
| `schedule_equipment_unavailable` | No se programa mantenimiento para un equipo en ese estado. |
| `schedule_technician_inactive` | No se asigna un plan a un técnico inactivo. |
| `technician_inactive` | No se puede asignar un ticket a un técnico inactivo. |
| `technician_profile_exists` | El usuario ya tiene perfil de técnico. |
| `ticket_assign_wrong_status` | En el estado actual del ticket no se puede asignar técnico. |
| `ticket_classify_wrong_status` | Solo se clasifican las solicitudes que esperan triaje. |
| `ticket_record_without_technician` | No se puede registrar trabajo: el ticket no tiene técnico asignado. |
| `ticket_reject_wrong_status` | Solo se rechazan las solicitudes que aún no empezaron. |
| `ticket_requires_technician` | No se puede avanzar el ticket sin técnico asignado. |
| `ticket_status_unknown` | El estado indicado no existe en el flujo. |
| `use_profile_to_change_password` | La contraseña propia se cambia desde el perfil. |
| `user_account_disabled` | La cuenta está desactivada. |
| `user_email_taken` | Ya existe un usuario con ese correo. |
| `user_employee_code_taken` | Ya existe un usuario con ese código de empleado. |
| `warranty_dates_invalid` | El fin de garantía no puede ser anterior al inicio. |
