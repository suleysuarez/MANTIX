# Mantix móvil

App Android de Mantix (Flutter, `com.suleysuarez.mantix`). Consume la API FastAPI de Mantix. Las decisiones, reglas y fases están en [`../docs/flutter-plan.md`](../docs/flutter-plan.md).

## Estado

| Fase | Estado |
| --- | --- |
| 0 Auditoría de reutilización | Hecha |
| 0.5 Prueba de concepto de Clerk | Sustituida por autenticación nativa Mantix para móvil |
| 1 Backend mínimo (códigos de error estables, OpenAPI como artefacto) | Hecha, en `MOVIL/backend` |
| 2 Base Flutter y autenticación | En implementación: estructura, tema, cliente HTTP, sesión nativa, router por permisos y Perfil |
| 3 Componentes y sistema de diseño | Hecha; falta revisarla a ojo en el teléfono |
| 4 Solicitante | Hecha en código y pruebas: mis solicitudes, detalle y nueva solicitud. Falta revisarla en el teléfono; los adjuntos son de solo lectura |
| 5 a 7 Técnico, Supervisor, Administrador | **Sin empezar.** Sus pantallas de inicio son marcadores |
| 8 Push y escaneo de QR | Sin empezar |
| 9 Calidad y entrega | Sin empezar (ícono por defecto, release firmado con la clave de debug) |

La app móvil usa autenticación nativa Mantix con correo y contraseña. Crear una cuenta no pide verificar el correo: se entra enseguida, pero la cuenta queda pendiente de aprobación hasta que un administrador les asigne un rol. La web Angular conserva Clerk. Con permiso de solicitudes, además lista, consulta y crea solicitudes de mantenimiento. Aún no hay pantallas de Técnico, Supervisor ni Administrador.

## Autenticación móvil

La app Flutter usa los endpoints nativos de FastAPI `/mobile-auth/register` y `/mobile-auth/login`. Crear la cuenta **no envía ningún correo ni código**: la cuenta queda lista y la app inicia sesión enseguida. El backend firma tokens Mantix y Flutter los guarda con `flutter_secure_storage` (Keystore/Keychain). Los endpoints de verificación y de recuperación de contraseña por correo (`/verify-email`, `/resend-verification`, `/forgot-password`, `/reset-password`) siguen en la API, pero la app ya no los usa.

El correo solo haría falta para esos endpoints de recuperación, que la app no ofrece hoy (ver `backend/README.md` si se vuelven a usar). **Sin verificar el correo, cualquiera puede crear una cuenta con la dirección de otra persona:** por eso las cuentas nuevas no reciben roles automáticamente y quedan pendientes hasta que un administrador asigne el rol correspondiente. La app consulta `GET /auth/me` para cargar roles y permisos.

**La autenticación Clerk de Angular/web no se modifica.** FastAPI acepta tanto los tokens Clerk existentes como los tokens nativos de la app.

Variables privadas del backend: `MOBILE_JWT_SECRET`, `MOBILE_ACCESS_TOKEN_MINUTES` (480 por defecto), `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` y `AUTH_VERIFICATION_EXPIRE_MINUTES`. `SMTP_FROM` debe ser la misma cuenta que `SMTP_USERNAME`. Nunca se incluyen en `dart_defines.json`.

## Ejecutar

1. Configura `MOVIL/backend/.env` con la cadena de conexión de **Neon** en `DATABASE_URL` (formato `postgresql://...`, con SSL habilitado; no uses `db` como host), `MOBILE_JWT_SECRET` (mínimo 32 bytes), las cinco variables `SMTP_*` y `AUTH_VERIFICATION_EXPIRE_MINUTES`. Si quieres que la web y Flutter compartan los mismos usuarios y datos, usa la misma base de datos Neon que tiene configurada `WEB/backend/.env`. No subas este archivo al repositorio.
2. Aplica las migraciones de forma explícita contra Neon: `docker compose run --build --rm backend alembic upgrade head` (ejecútalo una vez después de configurar `MOVIL/backend/.env` y antes de iniciar la API).
3. Levanta el backend móvil con `docker compose up --build -d` dentro de `MOVIL/`; escucha en el puerto 8001 y usa el `DATABASE_URL` de Neon definido en `MOVIL/backend/.env`. El stack móvil ya no inicia una base PostgreSQL local.
4. Crea tu archivo de variables a partir del ejemplo (`dart_defines.json` está ignorado por Git):

   ```bash
   cd MOVIL
   cp dart_defines.example.json dart_defines.json   # configura la URL de la API
   flutter pub get
   flutter run --dart-define-from-file=dart_defines.json
   ```

| Variable | Para qué | Por defecto |
| --- | --- | --- |
| `API_BASE_URL` | URL del backend | `http://10.0.2.2:8001` |
| `APP_VERSION` | Se envía en `X-App-Version` | `1.0.0` |

- **Emulador:** `10.0.2.2` es el `localhost` del equipo. El backend del móvil usa el puerto 8001; si usas el backend de la web, configura su puerto real.
- **Teléfono por USB:** `adb reverse tcp:8001 tcp:8001` y `API_BASE_URL=http://localhost:8001` (es el valor del ejemplo).
- La secret key de Clerk vive solo en el backend para la web. Ningún secreto se incluye en Flutter.

## Red y permisos de Android

- `INTERNET` está en el manifiesto principal.
- El tráfico HTTP sin cifrar (`usesCleartextTraffic`) solo está en `android/app/src/debug`. Los builds de release y profile no lo permiten, así que un release necesita una API con HTTPS.

## Probar

```bash
flutter analyze
flutter test
```

## Estructura

```text
lib/
  main.dart
  pages/         pantallas completas, por módulo (auth, home, profile, requests, dev)
  widgets/       componentes reutilizables (shared, auth)
  models/        clases de datos (auth, requests, page_info)
  services/      cliente HTTP (Dio), proveedor de token (nativo), interceptor
  repositories/  acceso a datos por módulo (auth, home, requests)
  bloc/          un Bloc por flujo (auth, paged, requests)
  core/          app.dart, config, errors, format, routing, theme, validation
assets/          imágenes
test/            espejo de lib/
backend/         API FastAPI compartida: Clerk web + autenticación nativa móvil
docs/            error-codes.md, api-reference.md, rbac-matriz.md
```

## Qué va dónde

- `pages/<mod>`: pantalla completa por ruta; solo `BlocBuilder`/`BlocListener`, sin Dio ni repositorios.
- `widgets/<mod|shared>`: componentes reutilizables sin lógica de negocio.
- `models/<mod>`: clases de datos con `Equatable`; sin Flutter ni red.
- `services/`: cliente HTTP, interceptor, proveedor de token.
- `repositories/<mod>`: un repositorio por módulo; usa services y devuelve models o `Failure`.
- `bloc/<mod>`: un Bloc por flujo con `_bloc`, `_event` y `_state`.
- `core/`: transversal (app, config, errors, format, routing, theme, validation).

Ejemplo, módulo nuevo `tickets`: `models/tickets/ticket_models.dart`, `repositories/tickets/tickets_repository.dart`, `bloc/tickets/tickets_{bloc,event,state}.dart`, `pages/tickets/tickets_screen.dart`, la ruta en `core/routing/app_router.dart` y el espejo en `test/`.

## Reglas que ya se cumplen en el código

- La app decide por **permisos** de `GET /auth/me`, nunca por nombre de rol.
- Sin roles es «pendiente de aprobación»; con roles y cero permisos es «sin acceso asignado».
- El token móvil se guarda en el almacenamiento seguro del sistema operativo.
- Errores sin detalles internos del servidor; mensajes en español por `code` del backend.
- Colores solo en `core/theme`; objetivos táctiles de al menos 48 px.

## Límites conocidos

- La sesión móvil usa JWT de acceso sin refresh token todavía; al expirar, el usuario debe iniciar sesión de nuevo.
- Los permisos solo deciden el inicio; todavía no hay pantallas que ocultar o deshabilitar por permiso.
