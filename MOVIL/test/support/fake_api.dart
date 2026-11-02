import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mantix/core/auth/auth_token_provider.dart';

/// What the fake server saw, copied at the moment of the request (Dio reuses and mutates the
/// same options when a request is retried).
class SeenRequest {
  SeenRequest(RequestOptions options)
    : uri = options.uri,
      authorization = options.headers['Authorization'] as String?,
      requestId = options.headers['X-Request-ID'] as String?,
      appVersion = options.headers['X-App-Version'] as String?;

  final Uri uri;
  final String? authorization;
  final String? requestId;
  final String? appVersion;
}

class FakeResponse {
  const FakeResponse(this.status, [this.body]);
  final int status;
  final Object? body;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FutureOr<FakeResponse> Function(SeenRequest request) handler;
  final seen = <SeenRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = SeenRequest(options);
    seen.add(request);
    final response = await handler(request);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Starts with the token `old`. A renewal takes a moment and leaves `new`.
class FakeTokenProvider implements AuthTokenProvider {
  FakeTokenProvider({this.token = 'old', this.renewsTo = 'new'});

  String? token;
  final String? renewsTo;
  int refreshCalls = 0;

  @override
  Future<String?> currentToken() async => token;

  @override
  Future<String?> refreshToken() async {
    refreshCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    token = renewsTo;
    return renewsTo;
  }
}
