# Plan de la app móvil (Flutter)

Decisiones y reglas aprobadas para migrar Mantix a una app móvil. La app usa la API FastAPI sin romper la web. Desde la Fase 0.5 corre contra una **copia propia del backend** (`MOVIL/backend`), para no tocar `WEB/backend`.

## Decisiones

| Tema | Decisión |
| --- | --- |
| Plataformas | Solo Android |
| Identificador | `com.suleysuarez.mantix`; nombre visible «Mantix» |
| Ubicación | Un solo repositorio de GitHub (`MANTIX`) con dos carpetas: `WEB/` (backend, frontend, docs de la web y Compose) y `MOVIL/` (el proyecto Flutter). En local, la app se desarrolla en `MANTIX-MOVIL`, una copia de trabajo (git worktree) del mismo repositorio. `MOVIL/` incluye además `backend/` (copia de `WEB/backend` con ajustes para Clerk nativo) y su propio `docker-compose.yml`, con base de datos y puertos aparte del stack de la web |
| Autenticación (**OBSOLETO en el móvil**, se conserva como historial; vigente: fila siguiente) | **Clerk**, con `clerk_flutter` (beta, mantenido por la comunidad, no es oficial de Clerk). Probado con un inicio de sesión real: ver «Resultados de la Fase 0.5». El refresco y la rotación de tokens los gestiona Clerk, no el backend. La publishable key entra por `--dart-define`; la secret key vive solo en el backend |
| Backend del móvil (**OBSOLETO en lo del `azp`**: la app ya no usa tokens de Clerk; la web sí) | Copia propia en `MOVIL/backend`; `WEB/backend` no se modifica. Los tokens de Clerk del móvil no traen el claim `azp`, y el SDK del backend rechaza un token sin `azp` si hay orígenes autorizados configurados. La copia valida el `azp` por su cuenta: si el token lo trae debe estar en `CLERK_AUTHORIZED_PARTIES`; si no lo trae, el SDK sigue verificando firma, emisor y expiración. **Riesgo asumido:** las dos copias pueden divergir, y cualquier arreglo en una habrá que repetirlo en la otra |
| Permisos | Solo los permisos efectivos de `GET /auth/me`; nunca nombres de rol. Los permisos solo ocultan y deshabilitan: la autorización real es del backend |
| Autenticación (**vigente**) | Nativa de Mantix: correo y contraseña, con verificación por código enviado por SMTP. La web Angular sigue con Clerk. Detalle en «Autenticación nativa del móvil (vigente)» |
| Cuenta pendiente | Lista de **roles** vacía (igual que la web) → pantalla «pendiente de aprobación». Con roles pero **cero permisos** → pantalla «Sin acceso asignado». Son dos casos distintos |
| Home | Función pura `home_resolver` sobre los permisos; el primero que coincida (ver abajo); si ninguno, Perfil |
| Rol Auditor | Fuera de la app móvil: sin home, sin pantallas y sin tests propios. El backend y la web no se tocan; si alguien tiene ese rol, la app lo trata como cualquier rol, por sus permisos |
| Offline | Fuera de la primera versión |
| Push (Firebase/FCM) | Fase 8; claves por variables de entorno |
| Hosting de la API | Aún no definido. En desarrollo el backend del móvil escucha en el puerto 8001: `http://10.0.2.2:8001` (emulador) o `http://localhost:8001` en un teléfono por USB con `adb reverse tcp:8001 tcp:8001` |
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

## Arquitectura: BLoC para todo el proyecto

**Decisión (reemplaza a Riverpod):** todo el estado de la app va en `flutter_bloc`. Riverpod se retiró en la migración (commit `refactor(mobile): migrate the app from Riverpod to BLoC`).

Paquetes: `flutter_bloc` 9.1.1, `bloc` 9.2.1, `equatable` 3.0.0; en pruebas `bloc_test` 10.0.0 y `mocktail` 1.0.5. Dio (HTTP; interceptor con `QueuedInterceptor` para una sola renovación aunque fallen varias peticiones), `go_router` con `redirect` por sesión y permiso y `flutter_secure_storage` (aún sin uso: ver Fase 9). Cliente HTTP escrito a mano (no generado desde OpenAPI). **Los modelos se escriben a mano con `Equatable`**: `freezed`, `json_serializable` y `build_runner` se retiraron porque no tenían ni un archivo generado y `build_runner` ≥ 2.16.2 no resuelve junto con `bloc_test` en este SDK. El código generado se puede reevaluar más adelante.

### Reglas

1. Cada flujo con eventos (auth, listados, detalle, formularios, dashboard…) es un **Bloc** con tres archivos en `bloc/<mod>/`: `<x>_bloc.dart`, `<x>_event.dart` y `<x>_state.dart` (los dos últimos con `part of`).
2. Un **Cubit** solo para estado derivado o trivial. Hoy hay uno: `PermissionsCubit`, derivado del `AuthBloc`, sin eventos propios. El filtro de estado de «Mis solicitudes» y el texto del buscador de equipos son estado efímero de la pantalla (`setState`); al cambiar, la pantalla crea un Bloc nuevo con una `key`.
3. Las pantallas solo reaccionan con `BlocBuilder`, `BlocListener`, `BlocSelector` o `context.select`; ninguna llama a un repositorio ni a Dio.
4. Los estados son `Equatable` y explícitos (inicial/cargando, éxito, vacío y error con el `Failure` sellado). **Ningún estado guarda tokens.** Los eventos son clases selladas.
5. Inyección sin `get_it`: `RepositoryProvider` y `BlocProvider` en la raíz (`MantixApp`) y un `BlocProvider` por pantalla (ruta) para los Bloc de esa pantalla.
6. `go_router` solo reacciona al estado de sesión (`refreshListenable` sobre el stream del `AuthBloc`); `redirectFor` y `resolveHome` son funciones puras.
7. El cliente HTTP no depende de widgets ni de Bloc: avisa de la sesión expirada con el callback `onSessionExpired`, que `main.dart` conecta al `AuthBloc`.
8. Los Bloc procesan los eventos **de uno en uno**. Si un evento no debe repetirse mientras hay otro igual en curso (por ejemplo «cargar más»), se descarta antes de encolarlo, como hace `PagedBloc`.

### Estructura

```
lib/
  main.dart
  pages/<mod>/ widgets/<mod|shared>/ models/<mod>/ services/ repositories/<mod>/ bloc/<mod>/
  core/{app.dart, config, errors, format, routing, theme, validation}
```

Regla «qué va dónde»:

```
pages/<mod>/         Pantalla completa (una por ruta). Solo BlocBuilder/BlocListener; sin Dio ni repositorios.
widgets/<mod|shared>/ Componentes reutilizables sin lógica de negocio.
models/<mod>/        Clases de datos (Equatable, fromJson a mano). Sin Flutter ni red.
services/            Cliente HTTP, interceptor, proveedor de token (Clerk/nativo), descargas.
repositories/<mod>/  Un repositorio por módulo; usa services y devuelve models o Failure.
bloc/<mod>/          Un Bloc por flujo: <x>_bloc.dart, <x>_event.dart, <x>_state.dart. Cubit solo si es trivial.
core/                Transversal: app.dart, theme, routing, config, errors, format, validation.
test/                Espejo de lib/ (test/bloc/requests/, test/pages/requests/...).
assets/, pubspec.yaml, README.md   Fuera de lib.
```

Ejemplo, módulo nuevo `tickets`:
  models/tickets/ticket_models.dart
  repositories/tickets/tickets_repository.dart
  bloc/tickets/tickets_{bloc,event,state}.dart
  pages/tickets/tickets_screen.dart
  widgets/tickets/ticket_card.dart      (solo si se reutiliza)
  core/routing/app_router.dart          (añadir la ruta)
  test/bloc/tickets/, test/pages/tickets/

Migración de estructura: rama `refactor/mobile-structure`, un commit por capa, sin cambios de comportamiento (`features/` y `shared/` ya no existen).

### Equivalencia con la estructura exigida

La estructura que se exige tiene seis carpetas dentro de `lib/` más `main.dart`, y fuera de `lib/` están `assets/`, `test/`, `pubspec.yaml` y `README.md`. Así se corresponde con `MOVIL/`:

| Exigido | En el proyecto | Qué contiene |
|---|---|---|
| `lib/main.dart` | `lib/main.dart` | Punto de entrada: arma Dio, repositorios y `AuthBloc`, y llama a `runApp`. |
| `lib/pages` | `lib/pages/<mod>/` | Pantallas completas (auth, home, profile, requests, dev). |
| `lib/widgets` | `lib/widgets/{shared,auth}/` | Componentes reutilizables sin lógica de negocio. |
| `lib/models` | `lib/models/` | Clases de datos con `Equatable`: perfil, página, solicitudes. |
| `lib/services` | `lib/services/` | Cliente HTTP (Dio) con su interceptor, proveedor de token. |
| `lib/repositories` | `lib/repositories/<mod>/` | Acceso a datos por módulo (auth, home, requests). |
| `lib/bloc` | `lib/bloc/<mod>/` | Un Bloc por flujo (auth, paged, requests) con `_bloc`, `_event` y `_state`. |
| `assets/` | `MOVIL/assets/` | Imágenes. |
| `test/` | `MOVIL/test/` | Espejo de `lib/`. |
| `pubspec.yaml`, `README.md` | `MOVIL/` | Igual. |

**Por qué existe `lib/core/` y qué contiene.** No está en la lista exigida: se añadió porque hay código que no es de una sola capa y que usan todas. Si se repartiera por las seis carpetas, `pages` o `bloc` tendrían que importarse entre sí, y varias piezas no encajan en ninguna (tema, rutas, configuración). Contiene solo código transversal:

- `app.dart`: widget raíz (`MantixApp`) con los `RepositoryProvider` y `BlocProvider` globales.
- `config/`: configuración por `--dart-define` (`API_BASE_URL`, `APP_VERSION`).
- `errors/`: `Failure`, traducción de errores HTTP por código y mensajes en español.
- `format/`: formateo de fechas y metadatos de estados y prioridades.
- `routing/`: `go_router`, redirecciones por sesión y permiso, `home_resolver`.
- `theme/`: colores, tokens y tema (los colores solo se leen de aquí).
- `validation/`: validadores de formularios.

Regla para decidir: si algo lo usan varias capas y no habla con la API ni guarda estado de un flujo, va en `core/`. Si es de un flujo o de un módulo, va en su capa. `core/` no contiene Blocs, repositorios, modelos ni pantallas.

### Ejemplo: formulario de nueva solicitud

```dart
// bloc/requests/create_request_event.dart
sealed class CreateRequestEvent { const CreateRequestEvent(); }
class CreateRequestSubmitted extends CreateRequestEvent {
  const CreateRequestSubmitted(this.request);
  final NewRequest request;
}

// bloc/requests/create_request_state.dart
enum CreateStatus { initial, submitting, success, failure }
class CreateRequestState extends Equatable { /* status, createdId, failure */ }

// la pantalla
BlocProvider(
  create: (context) => CreateRequestBloc(repository: context.read<RequestsRepository>()),
  child: BlocListener<CreateRequestBloc, CreateRequestState>(
    listener: (context, state) { /* success -> detalle; failure -> errores por campo */ },
    child: /* formulario; el botón se deshabilita con status == submitting */,
  ),
);
```

### Autenticación nativa del móvil (vigente)

Sustituye a Clerk en la app. El backend es `MOVIL/backend` (`services/mobile_auth.py`, `api/routes/mobile_auth.py`).

**Endpoints** (prefijo `/mobile-auth`, públicos): `register`, `verify-email`, `resend-verification`, `login`, `forgot-password`, `reset-password`. `GET /auth/me` carga el perfil, los roles y los permisos con el token propio.

**Flujo:**
1. `register` recibe correo, contraseña, **nombre (obligatorio) y apellido (opcional)**, crea la cuenta sin verificar (el nombre completo se guarda en `users.full_name`) y envía un código de 6 dígitos al correo (202). Desde la pantalla de verificación la app permite volver al registro («Volver al registro») para corregir los datos.
2. `verify-email` recibe correo, código **y contraseña**: consume el código, fija la contraseña (la elige quien tiene el código en su buzón), marca el correo como verificado y devuelve la sesión. Sin verificar no se puede iniciar sesión.
3. `login` devuelve el token. Las cuentas nuevas no reciben roles: quedan pendientes hasta que un administrador asigne uno. Excepción: la primera cuenta verificada de una base sin administradores recibe ADMIN.
4. Recuperación: `forgot-password` envía un código; `reset-password` lo consume y fija la contraseña nueva.

**Códigos:** 6 dígitos, caducan a los 10 minutos (`AUTH_VERIFICATION_EXPIRE_MINUTES`), un solo uso, 5 intentos por código y guardados con HMAC-SHA256 con una clave derivada de `MOBILE_JWT_SECRET`. Pedir otro código invalida el anterior.

**Contraseñas:** Argon2id (`pwdlib`), de 10 a 128 caracteres con mayúscula, minúscula y dígito.

**Token:** JWT HS256 con prefijo `mjwt.`, firmado con `MOBILE_JWT_SECRET` (solo en el backend), 480 minutos por defecto. **No hay refresco.** El token lleva la versión de sesión de la cuenta (`users.token_version`, claim `ver`): `POST /mobile-auth/logout` y `reset-password` la incrementan y con eso dejan de servir todos los tokens anteriores, en todos los dispositivos. En cada petición se comprueba además que la cuenta siga activa y verificada. Los tokens emitidos antes de existir el claim cuentan como versión 0.

**Cierre de sesión en la app:** `AuthBloc` llama a `AuthRepository.revokeSession()` (`POST /mobile-auth/logout`, 5 s como máximo) y después borra el token local. Es de mejor esfuerzo: sin red o con error del servidor, el cierre local continúa. Cerrar sesión en un dispositivo cierra la sesión en todos. Una sesión expirada no llama al servidor.

**Almacenamiento en la app:** `flutter_secure_storage` (`NativeAuthProvider`, Keystore en Android). El `AuthBloc` solo pregunta al `AuthProvider` y no guarda el token en sus estados.

**Correo:** SMTP (Gmail con contraseña de aplicación) con STARTTLS obligatorio y verificación del certificado. Solo para desarrollo o demostración. Un envío fallido no cambia la respuesta de la API (siempre 202). Un único limitador: 60 s entre correos a la misma cuenta, 5 por hora por cuenta y 60 por hora en total, en memoria. Configuración en `MOVIL/backend/README.md`.

**Límites de la API:** 120 peticiones por minuto por IP en toda la API y 20 por minuto en `/mobile-auth/*`, en memoria del proceso.

**Pendiente de seguridad (sin decidir):** refresco de tokens con rotación; respuestas que revelan si un correo existe (409 y `auth_email_already_verified`); las cuentas creadas primero en la web no pueden fijar una contraseña en el móvil.

### Sesión: cómo el `AuthBloc` envuelve a Clerk (OBSOLETO, historial)

> **OBSOLETO:** la app ya no usa Clerk. Se conserva como historial; lo vigente está en la sección anterior.

Clerk sigue siendo la **única fuente de verdad** de «hay sesión» y de los tokens (los guarda y renueva el SDK). El `AuthBloc` no copia nada de eso: solo pregunta al `AuthProvider` (`accessToken()`, `signOut()`) y escucha su flujo `signInChanges`, que emite cuando Clerk inicia o cierra sesión por su cuenta. Con cada cambio carga `GET /auth/me` y traduce el resultado en un `AuthState`: `AuthUnknown`, `AuthUnauthenticated`, `AuthUnavailable`, `AuthPending` (roles vacíos), `AuthNoAccess` (roles sin permisos) o `Authenticated`. Así no hay dos estados de sesión que puedan discrepar.

Errores: tipo sellado `Failure` (red, 401, 403, 404, 409, 422 con campos, servidor). Se mapea por el campo `code`; un `code` desconocido se mapea por el estado HTTP, sin romper.

## Fases

| Fase | Contenido |
| --- | --- |
| 0 | Auditoría de reutilización (hecha) |
| 0.5 | Prueba de concepto de autenticación con Clerk (**hecha**; **obsoleta**: sustituida por la autenticación nativa; ver resultados abajo como historial) |
| 1 | Backend mínimo (se aplica a `MOVIL/backend`, no a `WEB/backend`): códigos de error específicos y estables con tabla documentada, corregir la descripción obsoleta de `/equipment/{id}/attachments` y la lista de roles en `main.py`, exportar el OpenAPI como artefacto de CI (**hecha**; ver «Resultado de la Fase 1») |
| 2 | Base Flutter y autenticación (**hecha**) |
| 3 | Componentes y sistema de diseño (**hecha**; falta revisarla a ojo en el teléfono) |
| 4 | Solicitante (**hecha en código y pruebas**; falta revisarla a ojo en el teléfono; ver «Resultado de la Fase 4») |
| 4.1 | Rediseño de interfaz: hojas inferiores, paginación, filtros con multiselección, tablero por estados, triaje y asignación desde el tablero (**hecha en código y pruebas**; falta revisarla a ojo en el teléfono; ver «Interfaz con hojas inferiores, paginación y tablero») |
| 5 | Técnico |
| 6 | Supervisor |
| 7 | Administrador |
| 8 | Capacidades móviles (push, escaneo de QR) |
| 9 | Calidad y entrega. El almacenamiento seguro de la sesión ya está resuelto con la autenticación nativa (ver «Sesión de Clerk en almacenamiento seguro», obsoleta) |

Verificación previa de la Fase 4 (hecha): ver «Resultado de la Fase 4».

## Resultado de la Fase 4 (Solicitante)

**Verificación previa (solo lectura del backend):**

- El Solicitante tiene `equipos:ver`, y `GET /equipment` **no filtra por usuario**: recibe todo el catálogo, con serie, ubicación actual, custodio actual y último mantenimiento. Solo se oculta `purchase_cost` (exige `equipos:editar`).
- `GET /equipment?search=` es una búsqueda parcial, sin distinguir mayúsculas, sobre etiqueta, serie, marca y modelo (máximo 100 caracteres). No existe búsqueda exacta por `asset_tag`.
- `GET /maintenance/requests` devuelve solo los tickets propios a quien no es supervisor, administrador ni técnico (según la descripción de la ruta).
- **Decisión:** la app no oculta nada en el servidor; el selector de equipo solo lee y muestra etiqueta, marca, modelo y tipo, y descarta custodio y ubicación. La API sigue exponiéndolos a un Solicitante que la llame directamente.

**Qué hay en la app:** «Mis solicitudes» (lista paginada con `Paginator` (botones y tamaño de página), filtro por estado, estados de carga, vacío y error), detalle de la solicitud (datos, técnico, historial y adjuntos en solo lectura) y «Nueva solicitud» (selector de equipo con búsqueda, validación en el cliente y los 422 del servidor bajo cada campo). La ruta de crear exige `solicitudes:crear` y el botón se oculta sin ese permiso.

**Fuera de esta fase, por decidir:** subir y descargar adjuntos (necesita un selector de archivos como dependencia nueva y manejo de descargas), cancelar una solicitud y elegir categoría.

## Gestión de equipos (pasos 1 a 3: consulta, alta, filtros y paginación)

Pantalla `/modulos/equipos` (`pages/equipment/equipment_screen.dart`), solo con el permiso `equipos:ver` (lo exige el router y el menú). Sigue la web: título y descripción, cuatro tarjetas con los contadores por estado y el listado del catálogo.

- **Tarjetas** (`GET /equipment/summary`): Total, Operativos (`assigned` + `in_storage`, con la tasa sobre el total), En mantenimiento (`in_repair`) y Crítico (`lost`, `retired`, `disposed`). Las agrupaciones son las de la web. Cada tarjeta es un botón que filtra el listado por sus estados (`status=a,b,c`); la tarjeta activa queda marcada.
- **Listado** (`GET /equipment`, más recientes primero): en **tabla** (una fila por equipo: marca y modelo, descripción o «Serie: …», etiqueta, ubicación y estado) o en **cuadrícula** de dos columnas; tocar un equipo abre su ficha (solo lectura). Buscador por etiqueta, serie, marca o modelo (máximo 100 caracteres, con 400 ms de espera). Estados de carga, vacío (distinto con y sin filtros), error con reintento; el encabezado siempre es visible.
- **Filtros** (botón con embudo y contador de filtros activos): las cuatro tarjetas del resumen (compactas, de dos filas: icono, número y nombre; la seleccionada lleva borde mostaza) y una hoja con **categoría** y **estado** como multiselección (casillas que no cierran la hoja, «Aplicar» y «Limpiar») y **fecha de registro** con un calendario compacto (`date_from`/`date_to`). Cada filtro activo sale como chip que se quita solo. Cualquier filtro vuelve a la página 1. Varias categorías viajan como `equipment_type_id` repetido.
- **Paginación** (excepción a la regla general de «size=20 y scroll infinito», pedida para los listados): componente `Paginator` (`widgets/shared/paginator.dart`): una fila de ancho completo, centrada y sin cuadro de fondo, con flechas en los extremos y los números de página en medio, con «…» y siempre la primera y la última («1 2 3 4 5 … 99»; la actual, en un círculo mostaza con aro; en pantallas estrechas caben menos números). Sin flecha «anterior» en la primera página ni «siguiente» en la última; con una sola página se muestra solo «1». No escribe el rango («1-10 de 38»). Debajo, el selector de tamaño de 5, 10, 20 o 50, que solo aparece si el total supera 5. Cambiar de tamaño vuelve a la página 1. Los datos de la página se siguen mostrando mientras llega la siguiente.
- **Bloc:** `EquipmentListBloc` (por páginas; cambiar un filtro o el tamaño de página crea uno nuevo, moverse entre páginas es un evento), `EquipmentSummaryBloc` (contadores) y `EquipmentCatalogBloc` (categorías y ubicaciones, para el filtro y el formulario). La pantalla solo usa `BlocBuilder`.
- **Widgets compartidos nuevos** (`widgets/home/`): `MantixAppBar` (la «M» a la izquierda y el avatar), `MantixDrawer` (menú por permisos, con la pantalla actual resaltada) y `BrandLogo`; el dashboard los usa también. `PagedListView` admite un `header` que se desplaza con la lista.
- **Los decimales** de la tasa llevan coma («81,6% tasa»); la maqueta usaba punto.

- **Registrar nuevo equipo** (solo con `equipos:crear`; se abre en una hoja inferior arrastrable desde «Nuevo equipo», ya no es una ruta). Panel con secciones numeradas: **1 Información general** (código de activo, categoría, marca y modelo obligatorios; serie y descripción opcionales), **2 Asignación y ubicación** (ubicación física con `GET /locations` y responsable buscado por nombre o correo con `GET /equipment/custodian-candidates`; cada campo solo se ofrece con `equipos:editar` y `equipos:asignar`) y **3 Estado y garantía** (estado obligatorio, «En almacén» por defecto, costo, fecha de adquisición y garantía). Valida en el cliente (costo sin negativos y con dos decimales como máximo, fecha de adquisición no futura, garantía coherente), muestra bajo cada campo los errores 422 y avisa con un mensaje específico si la etiqueta o la serie ya existen (409).
- **Ubicación y responsable no van en el alta:** `POST /equipment` no los admite, así que se asignan después con `POST /equipment/{id}/location` y `POST /equipment/{id}/custody`. Si el equipo se registra pero una asignación falla, el alta cuenta como hecha y un aviso explica qué no se pudo asignar. Al terminar, el listado y los contadores se recargan solos (`EquipmentRepository.changes`).

**Pendiente de este módulo** (sin hacer):
- **Exportar y adjuntar al crear un equipo (hecho).** Paquetes aprobados y fijados en `pubspec.lock`: `file_picker`, `share_plus` e `image_picker`, los tres detrás de interfaces en `lib/services/` (sin `path_provider`: el temporal sale de `dart:io`). Sin permisos nuevos en el APK: el manifiesto fusionado solo declara `INTERNET`; no hay `CAMERA` ni almacenamiento porque la foto la toma la app de cámara del sistema y los archivos vienen del selector del sistema. Se añadió la consulta `IMAGE_CAPTURE` en `<queries>` (visibilidad, no permiso). Formulario: sección «Adjuntos» (solo con `equipos:adjuntar`) con «Tomar foto», «Elegir de la galería» (JPG o PNG; HEIC se rechaza) y «Elegir un archivo» (PDF o TXT), máximo 5 entre fotos y archivos y 10 MB cada uno; la foto se comprime (calidad 85, 2048 px) y si aun así pasa de 10 MB se avisa. Los adjuntos se suben después de crear el equipo, uno a uno, desde la ruta del archivo y con progreso; si alguno falla el equipo no se deshace, se ve el motivo de cada archivo y «Reintentar fallidos» repite solo esos. Si Android cierra la app mientras se toma la foto, `retrieveLostData` la recupera al reabrir el formulario. Listado: botón «Exportar» (solo con `reportes:exportar`) con Excel, CSV o PDF; se descarga en streaming a un temporal, se comparte y se borra siempre; aplica los filtros de estado y categoría (la búsqueda por texto no existe en el servidor). Los 413 y 415 se traducen por código. **La cámara y la hoja de compartir no se han probado en un teléfono:** queda para una prueba manual.
- Edición del equipo (`equipos:editar`) y reasignar custodio y ubicación desde la ficha. La ficha ya muestra los datos agrupados, los mantenimientos, el historial (registro, mantenimientos y tickets) y los adjuntos, en solo lectura.

## Interfaz con hojas inferiores, paginación y tablero

Cerrada en código y pruebas en la rama `feat/mobile-ui-sheets-pagination`. Todos los detalles y formularios de esta parte son **hojas inferiores arrastrables** (`showMantixSheet`, hasta el 90 % de la altura, con asa, título y botón de cerrar; el encabezado de la pantalla de fondo sigue visible).

- **Componentes compartidos** (`widgets/shared/`): `Paginator`, `MultiSelectSheet` y `FilterButton` (embudo con contador), `showDateRangeDialog` (calendario compacto con validación desde ≤ hasta), `SearchPicker` (búsqueda con resultados por páginas y «Ver más resultados», sin paginador numerado; «Crear nueva» solo si se pasa un callback), `Timeline`, `DetailSection`/`DetailField`/`DetailHeader` (acento mostaza `AppColors.mustard` con texto navy).
- **Equipos:** filtros con multiselección y fechas, ficha en hoja (datos en secciones, historial, mantenimientos y adjuntos), formulario de alta en hoja con selector de categoría con búsqueda y «Crear nueva categoría» (`POST /equipment/types`, solo con `equipos:crear`; un 409 `equipment_type_name_taken` se maneja por `code` y ofrece usar la categoría que ya existe). Un equipo nuevo vuelve el listado a la página 1, sale primero y se resalta unos segundos.
- **Mantenimientos del equipo:** la ficha lista los 10 más recientes (`GET /equipment/{id}/maintenance-records`, exige `tickets:ver_todos`: sin ese permiso no se muestra la lista ni un error y queda el «Último mantenimiento»). Los costos solo llegan a quien tiene `equipos:editar`.
- **Tickets:** encabezado como el de Equipos, resumen, filtros con multiselección (estado, prioridad, equipo) y fechas, tabla paginada, detalle y formulario en hojas, y **tablero** con un estado debajo de otro (colapsables, con contador, sin desplazamiento horizontal). Mover una tarjeta: arrastrar con pulsación larga (la pantalla se desplaza sola cerca del borde y solo se resaltan los destinos válidos) o el menú «Mover a…». Las transiciones válidas salen de `GET /maintenance/requests/workflow`; no hay movimiento optimista: si el servidor rechaza el cambio la tarjeta se queda y sale un aviso en español.
- **Triaje y asignación desde el tablero:** «En triaje» abre una hoja que pide **categoría** (selector con búsqueda sobre `GET /maintenance/categories`) y **prioridad** (`GET /priorities`) y manda `POST …/classify`; «Asignado» abre una hoja con la búsqueda de **técnicos activos** (`GET /technicians`, por páginas, con búsqueda en el servidor) y manda `POST …/assignment`. Resolver y cancelar piden un texto en un diálogo corto. `TicketBoardBloc` decide el endpoint según el destino.
- **Catálogos:** `CatalogsRepository` (categorías con caché de 5 minutos, prioridades y técnicos), `CategorySearchBloc`, `TechnicianSearchBloc` (descarta las cuentas inactivas) y `PrioritiesCubit`. Son la base de la pantalla de Solicitudes Pendientes.
- **Un ticket nuevo** (y una solicitud nueva en «Mis solicitudes») vuelve a la página 1 sin filtros, sale primero y se resalta. Mantenimiento no existe aún en la app.
- **Detalle por ruta** (`RequestDetailScreen`, desde «Mis solicitudes» y las notificaciones): usa el mismo `TicketDetailBody` que la hoja, solo añade la barra superior y recargar tirando hacia abajo.

**Verificación:** 600 pruebas (bloc, repositorio y widget), `flutter analyze` sin avisos y, para cada pantalla y hoja nueva, una prueba sin overflow a 320×568 y 360×640 con texto a 1,3. No se ha visto aún en un teléfono.

**Pendientes reales de esta parte:**

- Revisarla a ojo en el teléfono contra el backend de la rama `feat/api-mobile-needs`.
- **Orden de integración de las ramas** (propuesto): 1) PR de `feat/api-mobile-needs` a `develop` (solo toca `MOVIL/backend`, `MOVIL/docs` y añade una sección propia a este archivo); 2) rebasar `feat/mobile-ui-sheets-pagination` sobre `develop`; 3) PR de la app. Las dos ramas editan este archivo en bloques distintos y un `git merge-tree` entre ellas no da conflictos; para que siga así, **la rama del backend es dueña de «Cambios de API solo en MOVIL/backend» y la de la app de lo demás**.
- Edición del equipo, reasignar custodio y ubicación desde la ficha.
- La pantalla de Solicitudes Pendientes ya está hecha (sección siguiente).

## Solicitudes pendientes (bandeja de triaje)

Hecha en código y pruebas en la rama `feat/mobile-pending-requests` (sale de `feat/mobile-ui-sheets-pagination`). Ruta `/solicitudes-pendientes`, con su elemento en el menú; exige `solicitudes:ver_todos` (la ruta lo comprueba; la autorización real es del backend). Quien ve todas las solicitudes (`solicitudes:ver_todos`) ya no tiene «Mis solicitudes» en el menú; quien solo ve las suyas conserva «Mis solicitudes» y no ve «Solicitudes pendientes».

- **Qué muestra:** encabezado a todo el ancho con `assets/images/solicitudes.png` (sin etiqueta); búsqueda y botón de filtros; cuatro cifras del mismo tamaño en un cuadro de 2×2, sin desplazamiento (EN COLA, SIN TÉCNICO, MÁS ANTIGUA, ESPERA MEDIANA); «Pulso de la cola» en dos columnas (primera respuesta y aprobación/rechazo arriba; barras por prioridad y por categoría abajo; el periodo del subtítulo lo da el servidor); y el tablero «Solicitudes por estado», con una columna por cada estado `in_queue` del flujo (hoy Recibidas, Clasificadas y Asignadas) **repartidas en todo el ancho y del mismo tamaño, sin desplazamiento horizontal** (la tarjeta muestra solo el nombre del ticket y cuánto lleva esperando; el resto está en el detalle al tocarla; cada columna lleva su nombre y cuántas hay en la misma línea, sin color propio y sin texto de «N columnas visibles»). Los rótulos de columna, «Espera mediana» y el formato de horas, porcentajes y variaciones («24,1 h», «▲ 12,5%») son los de la web (`core/format/queue_format.dart`, con las pruebas de sus specs). Los nombres de prioridad y categoría salen de `GET /priorities` y `GET /maintenance/categories`; ninguno va escrito en la app. Color: las cifras son sobrias (azul claro); el mostaza de la paleta solo marca las variaciones que alertan y el destino al arrastrar una tarjeta.
- **De dónde sale cada dato:** `GET /maintenance/queue/summary?period=30d` (`solicitudes:ver_todos`) da las cifras y el pulso; `GET /maintenance/requests/workflow` da las columnas, las transiciones, los datos que exige cada destino y si se puede entrar en él; `GET /maintenance/requests?status=<uno>&size=10&sort=-created_at` da las tarjetas de cada columna (total en `X-Total-Count`).
- **Carga:** 10 tarjetas por columna y «Ver más (N restantes)» (excepción pedida a la regla de `size=20`); nunca se pide el catálogo completo. Cada bloque carga y falla por separado: si el resumen cae, las cifras y el pulso dicen «no disponible» con reintento y el tablero sigue; si una columna cae, solo ella muestra el error con reintento. Tirar hacia abajo recarga resumen y columnas.
- **Filtros** (hoja con «Aplicar» y «Limpiar»): categoría, prioridad y técnico con multiselección, y «Recibidas entre» (la inicial no puede ser futura, la final no anterior y como máximo 366 días). Cada filtro activo sale como chip que se quita. Categorías múltiples viajan como `category=a,b` y técnicos como `technician_id` repetido; **ambos necesitan el backend de `feat/api-mobile-needs`** (cambios 7 y 8), igual que el nombre del equipo en la tarjeta: sin él la tarjeta muestra «Equipo #id».
- **Mover una tarjeta:** pulsación larga y arrastre (la pantalla se desplaza sola cerca del borde de arriba o de abajo; solo se resaltan las columnas válidas) o menú «Mover a…» (con «Rechazar» para cancelar). Soltar donde no se puede devuelve la tarjeta y lo explica en español (falta de permiso o transición no permitida) sin pedir nada. Destinos que exigen datos: Clasificadas pide categoría y prioridad (`POST …/classify`, `solicitudes:editar`), Asignadas un técnico activo (`POST …/assignment`, `tickets:asignar`) y Rechazar un motivo de 5 a 500 caracteres (`POST …/reject`, `solicitudes:aprobar`); cerrar la hoja deja la tarjeta donde estaba. A diferencia del tablero de Tickets, aquí el cambio es **optimista**: la tarjeta cambia de columna al confirmar y vuelve a su sitio si el servidor lo rechaza (técnico inactivo, sin permiso, sin red), con el mensaje por `code`. Al aceptarse se recargan columnas y cifras. Tocar una tarjeta abre su detalle.
- **Arquitectura:** `QueueSummaryBloc`, `RequestBoardBloc` y `TriageActionsBloc` (`bloc/queue/`); `QueueRepository`; `CategoryNamesCubit`; modelos en `models/queue/`; widgets en `widgets/queue/`. `TriageActionsBloc` no toca el tablero: emite un resultado (`started`, `succeeded`, `failed`, `blocked`) y la pantalla se lo pasa a los otros dos.
- **Colores:** todos de `AppColors` y `StatusColors` (solo se añadieron `bannerDeep` y `bannerLight`, que coinciden con el fondo de la imagen del encabezado).

**Verificación:** 715 pruebas, `flutter analyze` sin avisos, sin overflow a 320×568 y 360×640 con texto a 1,3, y `flutter build apk --debug`. La revisión a ojo en el teléfono (arrastre con el dedo, desplazamiento automático, aspecto del encabezado) la hace la persona dueña del proyecto.

**Pendientes de esta pantalla:**

- El backend de `feat/api-mobile-needs` (PR #94) y esta pantalla (PR #95) ya están fusionados en `develop`. Falta **reconstruir el contenedor** `mantix-movil-backend-1` para probar contra el código nuevo (nombre del equipo, filtro por técnico y por varias categorías).
- Con el backend ya en `develop`, `TechnicianSearchBloc` puede pedir `is_active=true` en vez de descartar los inactivos, y `CategorySearchBloc` puede pedir `search` y páginas al servidor en vez de filtrar en la app (cambios 9 y 10).
- Sin selector de periodo (7 días, 30 días, 12 meses) ni orden por prioridad ni filtro «solo sin técnico», que la web sí tiene; se añaden si se piden.


## Usuarios y roles

Hecha en código y pruebas en la rama `feat/mobile-users-roles` (sale de `feat/mobile-ui-polish`; ver «Ramas»). Ruta `/usuarios`. En el menú hay **un solo** elemento, «Usuarios y roles», que sustituye a «Usuarios», «Roles y permisos» y «Usuarios pendientes» (los tres abrían «próximamente»; `/modulos/usuarios`, `/modulos/roles` y `/modulos/usuarios-pendientes` redirigen a la nueva). La ruta exige `usuarios:ver` (solo tener `usuarios:asignar` no basta); la autorización real es del backend.

- **Tres pestañas.** **Usuarios:** una tarjeta baja con las cifras (total, activos, inactivos, sin ingresar), búsqueda (espera a que se deje de escribir), filtros (rol, estado de la cuenta y fecha de creación, con chips que se quitan) y la lista por páginas con el `Paginator` (20 por página); cada tarjeta lleva nombre, correo, roles («Sin rol» en mostaza), estado y último acceso. **Pendientes:** quienes ya iniciaron sesión y no tienen rol, con la explicación y el número en la pestaña. **Roles:** los roles que existen **en solo lectura** (nombre, código, cuántas personas lo tienen y, con `usuarios:asignar`, la descripción). Sin matriz de permisos y sin crear, editar ni borrar roles: eso se hace en la web.
- **Qué se puede hacer** (cada botón sale solo con su permiso efectivo de `/auth/me`, nunca por el nombre del rol): al tocar una persona se abre su ficha, con **cambiar roles** (`usuarios:asignar`; casillas, de 1 a 10 roles), **editar teléfono y código de empleado** (`usuarios:editar`; guarda solo lo que cambió y vaciar un campo lo borra) y **activar o desactivar la cuenta** (`usuarios:cambiar_estado`; desactivar pide confirmación y no se ofrece sobre la propia cuenta). En Pendientes, **Asignar rol** (`usuarios:asignar`). Si sale bien, la ficha se cierra, se avisa en pantalla y las listas y cifras se recargan solas; si falla, el motivo sale dentro de la ficha, en español y por `code`, sin detalles internos.
- **De dónde sale cada dato** (prefijo `/admin`, no `/users`): `GET /admin/users` (paginada; `search`, `role`, `is_active`, `created_from`, `created_to`, `sort=name`), `GET /admin/users/summary`, `GET /admin/users/pending` (`usuarios:ver`); `GET /admin/roles` (roles activos, para elegir y filtrar) y `GET /admin/roles/manage` (con descripción, solo con `usuarios:asignar`; sin ese permiso los conteos salen de `by_role` del resumen); `PUT /admin/users/{id}/roles` (`usuarios:asignar`, sirve igual para un pendiente), `POST /admin/users/{id}/activate` y `/deactivate` (`usuarios:cambiar_estado`), `PATCH /admin/users/{id}` (`usuarios:editar`; solo teléfono y código).
- **Errores por `code`** (todos en `docs/error-codes.md` y en la tabla de la app): `cannot_deactivate_self`, `last_admin_protected`, `cannot_revoke_own_admin`, `user_employee_code_taken`, `role_not_found` y `user_not_found`. Antes de pedir nada la app valida: al menos un rol y como máximo diez, formato del teléfono (debe empezar por `+` o un dígito) y del código de empleado (2 a 50: letras, números, `. _ -`; se guarda en mayúsculas), que haya algo que cambiar y que no se desactive la propia cuenta. Estado de la cuenta: «Activo», «Inactivo» o «Pendiente de primer ingreso» (activa y sin acceso), como la web.
- **Arquitectura:** `UsersListBloc` (paginado, con los filtros en el constructor como Equipos), `UsersSummaryBloc`, `PendingUsersBloc`, `RolesBloc`, `AssignableRolesCubit` y `UserActionsBloc` (`bloc/users/`); `UsersRepository` (avisa de cada cambio por un `Stream` y las listas se recargan solas); modelos en `models/users/`; reglas de formato en `core/format/users_format.dart`; widgets en `widgets/users/`. Colores solo de la paleta (azul claro y acero para lo normal, mostaza suave para lo que espera algo, gris para lo inactivo).

**Fuera de esta versión (decidido):** **crear usuario**, restablecer contraseña y crear, editar o borrar roles.

**Ajuste de interfaz** (según la maqueta): las tres pestañas son píldoras (la elegida en mostaza, «Pendientes» con su número) y el encabezado cambia con la pestaña (icono en caja azul claro, línea mostaza, título y explicación). Las cifras son tres tarjetas con icono (total, activos e inactivos; «Sin ingresar» salió de las cifras). La tarjeta de usuario lleva el rol con su icono a la izquierda y el estado a la derecha, y el último acceso quedó solo en la ficha. En Pendientes cada persona lleva el chip «Pendiente de asignación» y el botón «Asignar rol» debajo de su tarjeta, con una ayuda al final solo para quien puede asignar. Las tarjetas de rol llevan su icono (por código, solo decora) y cuántas personas lo tienen. Diferencias con la maqueta: no hay **«Crear rol»** (crear roles sigue fuera de esta versión), no se muestra la **fecha de solicitud** del pendiente (`GET /admin/users/pending` no la trae), las tarjetas de rol no llevan flecha (no hay detalle del rol) y se mantiene el paginador del proyecto en vez de «1 de 1». Los textos «Define y administra los roles» y «permisos» se cambiaron porque la app solo consulta.


**Verificación:** 865 pruebas (bloc, repositorio y widget; incluye cada flujo y cada error, y que el servidor reciba la petición correcta), `flutter analyze` sin avisos, sin overflow a 320×568 y 360×640 con texto a 1,3 y `flutter build apk --debug`. La revisión a ojo en el teléfono, y contra un backend real, la hace la persona dueña del proyecto.

**Pendientes de backend de esta pantalla** (no se tocó `MOVIL/backend`):

- **Crear usuario no sirve en el móvil.** `POST /admin/users` deja una cuenta «pre-registrada» sin contraseña, pensada para la web (la persona entra con Clerk y la cuenta se vincula). En la autenticación del móvil **todos** los pasos exigen que la cuenta ya tenga contraseña: `POST /mobile-auth/register` responde `user_email_taken` porque la cuenta existe, y verificar el correo, reenviar el código y «olvidé mi contraseña» responden como si el código fuera inválido. Una cuenta creada así solo podría entrar por la web. Por eso no entra en esta versión. Si se quiere, la salida es que `register` «reclame» una cuenta pre-registrada (sin contraseña, sin Clerk y sin verificar): fija la contraseña, envía el código y **conserva los roles**; es un cambio pequeño en `services/mobile_auth.py` con pruebas, y **no está aprobado**.
- **Restablecer la contraseña de otra persona** (`POST /admin/users/{id}/password`) solo funciona para cuentas vinculadas a Clerk; para cuentas del móvil responde 409 `password_reset_unavailable`, con un texto engañoso («aún no ha iniciado sesión»). Por eso la app no lo ofrece.
- `GET /admin/users/pending` no está paginado y solo trae `id`, `email` y `full_name` (sin fecha de registro).
- `GET /admin/roles` solo da `id`, `code` y `name`; la descripción y el conteo completos piden `usuarios:asignar` (`/admin/roles/manage`).
- `PATCH /admin/users/{id}` con un campo en `null` para borrarlo es lo que usa la web y lo que espera la app, pero **no se ha probado contra el backend real**.
- `GET /admin/users` no tiene filtro «sin rol» (se obtiene de la pestaña Pendientes).
- **El último acceso se registra al iniciar sesión en el móvil (resuelto, ver cambio 11 de «Cambios de API solo en MOVIL/backend»).** Antes `last_login_at` solo lo escribía el flujo de Clerk y quien entraba solo por la app se veía como «Pendiente de primer ingreso» y «Último acceso: Nunca». Las cuentas que ya habían entrado siguen vacías hasta su próximo inicio de sesión.

**Ramas:** `feat/mobile-users-roles` sale de `feat/mobile-ui-polish`, que tampoco se ha subido ni tiene PR (ajustes de la bandeja, el paginador, Equipos y el banner del dashboard). Orden de integración propuesto: 1) `feat/mobile-ui-polish`; 2) `feat/mobile-users-roles` (que ya incluye lo anterior). Nada se ha subido ni fusionado.

## Técnicos

Hecha en código y pruebas en la rama `feat/mobile-technicians` (sale de `feat/mobile-users-roles`). Ruta `/tecnicos` (`/modulos/tecnicos` redirige a ella), con su elemento en el menú y el enlace «Ver técnicos» del dashboard; exige `tecnicos:ver` (la ruta lo comprueba; la autorización real es del backend).

- **Qué muestra:** encabezado con el banner `assets/images/tecnicos.png` («PERSONAL TÉCNICO Y ESPECIALISTAS», sin la etiqueta «BANDEJA DE TRIAJE» de la maqueta); cinco cifras (total, disponibles, con tickets activos, no disponibles y resueltos; las cuatro primeras filtran la lista al tocarlas); búsqueda por nombre, especialidad, código o correo (sin tildes); filtros en hoja con multiselección y «Aplicar»/«Limpiar» (especialidad, disponibilidad, estado de la cuenta y carga) con un chip por cada uno; orden (por defecto **menor carga primero**, también disponibilidad, más resueltos y nombre); lista en **tarjetas** o **tabla** y `Paginator` con tamaño elegible (20 por defecto, sin «1 de 1»). La ficha de cada técnico es una hoja inferior: datos, carga, indicadores del periodo y tickets abiertos. El rendimiento se presenta como apoyo para repartir trabajo, no como ranking: sin colores de «bueno» o «malo» ni comparación entre personas.
- **De dónde sale cada dato:** `GET /technicians` (`tecnicos:ver`; todos, por páginas de 500), `GET /dashboard/workload?days=30` (`dashboard:ver`; abiertos y resueltos), `GET /dashboard/technicians?period=30d` (`dashboard:ver`; mediana del MTTR, SLA, n y reabiertos, con «pocos datos» y «N sin SLA excluidos» decididos por el servidor) y `GET /maintenance/requests?technician_id=…&status=…` (`tickets:ver`; tickets abiertos de la ficha). `hourly_rate` solo llega a quien tiene `tecnicos:editar`; a los demás ni se les enseña el campo.
- **Filtrado en la app:** el servidor no ordena ni filtra por carga ni por especialidad, así que la pantalla trae el catálogo completo y filtra, ordena y pagina ella, igual que la web. Por eso no se pagina en el servidor.
- **Cada bloque carga y falla por separado:** si falla la carga, la lista sigue y las cifras de tickets dicen «no disponible» con reintento; en la ficha, indicadores y tickets se reintentan cada uno por su lado. Sin `tickets:ver` la ficha ni pide los tickets.
- **Acciones** (cada botón sale solo con su permiso efectivo de `/auth/me`, nunca por el nombre del rol):
  - **Registrar técnico** (`POST /technicians`, `tecnicos:crear`): botón mostaza en el encabezado, formulario en hoja inferior (usuario con búsqueda, especialización, tarifa). Se oculta si falta `equipos:asignar`, porque el selector de usuario usa `GET /equipment/custodian-candidates`. Al guardar, la lista vuelve a la página 1 sin filtros, el técnico sale de primero y se resalta unos segundos.
  - **Editar perfil** (`PATCH /technicians/{id}`, `tecnicos:editar`): especialización y tarifa; solo viaja lo que cambió y vaciar un campo lo borra.
  - **Marcar como disponible o no disponible** (`PATCH /technicians/{id}`, `tecnicos:editar`): pasar a no disponible pide confirmación y avisa de los tickets abiertos, que siguen asignados.
  - **Desactivar o activar la cuenta** (`POST /admin/users/{id}/deactivate` o `/activate`, `usuarios:cambiar_estado`): el perfil de técnico **no tiene un estado propio**; su `is_active` es el de la cuenta de usuario. Por eso desactivarlo desactiva la cuenta entera: la persona no puede entrar a Mantix con ningún rol y no se le pueden asignar tickets. La confirmación lo explica y avisa de los tickets abiertos; activar de nuevo no la pide. Nunca sobre la propia cuenta. El resto de la app (`TechnicianSearchBloc`) ya descarta a los técnicos inactivos al asignar.
- **Validaciones antes de pedir nada:** usuario elegido, especialización de hasta 100 caracteres, tarifa vacía u ≥ 0 con coma o punto y como máximo dos decimales (hasta 99 999 999,99), y que haya algo que cambiar. La tarifa se muestra como «$35,00».
- **Errores por `code`:** `technician_profile_exists` (409), `user_not_found`, `technician_not_found`, `last_admin_protected`, `cannot_deactivate_self` y los 403 genéricos; el motivo sale dentro de la hoja y lo escrito no se pierde.
- **Repositorio compartido:** `TechniciansRepository` (`lib/repositories/technicians/`) es el único que llama a `/technicians`; lo usan la pantalla y el selector «Asignar técnico» del tablero y de la bandeja (`TechnicianSearchBloc`, que ahora pide `is_active=true`). `CatalogsRepository` ya no tiene técnicos. Blocs en `bloc/technicians/`: `TechniciansListBloc`, `TechnicianDetailBloc` y `TechnicianActionsBloc`; reglas de formato portadas de la web en `core/format/technicians_format.dart`.
- **Colores:** todos de `AppColors` y `StatusColors`; el formulario usa la cabecera navy con borde mostaza y tarjetas por campo con iconos azul claro y mostaza.

**Verificación:** 1023 pruebas (bloc, repositorio, formato y widget; incluyen las de 320×568 y 360×640 con texto a 1,3 sin overflow), `flutter analyze` sin avisos. **No se ha visto en un teléfono ni se ha corrido `flutter build apk --debug` en esta rama:** la revisión a ojo la hace la persona dueña del proyecto. Comprobar a mano: el aspecto del banner y de las cifras, el formulario con el teclado abierto, el resaltado del técnico nuevo, la tabla en pantallas estrechas y la confirmación de desactivar la cuenta.

**Diferencias con la maqueta:** la etiqueta «BANDEJA DE TRIAJE», «RESULTADOS» (es «RESUELTOS»), los chips «En proceso» y «Cerrado» (son de ticket) y las columnas «DISP.» y «CARGA» (son abiertos y resueltos) eran errores del diseño y no se copiaron. La especialidad va bajo el nombre en la tabla para que quepa sin desplazamiento horizontal.

**Pendientes de backend de esta pantalla** (no se tocó `MOVIL/backend` ni `WEB/backend`):

- `GET /technicians` no trae la carga, ni ordena o filtra por ella ni por especialidad, y no busca por `employee_code`; por eso se trae todo y se filtra en la app. Un endpoint de resumen de técnicos y esos filtros permitirían paginar en el servidor.
- No existe `GET /technicians/{id}` ni un estado propio del perfil de técnico: «desactivar» es desactivar la cuenta de usuario (`usuarios:cambiar_estado`).
- Buscar al usuario para registrar un técnico exige `equipos:asignar` (`/equipment/custodian-candidates`); un buscador de usuarios propio, que excluya a quien ya tiene perfil, evitaría ese permiso ajeno y el 409.
- `WEB/backend` no tiene el filtro `is_active` de `GET /technicians` (solo `MOVIL/backend`).
- La web muestra «Registrar técnico» con `tecnicos:editar`, pero el backend exige `tecnicos:crear`; la app sigue al backend.
- No existe una pantalla de exportar técnicos en la app (la web usa `tecnicos:exportar`).

**Ramas:** `feat/mobile-technicians` sale de `feat/mobile-users-roles`, que a su vez sale de `feat/mobile-ui-polish` (ver «Usuarios y roles»). Nada se ha subido ni fusionado.

## Mantenimientos

Hecha en código y pruebas en la rama `feat/mobile-maintenance` (sale de `feat/mobile-technicians`). Ruta `/mantenimiento` (`/modulos/mantenimiento` redirige a ella), con su elemento en el menú; exige `mantenimiento:ver` (la ruta lo comprueba; la autorización real es del backend). Quien solo ve lo asignado (el Técnico) recibe únicamente sus planes.

- **Qué muestra:** encabezado claro (icono del calendario con reloj, línea mostaza, título y explicación) y el conmutador **Calendario / Lista** (el seleccionado en navy).
  - **Calendario:** el mes con flechas, la semana de lunes a domingo y los días de otros meses en gris. Hoy va en un círculo navy; cada día con servicios lleva un fondo suave y un punto por tipo (azul programado, mostaza vencido, verde hecho), con una leyenda debajo. Tocar un día muestra sus servicios debajo y tocarlo otra vez los oculta. «Ir a hoy» sale solo cuando se mira otro mes.
  - **Próximos mantenimientos:** hasta 3 tarjetas (vencidos primero) con icono, título, etiqueta del equipo, fecha, estado y flecha; «Ver todos» lleva a la lista. Mira 30 días atrás y 30 adelante, sin lo ya hecho.
  - **Lista:** todos los planes por páginas (20 por defecto, tamaño elegible) con búsqueda por título o equipo, filtros en hoja (estado, técnico —solo con `tecnicos:ver`— y orden) y un chip por cada filtro que se quita.
  - **Ficha del plan** en hoja inferior: equipo, próximo servicio, cada cuánto se repite, recordatorio, técnico, horas estimadas, descripción e historial (servicios hechos, a tiempo o con retraso, y cambios de fecha con su motivo). El plan y el historial cargan y se reintentan por separado.
  - Estados de cargando (esqueleto), vacío, error con reintento y tirar para refrescar en cada bloque. Si falla el calendario, los próximos siguen, y al revés.
- **De dónde sale cada dato:** `GET /maintenance/calendar?start&end` (`mantenimiento:ver`; el servidor admite 62 días como máximo y la cuadrícula del mes tiene 42), `GET /maintenance/schedules` (`mantenimiento:ver`; `search`, `technician_id`, `overdue`, `is_active`, `sort` por `next_due_at`, `title` o `created_at`, paginado por cabeceras), `GET /maintenance/schedules/{id}` y `/history`. Los inactivos no entran al calendario.
- **Acciones** (cada botón sale solo con su permiso efectivo de `/auth/me`, nunca por el nombre del rol):
  - **Programar mantenimiento** (`POST /maintenance/schedules`, `mantenimiento:crear`): botón mostaza en el encabezado y formulario en hoja inferior con equipo\*, título\*, descripción, cada cuántos días\* (30 por defecto), recordar en (días de antelación)\* (3), primer servicio\* (propone mañana a las 9:00) y horas estimadas; el técnico responsable solo se ofrece con `tecnicos:ver` (sin técnico, el recordatorio le llega a quien programa). El botón se oculta si falta `equipos:ver`, porque el equipo se busca con `GET /equipment`.
  - **Marcar como hecho** (`POST …/{id}/complete`, `mantenimiento:editar`): pide las horas reales, que son opcionales; la próxima fecha avanza un intervalo.
  - **Desactivar o activar el plan** (`PATCH …/{id}` con `is_active`, `mantenimiento:editar`): desactivar pide confirmación y explica que el plan deja de verse en el calendario y en los próximos y que no se podrá marcar como hecho; activar no la pide. Un plan inactivo solo ofrece «Activar plan», porque el servidor rechaza completarlo (422).
  - Si una acción sale bien, la ficha o el formulario se cierran, la pantalla avisa y el calendario, los próximos y la lista se recargan solos; si falla, el motivo sale dentro de la hoja con lo escrito conservado.
- **Validaciones antes de pedir nada** (las de la web): equipo elegido, título de 3 a 200 caracteres, descripción sin ser solo espacios (hasta 2000), intervalo entero de 1 a 3650, recordatorio entero de 0 a 365 que no supere el intervalo, primer servicio no anterior a ahora y horas mayores que 0, hasta 999 y con dos decimales (coma o punto). Cada error sale bajo su campo cuando se toca o se intenta programar.
- **Errores por `code`:** `schedule_not_found` (404), `schedule_equipment_unavailable` y `schedule_technician_inactive` (409), `equipment_not_found` y los 403 genéricos; el 422 del servidor llega por campo.
- **Arquitectura:** `MaintenanceRepository` (`lib/repositories/maintenance/`, avisa de cada cambio por un `Stream`); Blocs en `bloc/maintenance/`: `MaintenanceCalendarBloc` (descarta una respuesta que llega tarde de otro mes), `UpcomingMaintenanceBloc`, `SchedulesListBloc`, `ScheduleDetailBloc` y `ScheduleActionsBloc`; `EquipmentSearchBloc` en `bloc/equipment/`. La cuadrícula del calendario y las reglas del formulario están portadas de la web (`core/format/maintenance_calendar.dart` y `maintenance_format.dart`). Modelos en `models/maintenance/`; widgets en `widgets/maintenance/`. Sin paquetes nuevos: el calendario es de widgets propios y la fecha y hora usan los selectores de Material.
- **Colores:** todos de `AppColors` y `StatusColors`; lo vencido va en mostaza con texto navy (no en rojo) y el nombre del estado siempre va escrito.

**Verificación:** 1210 pruebas (bloc, repositorio, formato y widget; incluyen las de 320×568 y 360×640 con texto a 1,3 sin overflow), `flutter analyze` sin avisos. **No se ha visto en un teléfono ni se ha corrido `flutter build apk --debug` en esta rama:** la revisión a ojo la hace la persona dueña del proyecto. Comprobar a mano: el aspecto del calendario (tamaño de las celdas al tocar, fondos y puntos), el fondo degradado, el formulario con el teclado abierto, el selector de fecha y hora (cambiar de día, no solo aceptar el propuesto), la ficha con sus botones y el aviso que sale tras cada acción.

**Diferencias con las imágenes:** «Pendiente» es **«Vencido»** (la API no tiene ese estado); «Planta Principal» y «Planta Norte» son la **etiqueta del equipo** (la API no trae ubicación); el «Este campo es obligatorio» no sale al abrir el formulario vacío, sino al tocar el campo o al intentar programar. Se añadieron la leyenda de los puntos y «Ir a hoy».

**Fuera de esta versión (decidido):** editar un plan y reprogramar su fecha, aunque `PATCH /maintenance/schedules/{id}` lo admite (`next_due_at` con `reschedule_reason`).

**Pendientes de backend de esta pantalla** (no se tocó `MOVIL/backend` ni `WEB/backend`):

- Ni los planes ni el calendario traen la ubicación del equipo; solo etiqueta, marca y modelo.
- No existe un estado «pendiente»: la API distingue programado, vencido, hecho a tiempo, hecho con retraso e inactivo.
- El calendario admite como máximo 62 días por petición, así que no hay vista de año ni de rangos largos.
- Elegir el equipo del formulario exige `equipos:ver` (`GET /equipment`); un buscador de equipos propio del módulo evitaría ese permiso ajeno.
- `GET /maintenance/overview` (mezcla preventivo y correctivo, cumplimiento semanal, costos) existe y la web lo usa, pero la app no lo muestra.

**Ramas:** `feat/mobile-maintenance` sale de `feat/mobile-technicians`, que sale de `feat/mobile-users-roles` y esta de `feat/mobile-ui-polish` (ver «Usuarios y roles»). Nada se ha subido ni fusionado.

## Reportes

Hecha en código y pruebas en la rama `feat/mobile-reports` (sale de `feat/mobile-maintenance`). Ruta `/inicio/reportes` (la que ya tenía el menú; antes era un marcador de posición); exige `reportes:ver`. Exportar exige además `reportes:exportar`: sin él no se muestran los formatos ni el botón. La autorización real es del backend. No se tocó ningún backend.

- **Solo 4 reportes**, en este orden: Tickets de mantenimiento, Planes de mantenimiento, Inventario de equipos y Resumen operativo. Se quedan fuera las existencias y los movimientos de inventario (la app no tiene ese módulo) y los listados de técnicos y usuarios, que ya tienen su pantalla.
- **Solo PDF y Excel** (la web también exporta CSV). Las tarjetas de formato llevan los textos de la web. PDF y Excel salen del mismo generador y la misma paleta que en la web, así que el archivo es el mismo.
- **De dónde sale cada dato:** `GET /reports/catalog` (reportes y filtros que admite cada uno, límite de filas), `POST /reports/preview` (primeras filas, total y comparativo), `POST /reports/generate` (el archivo, descargado en streaming a un temporal con espera de hasta 120 s, compartido con la hoja del sistema y borrado después) y `GET /reports/history` (paginado por cabeceras).
- **Filtros:** solo viaja lo que el reporte admite (el servidor rechaza el resto). Fechas pasadas o futuras (los planes tienen fechas por venir), máximo 366 días; con un rango inválido no se pide nada y se explica. Comparativo con el periodo anterior solo en tickets y planes, y solo con las dos fechas. Cambiar de reporte limpia los filtros.
- **Contador de lo que se exportará:** sale de la vista previa (`total_rows`), con el aviso de archivo grande desde 2.000 filas y el bloqueo por encima del máximo del servidor, como la web.
- **Historial:** «Exportaciones recientes», por páginas, que se recarga solo después de exportar y falla por separado.
- **Estructura:** `ReportsRepository`; blocs `ReportsCatalogBloc`, `ReportPreviewBloc` (uno por reporte; descarta respuestas viejas), `ReportExportBloc` (una exportación a la vez) y `ReportHistoryBloc`; reglas en `core/format/report_format.dart`; widgets en `widgets/reports/`. Mostaza con texto navy para el reporte elegido, el formato elegido y el botón de exportar.
- **Cambio compartido:** el título de `FilterSheet` ahora se ajusta al ancho (desbordaba con textos largos y texto grande).
- **Verificación pendiente en dispositivo:** que el PDF y el Excel se abran bien desde la hoja de compartir en Android.

**Pendientes de backend de esta pantalla** (no se tocó `MOVIL/backend` ni `WEB/backend`):

- No hay un conteo barato para estos 4 reportes: la web tiene `/reports/{report}/export/count`, pero solo para tickets, técnicos y usuarios. La app usa la vista previa, que además trae las filas.
- Las opciones de columnas y de incluir el resumen solo existen en esas exportaciones; en estos 4 reportes el archivo sale con el contenido por defecto del servidor.
- `docs/error-codes.md` no tiene códigos propios de reportes salvo `export_forbidden`; ante un 422 al generar, la app pide acotar los filtros sin mostrar el detalle del servidor.
- `GET /reports/overview` (actividad de exportaciones) existe, pero la app no lo muestra.

**Ramas:** `feat/mobile-reports` sale de `feat/mobile-maintenance`. Nada se ha subido ni fusionado.

## Notificaciones y encabezado de los módulos

Todos los módulos con menú (dashboard, equipos, solicitudes, bandeja, reportes y los módulos aún sin construir) comparten `MantixAppBar` y `MantixDrawer`: la «M» a la izquierda, la campana de notificaciones, el avatar (abre el perfil) y el menú por permisos.

- **Campana:** muestra un punto cuando hay notificaciones sin leer y abre un panel (`GET /notifications`) con título, mensaje y fecha. Tocar una sin leer la marca como leída (`POST /notifications/{id}/read`) y «Marcar todas como leídas» usa `POST /notifications/read-all`. Se actualiza al instante en pantalla y, si el servidor falla, se vuelve a pedir la bandeja.
- **Bloc:** `NotificationsBloc` es global (vive en `MantixApp`): carga la bandeja al iniciar sesión, la vacía al cerrarla y se refresca al abrir el panel. Las «alertas» del dashboard («Atención inmediata») siguen en su sección y ya no se muestran en la campana.
- **Sin actualización automática:** la bandeja se actualiza al iniciar sesión y al abrir el panel; no hay sondeo periódico ni notificaciones push.

## Contrato de la API que usa la app

- Listados: array JSON plano; total en `X-Total-Count`, `X-Page`, `X-Page-Size`, `X-Total-Pages`. Parámetros `page`, `size` (máximo 500), `sort`, `search`. `/notifications` es la excepción (`limit`, `offset`, `{unread_count, items}`).
- Errores: `{detail, code, errors: [{field, message, type}] | null, request_id}`. Los `code` son estables y están en `MOVIL/docs/error-codes.md` (generado desde `MOVIL/backend/app/core/error_codes.py`); la app decide por `code` y, si es desconocido, por el estado HTTP.
- Estados del ticket: `GET /maintenance/requests/workflow`.
- Referencia completa: `docs/api-reference.md`.

## Resultados de la Fase 0.5 (Clerk en el móvil) — OBSOLETO, historial

> **OBSOLETO:** la app móvil ya no usa Clerk ni `clerk_flutter`. Estos resultados (incluido el problema del claim `azp`) se conservan solo como historial.

Medidos con un inicio de sesión real en un teléfono Android, contra el backend del móvil.

| Pregunta | Resultado |
| --- | --- |
| ¿El backend original acepta el token del móvil? | **No.** `GET /auth/me` da 401: el token no trae `azp` y el SDK lo exige si hay orígenes autorizados |
| Claim `azp` | No existe. Claims presentes: `exp, fva, iat, iss, nbf, sid, sts, sub, v` |
| `CLERK_AUTHORIZED_PARTIES` | Con el backend original ningún valor sirve, ni siquiera la lista vacía (por el código del SDK; esa parte se dedujo leyendo el código, no se probó) |
| ¿La copia del backend lo acepta? | **Sí.** `GET /auth/me` da 200 y el primer usuario recibe ADMIN en una base vacía |
| Duración del token | 60 s |
| Emisor | La misma instancia de Clerk que usa la web |

**Funciona:** registro y acceso con correo y contraseña, y la sesión sobrevive a reinstalar la app.

**No funciona o no se probó:**

- El acceso con Google falla con «Error received from server». No se diagnosticó: falta el texto completo del error.
- El formulario de Clerk solo trae textos en inglés.
- No se probó renovar el token pasados 60 s, cerrar sesión, recuperar contraseña ni un segundo usuario (debería quedar pendiente de aprobación).
- Los 4 tests nuevos de `MOVIL/backend/tests/test_clerk_auth.py` ya se ejecutaron y pasan (ver «Resultado de la Fase 1»).
- No se necesitó la huella SHA-256 para iniciar sesión. No se verificó si en el panel de Clerk estaba activado «Native applications».

## Resultado de la Fase 1 (backend del móvil)

Todo en `MOVIL/backend`; `WEB/backend` no se tocó.

- **Códigos de error:** 117 sitios que lanzan errores llevan ahora un `code` específico (`ticket_not_found`, `user_email_taken`, `ticket_requires_technician`…). Siguen los genéricos por estado HTTP como respaldo, y `invalid_transition`, `payload_too_large` y `unsupported_media_type` conservan su significado. Los 49 `unprocessable` y los `unsupported_media_type` de archivos quedan genéricos a propósito.
- **Tabla documentada:** `MOVIL/docs/error-codes.md`, generada con `python -m scripts.error_codes_doc`. Un test comprueba que cada código usado está registrado, que su estado HTTP coincide con el del tipo de error, que no hay códigos documentados sin usar y que el documento está al día.
- **Descripciones obsoletas corregidas:** la descripción de la API lista los cinco roles (faltaba AUDITOR), y los textos de adjuntos de equipo, movimientos de inventario, listado de usuarios y exportaciones nombran los permisos reales (`equipos:adjuntar`, `inventario:editar`, `usuarios:ver`…).
- **OpenAPI como artefacto:** `python -m scripts.export_openapi` y el workflow `.github/workflows/mobile-backend.yml`. No se pudo probar el workflow en GitHub desde local; el script y los tests sí se ejecutaron.
- **Verificación:** 1448 tests del backend contra un PostgreSQL desechable creado solo para la prueba (ninguno omitido) y `ruff` limpio. Sin esa base, 9 pruebas fallan y 115 se omiten por falta de `DATABASE_URL`; esas mismas 9 también fallan en el `WEB/backend` original, así que son del entorno y no de estos cambios.
- **Cambió el `code` de tres respuestas** (`invalid_transition` → `ticket_requires_technician` y `ticket_assign_wrong_status`; `conflict` → `equipment_identifier_taken`). Ningún cliente de la web usa `MOVIL/backend`, pero cualquier cliente nuevo debe tomarlos de la tabla.

## Pendientes de backend

- `MOVIL/backend` es una copia de `WEB/backend`: sincronizar los arreglos que se hagan en cualquiera de las dos.
- La suite completa de `MOVIL/backend` aún no corre en CI: el workflow `mobile-backend.yml` solo exporta el OpenAPI y comprueba los documentos generados. Falta replicar el job con PostgreSQL de `.github/workflows/ci.yml`.
- Diagnosticar el acceso con Google.
- **DECISIÓN PENDIENTE (no aprobada): unificar en un solo backend (`WEB/backend`).** Ya no incluye la validación de `azp` para el móvil (obsoleta). Sí incluiría los `code` de error, `error_codes.py`, los scripts de OpenAPI y **la autenticación nativa** (`mobile_auth`, `email_sender`, `code_email_limiter`, columnas `password_hash` y `email_verified_at`, tabla `auth_email_codes` y las migraciones `f5b6c7d8e9a0` y `f6c7d8e9a0b1`). Riesgos: dos esquemas distintos sobre la misma base si una copia migra y la otra no, y el desfase de modelos que detecta el CI. Orden propuesto en PR separados: corregir en `MOVIL/backend`, pruebas y CI de `MOVIL/backend`, modelo y migraciones en `WEB/backend`, servicio y rutas en `WEB/backend`, apuntar la app y retirar `MOVIL/backend` solo con aprobación.
- Equipos: `GET /equipment` entrega a un Solicitante todo el catálogo, con custodio y ubicación. Si se quiere limitar, hace falta un alcance por usuario o un permiso nuevo en `WEB/backend` (afecta también a la web).
- Equipos: no hay búsqueda exacta por `asset_tag`; el escaneo de QR de la Fase 8 la necesitará (filtro `asset_tag` o comparar en el cliente).
- **Implementado en la rama `feat/api-mobile-needs` (backend, ya fusionada en `develop` con el PR #94):** fechas (`date_from`/`date_to`) y varias categorías en `GET /equipment`, `GET /equipment/{id}/maintenance-records`, `POST /equipment/types`, `equipment` dentro de cada ticket de la lista, y varias prioridades y equipos en `GET /maintenance/requests`, todo con tests y sin migraciones ni permisos nuevos. La app ya usa todo eso. Contra un backend **sin** esa rama: las fechas y las categorías repetidas no filtran bien, «Crear nueva categoría» falla con su mensaje y la lista de mantenimientos de la ficha muestra un error con reintento (el resto de la ficha sigue). El detalle por commit está en la sección «Cambios de API solo en MOVIL/backend» de esa rama.
- Catálogos del tablero: `GET /maintenance/categories` no admite búsqueda ni páginas (la app filtra y reparte por páginas en el cliente y guarda la lista 5 minutos) y `GET /technicians` no filtra por cuenta activa (la app descarta los inactivos de cada página, así que una página puede traer menos de 20 y el total cuenta inactivos). Un filtro `is_active` en técnicos y búsqueda en categorías lo resolverían.
(Se completa durante el desarrollo: archivo, motivo y fase que lo necesita.)

## Cambios de API solo en MOVIL/backend (pendientes de unificar)

Rama `feat/api-mobile-needs`, desde `develop` (los cambios 7 a 10 los pide la pantalla de Solicitudes Pendientes de la app). Todos son **aditivos y retrocompatibles**: campos y filtros nuevos y opcionales, ningún `detail` existente cambió, **sin migraciones, sin modelos nuevos y sin permisos nuevos** (se reutilizan `tickets:ver_todos`, `equipos:editar` y `equipos:crear`). Mantienen la paginación por cabeceras (`X-Total-Count`, `X-Page`, `X-Page-Size`, `X-Total-Pages`) y el cuerpo de error `{detail, code, errors, request_id}`. No se tocó `WEB/`.

| # | Cambio | Dónde (archivo · función) | Commit |
|---|---|---|---|
| 1 | Cada ticket de la lista trae `equipment` (`id`, `asset_tag`, `brand`, `model`), cargado en lote (3 consultas por página, sin N+1) | `schemas/maintenance.py` · `MaintenanceRequestListItem.equipment`; `repositories/maintenance.py` · `MaintenanceRepository.list_requests` (`selectinload`) | `99e00a0` (+ `032fb1d`, `aa48746`, `71cb690`: ajustes de su prueba) |
| 2 | `GET /equipment/{id}/maintenance-records`: historial de mantenimientos del equipo, paginado, más reciente primero. Exige `tickets:ver_todos`; los costos salen vacíos sin `equipos:editar`. 404 `equipment_not_found` | `api/routes/equipment.py` · `list_equipment_maintenance_records`; `services/equipment.py` · `EquipmentService.list_maintenance_records`; `repositories/equipment.py` · `EquipmentRepository.list_maintenance_records` | `51c9752` |
| 3 | `GET /equipment?date_from=&date_to=` (sobre `created_at`, extremos incluidos; sin zona = UTC). `desde > hasta` → 422 `invalid_date_range`; formato inválido → 422 `validation_error` | `api/routes/equipment.py` · `list_equipment`; `services/equipment.py` · `list_equipment`, `_utc`; `repositories/equipment.py` · `list_equipment` | `2bc03a9` |
| 4 | `GET /equipment?equipment_type_id=1&equipment_type_id=2`: varias categorías (máx. 20; más → 422 `validation_error`). Un valor sigue igual | `api/routes/equipment.py` · `list_equipment`; `services/equipment.py` y `repositories/equipment.py` · `list_equipment(equipment_type_ids=…)` | `65677bb` |
| 5 | `GET /maintenance/requests`: `priority=critical,high` (lista por coma, como `status`) y `equipment_id` repetido; máx. 20 en cada filtro (por coma → 422 `filter_too_many_values`; repetido → 422 `validation_error`) | `api/routes/maintenance.py` · `list_maintenance_requests`; `services/maintenance.py` · `MaintenanceService.list_requests`; `repositories/maintenance.py` · `MaintenanceRepository.list_requests`; `core/filters.py` · `split_filter_list`, `MAX_FILTER_VALUES` | `97ea744` |
| 6 | `POST /equipment/types`: crea una categoría. Exige `equipos:crear`. Nombre recortado y con espacios colapsados (2–100 caracteres, con al menos una letra o dígito); único sin distinguir mayúsculas → 409 `equipment_type_name_taken` con el nombre existente en `detail`; el `code` se deriva del nombre (`PROYECTOR_HD`, con sufijo `_2`, `_3`… si choca); 201 con `{id, code, name}`; auditoría `equipment_type.created` | `api/routes/equipment.py` · `create_equipment_type`; `services/equipment.py` · `EquipmentService.create_type`, `_free_type_code`, `_type_code_base`; `repositories/equipment.py` · `find_type_by_name`, `type_code_exists`, `create_type`; `schemas/equipment.py` · `EquipmentTypeCreate` | `9003eed` |
| 7 | `GET /maintenance/requests?technician_id=1&technician_id=2`: tickets que tienen **ahora** a alguno de esos técnicos asignados (una asignación ya cerrada no cuenta); máx. 20 (más o no numérico → 422 `validation_error`). Se combina con los demás filtros | `api/routes/maintenance.py` · `list_maintenance_requests`; `services/maintenance.py` · `MaintenanceService.list_requests`; `repositories/maintenance.py` · `list_requests(technician_ids=…)` | `2d2a9a4` |
| 8 | `GET /maintenance/requests?category=hardware,network`: `category` admite lista separada por coma como `status` y `priority` (máx. 20 → 422 `filter_too_many_values`); un valor sigue igual | `api/routes/maintenance.py`; `services/maintenance.py` · `list_requests`; `repositories/maintenance.py` · `list_requests(categories=…)`; `core/filters.py` · `split_filter_list` | `2d2a9a4` |
| 9 | `GET /technicians?is_active=true`: solo técnicos cuya cuenta de usuario está activa (los que se pueden asignar); sin el parámetro, todos como antes | `api/routes/technician.py` · `list_technicians`; `services/technician.py` · `TechnicianService.list`; `repositories/technician.py` · `TechnicianRepository.list` | `2d2a9a4` |
| 10 | `GET /maintenance/categories?search=&page=&size=`: búsqueda por nombre y páginas con las cabeceras de paginación; sin parámetros devuelve todo el catálogo activo como antes (tamaño por defecto 200) | `api/routes/queue.py` · `list_categories`; `services/queue.py` · `QueueService.categories`; `repositories/queue.py` · `QueueRepository.active_categories` | `2d2a9a4` |
| 11 | **El último acceso (`last_login_at`) se registra al iniciar sesión en el móvil** y deja de leerse del flujo de Clerk. `login` y `verify-email` llaman a `record_login`: sellan `last_login_at` como mucho una vez cada 30 minutos y dejan la entrada de auditoría `auth.login`, en la misma transacción. Se quitó `_touch_login` de `ClerkAuthService` (el servicio de Clerk ya no escribe el acceso). Sin migraciones: la columna ya existía | `services/login_tracking.py` · `record_login`; `services/mobile_auth.py` · `MobileAuthService._record_login`, `login`, `verify_email`; `services/auth.py` · `ClerkAuthService.resolve_local_user` | `aaa39dd` |

**Pruebas del cambio 11:** escritas en `tests/test_login_tracking.py` (con dobles, sin base de datos) y ajustadas en `tests/test_clerk_auth.py`, pero **no se han ejecutado**: las reglas del proyecto prohíben correr `pytest` mientras no haya una base de pruebas aislada. `ruff` y la compilación sí pasan. Correrlas con `TEST_DATABASE_URL` apuntando a una base local `*_test` antes de integrar.

**Códigos de error nuevos** (en `core/error_codes.py` y `docs/error-codes.md`): `invalid_date_range` (422), `filter_too_many_values` (422) y `equipment_type_name_taken` (409). Documentos regenerados: `docs/api-reference.md` y `docs/error-codes.md` (ambos verificados por tests).

**Al llevarlo a `WEB/backend`:**

- Es un cherry-pick por commit; cada uno trae su prueba. Los tres comparten `core/filters.py` (cambios 4 y 5) y la entrada de `docs/error-codes.md`.
- Hay que regenerar los dos documentos con `python -m scripts.api_docs` y `python -m scripts.error_codes_doc`.
- La unicidad de categorías sin distinguir mayúsculas se valida en el servicio, no en la base: dos altas simultáneas con el mismo nombre en mayúsculas distintas podrían pasar las dos. Cerrarlo del todo exige un índice único sobre `lower(name)` (migración): decisión pendiente, no se hizo.
- `/reports/equipment` sigue aceptando una sola categoría (lo usa la exportación de la app).

**Pruebas:** contra una base PostgreSQL local desechable (`TEST_DATABASE_URL` con host `localhost` y nombre terminado en `_test`; nunca la de Neon). Los tests que usan `MIGRATED_DATABASE_URL` (base migrada con Alembic) no se corrieron. Fallan igual en `develop`, sin estos cambios: los 3 de `test_clerk_auth` y los 2 que revisan rutas públicas (`test_rbac::test_every_endpoint_requires_authentication` y `test_rbac_enforcement::test_every_route_declares_a_permission…`), por `/mobile-auth/*`.

## Sesión de Clerk en almacenamiento seguro (Fase 9) — OBSOLETO, resuelto

> **OBSOLETO:** `NativeAuthProvider` guarda el token propio con `flutter_secure_storage` y `clerk_flutter` ya no está en el proyecto. El `Persistor` que se planteaba aquí no hace falta.

**Hallazgo:** `clerk_flutter` guarda la sesión en `clerk_sdk.json`, dentro de los documentos privados de la app, y no en almacenamiento seguro. `flutter_secure_storage` está declarado en `pubspec.yaml` pero no se usa en `lib/`.

**Hecho:** `android:allowBackup="false"` en el manifiesto principal, para que ese archivo no salga en copias de seguridad en la nube.

**Pendiente (no implementar todavía):** un `Persistor` propio sobre `flutter_secure_storage` y comprobar que la sesión sobrevive a reiniciar la app. Ojo: la Fase 0.5 vio la sesión sobrevivir a reinstalar, probablemente por la restauración automática de Android; con `allowBackup="false"` eso ya no debería ocurrir (sin verificar en el teléfono).
