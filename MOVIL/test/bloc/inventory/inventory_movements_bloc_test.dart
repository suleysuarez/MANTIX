import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/inventory/inventory_movements_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/inventory/inventory_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

Map<String, Object?> movementJson(int id, {String kind = 'in', int quantity = 5, int stockAfter = 5, String? notes}) => {
      'id': id, 'item_id': 7, 'kind': kind, 'quantity': quantity, 'stock_after': stockAfter,
      'unit_cost': null, 'notes': notes, 'created_by': 'Ana Pérez', 'created_at': '2026-11-12T15:00:00Z',
    };

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late InventoryMovementsBloc bloc;

  setUp(() {
    handler = (_) => errorResponse(404);
    adapter = FakeAdapter((options) => handler(options));
    bloc = InventoryMovementsBloc(repository: InventoryRepository(dioWith(adapter)), itemId: 7)..add(const InventoryMovementsStarted());
    addTearDown(bloc.close);
  });

  test('carga la primera página con size=20 y reconoce la carga inicial del alta', () async {
    handler = (_) => pagedResponse([movementJson(2, kind: 'out', quantity: -2, stockAfter: 3), movementJson(1, quantity: 5, notes: 'Carga inicial')]);

    final state = await bloc.stream.firstWhere((s) => s.loaded);

    expect(state.items.map((m) => m.id), [2, 1]);
    expect(state.items.first.quantity, -2);
    expect(state.items.last.isInitialLoad, isTrue);
    expect(state.items.first.isInitialLoad, isFalse);
    expect(state.reachedEnd, isTrue, reason: 'una sola página: ya se puede mostrar el alta del ítem');
    final request = adapter.requests.single;
    expect(request.path, '/inventory/items/7/movements');
    expect((request.queryParameters['page'], request.queryParameters['size']), (1, 20));
  });

  test('un ítem sin existencias iniciales tiene el historial vacío pero cargado', () async {
    handler = (_) => pagedResponse(const []);

    final state = await bloc.stream.firstWhere((s) => s.loaded);

    expect(state.items, isEmpty);
    expect(state.reachedEnd, isTrue);
  });

  test('pedir más añade la página siguiente y solo al final llega reachedEnd', () async {
    handler = (o) {
      final page = o.queryParameters['page'] as int;
      return pagedResponse([movementJson(page * 10)], page: page, totalPages: 2, total: 2);
    };
    final first = await bloc.stream.firstWhere((s) => s.loaded);
    expect(first.reachedEnd, isFalse);

    bloc.add(const InventoryMovementsMoreRequested());
    final second = await bloc.stream.firstWhere((s) => !s.loadingMore && s.items.length == 2);

    expect(second.items.map((m) => m.id), [10, 20]);
    expect(second.reachedEnd, isTrue);
    bloc.add(const InventoryMovementsMoreRequested());
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, hasLength(2), reason: 'sin más páginas no vuelve a pedir');
  });

  test('si falla la primera carga deja el error y permite reintentar', () async {
    handler = (_) => errorResponse(500);
    final failed = await bloc.stream.firstWhere((s) => s.failure != null);
    expect(failed.failure, isA<Failure>());
    expect(failed.loaded, isFalse);

    handler = (_) => pagedResponse([movementJson(1)]);
    bloc.add(const InventoryMovementsStarted());
    final ok = await bloc.stream.firstWhere((s) => s.loaded);
    expect(ok.failure, isNull);
    expect(ok.items, hasLength(1));
  });
}
