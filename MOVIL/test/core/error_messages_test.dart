import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/error_messages.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/errors/failure_mapper.dart';

DioException error(int status, Object? body) {
  final request = RequestOptions(path: '/x');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status, data: body),
  );
}

/// Lee `docs/error-codes.md` (el contrato que publica el backend) y devuelve código → estado HTTP.
Map<String, int> documentedCodes() {
  final file = File('docs/error-codes.md');
  expect(file.existsSync(), isTrue, reason: 'falta ${file.absolute.path}; ejecuta los tests desde MOVIL/');
  final codes = <String, int>{};
  int? status;
  for (final line in file.readAsLinesSync()) {
    final heading = RegExp(r'^### (\d{3})').firstMatch(line);
    if (heading != null) {
      status = int.parse(heading.group(1)!);
      continue;
    }
    final row = RegExp(r'^\| `([a-z0-9_]+)` \|').firstMatch(line);
    if (row != null && status != null) codes[row.group(1)!] = status;
  }
  return codes;
}

void main() {
  group('mensajes por código', () {
    test('un código específico da su propio mensaje y se conserva', () {
      final failure = mapDioException(error(409, {'code': 'ticket_requires_technician', 'detail': 'x', 'request_id': 'r1'}));

      expect(failure, isA<ConflictFailure>());
      expect(failure.message, messagesByErrorCode['ticket_requires_technician']);
      expect(failure.code, 'ticket_requires_technician');
      expect(failure.requestId, 'r1');
    });

    test('funciona en 403, 404 y 409', () {
      expect(mapDioException(error(403, {'code': 'ticket_view_forbidden'})).message, messagesByErrorCode['ticket_view_forbidden']);
      expect(mapDioException(error(404, {'code': 'equipment_not_found'})).message, messagesByErrorCode['equipment_not_found']);
      expect(mapDioException(error(409, {'code': 'equipment_identifier_taken'})).message, messagesByErrorCode['equipment_identifier_taken']);
    });

    test('un código desconocido se queda con el mensaje genérico del estado', () {
      final failure = mapDioException(error(409, {'code': 'codigo_de_un_servidor_nuevo'}));

      expect(failure, isA<ConflictFailure>());
      expect(failure.message, const ConflictFailure().message);
    });

    test('sin código tampoco rompe', () {
      expect(mapDioException(error(404, {'detail': 'x'})).message, const NotFoundFailure().message);
      expect(mapDioException(error(409, 'texto plano')).message, const ConflictFailure().message);
    });

    test('un código conocido con un estado inesperado no cambia el mensaje', () {
      final failure = mapDioException(error(500, {'code': 'ticket_not_found'}));

      expect(failure, isA<ServerFailure>());
      expect(failure.message, const ServerFailure().message);
    });

    test('el código de sesión caducada no se reemplaza por otro mensaje', () {
      expect(mapDioException(error(401, {'code': 'unauthorized'})).message, const UnauthorizedFailure().message);
    });
  });

  group('contrato con docs/error-codes.md', () {
    test('cada código con mensaje propio existe en la tabla del backend', () {
      final documented = documentedCodes();
      final orphans = messagesByErrorCode.keys.where((code) => !documented.containsKey(code)).toList();

      expect(orphans, isEmpty, reason: 'códigos que el backend no documenta (¿se renombraron?)');
    });

    test('cada código solo se usa en un estado donde la app lo traduce (403, 404, 409, 413 o 415)', () {
      final documented = documentedCodes();
      final wrong = {
        for (final code in messagesByErrorCode.keys)
          if (!{403, 404, 409, 413, 415}.contains(documented[code])) code: documented[code],
      };

      expect(wrong, isEmpty);
    });

    test('la tabla del backend no está vacía y trae los genéricos', () {
      final documented = documentedCodes();

      expect(documented.length, greaterThan(80));
      for (final generic in ['unauthorized', 'forbidden', 'not_found', 'conflict', 'validation_error', 'invalid_transition']) {
        expect(documented, contains(generic));
      }
    });

    test('todos los mensajes están en español y terminan en punto', () {
      for (final entry in messagesByErrorCode.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        expect(entry.value.endsWith('.'), isTrue, reason: entry.key);
      }
    });
  });
}
