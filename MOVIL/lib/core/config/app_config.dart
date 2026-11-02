/// Runtime configuration, read from `--dart-define` so no URL or key lives in the repository.
///
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///     flutter build apk --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://...
enum AppEnv { development, production }

class AppConfig {
  const AppConfig._({
    required this.env,
    required this.apiBaseUrl,
    required this.appVersion,
  });

  /// Android emulator alias for the host machine's localhost.
  static const developmentApiBaseUrl = 'http://10.0.2.2:8000';

  final AppEnv env;

  /// Without trailing slash.
  final String apiBaseUrl;

  /// Sent as `X-App-Version` on every request.
  final String appVersion;

  bool get isProduction => env == AppEnv.production;

  factory AppConfig.fromEnvironment() => AppConfig.resolve(
    env: const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    appVersion: const String.fromEnvironment(
      'APP_VERSION',
      defaultValue: '0.0.0',
    ),
  );

  /// Validates the raw values. Production needs an explicit HTTPS URL; development falls back
  /// to the emulator's host address.
  factory AppConfig.resolve({
    required String env,
    required String apiBaseUrl,
    required String appVersion,
  }) {
    final parsedEnv = switch (env) {
      'development' => AppEnv.development,
      'production' => AppEnv.production,
      _ => throw ArgumentError.value(
        env,
        'APP_ENV',
        'Use development or production',
      ),
    };
    var url = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) {
      if (parsedEnv == AppEnv.production) {
        throw StateError('API_BASE_URL is required when APP_ENV=production');
      }
      url = developmentApiBaseUrl;
    }
    if (parsedEnv == AppEnv.production && !url.startsWith('https://')) {
      throw StateError(
        'API_BASE_URL must use https:// when APP_ENV=production',
      );
    }
    return AppConfig._(
      env: parsedEnv,
      apiBaseUrl: url,
      appVersion: appVersion.trim().isEmpty ? '0.0.0' : appVersion.trim(),
    );
  }
}
