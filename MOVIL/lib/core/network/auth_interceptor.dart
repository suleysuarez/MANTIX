import 'package:dio/dio.dart';

import '../auth/auth_token_provider.dart';

/// Sends the bearer token to the Mantix API, and only there, and renews it after a 401.
///
/// When several requests fail with a 401 at once, the token is renewed once and they share the
/// result. Each request is retried at most once: a second 401 ends the session instead of
/// looping.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.apiBaseUrl,
    required this.tokenProvider,
    required this.onSessionExpired,
  }) : _api = Uri.parse(apiBaseUrl);

  /// Used to resend the request; it runs through the same interceptors again.
  final Dio dio;
  final String apiBaseUrl;
  final AuthTokenProvider tokenProvider;

  /// Called when the session cannot continue. It may be called several times in a row.
  final void Function() onSessionExpired;

  static const _sentTokenKey = 'auth.sentToken';
  static const _retriedKey = 'auth.retried';

  final Uri _api;
  String? _staleToken;
  Future<String?>? _renewal;

  /// Same scheme, host and port as the API, and under its path. Anything else (another host,
  /// or an absolute URL passed by mistake) never gets the token.
  bool _isApi(Uri uri) {
    final basePath = _api.path.endsWith('/') ? _api.path : '${_api.path}/';
    return uri.scheme == _api.scheme &&
        uri.host == _api.host &&
        uri.port == _api.port &&
        (_api.path.isEmpty ||
            _api.path == '/' ||
            '${uri.path}/'.startsWith(basePath));
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // A retry already carries the renewed token.
    if (options.extra[_retriedKey] != true && _isApi(options.uri)) {
      String? token;
      try {
        token = await tokenProvider.currentToken();
      } catch (_) {
        token = null;
      }
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
        options.extra[_sentTokenKey] = token;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final sentToken = options.extra[_sentTokenKey];
    if (err.response?.statusCode != 401 || sentToken is! String) {
      return handler.next(err);
    }
    if (options.extra[_retriedKey] == true) {
      onSessionExpired();
      return handler.next(err);
    }

    final fresh = await _renew(sentToken);
    if (fresh == null) {
      onSessionExpired();
      return handler.next(err);
    }

    options.headers['Authorization'] = 'Bearer $fresh';
    options.extra[_sentTokenKey] = fresh;
    options.extra[_retriedKey] = true;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.reject(retryError);
    }
  }

  /// One renewal per expired token. The check and the assignment happen without an `await` in
  /// between, so concurrent failures of the same token share the same future.
  Future<String?> _renew(String staleToken) {
    if (_staleToken == staleToken && _renewal != null) return _renewal!;
    _staleToken = staleToken;
    final renewal = _renewal = _safeRefresh();
    renewal.then((token) {
      // A failed renewal is not remembered: a later request may try again.
      if (token == null && identical(_renewal, renewal)) {
        _staleToken = null;
        _renewal = null;
      }
    });
    return renewal;
  }

  Future<String?> _safeRefresh() async {
    try {
      return await tokenProvider.refreshToken();
    } catch (_) {
      return null;
    }
  }
}
