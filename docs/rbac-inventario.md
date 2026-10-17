# Mantix · RBAC con herencia — inventario y propuesta (antes de la Fase 1)

Documento de revisión. Describe lo que existe hoy, lo que falta, el catálogo de permisos propuesto, el mapeo de roles, las brechas de seguridad encontradas y el inventario completo de endpoints y pantallas. **No se ha escrito código del RBAC todavía.**

## 1. Qué existe hoy

**Autenticación.** Clerk (no hay JWT propio ni refresh tokens en Mantix). El backend verifica la sesión de Clerk (`app/core/clerk.py`), resuelve o crea el usuario local (`ClerkAuthService.resolve_local_user`) y construye un `AuthContext` con los roles y permisos *directos* de sus roles activos. El renovado del token lo hace el SDK de Clerk en el navegador; el interceptor ya adjunta el token y gestiona la sesión.

**Modelo.** Tablas `users`, `roles`, `permissions`, `user_roles`, `role_permissions` (tabla puente). Los roles tienen `code`, `name`, `is_active`; los permisos, `code` (formato `recurso.accion`, p. ej. `equipment.manage`), `module`, `is_active`. Roles sembrados por migración: `ADMIN`, `SUPERVISOR`, `TECHNICIAN`, `EMPLOYEE`. La matriz por defecto vive en `app/core/permissions.py` y un test la compara con la base.

**Backend.** `require_permission(codigo)` y `require_role(...)` en `app/api/dependencies.py`; `AuthContext` en `app/core/authz.py`; endpoints `/admin/roles`, `/admin/roles/matrix`, `/admin/permissions` (solo lectura), asignar/quitar roles, reglas de "último administrador". `test_rbac.py` recorre todas las rutas y comprueba la matriz.

**Frontend.** `LocalProfileService` (perfil de `/auth/me` con permisos), guards `permissionGuard` y `roleGuard`, menú filtrado por permiso/rol (`nav-items.ts`), pantalla 403 (`/acceso-denegado`) y pantalla de cuenta pendiente. Cada pantalla decide sus botones con `profile.can('...')`.

## 2. Qué falta (frente a lo que pides)

| Pedido | Estado |
|---|---|
| Herencia entre roles (padre/hijo, recursiva, sin ciclos, con caché) | **No existe.** Los roles son planos. |
| Permisos `recurso:acción` en español | **No existe.** Hay 16 permisos gruesos en inglés con punto (`equipment.manage` mezcla crear, editar, custodia, importar…). |
| Alcance de datos en el **Repository** | **Parcial y en el lugar equivocado:** está en los servicios (`maintenance`, `dashboard`, `queue`, `attachment`, `export`) y se decide por **código de rol** (`is_elevated`), no por permiso. Un rol personalizado no funcionaría. |
| Transiciones por rol en el State Pattern | **Parcial:** `_require_can_act` (asignado o supervisor) y `_require_elevated`; falta una tabla "estado→estado permitido por permiso". |
| Auditar accesos denegados (403) y cambios en la matriz | **No existe.** Sí se audita asignar/quitar rol. |
| Reglas: rol no concede lo que no tiene; nadie se sube el rol; solo Administrador asigna | **Parcial:** último admin y "no revocarte el tuyo" sí; "no conceder permisos que no tienes" y auto-escalada con un rol personalizado, no. |
| Mensajes 403 claros en español | Hoy: `"insufficient permissions"` (inglés). |
| Directiva `*hasPermission`, servicio único, Kanban por rol, dashboard por rol, matriz editable | **No existen.** |
| Un test que falle si una ruta no declara permiso | **Parcial:** `test_rbac` exige permiso salvo las rutas "solo sesión" (`ctx`/`user`), que hoy pasan sin declarar nada. |

## 3. Roles: mapeo con lo existente (no se duplica ninguno)

| Propuesta | Rol actual | Cambio |
|---|---|---|
| Solicitante | `EMPLOYEE` | Solo renombrar la etiqueta visible a "Solicitante" (el código no cambia). |
| Técnico (hereda Solicitante) | `TECHNICIAN` | Pasa a heredar de `EMPLOYEE`: **gana** crear solicitudes (hoy no puede). |
| Supervisor (hereda Técnico) | `SUPERVISOR` | Hereda de `TECHNICIAN`. |
| Administrador (hereda Supervisor) | `ADMIN` | Hereda de `SUPERVISOR`. |
| Auditor (opcional, sin herencia operativa) | — | **Rol nuevo** `AUDITOR` (reportes + auditoría, solo lectura). Lo propongo; dime si lo quieres. |

Los cuatro roles base se marcan `is_system` (no se eliminan ni se renombra su código).

### Diferencias de comportamiento respecto a hoy (a confirmar)

1. **Auditoría:** hoy el Supervisor tiene `audit.read`; en tu propuesta es del Administrador. Quedaría solo Administrador (y Auditor).
2. **Importaciones masivas** (equipos e inventario): hoy las hace el Supervisor (`equipment.manage` / `inventory.manage`); en tu propuesta, solo Administrador.
3. **Solicitante hoy ve Mantenimiento, Técnicos y Equipos completos** (porque `maintenance.read` es una sola llave): ver el calendario/planes preventivos y la lista de técnicos con su **tarifa por hora**. En la propuesta pierde `mantenimiento:ver` y `tecnicos:ver`. Conserva `equipos:ver` (lo necesita para elegir el equipo al crear una solicitud), pero **sin costo de compra**.
4. **Dashboard del Solicitante:** hoy no tiene `dashboard.read` aunque la pantalla se abre (los datos fallan con 403). En la propuesta tiene `dashboard:ver` con sus propias solicitudes.
5. **Técnico** gana: crear solicitudes (por herencia). Pierde: nada.
6. **Configuración:** hoy mezcla `users.manage` (salud, organización) y `priorities.manage` (catálogos). Pasa a `configuracion:ver/editar`, solo Administrador.

## 4. Catálogo de permisos propuesto (`recurso:acción`)

Acciones fuera de tu lista que necesito añadir porque las usan pantallas reales: **`ver_asignados`**, **`ver_todos`** (alcance de datos), **`adjuntar`** (subir archivos) y **`consumir`** (descontar inventario). Las demás son las tuyas. No creo permisos sin uso (por ejemplo `eliminar` en tickets o equipos: hoy no existe esa operación en la API).

Alcance de datos, por permisos (no por nombre de rol, así sirve para roles personalizados):
`<recurso>:ver_todos` → todo · `<recurso>:ver_asignados` → lo asignado a la persona (y lo suyo) · `<recurso>:ver` → solo lo propio.

| Recurso | Acciones |
|---|---|
| dashboard | `ver`, `ver_todos` |
| equipos | `ver`, `crear`, `editar`, `asignar` (custodia), `adjuntar`, `exportar`, `importar` |
| solicitudes | `ver`, `ver_todos`, `crear`, `editar` (clasificar), `aprobar` (aceptar/rechazar) |
| tickets | `ver`, `ver_asignados`, `ver_todos`, `editar` (registrar trabajo), `asignar`, `cambiar_estado`, `adjuntar`, `exportar` |
| tecnicos | `ver`, `crear`, `editar`, `exportar` |
| mantenimiento | `ver`, `crear`, `editar` |
| inventario | `ver`, `crear`, `editar`, `eliminar`, `consumir`, `importar`, `exportar` |
| reportes | `ver`, `exportar` |
| usuarios | `ver`, `crear`, `editar`, `cambiar_estado`, `asignar` (roles) |
| perfil | `ver`, `editar` |
| configuracion | `ver`, `editar` (incluye organización, catálogos y la matriz de roles) |
| auditoria | `ver` |

### Asignación inicial (solo lo **propio** de cada rol; el resto se hereda)

| Rol | Permisos propios | Hereda de |
|---|---|---|
| Solicitante (`EMPLOYEE`) | `dashboard:ver`, `perfil:ver`, `perfil:editar`, `solicitudes:ver`, `solicitudes:crear`, `tickets:ver`, `tickets:adjuntar`, `equipos:ver` | — |
| Técnico (`TECHNICIAN`) | `tickets:ver_asignados`, `tickets:editar`, `tickets:cambiar_estado`, `mantenimiento:ver`, `inventario:ver`, `inventario:consumir`, `tecnicos:ver` | Solicitante |
| Supervisor (`SUPERVISOR`) | `dashboard:ver_todos`, `solicitudes:ver_todos`, `solicitudes:editar`, `solicitudes:aprobar`, `tickets:ver_todos`, `tickets:asignar`, `tickets:exportar`, `tecnicos:crear`, `tecnicos:editar`, `tecnicos:exportar`, `mantenimiento:crear`, `mantenimiento:editar`, `inventario:crear`, `inventario:editar`, `inventario:exportar`, `equipos:crear`, `equipos:editar`, `equipos:asignar`, `equipos:adjuntar`, `equipos:exportar`, `reportes:ver`, `reportes:exportar` | Técnico |
| Administrador (`ADMIN`) | `usuarios:ver`, `usuarios:crear`, `usuarios:editar`, `usuarios:cambiar_estado`, `usuarios:asignar`, `configuracion:ver`, `configuracion:editar`, `auditoria:ver`, `equipos:importar`, `inventario:importar`, `inventario:eliminar` | Supervisor |
| Auditor (`AUDITOR`, opcional) | `dashboard:ver`, `dashboard:ver_todos`, `perfil:ver`, `perfil:editar`, `reportes:ver`, `reportes:exportar`, `auditoria:ver` | — |

**Expandir y contraer (para no romper nada entre fases).** En la Fase 1 los permisos nuevos se **añaden** junto a los actuales (que siguen funcionando); en la Fase 2 cada endpoint pasa al permiso nuevo y una migración final retira los antiguos. Equivalencias principales: `equipment.read`→`equipos:ver`; `equipment.manage`→`equipos:crear/editar/asignar/importar`; `maintenance.read`→`tickets:ver`/`mantenimiento:ver`; `maintenance.create`→`solicitudes:crear`; `maintenance.manage`→`tickets:asignar/cambiar_estado/editar` + `solicitudes:editar/aprobar`; `technicians.manage`→`tecnicos:crear/editar`; `users.manage`→`usuarios:*` + `configuracion:*`; `priorities.manage`→`configuracion:editar`; `dashboard.read`→`dashboard:ver`; `reports.read`→`reportes:ver/exportar`; `audit.read`→`auditoria:ver`; `attachments.write`→`tickets:adjuntar`/`equipos:adjuntar`; `schedules.manage`→`mantenimiento:crear/editar`; `inventory.read/manage/consume`→`inventario:ver/crear-editar-importar/consumir`.

## 5. Brechas de seguridad encontradas hoy

1. **Fuga de datos al Solicitante.** Con `maintenance.read` / `equipment.read` un Solicitante puede pedir `GET /technicians` (ve **tarifa por hora** de cada técnico), `GET /equipment` (ve **costo de compra**), `GET /maintenance/schedules`, `/calendar` y `/overview` (planes preventivos de toda la empresa). Son endpoints sin alcance de datos.
2. **Autorización por código de rol, no por permiso** (`is_elevated`, `require_role`, `roleGuard`): un rol personalizado con los permisos "correctos" seguiría sin poder hacer nada, y cualquiera con el código `SUPERVISOR` hereda poderes ocultos.
3. **Alcance en los servicios, no en el repositorio:** cada consulta nueva debe acordarse de filtrar. Hoy lo hacen mantenimiento, dashboard, cola y exportaciones; las listas de equipos, inventario y técnicos no filtran porque no hay concepto de alcance.
4. **Rutas "solo sesión" sin permiso declarado:** adjuntos (descargar/borrar) y todo `/profile` y `/notifications`. La regla está dentro del servicio (adjuntos) o es inherentemente propia (perfil), pero no figura en la declaración de la ruta y el test no lo detecta.
5. **Un rol personalizado con `users.manage` podría asignarse `ADMIN` a sí mismo** (no existe la regla "un rol no concede lo que no tiene").
6. **Los 403 no se auditan** y el mensaje está en inglés.
7. **Dashboard del Solicitante inconsistente:** la ruta abre pero sus endpoints devuelven 403.
8. El **nombre del rol** se usa en el frontend (`roleGuard('maintenance.manage','ADMIN','SUPERVISOR')`) para la pantalla Solicitudes.

## 6. Inventario de endpoints (111)

`Guardia actual` es lo que declara hoy la ruta; `Permiso propuesto` es el de la matriz anterior (la Fase 2 lo aplicará).

| Método | Endpoint | Guardia actual | Permiso propuesto | Alcance / regla extra |
|---|---|---|---|---|
| GET | `/admin/permissions` | users.manage | `configuracion:ver` |  |
| GET | `/admin/roles` | users.manage | `usuarios:ver` |  |
| GET | `/admin/roles/matrix` | users.manage | `configuracion:ver` |  |
| GET | `/admin/users` | users.manage | `usuarios:ver` |  |
| POST | `/admin/users` | users.manage | `usuarios:crear` |  |
| GET | `/admin/users/pending` | users.manage | `usuarios:ver` |  |
| GET | `/admin/users/summary` | users.manage | `usuarios:ver` |  |
| GET | `/admin/users/{user_id}` | users.manage | `usuarios:ver` |  |
| PATCH | `/admin/users/{user_id}` | users.manage | `usuarios:editar` |  |
| POST | `/admin/users/{user_id}/activate` | users.manage | `usuarios:cambiar_estado` |  |
| POST | `/admin/users/{user_id}/deactivate` | users.manage | `usuarios:cambiar_estado` | no a sí mismo / último admin |
| POST | `/admin/users/{user_id}/password` | users.manage | `usuarios:editar` | no a sí mismo |
| POST | `/admin/users/{user_id}/roles` | users.manage | `usuarios:asignar` | no a sí mismo; no roles con más permisos |
| PUT | `/admin/users/{user_id}/roles` | users.manage | `usuarios:asignar` | no a sí mismo; no roles con más permisos |
| DELETE | `/admin/users/{user_id}/roles/{role_id}` | users.manage | `usuarios:asignar` | no último admin |
| DELETE | `/attachments/{attachment_id}` | solo sesión | `tickets:adjuntar / equipos:adjuntar` | quien lo subió o ver_todos |
| GET | `/attachments/{attachment_id}/download` | solo sesión | `tickets:ver / equipos:ver` | según el registro padre |
| GET | `/audit-logs` | audit.read | `auditoria:ver` |  |
| GET | `/auth/me` | solo sesión | `(autenticado)` | propio |
| GET | `/dashboard/alerts` | dashboard.read | `dashboard:ver` | propio / asignado / todo |
| GET | `/dashboard/kpis` | dashboard.read | `dashboard:ver` | propio / asignado / todo |
| GET | `/dashboard/resolution-times` | dashboard.read | `dashboard:ver` | propio / asignado / todo |
| GET | `/dashboard/summary` | dashboard.read | `dashboard:ver` | propio / asignado / todo |
| GET | `/dashboard/technicians` | dashboard.read | `dashboard:ver_todos` |  |
| GET | `/dashboard/top-failing-equipment` | dashboard.read | `dashboard:ver_todos` |  |
| GET | `/dashboard/trends` | dashboard.read | `dashboard:ver` | propio / asignado / todo |
| GET | `/dashboard/workload` | dashboard.read | `dashboard:ver_todos` |  |
| GET | `/equipment` | equipment.read | `equipos:ver` |  |
| POST | `/equipment` | equipment.manage | `equipos:crear` |  |
| GET | `/equipment/custodian-candidates` | equipment.manage | `equipos:asignar` |  |
| GET | `/equipment/summary` | equipment.read | `equipos:ver` |  |
| GET | `/equipment/types` | equipment.read | `equipos:ver` |  |
| GET | `/equipment/{equipment_id}` | equipment.read | `equipos:ver` |  |
| PATCH | `/equipment/{equipment_id}` | equipment.manage | `equipos:editar` |  |
| GET | `/equipment/{equipment_id}/attachments` | equipment.read | `equipos:ver` |  |
| POST | `/equipment/{equipment_id}/attachments` | attachments.write | `equipos:adjuntar` |  |
| POST | `/equipment/{equipment_id}/custody` | equipment.manage | `equipos:asignar` |  |
| POST | `/equipment/{equipment_id}/location` | equipment.manage | `equipos:editar` |  |
| POST | `/imports/equipment` | equipment.manage | `equipos:importar` |  |
| POST | `/inventory/import` | inventory.manage | `inventario:importar` |  |
| GET | `/inventory/import/template` | inventory.manage | `inventario:importar` |  |
| GET | `/inventory/items` | inventory.read | `inventario:ver` |  |
| POST | `/inventory/items` | inventory.manage | `inventario:crear` |  |
| DELETE | `/inventory/items/{item_id}` | inventory.manage | `inventario:eliminar` |  |
| GET | `/inventory/items/{item_id}` | inventory.read | `inventario:ver` |  |
| PATCH | `/inventory/items/{item_id}` | inventory.manage | `inventario:editar` |  |
| GET | `/inventory/items/{item_id}/movements` | inventory.read | `inventario:ver` |  |
| POST | `/inventory/items/{item_id}/movements` | inventory.consume | `inventario:consumir` | entradas/ajustes: inventario:editar |
| GET | `/inventory/options` | inventory.read | `inventario:ver` |  |
| POST | `/inventory/options` | inventory.manage | `inventario:crear` |  |
| GET | `/inventory/overview` | inventory.read | `inventario:ver` |  |
| GET | `/locations` | equipment.read | `equipos:ver` |  |
| POST | `/locations` | equipment.manage | `equipos:crear` |  |
| GET | `/maintenance/calendar` | maintenance.read | `mantenimiento:ver` |  |
| GET | `/maintenance/categories` | maintenance.read | `tickets:ver` |  |
| GET | `/maintenance/overview` | maintenance.read | `mantenimiento:ver` |  |
| GET | `/maintenance/queue/summary` | rol ADMIN/SUPERVISOR | `solicitudes:ver_todos` |  |
| GET | `/maintenance/requests` | maintenance.read | `tickets:ver` | propio / asignado / todo |
| POST | `/maintenance/requests` | maintenance.create | `solicitudes:crear` |  |
| GET | `/maintenance/requests/workflow` | maintenance.read | `tickets:ver` | propio / asignado / todo |
| GET | `/maintenance/requests/{request_id}` | maintenance.read | `tickets:ver` | propio / asignado / todo |
| DELETE | `/maintenance/requests/{request_id}/assignment` | maintenance.manage | `tickets:asignar` |  |
| POST | `/maintenance/requests/{request_id}/assignment` | maintenance.manage | `tickets:asignar` |  |
| GET | `/maintenance/requests/{request_id}/attachments` | maintenance.read | `tickets:ver` | propio / asignado / todo |
| POST | `/maintenance/requests/{request_id}/attachments` | attachments.write | `tickets:adjuntar` | propio / asignado / todo |
| POST | `/maintenance/requests/{request_id}/classify` | maintenance.manage | `solicitudes:editar` |  |
| GET | `/maintenance/requests/{request_id}/records` | maintenance.read | `tickets:ver` | propio / asignado / todo |
| POST | `/maintenance/requests/{request_id}/records` | maintenance.manage | `tickets:editar` | asignado / todo |
| POST | `/maintenance/requests/{request_id}/reject` | maintenance.manage | `solicitudes:aprobar` |  |
| POST | `/maintenance/requests/{request_id}/status` | maintenance.manage | `tickets:cambiar_estado` | transición permitida al rol; asignado / todo |
| GET | `/maintenance/schedules` | maintenance.read | `mantenimiento:ver` |  |
| POST | `/maintenance/schedules` | schedules.manage | `mantenimiento:crear` |  |
| POST | `/maintenance/schedules/run-reminders` | schedules.manage | `mantenimiento:editar` |  |
| GET | `/maintenance/schedules/{schedule_id}` | maintenance.read | `mantenimiento:ver` |  |
| PATCH | `/maintenance/schedules/{schedule_id}` | schedules.manage | `mantenimiento:editar` |  |
| POST | `/maintenance/schedules/{schedule_id}/complete` | schedules.manage | `mantenimiento:editar` |  |
| GET | `/maintenance/schedules/{schedule_id}/history` | maintenance.read | `mantenimiento:ver` |  |
| GET | `/notifications` | solo sesión | `(autenticado)` | propio |
| POST | `/notifications/read-all` | solo sesión | `(autenticado)` | propio |
| POST | `/notifications/{notification_id}/read` | solo sesión | `(autenticado)` | propio |
| GET | `/priorities` | maintenance.read | `tickets:ver` |  |
| POST | `/priorities` | priorities.manage | `configuracion:editar` |  |
| PATCH | `/priorities/{priority_id}` | priorities.manage | `configuracion:editar` |  |
| GET | `/profile` | solo sesión | `perfil:ver` | propio |
| PATCH | `/profile` | solo sesión | `perfil:editar` | propio |
| DELETE | `/profile/avatar` | solo sesión | `perfil:editar` | propio |
| GET | `/profile/avatar` | solo sesión | `perfil:ver` | propio |
| PUT | `/profile/avatar` | solo sesión | `perfil:editar` | propio |
| GET | `/profile/history` | solo sesión | `perfil:ver` | propio |
| POST | `/profile/password` | solo sesión | `perfil:editar` | propio |
| GET | `/reports/catalog` | reports.read | `reportes:ver` |  |
| GET | `/reports/equipment` | reports.read | `reportes:ver` |  |
| POST | `/reports/generate` | reports.read | `reportes:ver` | propio / asignado / todo |
| GET | `/reports/history` | reports.read | `reportes:ver` | propio |
| GET | `/reports/overview` | reports.read | `reportes:ver` |  |
| POST | `/reports/preview` | reports.read | `reportes:ver` | propio / asignado / todo |
| GET | `/reports/summary` | reports.read | `reportes:ver` |  |
| GET | `/reports/tickets` | reports.read | `reportes:ver` | propio / asignado / todo |
| POST | `/reports/{report}/export` | reports.read | `reportes:exportar (+ <recurso>:exportar)` | propio / asignado / todo |
| POST | `/reports/{report}/export/count` | reports.read | `reportes:exportar` | propio / asignado / todo |
| GET | `/reports/{report}/export/options` | reports.read | `reportes:exportar` |  |
| GET | `/settings/categories` | priorities.manage | `configuracion:ver` |  |
| POST | `/settings/categories` | priorities.manage | `configuracion:editar` |  |
| DELETE | `/settings/categories/{category_id}` | priorities.manage | `configuracion:editar` |  |
| PATCH | `/settings/categories/{category_id}` | priorities.manage | `configuracion:editar` |  |
| GET | `/settings/health` | users.manage | `configuracion:ver` |  |
| GET | `/settings/organization` | users.manage | `configuracion:ver` |  |
| PUT | `/settings/organization` | users.manage | `configuracion:editar` |  |
| GET | `/technicians` | maintenance.read | `tecnicos:ver` | sin tarifa salvo tecnicos:editar |
| POST | `/technicians` | technicians.manage | `tecnicos:crear` |  |
| PATCH | `/technicians/{technician_id}` | technicians.manage | `tecnicos:editar` |  |

Total: 111

## 7. Inventario de pantallas y acciones

| Pantalla (ruta) | Hoy | Permiso para entrar | Acciones a condicionar |
|---|---|---|---|
| Dashboard (`/dashboard`) | `authorizedGuard` (cualquier rol) | `dashboard:ver` | Bloques globales (carga de técnicos, equipos con más fallas, KPIs de toda la empresa): `dashboard:ver_todos` |
| Equipos (`/equipos`, detalle) | `equipment.read` | `equipos:ver` | Nuevo, editar, custodia, ubicación, adjuntar, importar, exportar; ocultar costo de compra sin `equipos:editar` |
| Tickets (`/tickets`) | `maintenance.read` | `tickets:ver` (+ alcance) | Nueva solicitud (`solicitudes:crear`), arrastrar en el Kanban (`tickets:cambiar_estado`, solo destinos permitidos), asignar/reasignar (`tickets:asignar`), registrar trabajo (`tickets:editar`), adjuntar, exportar |
| Solicitudes (`/solicitudes`) | `roleGuard(maintenance.manage, ADMIN, SUPERVISOR)` | `solicitudes:ver_todos` | Clasificar (`solicitudes:editar`), aceptar/rechazar (`solicitudes:aprobar`), asignar (`tickets:asignar`), Kanban |
| Técnicos (`/technicians`) | `maintenance.read` | `tecnicos:ver` | Nuevo, editar, disponibilidad, tarifa (solo `tecnicos:editar`), exportar |
| Mantenimiento (`/mantenimiento`) | `maintenance.read` | `mantenimiento:ver` | Crear plan, editar, completar, recordatorios (`mantenimiento:crear/editar`) |
| Inventario (`/inventario`) | `inventory.read` | `inventario:ver` | Nuevo ítem, editar, eliminar, importar, exportar, entradas/ajustes (`editar`) y consumo (`consumir`) |
| Reportes (`/reportes`) | `reports.read` | `reportes:ver` | Generar, vista previa, exportar PDF/Excel (`reportes:exportar`) |
| Usuarios (`/usuarios`, pendientes) | `users.manage` | `usuarios:ver` | Nuevo, editar, activar/desactivar, restablecer contraseña, asignar roles |
| Configuración (`/configuracion`) | `users.manage` | `configuracion:ver` | Editar organización, catálogos, matriz de roles (`configuracion:editar`) |
| Perfil (`/perfil`) | `authorizedGuard` | `perfil:ver` (todos los roles) | Editar datos, foto, contraseña |

## 8. Decisiones que necesito de ti antes de la Fase 1

1. **Naming/migración:** ¿apruebas el esquema *expandir y contraer* (permisos nuevos conviviendo con los viejos durante la Fase 1 y retirada de los viejos al final de la Fase 2)?
2. **¿Creo el rol `AUDITOR`?**
3. **Diferencias de la sección 3** (Supervisor sin auditoría ni importaciones; Solicitante sin Mantenimiento/Técnicos/costos): ¿las confirmas o quieres conservar alguna como hoy?
4. **Acciones extra** `ver_asignados`, `ver_todos`, `adjuntar`, `consumir`: ¿de acuerdo? Alternativa: codificar el alcance por nombre de rol (peor para roles personalizados).
5. **Git:** el árbol de trabajo tiene sin commitear todo lo de las fases 5–8 y los ajustes de CI. Para "commit por fase" limpio, te propongo **primero commitear ese trabajo en ramas/commits por tema** (Inventario, Reportes, Usuarios, Perfil, Configuración, CI) y luego abrir la rama `feat/rbac-model` para la Fase 1. ¿Lo hago así?
