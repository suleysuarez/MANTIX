import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/config/app_config.dart';

void main() {
  test('development falls back to the emulator host address', () {
    final config = AppConfig.resolve(
      env: 'development',
      apiBaseUrl: '',
      appVersion: '1.2.3',
    );
    expect(config.env, AppEnv.development);
    expect(config.apiBaseUrl, 'http://10.0.2.2:8000');
    expect(config.appVersion, '1.2.3');
    expect(config.isProduction, isFalse);
  });

  test('trims the URL and its trailing slashes', () {
    final config = AppConfig.resolve(
      env: 'development',
      apiBaseUrl: ' http://192.168.1.20:8000// ',
      appVersion: '',
    );
    expect(config.apiBaseUrl, 'http://192.168.1.20:8000');
    expect(config.appVersion, '0.0.0');
  });

  test('production needs an explicit https URL', () {
    expect(
      () =>
          AppConfig.resolve(env: 'production', apiBaseUrl: '', appVersion: '1'),
      throwsStateError,
    );
    expect(
      () => AppConfig.resolve(
        env: 'production',
        apiBaseUrl: 'http://api.example.com',
        appVersion: '1',
      ),
      throwsStateError,
    );
    final config = AppConfig.resolve(
      env: 'production',
      apiBaseUrl: 'https://api.example.com/',
      appVersion: '1',
    );
    expect(config.isProduction, isTrue);
    expect(config.apiBaseUrl, 'https://api.example.com');
  });

  test('rejects an unknown environment', () {
    expect(
      () => AppConfig.resolve(env: 'staging', apiBaseUrl: '', appVersion: '1'),
      throwsArgumentError,
    );
  });
}
