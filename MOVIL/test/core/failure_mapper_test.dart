import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/errors/failure_mapper.dart';

DioException error(int? status, [Object? body]) {
  final request = RequestOptions(path: '/x');
  return DioException(
    requestOptions: request,
    response: status == null ? null : Response(requestOptions: request, statusCode: status, data: body),
  );
}

void main() {
  test('sin respuesta es un fallo de red', () {
    expect(mapDioException(error(null)), isA<NetworkFailure>());
  });

  test('mapea por estado HTTP y conserva code y request_id', () {
    final failure = mapDioException(error(401, {'detail': 'x', 'code': 'unauthorized', 'request_id': 'abc'}));
    expect(failure, isA<UnauthorizedFailure>());
    expect(failure.code, 'unauthorized');
    expect(failure.requestId, 'abc');
    expect(mapDioException(error(403)), isA<ForbiddenFailure>());
    expect(mapDioException(error(404)), isA<NotFoundFailure>());
    expect(mapDioException(error(409)), isA<ConflictFailure>());
    expect(mapDioException(error(500)), isA<ServerFailure>());
  });

  test('un code desconocido no rompe: se decide por el estado', () {
    expect(mapDioException(error(404, {'code': 'algo_nuevo'})), isA<NotFoundFailure>());
  });

  test('el cuerpo que no es un mapa no rompe', () {
    expect(mapDioException(error(502, '<html>Bad gateway</html>')), isA<ServerFailure>());
  });

  test('un 422 devuelve los errores por campo', () {
    final failure = mapDioException(error(422, {
      'detail': 'x',
      'code': 'validation_error',
      'errors': [
        {'field': 'title', 'message': 'Requerido', 'type': 'missing'},
        {'field': 'title', 'message': 'Otro', 'type': 'x'},
        {'field': 'priority', 'message': 'Inválida', 'type': 'enum'},
        {'nope': 1},
      ],
    }));
    expect(failure, isA<ValidationFailure>());
    expect((failure as ValidationFailure).fieldErrors, {'title': 'Requerido', 'priority': 'Inválida'});
  });

  test('los mensajes no filtran detalles internos', () {
    final failure = mapDioException(error(500, {'detail': 'Traceback: secret'}));
    expect(failure.message, isNot(contains('Traceback')));
  });
}
