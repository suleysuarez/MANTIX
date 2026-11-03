# Mantix móvil

App Android de Mantix (Flutter). Reutiliza la API FastAPI de `WEB/backend` sin modificarla. Las decisiones y reglas están en [`docs/flutter-plan.md`](../docs/flutter-plan.md).

## Estado

Fase 2 (base y acceso) en curso. Hay estructura, tema, cliente HTTP, sesión, router por permisos y las pantallas de acceso (carga, login, pendiente, sin acceso, sin conexión) y Perfil. Las pantallas de inicio de las fases 4 a 7 son marcadores.

**Pendiente de la Fase 2:** conectar el proveedor de identidad. Hasta entonces `UnconfiguredAuthProvider` nunca devuelve token y la app arranca en la pantalla de acceso. La decisión de proveedor (Clerk) depende de la Fase 0.5.

## Ejecutar

```bash
cd MOVIL
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` es el `localhost` del equipo visto desde el emulador de Android. Sin `--dart-define` se usa ese valor. Para un dispositivo real usa la IP de tu equipo en la red local.

| Variable | Para qué | Por defecto |
| --- | --- | --- |
| `API_BASE_URL` | URL del backend | `http://10.0.2.2:8000` |
| `APP_VERSION` | Se envía en `X-App-Version` | `1.0.0` |

Ninguna clave ni URL real va en el código.

## Probar

```bash
flutter analyze
flutter test
```

## Estructura

```text
lib/
  core/
    auth/      perfil, home_resolver, sesión y origen del token
    config/    configuración por --dart-define
    errors/    Failure y traducción de errores de Dio
    network/   cliente HTTP y providers
    routing/   router y redirecciones por sesión
    theme/     paleta y tema
  shared/      widgets compartidos
  features/    auth, home, profile (presentation por ahora)
```

## Reglas que ya se cumplen en el código

- La app decide por **permisos** de `GET /auth/me`, nunca por nombre de rol.
- Sin roles es «pendiente de aprobación»; con roles y cero permisos es «sin acceso asignado».
- Un 401 renueva el token una sola vez y reintenta; varios 401 simultáneos provocan una sola renovación.
- Errores sin detalles internos del servidor.
- Colores solo en `core/theme`; objetivos táctiles de al menos 48 px.
