import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/network/api_client.dart';
import 'package:mantix/core/network/error_interceptor.dart';

import '../../support/fake_api.dart';

const unauthorized = FakeResponse(401, {
  'detail': 'Tu sesión no es válida',
  'code': 'unauthorized',
});

/// A server that accepts only the renewed token.
FakeResponse acceptsNewOnly(SeenRequest request) =>
    request.authorization == 'Bearer new'
    ? const FakeResponse(200, {'ok': true})
    : unauthorized;

class Harness {
  Harness(
    FakeResponse Function(SeenRequest) server, {
    FakeTokenProvider? provider,
  }) : tokens = provider ?? FakeTokenProvider() {
    adapter = FakeAdapter(server);
    dio = createApiClient(
      config: AppConfig.resolve(
        env: 'development',
        apiBaseUrl: 'http://10.0.2.2:8000',
        appVersion: '1.4.0',
      ),
      tokenProvider: tokens,
      onSessionExpired: () => expired++,
      adapter: adapter,
    );
  }

  final FakeTokenProvider tokens;
  late final FakeAdapter adapter;
  late final Dio dio;
  int expired = 0;
}

Future<Failure> failureOf(Future<Object?> request) async {
  try {
    await request;
  } on DioException catch (e) {
    return e.failure;
  }
  fail('the request should have failed');
}

void main() {
  group('token renewal', () {
    test(
      'several simultaneous 401s renew once and each retries once',
      () async {
        final h = Harness(acceptsNewOnly);

        final results = await Future.wait([
          h.dio.get<Object?>('/maintenance/requests'),
          h.dio.get<Object?>('/equipment'),
          h.dio.get<Object?>('/notifications'),
        ]);

        expect(results.map((r) => r.statusCode), [200, 200, 200]);
        expect(h.tokens.refreshCalls, 1);
        expect(h.adapter.seen.length, 6);
        expect(
          h.adapter.seen.where((r) => r.authorization == 'Bearer old').length,
          3,
        );
        expect(
          h.adapter.seen.where((r) => r.authorization == 'Bearer new').length,
          3,
        );
        expect(h.expired, 0);
      },
    );

    test('a request is retried only once, never in a loop', () async {
      final h = Harness((_) => unauthorized);

      final failure = await failureOf(h.dio.get<Object?>('/equipment'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(h.adapter.seen.length, 2); // the original and one retry
      expect(h.tokens.refreshCalls, 1);
      expect(h.expired, 1);
    });

    test('several requests that keep failing do not renew again', () async {
      final h = Harness((_) => unauthorized);

      await Future.wait([
        failureOf(h.dio.get<Object?>('/a')),
        failureOf(h.dio.get<Object?>('/b')),
        failureOf(h.dio.get<Object?>('/c')),
      ]);

      expect(h.tokens.refreshCalls, 1);
      expect(h.adapter.seen.length, 6);
      expect(h.expired, greaterThanOrEqualTo(1));
    });

    test('when the session cannot be renewed there is no retry', () async {
      final h = Harness(
        (_) => unauthorized,
        provider: FakeTokenProvider(renewsTo: null),
      );

      final failure = await failureOf(h.dio.get<Object?>('/equipment'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(h.adapter.seen.length, 1);
      expect(h.expired, 1);
    });

    test('a renewal that throws counts as no session', () async {
      final tokens = _ThrowingRefresh();
      final h = Harness((_) => unauthorized, provider: tokens);

      final failure = await failureOf(h.dio.get<Object?>('/equipment'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(h.adapter.seen.length, 1);
      expect(h.expired, 1);
    });

    test('without a token a 401 does not try to renew', () async {
      final h = Harness(
        (_) => unauthorized,
        provider: FakeTokenProvider(token: null),
      );

      final failure = await failureOf(h.dio.get<Object?>('/auth/me'));

      expect(failure, isA<UnauthorizedFailure>());
      expect(h.adapter.seen.single.authorization, isNull);
      expect(h.tokens.refreshCalls, 0);
      expect(h.expired, 0);
    });

    test('a non-401 error does not renew', () async {
      final h = Harness((_) => const FakeResponse(403, {'code': 'forbidden'}));

      await failureOf(h.dio.get<Object?>('/audit-logs'));

      expect(h.tokens.refreshCalls, 0);
      expect(h.adapter.seen.length, 1);
    });
  });

  group('the token only goes to the Mantix API', () {
    test('the API gets it', () async {
      final h = Harness((_) => const FakeResponse(200, {}));
      await h.dio.get<Object?>('/equipment');
      expect(h.adapter.seen.single.authorization, 'Bearer old');
    });

    for (final url in [
      'https://evil.example.com/steal',
      'http://10.0.2.2:9999/other-port',
      'https://10.0.2.2:8000/other-scheme',
      'http://10.0.2.2.evil.example.com:8000/look-alike',
    ]) {
      test('not $url', () async {
        final h = Harness(acceptsNewOnly);

        final failure = await failureOf(h.dio.get<Object?>(url));

        expect(failure, isA<UnauthorizedFailure>());
        expect(h.adapter.seen.single.authorization, isNull);
        expect(h.tokens.refreshCalls, 0);
        expect(h.expired, 0);
      });
    }

    test('redirects are not followed', () {
      final h = Harness((_) => const FakeResponse(200, {}));
      expect(h.dio.options.followRedirects, isFalse);
    });
  });

  group('headers', () {
    test('every request carries X-Request-ID and X-App-Version', () async {
      final h = Harness((_) => const FakeResponse(200, {}));

      await h.dio.get<Object?>('/equipment');
      await h.dio.get<Object?>('/equipment');

      final [first, second] = h.adapter.seen;
      expect(first.appVersion, '1.4.0');
      expect(first.requestId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second.requestId, isNot(first.requestId));
    });

    test('a retry keeps the request id', () async {
      final h = Harness(acceptsNewOnly);

      await h.dio.get<Object?>('/equipment');

      final [original, retry] = h.adapter.seen;
      expect(retry.requestId, original.requestId);
      expect(retry.appVersion, '1.4.0');
    });

    test('they are also sent to other URLs, but never the token', () async {
      final h = Harness((_) => const FakeResponse(200, {}));
      await h.dio.get<Object?>('https://example.com/file.pdf');
      expect(h.adapter.seen.single.appVersion, '1.4.0');
      expect(h.adapter.seen.single.authorization, isNull);
    });
  });

  group('errors become Failure', () {
    test('403 with its code', () async {
      final h = Harness(
        (_) => const FakeResponse(403, {
          'detail': 'forbidden',
          'code': 'forbidden',
          'request_id': 'r1',
        }),
      );
      final failure = await failureOf(h.dio.get<Object?>('/audit-logs'));
      expect(failure, isA<ForbiddenFailure>());
      expect(failure.requestId, 'r1');
    });

    test('422 with the errors per field', () async {
      final h = Harness(
        (_) => const FakeResponse(422, {
          'detail': 'request validation failed',
          'code': 'validation_error',
          'errors': [
            {'field': 'title', 'message': 'Field required', 'type': 'missing'},
          ],
        }),
      );
      final failure = await failureOf(
        h.dio.post<Object?>('/maintenance/requests'),
      ) as ValidationFailure;
      expect(failure.fieldErrors, {'title': 'Este campo es obligatorio.'});
    });

    test('409 and 404', () async {
      expect(
        await failureOf(
          Harness(
            (_) => const FakeResponse(409, {'code': 'invalid_transition'}),
          ).dio.post<Object?>('/x'),
        ),
        isA<ConflictFailure>(),
      );
      expect(
        await failureOf(
          Harness((_) => const FakeResponse(404, {'code': 'not_found'})).dio
              .get<Object?>('/x'),
        ),
        isA<NotFoundFailure>(),
      );
    });

    test('500 and an unknown code on a 4xx', () async {
      expect(
        await failureOf(
          Harness((_) => const FakeResponse(500, {'code': 'internal_error'}))
              .dio
              .get<Object?>('/x'),
        ),
        isA<ServerFailure>(),
      );
      expect(
        await failureOf(
          Harness((_) => const FakeResponse(429, {'code': 'rate_limited'})).dio
              .get<Object?>('/x'),
        ),
        isA<RejectedFailure>(),
      );
    });

    test('no connection is a NetworkFailure', () async {
      final h = Harness((request) {
        throw DioException(
          requestOptions: RequestOptions(path: request.uri.path),
          type: DioExceptionType.connectionError,
        );
      });
      expect(await failureOf(h.dio.get<Object?>('/x')), isA<NetworkFailure>());
    });

    test('the user message never contains the token', () async {
      final h = Harness((_) => unauthorized);
      final failure = await failureOf(h.dio.get<Object?>('/x'));
      expect(failure.message, isNot(contains('old')));
      expect(failure.message, isNot(contains('Bearer')));
    });
  });

  test('no Dio logging interceptor is installed (it prints Authorization)', () {
    final h = Harness((_) => const FakeResponse(200, {}));
    expect(h.dio.interceptors.whereType<LogInterceptor>(), isEmpty);
  });
}

class _ThrowingRefresh extends FakeTokenProvider {
  @override
  Future<String?> refreshToken() async {
    refreshCalls++;
    throw StateError('network down');
  }
}
