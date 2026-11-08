import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/services/api_client.dart';

import '../support/fakes.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test', appVersion: '9.9.9');

void main() {
  test('envía X-App-Version y el token como Bearer', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, {'ok': true}));
    final dio = createApiClient(config: config, auth: FakeAuthProvider(), adapter: adapter);

    await dio.get<Object?>('/auth/me');

    final headers = adapter.requests.single.headers;
    expect(headers['X-App-Version'], '9.9.9');
    expect(headers['Authorization'], 'Bearer token-0');
  });

  test('sin token no añade Authorization', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, {}));
    final dio = createApiClient(config: config, auth: FakeAuthProvider(token: null), adapter: adapter);

    await dio.get<Object?>('/x');

    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('ante un 401 renueva el token una vez y reintenta', () async {
    final auth = FakeAuthProvider();
    final adapter = FakeAdapter((options) {
      final ok = options.headers['Authorization'] == 'Bearer token-1';
      return ok ? jsonResponse(200, {'ok': true}) : jsonResponse(401, {'detail': 'x', 'code': 'unauthorized'});
    });
    final dio = createApiClient(config: config, auth: auth, adapter: adapter);

    final response = await dio.get<Object?>('/auth/me');

    expect(response.statusCode, 200);
    expect(auth.refreshCalls, 1);
    expect(adapter.requests.length, 2);
  });

  test('si el reintento también da 401, no entra en bucle', () async {
    final auth = FakeAuthProvider();
    final adapter = FakeAdapter((_) => jsonResponse(401, {'detail': 'x'}));
    final dio = createApiClient(config: config, auth: auth, adapter: adapter);

    await expectLater(
      dio.get<Object?>('/auth/me'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'estado', 401)),
    );

    expect(adapter.requests.length, 2);
    expect(auth.refreshCalls, 1);
  });

  test('varios 401 simultáneos provocan una sola renovación', () async {
    final auth = FakeAuthProvider();
    final adapter = FakeAdapter((options) {
      final ok = options.headers['Authorization'] == 'Bearer token-1';
      return ok ? jsonResponse(200, {'ok': true}) : jsonResponse(401, {'detail': 'x'});
    });
    final dio = createApiClient(config: config, auth: auth, adapter: adapter);

    final responses = await Future.wait([
      dio.get<Object?>('/a'),
      dio.get<Object?>('/b'),
      dio.get<Object?>('/c'),
    ]);

    expect(responses.map((r) => r.statusCode), [200, 200, 200]);
    expect(auth.refreshCalls, 1);
  });

  test('un error distinto de 401 no renueva el token', () async {
    final auth = FakeAuthProvider();
    final adapter = FakeAdapter((_) => jsonResponse(500, {'detail': 'x'}));
    final dio = createApiClient(config: config, auth: auth, adapter: adapter);

    await expectLater(dio.get<Object?>('/x'), throwsA(isA<DioException>()));

    expect(auth.refreshCalls, 0);
    expect(adapter.requests.length, 1);
  });
}
