import 'package:dio/dio.dart';

import '../auth/auth_provider.dart';
import '../config/app_config.dart';

const _retriedKey = 'mantix_retried_after_401';

/// Crea el cliente HTTP de la app.
///
/// * Añade `Authorization: Bearer` con el token del [AuthProvider].
/// * Envía `X-App-Version` en cada petición.
/// * Ante un 401 pide un token nuevo **una sola vez** y reintenta; si vuelve a
///   fallar, deja pasar el error y avisa con [onSessionExpired]. Un
///   `QueuedInterceptor` serializa las peticiones para que varios 401
///   simultáneos no pidan varias renovaciones.
///
/// [onSessionExpired] es un callback simple (no depende de widgets ni de Bloc): el
/// `AuthBloc` se lo registra al arrancar la app.
Dio createApiClient({
  required AppConfig config,
  required AuthProvider auth,
  HttpClientAdapter? adapter,
  void Function()? onSessionExpired,
}) {
  final dio = Dio(BaseOptions(
    baseUrl: config.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'X-App-Version': config.appVersion, 'Accept': 'application/json'},
  ));
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.add(_AuthInterceptor(dio, auth, onSessionExpired));
  return dio;
}

String? _bearer(Object? header) {
  if (header is! String || !header.startsWith('Bearer ')) return null;
  return header.substring('Bearer '.length);
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor(this._dio, this._auth, this._onSessionExpired);

  final Dio _dio;
  final AuthProvider _auth;
  final void Function()? _onSessionExpired;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _auth.accessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 || request.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    // Si otra petición ya renovó el token mientras esta fallaba, basta con
    // reintentar con el vigente: así varios 401 seguidos provocan una sola renovación.
    final usedToken = _bearer(request.headers['Authorization']);
    final current = await _auth.accessToken();
    final fresh = current != null && current != usedToken ? current : await _auth.accessToken(forceRefresh: true);
    if (fresh == null) {
      _onSessionExpired?.call();
      return handler.next(err);
    }
    request.extra[_retriedKey] = true;
    request.headers['Authorization'] = 'Bearer $fresh';
    // El reintento usa un cliente aparte, sin este interceptor: si fallara con
    // otro 401 entraría en la cola de errores que sigue ocupada con esta
    // petición y se bloquearía.
    final retryClient = Dio(_dio.options)..httpClientAdapter = _dio.httpClientAdapter;
    try {
      handler.resolve(await retryClient.fetch<Object?>(request));
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) _onSessionExpired?.call();
      handler.next(retryError);
    }
  }
}
