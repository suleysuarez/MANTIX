import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/catalogs/category_names_cubit.dart';
import 'package:mantix/repositories/catalogs/catalogs_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  test('carga los nombres por código', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, [
          {'code': 'network', 'name': 'Red'},
          {'code': 'hardware', 'name': 'Hardware'},
        ]));
    final cubit = CategoryNamesCubit(CatalogsRepository(dioWith(adapter)));
    addTearDown(cubit.close);
    expect(cubit.state.loaded, isFalse);

    await cubit.load();

    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.names, {'network': 'Red', 'hardware': 'Hardware'});
  });

  test('si el catálogo no carga queda vacío pero terminado: la bandeja rotula con el código', () async {
    final cubit = CategoryNamesCubit(CatalogsRepository(dioWith(FakeAdapter((_) => errorResponse(500)))));
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.names, isEmpty);
  });
}
