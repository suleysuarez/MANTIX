import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/catalogs/category_search_bloc.dart';
import 'package:mantix/bloc/catalogs/priorities_cubit.dart';
import 'package:mantix/bloc/catalogs/technician_search_bloc.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/catalogs/catalogs_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

Map<String, Object?> technician(int id, String name, {bool active = true}) => {
      'id': id,
      'user_id': id + 100,
      'full_name': name,
      'email': '$id@x.co',
      'employee_code': null,
      'specialization': null,
      'is_available': true,
      'is_active': active,
      'hourly_rate': null,
      'created_at': '2026-10-01T10:00:00Z',
    };

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;

  CatalogsRepository repository() => CatalogsRepository(dioWith(adapter));

  setUp(() {
    handler = (_) => jsonResponse(200, []);
    adapter = FakeAdapter((options) => handler(options));
  });

  group('CategorySearchBloc', () {
    final categories = [for (final name in ['Hardware', 'Software', 'Red', 'Impresoras', 'Accesos', 'Correo']) {'code': name.toLowerCase(), 'name': name}];

    test('reparte las categorías por páginas con el contrato de un listado del servidor', () async {
      handler = (_) => jsonResponse(200, categories);
      final bloc = CategorySearchBloc(repository: repository(), pageSize: 4)..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.success);

      expect(bloc.state.items.map((c) => c.name), ['Hardware', 'Software', 'Red', 'Impresoras']);
      expect(bloc.state.info?.total, 6);
      expect(bloc.state.info?.totalPages, 2);
      expect(bloc.state.hasMore, isTrue);

      bloc.add(const PagedLoadMoreRequested());
      await bloc.stream.firstWhere((state) => state.items.length == 6);
      expect(bloc.state.items.last.name, 'Correo');
      expect(bloc.state.hasMore, isFalse);
    });

    test('busca por nombre sin distinguir mayúsculas y sin volver a pedir el catálogo', () async {
      handler = (_) => jsonResponse(200, categories);
      final repo = repository();
      final first = CategorySearchBloc(repository: repo)..add(const PagedStarted());
      await first.stream.firstWhere((state) => state.status == PagedStatus.success);
      final searched = CategorySearchBloc(repository: repo, search: '  SOFT ')..add(const PagedStarted());
      await searched.stream.firstWhere((state) => state.status == PagedStatus.success);
      addTearDown(first.close);
      addTearDown(searched.close);

      expect(searched.state.items.map((c) => c.name), ['Software']);
      expect(adapter.requests.where((r) => r.path == '/maintenance/categories'), hasLength(1));
    });

    test('un fallo al cargar deja el estado de error con el motivo', () async {
      handler = (_) => errorResponse(500);
      final bloc = CategorySearchBloc(repository: repository())..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.failure);

      expect(bloc.state.failure, isA<ServerFailure>());
    });
  });

  group('TechnicianSearchBloc', () {
    test('descarta los técnicos con la cuenta inactiva y conserva el total del servidor', () async {
      handler = (_) => pagedResponse([technician(1, 'Luis'), technician(2, 'Ana', active: false), technician(3, 'Marta')], total: 3);
      final bloc = TechnicianSearchBloc(repository: repository())..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.success);

      expect(bloc.state.items.map((t) => t.fullName), ['Luis', 'Marta']);
      expect(bloc.state.info?.total, 3, reason: 'el total es el del servidor, que no filtra por cuenta activa');
    });

    test('pide al servidor la búsqueda, el tamaño de página y las páginas siguientes', () async {
      handler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([technician(page, 'Técnico $page')], page: page, totalPages: 2, total: 2);
      };
      final bloc = TechnicianSearchBloc(repository: repository(), search: 'tec', pageSize: 5)..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.success);
      expect(adapter.requests.single.queryParameters, containsPair('search', 'tec'));
      expect(adapter.requests.single.queryParameters, containsPair('size', 5));

      bloc.add(const PagedLoadMoreRequested());
      await bloc.stream.firstWhere((state) => state.items.length == 2);
      expect(adapter.requests.last.queryParameters, containsPair('page', 2));
    });

    test('sin permiso para ver técnicos termina en error', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = TechnicianSearchBloc(repository: repository())..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.failure);

      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });
  });

  group('PrioritiesCubit', () {
    test('carga las prioridades de la más urgente a la menos', () async {
      handler = (_) => jsonResponse(200, [
            {'id': 1, 'code': 'low', 'name': 'Baja', 'level': 1},
            {'id': 4, 'code': 'critical', 'name': 'Crítica', 'level': 4},
            {'id': 3, 'code': 'high', 'name': 'Alta', 'level': 3},
          ]);
      final cubit = PrioritiesCubit(repository());
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.status, PrioritiesStatus.success);
      expect(cubit.state.priorities.map((p) => p.code), ['critical', 'high', 'low']);
    });

    test('un fallo deja el motivo y cargar de nuevo se recupera', () async {
      handler = (_) => errorResponse(500);
      final cubit = PrioritiesCubit(repository());
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.status, PrioritiesStatus.failure);
      expect(cubit.state.failure, isNotNull);

      handler = (_) => jsonResponse(200, [
            {'id': 1, 'code': 'low', 'name': 'Baja', 'level': 1},
          ]);
      await cubit.load();
      expect(cubit.state.status, PrioritiesStatus.success);
      expect(cubit.state.failure, isNull);
    });
  });
}
