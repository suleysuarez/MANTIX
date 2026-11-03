import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mantix/core/auth/auth_provider.dart';

/// Adaptador HTTP en memoria: cada petición pasa por [handler] y se registra.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Object? body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

/// Proveedor de tokens de prueba: cada renovación forzada emite `token-N`.
class FakeAuthProvider implements AuthProvider {
  FakeAuthProvider({String? token = 'token-0'}) {
    _token = token;
  }

  late String? _token;
  int refreshCalls = 0;
  bool signedOut = false;

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (forceRefresh && _token != null) {
      refreshCalls++;
      _token = 'token-$refreshCalls';
    }
    return _token;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    _token = null;
  }
}
