import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';

Map<String, Object?> body(String code, {List<Map<String, String>>? errors}) => {
  'detail': 'internal english detail',
  'code': code,
  'errors': errors,
  'request_id': 'abc123',
};

void main() {
  group('by backend code', () {
    final cases = <(int, String, Type)>[
      (401, 'unauthorized', UnauthorizedFailure),
      (403, 'forbidden', ForbiddenFailure),
      (404, 'not_found', NotFoundFailure),
      (409, 'conflict', ConflictFailure),
      (409, 'business_rule_violation', ConflictFailure),
      (409, 'invalid_transition', ConflictFailure),
      (422, 'validation_error', ValidationFailure),
      (422, 'unprocessable', ValidationFailure),
      (500, 'internal_error', ServerFailure),
      (413, 'payload_too_large', RejectedFailure),
      (415, 'unsupported_media_type', RejectedFailure),
      (429, 'rate_limited', RejectedFailure),
    ];
    for (final (status, code, type) in cases) {
      test('$code -> $type', () {
        final failure = Failure.fromResponse(status, body(code));
        expect(failure.runtimeType, type);
        expect(failure.code, code);
        expect(failure.requestId, 'abc123');
      });
    }
  });

  group('unknown or missing code falls back to the HTTP status', () {
    test('unknown code on a 404', () {
      expect(
        Failure.fromResponse(404, body('brand_new_code')),
        isA<NotFoundFailure>(),
      );
    });
    test('no body at all', () {
      expect(Failure.fromResponse(403, null), isA<ForbiddenFailure>());
      expect(Failure.fromResponse(502, 'Bad Gateway'), isA<ServerFailure>());
      expect(
        Failure.fromResponse(400, <String, Object?>{}),
        isA<RejectedFailure>(),
      );
    });
    test('null status without body is rejected, not a crash', () {
      expect(Failure.fromResponse(null, null), isA<RejectedFailure>());
    });
    test('a non-string code is ignored', () {
      expect(Failure.fromResponse(409, {'code': 7}), isA<ConflictFailure>());
    });
  });

  group('messages', () {
    test('are Spanish and never expose the backend detail', () {
      final failure = Failure.fromResponse(403, body('forbidden'));
      expect(failure.message, 'No tienes permiso para realizar esta acción.');
      expect(failure.message, isNot(contains('english')));
    });
    test('invalid transition has its own message', () {
      expect(
        Failure.fromResponse(409, body('invalid_transition')).message,
        'Ese cambio de estado no está permitido desde el estado actual.',
      );
    });
    test('network failure has a connection message', () {
      expect(const NetworkFailure().message, contains('conexión'));
    });
  });

  group('422 field errors', () {
    test('maps each field to a Spanish message by type', () {
      final failure = Failure.fromResponse(
        422,
        body(
          'validation_error',
          errors: [
            {
              'field': 'title',
              'message': 'String should have at least 3 characters',
              'type': 'string_too_short',
            },
            {
              'field': 'description',
              'message': 'Field required',
              'type': 'missing',
            },
            {
              'field': 'equipment_id',
              'message': 'Input should be a valid integer',
              'type': 'int_parsing',
            },
            {'field': 'x', 'message': '?', 'type': 'something_new'},
          ],
        ),
      ) as ValidationFailure;
      expect(failure.fieldErrors, {
        'title': 'Debe tener al menos 3 caracteres.',
        'description': 'Este campo es obligatorio.',
        'equipment_id': 'Debe ser un número entero.',
        'x': 'El valor no es válido.',
      });
    });
    test('the first error of a field wins', () {
      final failure = Failure.fromResponse(
        422,
        body(
          'validation_error',
          errors: [
            {'field': 'a', 'message': '', 'type': 'missing'},
            {'field': 'a', 'message': '', 'type': 'int_parsing'},
          ],
        ),
      ) as ValidationFailure;
      expect(failure.fieldErrors, {'a': 'Este campo es obligatorio.'});
    });
    test('tolerates a missing or malformed errors list', () {
      expect(
        (Failure.fromResponse(
          422,
          body('validation_error'),
        ) as ValidationFailure).fieldErrors,
        isEmpty,
      );
      expect(
        (Failure.fromResponse(422, {
          'code': 'validation_error',
          'errors': 'oops',
        }) as ValidationFailure).fieldErrors,
        isEmpty,
      );
    });
  });

  test('a sealed switch covers every case', () {
    String describe(Failure f) => switch (f) {
      NetworkFailure() => 'network',
      UnauthorizedFailure() => '401',
      ForbiddenFailure() => '403',
      NotFoundFailure() => '404',
      ConflictFailure() => '409',
      ValidationFailure() => '422',
      ServerFailure() => '5xx',
      RejectedFailure() => '4xx',
    };
    expect(describe(const NetworkFailure()), 'network');
  });
}
