import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  test('listRequests: una prioridad y un equipo viajan solos; varios, como lista', () async {
    final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
    final repository = RequestsRepository(dioWith(adapter));

    await repository.listRequests(priorities: ['high'], equipmentIds: [12]);
    expect(adapter.requests.last.queryParameters, containsPair('priority', 'high'));
    expect(adapter.requests.last.queryParameters, containsPair('equipment_id', 12));

    await repository.listRequests(priorities: ['critical', 'high'], equipmentIds: [12, 13]);
    expect(adapter.requests.last.queryParameters, containsPair('priority', 'critical,high'));
    expect(adapter.requests.last.queryParameters, containsPair('equipment_id', [12, 13]));

    await repository.listRequests();
    expect(adapter.requests.last.queryParameters.keys, isNot(containsAll(['priority', 'equipment_id'])));
  });

  test('listRequests: el equipo de un solo ticket (historial del equipo) sigue funcionando', () async {
    final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
    await RequestsRepository(dioWith(adapter)).listRequests(equipmentId: 7, size: 10);

    expect(adapter.requests.single.queryParameters, containsPair('equipment_id', 7));
    expect(adapter.requests.single.queryParameters, containsPair('size', 10));
  });

  test('el ticket de la lista trae su equipo si el servidor lo envía y no falla si no', () {
    final with_ = TicketListItem.fromJson(ticketJson(equipment: {'id': 12, 'asset_tag': 'EQ-0012', 'brand': 'Dell', 'model': 'Latitude'}));
    final without = TicketListItem.fromJson(ticketJson());

    expect(with_.equipment?.label, 'EQ-0012 · Dell Latitude');
    expect(without.equipment, isNull);
  });

  test('workflow lee los estados en orden con sus datos requeridos', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, [
          {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned'], 'requires': ['category', 'priority'], 'can_enter': false},
          {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged'], 'requires': [], 'can_enter': true},
        ]));
    final workflow = await RequestsRepository(dioWith(adapter)).workflow();

    expect(adapter.requests.single.path, '/maintenance/requests/workflow');
    expect([for (final state in workflow) state.status], ['submitted', 'triaged']);
    expect(workflow.last.requires, ['category', 'priority']);
    expect(workflow.last.canEnter, isFalse);
    expect(workflow.first.allowedTargets, ['triaged']);
  });

  test('transitionStatus manda las notas y la resolución recortadas, y solo si existen', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, detailJson()));
    final repository = RequestsRepository(dioWith(adapter));

    await repository.transitionStatus(5, 'resolved', resolutionSummary: '  Se cambió el SSD ');
    expect(adapter.requests.last.data, {'status': 'resolved', 'resolution_summary': 'Se cambió el SSD'});

    await repository.transitionStatus(5, 'cancelled', notes: 'Duplicado');
    expect(adapter.requests.last.data, {'status': 'cancelled', 'notes': 'Duplicado'});

    await repository.transitionStatus(5, 'waiting', notes: '   ');
    expect(adapter.requests.last.data, {'status': 'waiting'});
  });

  test('crear un ticket emite su id en `created` y avisa en `changes`', () async {
    final adapter = FakeAdapter((_) => jsonResponse(201, detailJson(id: 42)));
    final repository = RequestsRepository(dioWith(adapter));
    final created = <int>[];
    var changes = 0;
    final subs = [repository.created.listen(created.add), repository.changes.listen((_) => changes++)];
    addTearDown(() async {
      for (final sub in subs) {
        await sub.cancel();
      }
    });

    await repository.create(const NewRequest(equipmentId: 12, title: 'No enciende', description: 'detalle', priority: 'medium'));
    await Future<void>.delayed(Duration.zero);

    expect(created, [42]);
    expect(changes, 1);
  });
}
