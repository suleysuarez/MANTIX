import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  group('listRequests', () {
    test('pide size=20, ordena por fecha y lee la paginación de las cabeceras', () async {
      final adapter = FakeAdapter((_) => pagedResponse([ticketJson()], totalPages: 3, total: 41));
      final result = await RequestsRepository(dioWith(adapter)).listRequests();

      final request = adapter.requests.single;
      expect(request.path, '/maintenance/requests');
      expect(request.queryParameters, {'page': 1, 'size': 20, 'sort': '-created_at'});
      expect(result.items.single.ticketNumber, 'TCK-0001');
      expect(result.info!.total, 41);
      expect(result.hasNext, isTrue);
    });

    test('envía el estado solo cuando hay filtro', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await RequestsRepository(dioWith(adapter)).listRequests(page: 2, status: 'resolved');
      expect(adapter.requests.single.queryParameters, containsPair('status', 'resolved'));
      expect(adapter.requests.single.queryParameters, containsPair('page', 2));
    });

    test('sin cabeceras de paginación se trata como una sola página', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [ticketJson()]));
      final result = await RequestsRepository(dioWith(adapter)).listRequests();
      expect(result.info, isNull);
      expect(result.hasNext, isFalse);
    });

    test('un 403 sale como ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));
      expect(RequestsRepository(dioWith(adapter)).listRequests(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('getRequest', () {
    test('lee el detalle con técnico e historial', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, detailJson()));
      final ticket = await RequestsRepository(dioWith(adapter)).getRequest(1);
      expect(adapter.requests.single.path, '/maintenance/requests/1');
      expect(ticket.technicianName, 'Luis Técnico');
      expect(ticket.history, hasLength(2));
      expect(ticket.equipment.label, 'EQ-0012 · Dell Latitude');
    });

    test('un 404 con código conocido usa el mensaje específico', () async {
      final adapter = FakeAdapter((_) => errorResponse(404, code: 'ticket_not_found'));
      await expectLater(
        RequestsRepository(dioWith(adapter)).getRequest(9),
        throwsA(isA<NotFoundFailure>().having((f) => f.message, 'message', 'Este ticket ya no existe.')),
      );
    });

    test('sin conexión sale como NetworkFailure', () async {
      final adapter = FakeAdapter((options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'));
      await expectLater(RequestsRepository(dioWith(adapter)).getRequest(1), throwsA(isA<NetworkFailure>()));
    });
  });

  group('create', () {
    test('envía el cuerpo esperado y devuelve el ticket creado', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, detailJson(id: 7, status: 'submitted')));
      final ticket = await RequestsRepository(dioWith(adapter)).create(const NewRequest(
        equipmentId: 12,
        title: 'No enciende',
        description: 'Pantalla negra',
        priority: 'high',
      ));

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/maintenance/requests');
      expect(request.data, {
        'equipment_id': 12,
        'title': 'No enciende',
        'description': 'Pantalla negra',
        'priority': 'high',
      });
      expect(ticket.id, 7);
    });

    test('un 422 trae los errores por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, code: 'unprocessable', errors: [
            {'field': 'title', 'message': 'no puede estar vacío', 'type': 'value_error'},
          ]));
      await expectLater(
        RequestsRepository(dioWith(adapter)).create(const NewRequest(equipmentId: 1, title: 'x', description: 'y', priority: 'low')),
        throwsA(isA<ValidationFailure>().having((f) => f.fieldErrors, 'fieldErrors', {'title': 'no puede estar vacío'})),
      );
    });
  });

  group('listAttachments', () {
    test('lee nombre, tipo y tamaño', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 15, 'file_name': 'foto.jpg', 'mime_type': 'image/jpeg', 'file_size': 234112},
          ]));
      final items = await RequestsRepository(dioWith(adapter)).listAttachments(4);
      expect(adapter.requests.single.path, '/maintenance/requests/4/attachments');
      expect(items.single.fileName, 'foto.jpg');
      expect(items.single.fileSize, 234112);
    });
  });

  group('searchEquipment', () {
    test('envía el texto recortado y no envía search si está vacío', () async {
      final adapter = FakeAdapter((_) => pagedResponse([equipmentJson()]));
      final repository = RequestsRepository(dioWith(adapter));

      await repository.searchEquipment(search: '  EQ-00  ');
      await repository.searchEquipment(search: '   ');
      await repository.searchEquipment();

      expect(adapter.requests[0].queryParameters, {'page': 1, 'size': 20, 'search': 'EQ-00'});
      expect(adapter.requests[1].queryParameters, {'page': 1, 'size': 20});
      expect(adapter.requests[2].queryParameters, {'page': 1, 'size': 20});
    });

    test('solo conserva los campos del selector, sin custodio ni ubicación', () async {
      final adapter = FakeAdapter((_) => pagedResponse([equipmentJson()]));
      final result = await RequestsRepository(dioWith(adapter)).searchEquipment();
      final option = result.items.single;
      expect(option.label, 'EQ-0012 · Dell Latitude');
      expect(option.typeName, 'Laptop');
      expect(option.toString(), isNot(contains('Otra Persona')));
    });
  });

  group('modelos', () {
    test('un ticket sin técnico ni historial se lee sin romper', () {
      final json = detailJson()
        ..['current_assignment'] = null
        ..remove('status_history');
      final ticket = TicketDetail.fromJson(json);
      expect(ticket.technicianName, isNull);
      expect(ticket.history, isEmpty);
    });

    test('la fecha se lee como hora local', () {
      final item = TicketListItem.fromJson(ticketJson());
      expect(item.createdAt.isUtc, isFalse);
      expect(item.createdAt.toUtc(), DateTime.utc(2026, 11, 2, 15, 30));
    });
  });
}
