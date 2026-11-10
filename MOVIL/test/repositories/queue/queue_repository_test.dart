import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/queue/queue_repository.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../models/queue/queue_models_test.dart' show summaryJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  group('QueueRepository', () {
    test('pide el resumen de 30 días por defecto y lo lee', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, summaryJson));
      final summary = await QueueRepository(dioWith(adapter)).summary();

      expect(adapter.requests.single.path, '/maintenance/queue/summary');
      expect(adapter.requests.single.queryParameters, {'period': '30d'});
      expect(summary.pendingTotal, 14);
    });

    test('sin permiso llega como ForbiddenFailure y un corte de red como NetworkFailure', () async {
      final forbidden = QueueRepository(dioWith(FakeAdapter((_) => errorResponse(403, code: 'forbidden'))));
      await expectLater(forbidden.summary(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('RequestsRepository para la bandeja', () {
    test('listRequests manda estado, orden, categorías, técnicos y prioridades como los entiende el backend', () async {
      final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
      final repository = RequestsRepository(dioWith(adapter));

      await repository.listRequests(status: 'submitted', size: 10, categories: const ['hardware', 'network'], technicianIds: const [4, 9], priorities: const ['critical', 'high'], search: ' laptop ');

      final query = adapter.requests.single.queryParameters;
      expect(query['status'], 'submitted');
      expect(query['size'], 10);
      expect(query['sort'], '-created_at');
      expect(query['category'], 'hardware,network');
      expect(query['technician_id'], [4, 9]);
      expect(query['priority'], 'critical,high');
      expect(query['search'], 'laptop');
    });

    test('sin esos filtros no manda nada de más', () async {
      final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
      await RequestsRepository(dioWith(adapter)).listRequests();

      final query = adapter.requests.single.queryParameters;
      expect(query.keys, unorderedEquals(['page', 'size', 'sort']));
    });

    test('el ticket de la lista guarda equipment_id para mostrar «Equipo #id» si no llega el equipo', () async {
      final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
      final page = await RequestsRepository(dioWith(adapter)).listRequests();
      expect(page.items.single.equipmentId, 12);
      expect(page.items.single.equipment, isNull);
    });

    test('reject manda el motivo recortado a /reject y avisa del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, detailJson(status: 'cancelled')));
      final repository = RequestsRepository(dioWith(adapter));
      var changes = 0;
      final sub = repository.changes.listen((_) => changes++);
      addTearDown(sub.cancel);

      await repository.reject(5, reason: '  Duplicada de TCK-1 ');
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/maintenance/requests/5/reject');
      expect(adapter.requests.single.data, {'reason': 'Duplicada de TCK-1'});
      expect(changes, 1);
    });

    test('reject sin permiso llega como ForbiddenFailure', () async {
      final repository = RequestsRepository(dioWith(FakeAdapter((_) => errorResponse(403, code: 'forbidden'))));
      await expectLater(repository.reject(5, reason: 'Motivo claro'), throwsA(isA<ForbiddenFailure>()));
    });
  });
}
