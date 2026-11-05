/// Configuration injected with --dart-define or dart_defines.json.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.appVersion});

  static const String defaultApiBaseUrl = 'http://10.0.2.2:8001';
  final String apiBaseUrl;
  final String appVersion;

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL', defaultValue: defaultApiBaseUrl),
    appVersion: String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
  );
}
