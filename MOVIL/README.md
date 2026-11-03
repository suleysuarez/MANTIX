# Mantix móvil

App Android de Mantix (Flutter, `com.suleysuarez.mantix`). Consume la API FastAPI de Mantix. Las decisiones, reglas y fases están en [`../docs/flutter-plan.md`](../docs/flutter-plan.md).

## Estado

| Fase | Estado |
| --- | --- |
| 0 Auditoría de reutilización | Hecha |
| 0.5 Prueba de concepto de Clerk | Hecha (registro e inicio con correo y contraseña; Google falla, sin diagnosticar) |
| 1 Backend mínimo (códigos de error estables, OpenAPI como artefacto) | Hecha, en `MOVIL/backend` |
| 2 Base Flutter y autenticación | Hecha: estructura, tema, cliente HTTP, sesión con Clerk, router por permisos, pantallas de acceso y Perfil |
| 3 Componentes y sistema de diseño | Hecha; falta revisarla a ojo en el teléfono |
| 4 a 7 Solicitante, Técnico, Supervisor, Administrador | **Sin empezar.** Las pantallas de inicio son marcadores |
| 8 Push y escaneo de QR | Sin empezar |
| 9 Calidad y entrega | Sin empezar (ícono por defecto, release firmado con la clave de debug) |

Hoy la app permite iniciar sesión con Clerk, ver el estado de la cuenta (activa, pendiente de aprobación o sin acceso asignado), el Perfil con roles y permisos, y cerrar sesión. No hay pantallas de negocio todavía.

## Autenticación

Clerk, con `clerk_flutter` (beta, no oficial). La app envía el JWT de sesión como `Authorization: Bearer` y consulta `GET /auth/me` para conocer roles y permisos. Los tokens de Clerk del móvil no traen el claim `azp`; por eso se usa `MOVIL/backend`, que lo valida por su cuenta (detalle en el plan).

Sin `CLERK_PUBLISHABLE_KEY` la app arranca igual, pero no puede iniciar sesión.

## Ejecutar

1. Levanta un backend (para el del móvil: `docker compose up --build -d` dentro de `MOVIL/`; escucha en el puerto 8001).
2. Crea tu archivo de variables a partir del ejemplo (`dart_defines.json` está ignorado por Git):

   ```bash
   cd MOVIL
   cp dart_defines.example.json dart_defines.json   # edita la publishable key de Clerk
   flutter pub get
   flutter run --dart-define-from-file=dart_defines.json
   ```

| Variable | Para qué | Por defecto |
| --- | --- | --- |
| `API_BASE_URL` | URL del backend | `http://10.0.2.2:8000` |
| `CLERK_PUBLISHABLE_KEY` | Publishable key de Clerk (`pk_...`) | vacía: sin inicio de sesión |
| `APP_VERSION` | Se envía en `X-App-Version` | `1.0.0` |

- **Emulador:** `10.0.2.2` es el `localhost` del equipo. El backend del móvil usa el puerto 8001, así que pon `API_BASE_URL` en `http://10.0.2.2:8001` o usa el 8000 si levantas el de la web.
- **Teléfono por USB:** `adb reverse tcp:8001 tcp:8001` y `API_BASE_URL=http://localhost:8001` (es el valor del ejemplo).
- La secret key de Clerk vive solo en el backend; ninguna clave ni URL real va en el código.

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
  core/
    auth/        perfil, home_resolver, sesión y origen del token (Clerk)
    config/      configuración por --dart-define
    domain/      metadatos de tickets
    errors/      Failure, códigos de error y mensajes en español
    network/     cliente HTTP (Dio), paginación y providers
    routing/     router y redirecciones por sesión
    theme/       paleta, tokens y tema
    validation/  validadores de formularios
  shared/        componentes reutilizables (estados cargando, vacío y error, chips, diálogos...)
  features/      auth, home (marcadores), profile, dev (galería de componentes, solo debug)
backend/         copia de WEB/backend con ajustes para Clerk nativo y códigos de error
docs/            error-codes.md, api-reference.md, rbac-matriz.md
```

## Reglas que ya se cumplen en el código

- La app decide por **permisos** de `GET /auth/me`, nunca por nombre de rol.
- Sin roles es «pendiente de aprobación»; con roles y cero permisos es «sin acceso asignado».
- Un 401 renueva el token una sola vez y reintenta; varios 401 simultáneos provocan una sola renovación.
- Errores sin detalles internos del servidor; mensajes en español por `code` del backend.
- Colores solo en `core/theme`; objetivos táctiles de al menos 48 px.

## Límites conocidos

- Clerk guarda su sesión en un archivo JSON dentro del almacenamiento privado de la app, no en el almacenamiento seguro del sistema. Ver el plan.
- Los permisos solo deciden el inicio; todavía no hay pantallas que ocultar o deshabilitar por permiso.
