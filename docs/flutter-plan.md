# Plan de la app móvil (Flutter)

Decisiones y reglas aprobadas para migrar Mantix a una app móvil. La app reutiliza la API FastAPI existente sin romper la web.

## Decisiones

| Tema | Decisión |
| --- | --- |
| Plataformas | Solo Android |
| Identificador | `com.suleysuarez.mantix`; nombre visible «Mantix» |
| Ubicación | Un solo repositorio de GitHub (`MANTIX`) con dos carpetas: `WEB/` (backend, frontend, docs de la web y Compose) y `MOVIL/` (el proyecto Flutter). En local, la app se desarrolla en `MANTIX-MOVIL`, una copia de trabajo (git worktree) del mismo repositorio |
| Autenticación | Clerk es el proveedor actual. La decisión final se toma tras la Fase 0.5 (prueba de concepto con el SDK de Clerk para Flutter, rama desechable `spike/clerk-flutter`). El refresco y la rotación de tokens los gestiona Clerk, no el backend |
| Permisos | Solo los permisos efectivos de `GET /auth/me`; nunca nombres de rol. Los permisos solo ocultan y deshabilitan: la autorización real es del backend |
| Cuenta pendiente | Lista de **roles** vacía (igual que la web) → pantalla «pendiente de aprobación». Con roles pero **cero permisos** → pantalla «Sin acceso asignado». Son dos casos distintos |
| Home | Función pura `home_resolver` sobre los permisos; el primero que coincida (ver abajo); si ninguno, Perfil |
| Rol Auditor | Fuera de la app móvil: sin home, sin pantallas y sin tests propios. El backend y la web no se tocan; si alguien tiene ese rol, la app lo trata como cualquier rol, por sus permisos |
| Offline | Fuera de la primera versión |
| Push (Firebase/FCM) | Fase 8; claves por variables de entorno |
| Hosting de la API | Aún no definido. En desarrollo: `http://10.0.2.2:8000` (emulador) o red local/túnel |
| Versionado | Sin prefijo `/v1`: cabecera `X-App-Version` y versión mínima configurable en el servidor para forzar actualización |
| Tráfico HTTP sin cifrar | `usesCleartextTraffic` solo en el manifiesto de debug (`android/app/src/debug`), nunca en el principal |
| Paginación | Los listados envían `size=20` explícito (el backend usa 200 en tickets) |
| Tipografía | Plus Jakarta Sans, pero con la fuente por defecto hasta tener los `.ttf` (la web la carga desde Google Fonts en woff2, que Flutter no admite; no hay `.ttf` en el repositorio) |

### Orden del home (permisos)

1. `dashboard:ver_todos` **y** `tickets:ver_todos` → dashboard global.
2. `tickets:ver_asignados` → bandeja de trabajo asignada.
3. `solicitudes:ver` → mis solicitudes.
4. `reportes:ver` → reportes.
5. `dashboard:ver` → dashboard propio.
6. Ninguno → Perfil.

Comprobado contra `backend/app/core/permissions.py`: todos esos códigos existen. Un rol que tenga `dashboard:ver_todos` pero no `tickets:ver_todos` (por ejemplo, uno personalizado) cae en reportes (paso 4) y no en el dashboard.

## Reglas generales

- Se trabaja **por fases** y se **detiene al terminar cada una**. No se avanza sin aprobación explícita.
- Responde solo con lo que existe; si algo no existe, «no existe». No supongas.
- **No romper la web:** todo cambio de backend es retrocompatible y los tests existentes siguen pasando.
- **Backend «justo a tiempo»:** se cambia solo lo que la fase en curso necesita. Lo que falte se anota en «Pendientes de backend».
- **Seguridad:** el token va en almacenamiento seguro, nunca en preferencias planas. Ningún secreto, clave ni URL real en el código: todo por `--dart-define` o archivos ignorados por Git.
- **Identidad visual:** paleta `#ADD7F6`, `#A2D2FF`, `#3E5C76`, `#778DA9`, `#CED4DA`, mostaza `#E4B363` y navy `#0B172A`, centralizada en un tema; ningún color suelto en los widgets. Glass solo en elementos puntuales. Contraste WCAG AA, etiquetas semánticas, objetivos táctiles de al menos 48 px y respeto a la escala de texto del sistema.
- **Interfaz en español**, con mensajes de error específicos y sin detalles internos.
- **Validación en el cliente** (fechas coherentes, sin negativos, trim y longitudes, archivos por tipo y tamaño); el backend es la fuente de verdad y sus 422 se muestran bajo el campo.
- **Cada pantalla** maneja cargando (skeleton), vacío (con ilustración), error (con reintento) y con datos. Scroll infinito con las cabeceras de paginación.
- Imágenes, íconos o animaciones que falten: se piden con nombre, medidas y formato.
- Una fase = una rama o commits propios. Al cerrar cada fase se actualiza este documento.
- **Tests por fase:** lo crítico con pruebas unitarias y de widgets; todo endpoint nuevo con tests de backend (200, 401, 403, 422 y casos límite).

### Entregables al cierre de cada fase

1. Qué se hizo y por qué. 2. Archivos creados o modificados. 3. Cómo ejecutarlo y probarlo. 4. Resultado de los tests. 5. Pendientes y puntos débiles. 6. Lo que se necesita del usuario.

## Arquitectura propuesta

Riverpod (estado), Dio (HTTP; interceptor con `QueuedInterceptor` para una sola renovación aunque fallen varias peticiones), `go_router` con `redirect` por sesión y permiso, `flutter_secure_storage`, `freezed` y `json_serializable`. Cliente HTTP escrito a mano (no generado desde OpenAPI). Carpetas `lib/{core,shared,features/<módulo>/{data,domain,presentation}}`.

Errores: tipo sellado `Failure` (red, 401, 403, 404, 409, 422 con campos, servidor). Se mapea por el campo `code`; un `code` desconocido se mapea por el estado HTTP, sin romper.

## Fases

| Fase | Contenido |
| --- | --- |
| 0 | Auditoría de reutilización (hecha) |
| 0.5 | Prueba de concepto de autenticación con Clerk |
| 1 | Backend mínimo: códigos de error específicos y estables con tabla documentada, corregir la descripción obsoleta de `/equipment/{id}/attachments` y la lista de roles en `main.py`, exportar el OpenAPI como artefacto de CI |
| 2 | Base Flutter y autenticación |
| 3 | Componentes y sistema de diseño |
| 4 | Solicitante |
| 5 | Técnico |
| 6 | Supervisor |
| 7 | Administrador |
| 8 | Capacidades móviles (push, escaneo de QR) |
| 9 | Calidad y entrega |

Antes de la Fase 4 hay que verificar y reportar el alcance de datos de equipos para el Solicitante y la búsqueda por `asset_tag`.

## Contrato de la API que usa la app

- Listados: array JSON plano; total en `X-Total-Count`, `X-Page`, `X-Page-Size`, `X-Total-Pages`. Parámetros `page`, `size` (máximo 500), `sort`, `search`. `/notifications` es la excepción (`limit`, `offset`, `{unread_count, items}`).
- Errores: `{detail, code, errors: [{field, message, type}] | null, request_id}`.
- Estados del ticket: `GET /maintenance/requests/workflow`.
- Referencia completa: `docs/api-reference.md`.

## Pendientes de backend

(Se completa durante el desarrollo: archivo, motivo y fase que lo necesita.)
