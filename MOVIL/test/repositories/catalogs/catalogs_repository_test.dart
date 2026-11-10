import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/catalogs/catalog_models.dart';
import 'package:mantix/repositories/catalogs/catalogs_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _technician = {
  'id': 5,
  'user_id': 105,
  'full_name': 'Luis Técnico',
  'email': 'luis@x.co',
  'employee_code': null,
  'specialization': 'Redes',
  'is_available': false,
  'is_active': true,
  'hourly_rate': null,
  'created_at': '2026-10-01T10:00:00Z',
};

void main() {
  test('categories lee código y nombre y se reutiliza durante un rato', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, [
          {'code': 'hardware', 'name': 'Hardware'},
          {'code': 'software', 'name': 'Software'},
        ]));
    final repository = CatalogsRepository(dioWith(adapter));

    final first = await repository.categories();
    final second = await repository.categories();

    expect(first, const [RequestCategory(code: 'hardware', name: 'Hardware'), RequestCategory(code: 'software', name: 'Software')]);
    expect(second, first);
    expect(adapter.requests, hasLength(1), reason: 'la segunda lectura sale del caché');
    expect(adapter.requests.single.path, '/maintenance/categories');
  });

  test('categories(refresh: true) vuelve a pedirlas', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, [
          {'code': 'hardware', 'name': 'Hardware'},
        ]));
    final repository = CatalogsRepository(dioWith(adapter));

    await repository.categories();
    await repository.categories(refresh: true);

    expect(adapter.requests, hasLength(2));
  });

  test('un fallo al pedir las categorías no se guarda en el caché', () async {
    var fail = true;
    final adapter = FakeAdapter((_) => fail
        ? errorResponse(500)
        : jsonResponse(200, [
            {'code': 'hardware', 'name': 'Hardware'},
          ]));
    final repository = CatalogsRepository(dioWith(adapter));

    await expectLater(repository.categories(), throwsA(isA<ServerFailure>()));
    fail = false;
    expect(await repository.categories(), hasLength(1));
  });

  test('priorities lee código, nombre y nivel', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, [
          {'id': 3, 'code': 'high', 'name': 'Alta', 'level': 3, 'is_active': true},
        ]));
    final priorities = await CatalogsRepository(dioWith(adapter)).priorities();

    expect(priorities, const [PriorityOption(code: 'high', name: 'Alta', level: 3)]);
    expect(adapter.requests.single.path, '/priorities');
  });

  test('technicians pide la página, el tamaño, el orden y el texto de búsqueda', () async {
    final adapter = FakeAdapter((_) => pagedResponse([_technician], page: 2, totalPages: 3, total: 41));
    final result = await CatalogsRepository(dioWith(adapter)).technicians(search: '  luis ', page: 2, size: 10);

    expect(adapter.requests.single.path, '/technicians');
    expect(adapter.requests.single.queryParameters, {'page': 2, 'size': 10, 'sort': 'name', 'search': 'luis'});
    expect(result.items.single, const TechnicianOption(id: 5, fullName: 'Luis Técnico', email: 'luis@x.co', specialization: 'Redes', isActive: true, isAvailable: false));
    expect(result.info?.total, 41);
    expect(result.info?.page, 2);
  });

  test('technicians sin texto no manda search', () async {
    final adapter = FakeAdapter((_) => pagedResponse([_technician]));
    await CatalogsRepository(dioWith(adapter)).technicians();
    expect(adapter.requests.single.queryParameters.keys, isNot(contains('search')));
  });

  test('sin el permiso de ver técnicos llega un ForbiddenFailure', () async {
    final adapter = FakeAdapter((_) => errorResponse(403, code: 'forbidden'));
    await expectLater(CatalogsRepository(dioWith(adapter)).technicians(), throwsA(isA<ForbiddenFailure>()));
  });
}
