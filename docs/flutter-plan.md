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
- **Filtros** (botón con embudo y contador de filtros activos): las tarjetas del resumen y una hoja con **categoría** y **estado** como multiselección (casillas que no cierran la hoja, «Aplicar» y «Limpiar») y **fecha de registro** con un calendario compacto (`date_from`/`date_to`). Cada filtro activo sale como chip que se quita solo. Cualquier filtro vuelve a la página 1. Varias categorías viajan como `equipment_type_id` repetido.
- **Paginación** (excepción a la regla general de «size=20 y scroll infinito», pedida para los listados): componente `Paginator` (`widgets/shared/paginator.dart`): una píldora de ancho completo con flechas en los extremos y los números de página en medio, con «…» y siempre la primera y la última («1 2 3 4 5 … 99»; la actual, en un círculo mostaza con aro; en pantallas estrechas caben menos números), y debajo «1-10 de 38» y el selector de tamaño de 5, 10, 20 o 50 que solo aparece si el total supera 5. Sin flecha «anterior» en la primera página ni «siguiente» en la última, y nada con una sola página. Cambiar de tamaño vuelve a la página 1. Los datos de la página se siguen mostrando mientras llega la siguiente.
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

- **Qué muestra:** encabezado a todo el ancho con `assets/images/solicitudes.png` (sin etiqueta); búsqueda y botón de filtros; cuatro cifras del mismo tamaño en un cuadro de 2×2, sin desplazamiento (EN COLA, SIN TÉCNICO, MÁS ANTIGUA, ESPERA MEDIANA); «Pulso de la cola» en dos columnas (primera respuesta y aprobación/rechazo arriba; barras por prioridad y por categoría abajo; el periodo del subtítulo lo da el servidor); y el tablero «Solicitudes por estado», con una columna por cada estado `in_queue` del flujo (hoy Recibidas, Clasificadas y Asignadas) **repartidas en todo el ancho y del mismo tamaño, sin desplazamiento horizontal** (tarjetas compactas). Los rótulos de columna, «Espera mediana» y el formato de horas, porcentajes y variaciones («24,1 h», «▲ 12,5%») son los de la web (`core/format/queue_format.dart`, con las pruebas de sus specs). Los nombres de prioridad y categoría salen de `GET /priorities` y `GET /maintenance/categories`; ninguno va escrito en la app. Color: mostaza de la paleta en las franjas de las cifras, el contador de cada columna y las variaciones que alertan.
- **De dónde sale cada dato:** `GET /maintenance/queue/summary?period=30d` (`solicitudes:ver_todos`) da las cifras y el pulso; `GET /maintenance/requests/workflow` da las columnas, las transiciones, los datos que exige cada destino y si se puede entrar en él; `GET /maintenance/requests?status=<uno>&size=10&sort=-created_at` da las tarjetas de cada columna (total en `X-Total-Count`).
- **Carga:** 10 tarjetas por columna y «Ver más (N restantes)» (excepción pedida a la regla de `size=20`); nunca se pide el catálogo completo. Cada bloque carga y falla por separado: si el resumen cae, las cifras y el pulso dicen «no disponible» con reintento y el tablero sigue; si una columna cae, solo ella muestra el error con reintento. Tirar hacia abajo recarga resumen y columnas.
- **Filtros** (hoja con «Aplicar» y «Limpiar»): categoría, prioridad y técnico con multiselección, y «Recibidas entre» (la inicial no puede ser futura, la final no anterior y como máximo 366 días). Cada filtro activo sale como chip que se quita. Categorías múltiples viajan como `category=a,b` y técnicos como `technician_id` repetido; **ambos necesitan el backend de `feat/api-mobile-needs`** (cambios 7 y 8), igual que el nombre del equipo en la tarjeta: sin él la tarjeta muestra «Equipo #id».
- **Mover una tarjeta:** pulsación larga y arrastre (la pantalla se desplaza sola cerca del borde de arriba o de abajo; solo se resaltan las columnas válidas) o menú «Mover a…» (con «Rechazar» para cancelar). Soltar donde no se puede devuelve la tarjeta y lo explica en español (falta de permiso o transición no permitida) sin pedir nada. Destinos que exigen datos: Clasificadas pide categoría y prioridad (`POST …/classify`, `solicitudes:editar`), Asignadas un técnico activo (`POST …/assignment`, `tickets:asignar`) y Rechazar un motivo de 5 a 500 caracteres (`POST …/reject`, `solicitudes:aprobar`); cerrar la hoja deja la tarjeta donde estaba. A diferencia del tablero de Tickets, aquí el cambio es **optimista**: la tarjeta cambia de columna al confirmar y vuelve a su sitio si el servidor lo rechaza (técnico inactivo, sin permiso, sin red), con el mensaje por `code`. Al aceptarse se recargan columnas y cifras. Tocar una tarjeta abre su detalle.
- **Arquitectura:** `QueueSummaryBloc`, `RequestBoardBloc` y `TriageActionsBloc` (`bloc/queue/`); `QueueRepository`; `CategoryNamesCubit`; modelos en `models/queue/`; widgets en `widgets/queue/`. `TriageActionsBloc` no toca el tablero: emite un resultado (`started`, `succeeded`, `failed`, `blocked`) y la pantalla se lo pasa a los otros dos.
- **Colores:** todos de `AppColors` y `StatusColors` (solo se añadieron `bannerDeep` y `bannerLight`, que coinciden con el fondo de la imagen del encabezado).

**Verificación:** 715 pruebas, `flutter analyze` sin avisos, sin overflow a 320×568 y 360×640 con texto a 1,3, y `flutter build apk --debug`. La revisión a ojo en el teléfono (arrastre con el dedo, desplazamiento automático, aspecto del encabezado) la hace la persona dueña del proyecto.

**Pendientes de esta pantalla:**

- Integrar `feat/api-mobile-needs` (hoy sin integrar) para que filtren técnico y varias categorías y salga el nombre del equipo; el orden de los PR es el de la sección anterior.
- Con ese backend integrado, `TechnicianSearchBloc` puede pedir `is_active=true` en vez de descartar los inactivos, y `CategorySearchBloc` puede pedir `search` y páginas al servidor en vez de filtrar en la app (cambios 9 y 10).
- Sin selector de periodo (7 días, 30 días, 12 meses) ni orden por prioridad ni filtro «solo sin técnico», que la web sí tiene; se añaden si se piden.


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
- **Implementado en la rama `feat/api-mobile-needs` (backend, sin integrar):** fechas (`date_from`/`date_to`) y varias categorías en `GET /equipment`, `GET /equipment/{id}/maintenance-records`, `POST /equipment/types`, `equipment` dentro de cada ticket de la lista, y varias prioridades y equipos en `GET /maintenance/requests`, todo con tests y sin migraciones ni permisos nuevos. La app ya usa todo eso. Contra un backend **sin** esa rama: las fechas y las categorías repetidas no filtran bien, «Crear nueva categoría» falla con su mensaje y la lista de mantenimientos de la ficha muestra un error con reintento (el resto de la ficha sigue). El detalle por commit está en la sección «Cambios de API solo en MOVIL/backend» de esa rama.
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
