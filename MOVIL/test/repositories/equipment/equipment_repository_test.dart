import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
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
}
