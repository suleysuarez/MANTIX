/// Error de dominio que ve la interfaz. Nunca expone detalles internos del servidor.
sealed class Failure {
  const Failure(this.message, {this.code, this.requestId});

  /// Mensaje en español, seguro para mostrar.
  final String message;

  /// Campo `code` de la respuesta (ver `docs/error-codes.md`); se conserva por si la
  /// interfaz decide algo según el caso.
  final String? code;
  final String? requestId;
}

class NetworkFailure extends Failure {
  const NetworkFailure() : super('No pudimos conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.');
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({super.code, super.requestId}) : super('Tu sesión expiró. Inicia sesión de nuevo.');
}

class ForbiddenFailure extends Failure {
  const ForbiddenFailure({super.code, super.requestId, String? message})
      : super(message ?? 'No tienes permiso para realizar esta acción.');
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({super.code, super.requestId, String? message}) : super(message ?? 'No encontramos lo que buscas.');
}

class ConflictFailure extends Failure {
  const ConflictFailure({super.code, super.requestId, String? message})
      : super(message ?? 'La acción entra en conflicto con el estado actual. Actualiza e inténtalo de nuevo.');
}

/// Un 422: `fieldErrors` asocia cada campo con su mensaje para mostrarlo bajo el campo.
class ValidationFailure extends Failure {
  const ValidationFailure({this.fieldErrors = const {}, super.code, super.requestId})
      : super('Revisa los datos ingresados.');

  final Map<String, String> fieldErrors;
}

class ServerFailure extends Failure {
  const ServerFailure({super.code, super.requestId}) : super('Algo salió mal en el servidor. Inténtalo más tarde.');
}
