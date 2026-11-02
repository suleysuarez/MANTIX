import 'package:dio/dio.dart';

import '../auth/auth_token_provider.dart';
import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';
import 'request_headers_interceptor.dart';

/// The only HTTP client of the app, pointed at the Mantix API.
///
/// No logging interceptor is installed on purpose: Dio's `LogInterceptor` prints headers,
/// including `Authorization`. Redirects are not followed so the token can never travel to another
/// host through a redirect.
Dio createApiClient({
  required AppConfig config,
  required AuthTokenProvider tokenProvider,
  required void Function() onSessionExpired,
  HttpClientAdapter? adapter,
  String Function()? newRequestId,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      headers: {'Accept': 'application/json'},
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.addAll([
    RequestHeadersInterceptor(
      appVersion: config.appVersion,
      newRequestId: newRequestId,
    ),
    AuthInterceptor(
      dio: dio,
      apiBaseUrl: config.apiBaseUrl,
      tokenProvider: tokenProvider,
      onSessionExpired: onSessionExpired,
    ),
    ErrorInterceptor(),
  ]);
  return dio;
}
