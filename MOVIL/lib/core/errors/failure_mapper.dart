import 'package:dio/dio.dart';

import 'error_messages.dart';
import 'failure.dart';

/// Traduce un error de Dio a un [Failure].
///
/// El tipo lo decide el estado HTTP. Si el `code` es uno de los específicos que la
/// app conoce ([messagesByErrorCode]) el mensaje es el de ese caso; un `code`
/// desconocido (por ejemplo, uno que añada un servidor más nuevo) se queda con el
/// mensaje genérico del estado, sin romper.
Failure mapDioException(DioException error) {
  final response = error.response;
  if (response == null) {
    return const NetworkFailure();
  }
  final body = response.data;
  final map = body is Map ? body : const <String, Object?>{};
  final code = map['code'] is String ? map['code'] as String : null;
  final requestId = map['request_id'] is String ? map['request_id'] as String : null;

  final specific = code == null ? null : messagesByErrorCode[code];
  switch (response.statusCode) {
    case 401:
      return UnauthorizedFailure(code: code, requestId: requestId);
    case 403:
      return ForbiddenFailure(code: code, requestId: requestId, message: specific);
    case 404:
      return NotFoundFailure(code: code, requestId: requestId, message: specific);
    case 409:
      return ConflictFailure(code: code, requestId: requestId, message: specific);
    case 422:
      return ValidationFailure(fieldErrors: _fieldErrors(map['errors']), code: code, requestId: requestId);
    default:
      return ServerFailure(code: code, requestId: requestId);
  }
}

/// Convierte cualquier error a un [Failure] que la interfaz pueda mostrar.
/// Lo desconocido se trata como fallo del servidor, sin exponer su contenido.
Failure toFailure(Object error) {
  if (error is Failure) return error;
  if (error is DioException) return mapDioException(error);
  return const ServerFailure();
}

Map<String, String> _fieldErrors(Object? errors) {
  if (errors is! List) return const {};
  final result = <String, String>{};
  for (final item in errors) {
    if (item is Map && item['field'] is String && item['message'] is String) {
      result.putIfAbsent(item['field'] as String, () => item['message'] as String);
    }
  }
  return result;
}
