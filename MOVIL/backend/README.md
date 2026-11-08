# Backend de la app móvil

API FastAPI que consume la app Flutter. Autenticación nativa con correo y contraseña; los códigos de verificación y de recuperación llegan por correo.

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

## Pruebas

Las pruebas nunca envían correos ni abren conexiones SMTP (`tests/conftest.py` lo impide). Las que usan base de datos exigen `TEST_DATABASE_URL` apuntando a una base **local** cuyo nombre termine en `_test`; con otra URL se niegan a ejecutarse. Nunca las apuntes a una base compartida o a Neon.
