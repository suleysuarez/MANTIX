/// Configuración que se inyecta en la compilación con `--dart-define`
/// (o `--dart-define-from-file=dart_defines.json`).
///
/// Ninguna URL real ni clave va en el código. La publishable key de Clerk es
/// pública por diseño, pero igualmente se inyecta para poder cambiarla por
/// entorno. La secret key de Clerk nunca llega a la app: vive solo en el backend.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.appVersion,
    this.clerkPublishableKey = '',
  });

  /// En el emulador de Android, `10.0.2.2` apunta al `localhost` del equipo.
  static const String defaultApiBaseUrl = 'http://10.0.2.2:8000';

  final String apiBaseUrl;

  /// Se envía en `X-App-Version` para que el servidor pueda exigir una mínima.
  final String appVersion;

  /// Publishable key de Clerk (`pk_...`). Vacía: el inicio de sesión no se conecta.
  final String clerkPublishableKey;

  bool get hasClerk => clerkPublishableKey.startsWith('pk_');

  factory AppConfig.fromEnvironment() => const AppConfig(
        apiBaseUrl: String.fromEnvironment('API_BASE_URL', defaultValue: defaultApiBaseUrl),
        appVersion: String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
        clerkPublishableKey: String.fromEnvironment('CLERK_PUBLISHABLE_KEY'),
      );
}
