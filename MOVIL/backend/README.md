# Backend de la app móvil

API FastAPI que consume la app Flutter. Autenticación nativa con correo y contraseña; los códigos de verificación y de recuperación llegan por correo.

## Correo por API HTTPS (Brevo)

Úsalo cuando el servidor **bloquea los puertos SMTP** (el plan gratuito de Render lo hace, según su documentación): Gmail por SMTP falla con `OSError` y `smtp_code=None`. La API viaja por HTTPS (puerto 443), que no está bloqueado.

1. Crea una cuenta en Brevo (plan gratuito).
2. En *Senders, Domains & Dedicated IPs → Senders* agrega y **verifica** el correo remitente (Brevo envía un enlace de confirmación). No hace falta un dominio propio.
3. En *SMTP & API → API Keys* crea una **clave de API** y cópiala una sola vez.
4. Define estas variables en el servicio (nunca en el repositorio):

| Variable | Qué poner |
|---|---|
| `BREVO_API_KEY` | La clave de API de Brevo |
| `EMAIL_FROM` | El remitente verificado en Brevo (admite `Nombre <cuenta@dominio>`). Si falta, se usa `SMTP_FROM` |

- Con `BREVO_API_KEY` presente **no se usa SMTP**; sin ella todo sigue como en la sección de SMTP de abajo.
- El arranque avisa en el registro si falta el remitente. Un envío fallido no cambia la respuesta de la API y se registra con el estado HTTP (`http_status`), sin la clave, sin el código y con el correo enmascarado.
- La cuenta gratuita de Brevo tiene cuota diaria; el limitador de envíos de abajo también aplica.

## Correo por SMTP (Gmail)

Solo para **desarrollo o demostración**. Una cuenta personal tiene cuota diaria y puede ser bloqueada si se abusa. Para producción hace falta un proveedor con dominio verificado.

### Preparar la cuenta de Gmail

1. Activa la **verificación en dos pasos** en tu cuenta de Google (Seguridad → Verificación en dos pasos).
2. Crea una **contraseña de aplicación** (Seguridad → Contraseñas de aplicaciones). Google muestra 16 caracteres, a veces separados en grupos: cópialos **sin espacios**.
3. No uses tu contraseña normal de Google: no funciona por SMTP.

### Variables (solo en `backend/.env`, que Git ignora)

| Variable | Qué poner |
|---|---|
| `SMTP_HOST` | `smtp.gmail.com` |
| `SMTP_PORT` | `587` (STARTTLS) |
| `SMTP_USERNAME` | La cuenta de Gmail completa |
| `SMTP_PASSWORD` | La contraseña de aplicación de 16 caracteres, sin espacios |
| `SMTP_FROM` | La **misma** cuenta que `SMTP_USERNAME` (admite `Nombre <cuenta@gmail.com>`) |

No hay valores por defecto. Nunca subas el `.env` ni pegues la contraseña en mensajes, issues o capturas. `docker compose` pasa el `.env` al contenedor con `env_file`, así que no se escribe nada en el compose.

### Comportamiento

- La conexión usa STARTTLS obligatorio con verificación del certificado y un tiempo de espera de 15 s. Si el servidor no ofrece STARTTLS, no se envía.
- Si falta una variable o `SMTP_FROM` no coincide con la cuenta, el arranque lo avisa en el registro y el envío falla con un error específico. La API sigue funcionando.
- Un envío fallido **nunca cambia la respuesta**: `register`, `resend-verification` y `forgot-password` responden igual (202). El error se registra sin el código, sin la contraseña y con el correo enmascarado (`a***@gmail.com`).
- Límites de envío, en un solo limitador: mínimo **60 s** entre correos a la misma cuenta, **5 por hora** por cuenta y **60 por hora** en todo el sistema. Si se superan, no se emite código nuevo (el código vigente y sus intentos no se tocan) y la respuesta sigue siendo 202.
- **Limitación:** los contadores viven en la memoria del proceso. Se reinician al arrancar y no se comparten entre procesos ni réplicas. Es aceptable para la demo; en producción haría falta un almacén compartido.

## Límites de la API

- Toda la API: `RATE_LIMIT_PER_MINUTE` por IP (120 por defecto), en memoria del proceso.
- `/mobile-auth/*`: además, **20 peticiones por minuto por IP**.
- Detrás de un proxy inverso, todas las peticiones llegan con la IP del proxy y comparten contador. Arranca `uvicorn` con `--proxy-headers` y la variable `FORWARDED_ALLOW_IPS` con la IP del proxy para que se use la IP real del cliente. Sin proxy no hace falta nada.

## Sesión y revocación

- El token de acceso es un JWT que dura 480 minutos por defecto (`MOBILE_ACCESS_TOKEN_MINUTES`). No hay refresco.
- Cada token lleva la versión de sesión de la cuenta (`users.token_version`). `POST /mobile-auth/logout` (con el token en `Authorization: Bearer`) y `reset-password` la incrementan, y todos los tokens anteriores de esa cuenta dejan de servir, en todos los dispositivos.
- Migración: `a7b8c9d0e1f2_user_token_version.py` añade la columna con valor 0. Los tokens emitidos antes de esta versión no llevan el dato y cuentan como versión 0, así que siguen válidos hasta el primer cierre de sesión o restablecimiento.
- La app llama a `/mobile-auth/logout` al cerrar sesión, antes de borrar el token local, y cierra igual si la llamada falla. Cerrar sesión en un dispositivo cierra la sesión en todos.

## Registro y contraseña

- `verify-email` recibe el correo, el código **y la contraseña**: la contraseña la fija quien tiene el código en su buzón. Así, quien pre-registró un correo ajeno con otra contraseña no la conserva cuando el dueño verifica, sin importar quién registró último.
- Si alguien vuelve a registrar un correo que quedó sin verificar, la última contraseña enviada reemplaza a la anterior y el código anterior deja de servir. Esa contraseña provisional se sustituye por la de `verify-email`.
- La app conserva la contraseña solo en memoria, entre el registro y la verificación.

## Pruebas

Las pruebas nunca envían correos ni abren conexiones SMTP (`tests/conftest.py` lo impide). Las que usan base de datos exigen `TEST_DATABASE_URL` apuntando a una base **local** cuyo nombre termine en `_test`; con otra URL se niegan a ejecutarse. Nunca las apuntes a una base compartida o a Neon.
