import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  group('listEquipment', () {
    test('pide size=20, ordena por fecha y lee la paginación de las cabeceras', () async {
      final adapter = FakeAdapter((_) => pagedResponse([equipmentItemJson()], totalPages: 3, total: 41));
      final result = await EquipmentRepository(dioWith(adapter)).listEquipment();

      final request = adapter.requests.single;
      expect(request.path, '/equipment');
      expect(request.queryParameters, {'page': 1, 'size': 20, 'sort': '-created_at'});
      expect(result.items.single.assetTag, 'DEMO-007');
      expect(result.info!.total, 41);
      expect(result.hasNext, isTrue);
    });

    test('envía el estado y la búsqueda solo cuando hay filtro, y recorta el texto', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(page: 2, statuses: 'assigned,in_storage', search: '  dell ');

      expect(adapter.requests.single.queryParameters, containsPair('page', 2));
      expect(adapter.requests.single.queryParameters, containsPair('status', 'assigned,in_storage'));
      expect(adapter.requests.single.queryParameters, containsPair('search', 'dell'));
    });

    test('un texto en blanco o un estado vacío no se envían', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(statuses: '', search: '   ');

      expect(adapter.requests.single.queryParameters.keys, isNot(contains('status')));
      expect(adapter.requests.single.queryParameters.keys, isNot(contains('search')));
    });

    test('un 403 sale como ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));
      expect(EquipmentRepository(dioWith(adapter)).listEquipment(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('summary', () {
    test('lee los contadores', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, {'total': 5, 'by_status': {'assigned': 3, 'in_repair': 2}}));
      final summary = await EquipmentRepository(dioWith(adapter)).summary();

      expect(adapter.requests.single.path, '/equipment/summary');
      expect(summary.total, 5);
      expect(summary.byStatus['in_repair'], 2);
    });

    test('un error del servidor sale como Failure sin detalles internos', () async {
      final adapter = FakeAdapter((_) => errorResponse(500));
      await expectLater(EquipmentRepository(dioWith(adapter)).summary(), throwsA(isA<ServerFailure>()));
    });
  });
  group('types', () {
    test('lee las categorías', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
            {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
          ]));
      final types = await EquipmentRepository(dioWith(adapter)).types();

      expect(adapter.requests.single.path, '/equipment/types');
      expect(types.map((t) => t.name), ['Laptop', 'Impresora']);
    });
  });

  group('create', () {
    const equipment = NewEquipment(assetTag: 'EQ-029', typeId: 1, brand: 'Dell', model: 'Latitude');

    test('hace POST con el cuerpo del formulario, devuelve el equipo y avisa del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, equipmentItemJson()));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      final created = await repository.create(equipment);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/equipment');
      expect(adapter.requests.single.data, equipment.toJson());
      expect(created.assetTag, 'DEMO-007');
      expect(changes, 1);
    });

    test('una etiqueta repetida sale como ConflictFailure con su código y no avisa del cambio', () async {
      final adapter = FakeAdapter((_) => errorResponse(409, code: 'equipment_identifier_taken'));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      await expectLater(repository.create(equipment), throwsA(isA<ConflictFailure>().having((f) => f.code, 'code', 'equipment_identifier_taken')));
      await Future<void>.delayed(Duration.zero);

      expect(changes, 0);
    });

    test('un 422 trae los errores por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, errors: [
            {'field': 'brand', 'message': 'Campo requerido', 'type': 'missing'},
          ]));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).create(equipment),
        throwsA(isA<ValidationFailure>().having((f) => f.fieldErrors.keys, 'campos', contains('brand'))),
      );
    });
  });
  group('listEquipment con página, tamaño y categoría', () {
    test('envía el tamaño de página y la categoría', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(page: 3, size: 50, typeId: 2);

      expect(adapter.requests.single.queryParameters, {'page': 3, 'size': 50, 'sort': '-created_at', 'equipment_type_id': 2});
    });
  });

  group('locations y custodios', () {
    test('locations lee las ubicaciones', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 3, 'code': 'HQ', 'name': 'Sede central', 'kind': 'site', 'parent_id': null},
          ]));
      final locations = await EquipmentRepository(dioWith(adapter)).locations();

      expect(adapter.requests.single.path, '/locations');
      expect(locations.single.name, 'Sede central');
    });

    test('custodianCandidates busca por texto recortado y lee usuarios', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 9, 'full_name': 'Ana Pérez', 'email': 'ana@example.com'},
          ]));
      final candidates = await EquipmentRepository(dioWith(adapter)).custodianCandidates('  ana ');

      expect(adapter.requests.single.path, '/equipment/custodian-candidates');
      expect(adapter.requests.single.queryParameters, {'search': 'ana'});
      expect(candidates.single.fullName, 'Ana Pérez');
    });

    test('custodianCandidates sin texto no envía búsqueda', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, []));
      await EquipmentRepository(dioWith(adapter)).custodianCandidates('  ');

      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('assignLocation y assignCustody hacen POST con su cuerpo y avisan del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, equipmentItemJson()));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      await repository.assignLocation(7, 3);
      await repository.assignCustody(7, 9);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests[0].path, '/equipment/7/location');
      expect(adapter.requests[0].data, {'location_id': 3});
      expect(adapter.requests[1].path, '/equipment/7/custody');
      expect(adapter.requests[1].data, {'assigned_to_user_id': 9});
      expect(changes, 2);
    });

    test('un 403 al asignar sale como ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));

      await expectLater(EquipmentRepository(dioWith(adapter)).assignCustody(7, 9), throwsA(isA<ForbiddenFailure>()));
    });
  });
}
