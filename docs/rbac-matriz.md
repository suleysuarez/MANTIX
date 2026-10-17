# Mantix · Matriz de permisos por rol

Generada con `python -m scripts.rbac_matrix` desde `app/core/permissions.py`: no se edita a mano.

**Herencia:** Solicitante → Técnico → Supervisor → Administrador (cada uno hereda del anterior). Auditor no hereda nada.

`●` lo concede el propio rol · `○` lo hereda de un rol anterior · vacío: no lo tiene.

Alcance de datos: `ver` = solo lo propio, `ver_asignados` = lo asignado a la persona (y lo suyo), `ver_todos` = todo.

| Permiso | Código | Solicitante | Técnico | Supervisor | Administrador | Auditor |
|---|---|:-:|:-:|:-:|:-:|:-:|
| Dashboard · Ver | `dashboard:ver` | ● | ● | ○ | ○ | ● |
| Dashboard · Ver todo | `dashboard:ver_todos` |  |  | ● | ○ | ● |
| Equipos · Ver | `equipos:ver` | ● | ● | ○ | ○ |  |
| Equipos · Crear | `equipos:crear` |  |  | ● | ○ |  |
| Equipos · Editar | `equipos:editar` |  |  | ● | ○ |  |
| Equipos · Asignar | `equipos:asignar` |  |  | ● | ○ |  |
| Equipos · Adjuntar archivos | `equipos:adjuntar` |  |  | ● | ○ |  |
| Equipos · Exportar | `equipos:exportar` |  |  | ● | ○ |  |
| Equipos · Importar | `equipos:importar` |  |  |  | ● |  |
| Solicitudes · Ver | `solicitudes:ver` | ● |  | ● | ○ |  |
| Solicitudes · Ver todo | `solicitudes:ver_todos` |  |  | ● | ○ |  |
| Solicitudes · Crear | `solicitudes:crear` | ● |  | ● | ○ |  |
| Solicitudes · Editar | `solicitudes:editar` |  |  | ● | ○ |  |
| Solicitudes · Aprobar o rechazar | `solicitudes:aprobar` |  |  | ● | ○ |  |
| Tickets · Ver | `tickets:ver` | ● | ● | ○ | ○ |  |
| Tickets · Ver lo asignado | `tickets:ver_asignados` |  | ● | ○ | ○ |  |
| Tickets · Ver todo | `tickets:ver_todos` |  |  | ● | ○ |  |
| Tickets · Editar | `tickets:editar` |  | ● | ○ | ○ |  |
| Tickets · Asignar | `tickets:asignar` |  |  | ● | ○ |  |
| Tickets · Cambiar estado | `tickets:cambiar_estado` |  | ● | ○ | ○ |  |
| Tickets · Adjuntar archivos | `tickets:adjuntar` | ● | ● | ○ | ○ |  |
| Tickets · Exportar | `tickets:exportar` |  | ● | ● | ○ |  |
| Técnicos · Ver | `tecnicos:ver` |  |  | ● | ○ |  |
| Técnicos · Crear | `tecnicos:crear` |  |  | ● | ○ |  |
| Técnicos · Editar | `tecnicos:editar` |  |  | ● | ○ |  |
| Técnicos · Exportar | `tecnicos:exportar` |  |  | ● | ○ |  |
| Mantenimiento · Ver | `mantenimiento:ver` |  | ● | ○ | ○ |  |
| Mantenimiento · Crear | `mantenimiento:crear` |  |  | ● | ○ |  |
| Mantenimiento · Editar | `mantenimiento:editar` |  |  | ● | ○ |  |
| Inventario · Ver | `inventario:ver` |  | ● | ○ | ○ |  |
| Inventario · Crear | `inventario:crear` |  |  | ● | ○ |  |
| Inventario · Editar | `inventario:editar` |  |  | ● | ○ |  |
| Inventario · Eliminar | `inventario:eliminar` |  |  |  | ● |  |
| Inventario · Consumir | `inventario:consumir` |  | ● | ○ | ○ |  |
| Inventario · Importar | `inventario:importar` |  |  |  | ● |  |
| Inventario · Exportar | `inventario:exportar` |  |  | ● | ○ |  |
| Reportes · Ver | `reportes:ver` |  |  | ● | ○ | ● |
| Reportes · Exportar | `reportes:exportar` |  |  | ● | ○ | ● |
| Usuarios · Ver | `usuarios:ver` |  |  |  | ● |  |
| Usuarios · Crear | `usuarios:crear` |  |  |  | ● |  |
| Usuarios · Editar | `usuarios:editar` |  |  |  | ● |  |
| Usuarios · Cambiar estado | `usuarios:cambiar_estado` |  |  |  | ● |  |
| Usuarios · Asignar | `usuarios:asignar` |  |  |  | ● |  |
| Perfil · Ver | `perfil:ver` | ● | ● | ○ | ○ | ● |
| Perfil · Editar | `perfil:editar` | ● | ● | ○ | ○ | ● |
| Configuración · Ver | `configuracion:ver` |  |  |  | ● |  |
| Configuración · Editar | `configuracion:editar` |  |  |  | ● |  |
| Auditoría · Ver | `auditoria:ver` |  |  |  | ● | ● |

Total: 48 permisos, 5 roles base.
