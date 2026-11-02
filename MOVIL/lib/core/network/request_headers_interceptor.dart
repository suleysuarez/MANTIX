import 'dart:math';

import 'package:dio/dio.dart';

/// Adds `X-Request-ID` (the backend echoes it and logs it) and `X-App-Version` to every request.
/// A retried request keeps its id, so both attempts show up under the same id in the logs.
class RequestHeadersInterceptor extends Interceptor {
  RequestHeadersInterceptor({
    required this.appVersion,
    String Function()? newRequestId,
  }) : _newRequestId = newRequestId ?? _randomId;

  final String appVersion;
  final String Function() _newRequestId;

  static final _random = Random.secure();

  static String _randomId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('X-Request-ID', _newRequestId);
    options.headers['X-App-Version'] = appVersion;
    handler.next(options);
  }
}
