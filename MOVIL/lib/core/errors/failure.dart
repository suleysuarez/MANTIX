/// Every error the UI can see. The user-facing [message] is Spanish and generic: the backend's
/// `detail` is never shown because it is English and may carry internal wording.
sealed class Failure implements Exception {
  const Failure(this.message, {this.code, this.requestId});

  final String message;

  /// The backend's stable `code`, when the response had one.
  final String? code;

  /// The backend's `request_id`, for support.
  final String? requestId;

  /// Builds the failure for an HTTP error response. The backend `code` decides first; a code
  /// that is missing or unknown falls back to the HTTP status, so a new code never breaks the app.
  factory Failure.fromResponse(int? statusCode, Object? body) {
    final map = body is Map ? body : const <Object?, Object?>{};
    final code = map['code'] is String ? map['code'] as String : null;
    final requestId = map['request_id'] is String
        ? map['request_id'] as String
        : null;
    final kind = _kindByCode[code] ?? _kindByStatus(statusCode);
    final message = _messageByCode[code] ?? _messageByKind[kind]!;
    return switch (kind) {
      _Kind.unauthorized => UnauthorizedFailure(
        message,
        code: code,
        requestId: requestId,
      ),
      _Kind.forbidden => ForbiddenFailure(
        message,
        code: code,
        requestId: requestId,
      ),
      _Kind.notFound => NotFoundFailure(
        message,
        code: code,
        requestId: requestId,
      ),
      _Kind.conflict => ConflictFailure(
        message,
        code: code,
        requestId: requestId,
      ),
      _Kind.validation => ValidationFailure(
        message,
        fieldErrors: _fieldErrors(map['errors']),
        code: code,
        requestId: requestId,
      ),
      _Kind.server => ServerFailure(message, code: code, requestId: requestId),
      _Kind.rejected => RejectedFailure(
        message,
        code: code,
        requestId: requestId,
      ),
    };
  }
}

/// No connection, timeout or an unreadable response.
final class NetworkFailure extends Failure {
  const NetworkFailure()
    : super(
        'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.',
      );
}

/// 401: no session or an expired one.
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message, {super.code, super.requestId});
}

/// 403: signed in but without permission.
final class ForbiddenFailure extends Failure {
  const ForbiddenFailure(super.message, {super.code, super.requestId});
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.code, super.requestId});
}

/// 409: the action is not valid for the record's current state.
final class ConflictFailure extends Failure {
  const ConflictFailure(super.message, {super.code, super.requestId});
}

/// 422: [fieldErrors] maps the request field to a Spanish message, to show under that field.
final class ValidationFailure extends Failure {
  const ValidationFailure(
    super.message, {
    this.fieldErrors = const {},
    super.code,
    super.requestId,
  });

  final Map<String, String> fieldErrors;
}

/// 5xx.
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, super.requestId});
}

/// Any other 4xx: 400, 413, 415, 429...
final class RejectedFailure extends Failure {
  const RejectedFailure(super.message, {super.code, super.requestId});
}

enum _Kind {
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  rejected,
}

const _kindByCode = <String?, _Kind>{
  'unauthorized': _Kind.unauthorized,
  'forbidden': _Kind.forbidden,
  'not_found': _Kind.notFound,
  'conflict': _Kind.conflict,
  'business_rule_violation': _Kind.conflict,
  'invalid_transition': _Kind.conflict,
  'validation_error': _Kind.validation,
  'unprocessable': _Kind.validation,
  'internal_error': _Kind.server,
  'payload_too_large': _Kind.rejected,
  'unsupported_media_type': _Kind.rejected,
  'rate_limited': _Kind.rejected,
  'bad_request': _Kind.rejected,
  'method_not_allowed': _Kind.rejected,
};

_Kind _kindByStatus(int? status) => switch (status) {
  401 => _Kind.unauthorized,
  403 => _Kind.forbidden,
  404 => _Kind.notFound,
  409 => _Kind.conflict,
  422 => _Kind.validation,
  final s? when s >= 500 => _Kind.server,
  _ => _Kind.rejected,
};

const _messageByKind = <_Kind, String>{
  _Kind.unauthorized: 'Tu sesión expiró. Inicia sesión de nuevo.',
  _Kind.forbidden: 'No tienes permiso para realizar esta acción.',
  _Kind.notFound: 'El registro ya no existe. Actualiza la pantalla.',
  _Kind.conflict:
      'La acción no se puede realizar en el estado actual del registro.',
  _Kind.validation: 'Revisa los campos marcados.',
  _Kind.server: 'El servidor tuvo un problema. Inténtalo de nuevo más tarde.',
  _Kind.rejected:
      'La solicitud no es válida. Revisa los datos e inténtalo de nuevo.',
};

/// More specific messages for the codes that have one.
const _messageByCode = <String?, String>{
  'invalid_transition':
      'Ese cambio de estado no está permitido desde el estado actual.',
  'payload_too_large': 'El archivo supera el tamaño máximo permitido.',
  'unsupported_media_type': 'El tipo de archivo no está permitido.',
  'rate_limited':
      'Demasiadas solicitudes. Espera un momento e inténtalo de nuevo.',
};

/// `errors` is `[{field, message, type}]`. Only `type` and `field` are used: the English
/// `message` is never shown. The first error of each field wins.
Map<String, String> _fieldErrors(Object? errors) {
  if (errors is! List) return const {};
  final result = <String, String>{};
  for (final item in errors) {
    if (item is! Map || item['field'] is! String) continue;
    final type = item['type'] is String ? item['type'] as String : '';
    final message = item['message'] is String ? item['message'] as String : '';
    result.putIfAbsent(
      item['field'] as String,
      () => _fieldMessage(type, message),
    );
  }
  return result;
}

String _fieldMessage(String type, String message) {
  switch (type) {
    case 'missing':
      return 'Este campo es obligatorio.';
    case 'string_too_short':
      final min = RegExp(r'at least (\d+)').firstMatch(message)?.group(1);
      return min == null
          ? 'Es demasiado corto.'
          : 'Debe tener al menos $min caracteres.';
    case 'string_too_long':
      final max = RegExp(r'at most (\d+)').firstMatch(message)?.group(1);
      return max == null
          ? 'Es demasiado largo.'
          : 'Debe tener como máximo $max caracteres.';
    case 'string_pattern_mismatch':
      return 'El formato no es válido.';
    case 'value_error':
      return RegExp('blank', caseSensitive: false).hasMatch(message)
          ? 'No puede estar vacío.'
          : 'El valor no es válido.';
    case 'greater_than_equal':
      return 'El valor es demasiado bajo.';
    case 'less_than_equal':
      return 'El valor es demasiado alto.';
    case 'int_parsing':
      return 'Debe ser un número entero.';
    case 'datetime_parsing' || 'date_parsing':
      return 'La fecha no es válida.';
    default:
      return 'El valor no es válido.';
  }
}
