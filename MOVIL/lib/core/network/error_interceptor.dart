import 'package:dio/dio.dart';

import '../errors/failure.dart';

/// Turns every failed request into a [Failure] stored in `DioException.error`. Repositories read
/// it with [DioFailure.failure].
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is Failure || err.type == DioExceptionType.cancel) {
      return handler.next(err);
    }
    final response = err.response;
    final failure = response != null
        ? Failure.fromResponse(response.statusCode, response.data)
        : const NetworkFailure();
    handler.next(err.copyWith(error: failure));
  }
}

extension DioFailure on DioException {
  /// The translated error. A request that did not pass through [ErrorInterceptor] counts as a
  /// connection problem.
  Failure get failure =>
      error is Failure ? error as Failure : const NetworkFailure();
}
