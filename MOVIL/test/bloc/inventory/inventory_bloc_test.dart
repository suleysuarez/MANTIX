import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/inventory/inventory_bloc.dart';
import 'package:mantix/repositories/inventory/inventory_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

Map<String, Object?> itemJson(int id, {String name = 'Cable'}) => {
      'id': id, 'sku': 'CAB-$id', 'name': name, 'category': 'accessory', 'unit': 'unidad', 'unit_cost': '10.00',
      'stock': 4, 'min_stock': 1, 'max_stock': null, 'status': 'ok', 'stock_value': '40.00', 'created_at': '2026-11-12T15:00:00Z',
    };

void main() {
  late FakeAdapter adapter;
  late InventoryBloc bloc;

  ResponseBody handle(RequestOptions o) {
    if (o.method == 'POST' && o.path == '/inventory/items') return jsonResponse(201, itemJson(9, name: 'Nuevo'));
    if (o.method == 'PATCH') return jsonResponse(200, itemJson(3, name: 'Editado'));
    if (o.path == '/inventory/overview') {
      return jsonResponse(200, {'stock_value': {'total': '40.00', 'change_pct': 35.6}, 'low_stock': 1, 'out_of_stock': 0, 'consumption': {'units': 2, 'value': '20.00'}});
    }
    if (o.path == '/inventory/options') return jsonResponse(200, <Object?>[]);
    return pagedResponse([itemJson(9, name: 'Nuevo'), itemJson(3)]);
  }

  setUp(() {
    adapter = FakeAdapter(handle);
    bloc = InventoryBloc(repository: InventoryRepository(dioWith(adapter)));
    addTearDown(bloc.close);
  });

  test('el listado pide primero lo más reciente y lee la variación del stock', () async {
    bloc.add(const InventoryStarted());
    final state = await bloc.stream.firstWhere((s) => !s.loading && s.overview != null);

    expect(adapter.requests.firstWhere((r) => r.path == '/inventory/items').queryParameters['sort'], '-created_at');
    expect(state.overview!.stockChangePct, 35.6);
  });

  test('al crear un ítem se limpian búsqueda y filtros y se recarga desde la página 1', () async {
    bloc.add(const InventoryQueryChanged(search: 'usb', category: 'tool', status: 'low'));
    await bloc.stream.firstWhere((s) => !s.loading && s.search == 'usb');

    bloc.add(const InventoryItemCreateRequested({'sku': 'NEW-1', 'name': 'Nuevo'}));
    final saved = await bloc.stream.firstWhere((s) => s.savedItem != null);
    expect((saved.search, saved.category, saved.status, saved.page), ('', null, null, 1));
    expect(saved.notice, 'Ítem creado correctamente.');

    await bloc.stream.firstWhere((s) => !s.loading && s.items.isNotEmpty);
    final reload = adapter.requests.where((r) => r.path == '/inventory/items' && r.method == 'GET').last.queryParameters;
    expect(reload.containsKey('search') || reload.containsKey('category') || reload.containsKey('status'), isFalse);
    expect(reload['page'], 1);
  });

  test('editar manda un PATCH al ítem y avisa que se guardó', () async {
    bloc.add(const InventoryItemUpdateRequested(3, {'name': 'Editado', 'max_stock': null}));
    final saved = await bloc.stream.firstWhere((s) => s.savedItem != null);

    final patch = adapter.requests.singleWhere((r) => r.method == 'PATCH');
    expect(patch.path, '/inventory/items/3');
    expect(patch.data, {'name': 'Editado', 'max_stock': null});
    expect(saved.savedItem!.name, 'Editado');
    expect(saved.notice, 'Cambios guardados.');
  });
}
