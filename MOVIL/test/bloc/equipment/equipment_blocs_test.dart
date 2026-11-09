import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/create_equipment_bloc.dart';
import 'package:mantix/bloc/equipment/custodian_search_bloc.dart';
import 'package:mantix/bloc/equipment/equipment_catalog_bloc.dart';
import 'package:mantix/bloc/equipment/equipment_list_bloc.dart';
import 'package:mantix/bloc/equipment/equipment_summary_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/models/page_info.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockEquipmentRepository extends Mock implements EquipmentRepository {}

const _equipment = Equipment(id: 1, assetTag: 'DEMO-001', brand: 'Dell', model: 'Latitude', status: 'assigned', typeCode: 'LAPTOP', typeName: 'Laptop');
const _summary = EquipmentSummary(total: 3, byStatus: {'assigned': 2, 'in_repair': 1});
const _types = [EquipmentType(id: 1, code: 'LAPTOP', name: 'Laptop')];
const _locations = [EquipmentLocation(id: 3, code: 'HQ', name: 'Sede central')];
const _page1 = PageInfo(total: 25, page: 1, pageSize: 10, totalPages: 3);
const _page2 = PageInfo(total: 25, page: 2, pageSize: 10, totalPages: 3);

void main() {
  late _MockEquipmentRepository repository;

  setUp(() {
    repository = _MockEquipmentRepository();
    when(() => repository.changes).thenAnswer((_) => const Stream<void>.empty());
  });

  void stubList({PagedResult<Equipment>? result}) => when(
        () => repository.listEquipment(
          page: any(named: 'page'),
          size: any(named: 'size'),
          statuses: any(named: 'statuses'),
          search: any(named: 'search'),
          typeId: any(named: 'typeId'),
        ),
      ).thenAnswer((_) async => result ?? const PagedResult(items: [_equipment], info: _page1));

  group('EquipmentListBloc', () {
    test('pide la primera página con los filtros y el tamaño con los que se creó', () async {
      stubList();
      final bloc = EquipmentListBloc(repository: repository, statuses: 'in_repair', search: 'dell', typeId: 2, pageSize: 20)..add(const EquipmentListStarted());
      addTearDown(bloc.close);

      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);

      verify(() => repository.listEquipment(page: 1, size: 20, statuses: 'in_repair', search: 'dell', typeId: 2)).called(1);
      expect(bloc.state.items, [_equipment]);
      expect(bloc.state.total, 25);
      expect(bloc.state.totalPages, 3);
    });

    test('sin filtros pide todo el catálogo de diez en diez', () async {
      stubList();
      final bloc = EquipmentListBloc(repository: repository)..add(const EquipmentListStarted());
      addTearDown(bloc.close);

      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);

      verify(() => repository.listEquipment(page: 1, size: 10, statuses: null, search: '', typeId: null)).called(1);
    });

    test('cambiar de página pide esa página y conserva los datos mientras llega', () async {
      stubList();
      final bloc = EquipmentListBloc(repository: repository)..add(const EquipmentListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);
      final second = Completer<PagedResult<Equipment>>();
      when(() => repository.listEquipment(page: 2, size: 10, statuses: null, search: '', typeId: null)).thenAnswer((_) => second.future);

      bloc.add(const EquipmentPageSelected(2));
      final waiting = await bloc.stream.firstWhere((s) => s.loadingPage);
      expect(waiting.items, [_equipment], reason: 'se siguen viendo los equipos anteriores');
      expect(waiting.page, 2);

      second.complete(const PagedResult(items: [_equipment], info: _page2));
      await bloc.stream.firstWhere((s) => !s.loadingPage);
      expect(bloc.state.page, 2);
      expect(bloc.state.info, _page2);
    });

    test('si falla la página el estado es de error y reintentar vuelve a pedirla', () async {
      when(() => repository.listEquipment(page: any(named: 'page'), size: any(named: 'size'), statuses: any(named: 'statuses'), search: any(named: 'search'), typeId: any(named: 'typeId')))
          .thenThrow(const NetworkFailure());
      final bloc = EquipmentListBloc(repository: repository)..add(const EquipmentListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.failure);
      expect(bloc.state.failure, isA<NetworkFailure>());

      stubList();
      bloc.add(const EquipmentListRefreshed());
      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);

      expect(bloc.state.items, [_equipment]);
    });

    test('refresh() vuelve a pedir la página actual y espera', () async {
      stubList();
      final bloc = EquipmentListBloc(repository: repository)..add(const EquipmentListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);

      await bloc.refresh();

      verify(() => repository.listEquipment(page: 1, size: 10, statuses: null, search: '', typeId: null)).called(2);
    });

    test('se recarga solo cuando el catálogo cambia', () async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      when(() => repository.changes).thenAnswer((_) => changes.stream);
      stubList();
      final bloc = EquipmentListBloc(repository: repository)..add(const EquipmentListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == EquipmentListStatus.success);

      changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => repository.listEquipment(page: 1, size: 10, statuses: null, search: '', typeId: null)).called(2);
    });
  });

  group('EquipmentSummaryBloc', () {
    blocTest<EquipmentSummaryBloc, EquipmentSummaryState>(
      'carga los contadores',
      build: () {
        when(() => repository.summary()).thenAnswer((_) async => _summary);
        return EquipmentSummaryBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const EquipmentSummaryStarted()),
      expect: () => [const EquipmentSummaryState(status: SummaryStatus.success, summary: _summary)],
    );

    blocTest<EquipmentSummaryBloc, EquipmentSummaryState>(
      'un error deja el estado de fallo sin contadores',
      build: () {
        when(() => repository.summary()).thenThrow(const NetworkFailure());
        return EquipmentSummaryBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const EquipmentSummaryStarted()),
      expect: () => [const EquipmentSummaryState(status: SummaryStatus.failure, failure: NetworkFailure())],
    );

    test('si un refresco falla se conservan los últimos contadores', () async {
      var calls = 0;
      when(() => repository.summary()).thenAnswer((_) async {
        if (++calls == 1) return _summary;
        throw const NetworkFailure();
      });
      final bloc = EquipmentSummaryBloc(repository: repository)..add(const EquipmentSummaryStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == SummaryStatus.success);

      await bloc.refresh();

      expect(bloc.state.status, SummaryStatus.failure);
      expect(bloc.state.summary, _summary);
    });

    test('los contadores se vuelven a pedir cuando el catálogo cambia', () async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      when(() => repository.changes).thenAnswer((_) => changes.stream);
      when(() => repository.summary()).thenAnswer((_) async => _summary);
      final bloc = EquipmentSummaryBloc(repository: repository)..add(const EquipmentSummaryStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == SummaryStatus.success);

      changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => repository.summary()).called(2);
    });
  });

  group('EquipmentCatalogBloc', () {
    blocTest<EquipmentCatalogBloc, EquipmentCatalogState>(
      'carga categorías y ubicaciones',
      build: () {
        when(() => repository.types()).thenAnswer((_) async => _types);
        when(() => repository.locations()).thenAnswer((_) async => _locations);
        return EquipmentCatalogBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const EquipmentCatalogStarted()),
      expect: () => [
        const EquipmentCatalogState(),
        const EquipmentCatalogState(status: CatalogStatus.success, types: _types, locations: _locations),
      ],
    );

    blocTest<EquipmentCatalogBloc, EquipmentCatalogState>(
      'si fallan las ubicaciones se conservan las categorías',
      build: () {
        when(() => repository.types()).thenAnswer((_) async => _types);
        when(() => repository.locations()).thenThrow(const ForbiddenFailure());
        return EquipmentCatalogBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const EquipmentCatalogStarted()),
      expect: () => [
        const EquipmentCatalogState(),
        const EquipmentCatalogState(status: CatalogStatus.failure, types: _types, failure: ForbiddenFailure()),
      ],
    );

    blocTest<EquipmentCatalogBloc, EquipmentCatalogState>(
      'si fallan las categorías se conservan las ubicaciones',
      build: () {
        when(() => repository.types()).thenThrow(const NetworkFailure());
        when(() => repository.locations()).thenAnswer((_) async => _locations);
        return EquipmentCatalogBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const EquipmentCatalogStarted()),
      expect: () => [
        const EquipmentCatalogState(),
        const EquipmentCatalogState(status: CatalogStatus.failure, locations: _locations, failure: NetworkFailure()),
      ],
    );
  });

  group('CustodianSearchBloc', () {
    const ana = CustodianCandidate(id: 9, fullName: 'Ana Pérez', email: 'ana@example.com');

    blocTest<CustodianSearchBloc, CustodianSearchState>(
      'busca y devuelve los usuarios',
      build: () {
        when(() => repository.custodianCandidates('ana')).thenAnswer((_) async => [ana]);
        return CustodianSearchBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CustodianSearched('  ana ')),
      expect: () => [
        const CustodianSearchState(query: 'ana', status: CustodianSearchStatus.loading),
        const CustodianSearchState(query: 'ana', status: CustodianSearchStatus.success, results: [ana]),
      ],
    );

    blocTest<CustodianSearchBloc, CustodianSearchState>(
      'un error de red queda como fallo con el motivo',
      build: () {
        when(() => repository.custodianCandidates(any())).thenThrow(const NetworkFailure());
        return CustodianSearchBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CustodianSearched('ana')),
      expect: () => [
        const CustodianSearchState(query: 'ana', status: CustodianSearchStatus.loading),
        const CustodianSearchState(query: 'ana', status: CustodianSearchStatus.failure, failure: NetworkFailure()),
      ],
    );

    test('la respuesta de una búsqueda anterior ya no interesa', () async {
      final slow = Completer<List<CustodianCandidate>>();
      when(() => repository.custodianCandidates('a')).thenAnswer((_) => slow.future);
      when(() => repository.custodianCandidates('ana')).thenAnswer((_) async => [ana]);
      final bloc = CustodianSearchBloc(repository: repository);
      addTearDown(bloc.close);

      bloc.add(const CustodianSearched('a'));
      bloc.add(const CustodianSearched('ana'));
      slow.complete(const []);
      await bloc.stream.firstWhere((s) => s.status == CustodianSearchStatus.success && s.query == 'ana');

      expect(bloc.state.query, 'ana');
      expect(bloc.state.results, [ana]);
    });
  });

  group('CreateEquipmentBloc', () {
    const form = NewEquipment(assetTag: 'EQ-029', typeId: 1, brand: 'Dell', model: 'Latitude');
    const withAssignments = NewEquipment(assetTag: 'EQ-029', typeId: 1, brand: 'Dell', model: 'Latitude', locationId: 3, custodianId: 9);

    blocTest<CreateEquipmentBloc, CreateEquipmentState>(
      'envía el alta y devuelve el equipo creado',
      build: () {
        when(() => repository.create(form)).thenAnswer((_) async => _equipment);
        return CreateEquipmentBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CreateEquipmentSubmitted(form)),
      expect: () => [
        const CreateEquipmentState(status: CreateEquipmentStatus.submitting),
        const CreateEquipmentState(status: CreateEquipmentStatus.success, created: _equipment),
      ],
      verify: (_) {
        verifyNever(() => repository.assignLocation(any(), any()));
        verifyNever(() => repository.assignCustody(any(), any()));
      },
    );

    blocTest<CreateEquipmentBloc, CreateEquipmentState>(
      'con ubicación y responsable los asigna tras crear el equipo',
      build: () {
        when(() => repository.create(withAssignments)).thenAnswer((_) async => _equipment);
        when(() => repository.assignLocation(1, 3)).thenAnswer((_) async {});
        when(() => repository.assignCustody(1, 9)).thenAnswer((_) async {});
        return CreateEquipmentBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CreateEquipmentSubmitted(withAssignments)),
      expect: () => [
        const CreateEquipmentState(status: CreateEquipmentStatus.submitting),
        const CreateEquipmentState(status: CreateEquipmentStatus.success, created: _equipment),
      ],
      verify: (_) {
        verifyInOrder([
          () => repository.create(withAssignments),
          () => repository.assignLocation(1, 3),
          () => repository.assignCustody(1, 9),
        ]);
      },
    );

    blocTest<CreateEquipmentBloc, CreateEquipmentState>(
      'si una asignación falla el equipo queda creado y se avisa del motivo',
      build: () {
        when(() => repository.create(withAssignments)).thenAnswer((_) async => _equipment);
        when(() => repository.assignLocation(1, 3)).thenThrow(const ForbiddenFailure());
        when(() => repository.assignCustody(1, 9)).thenAnswer((_) async {});
        return CreateEquipmentBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CreateEquipmentSubmitted(withAssignments)),
      expect: () => [
        const CreateEquipmentState(status: CreateEquipmentStatus.submitting),
        isA<CreateEquipmentState>()
            .having((s) => s.status, 'status', CreateEquipmentStatus.success)
            .having((s) => s.created, 'created', _equipment)
            .having((s) => s.warnings, 'warnings', [startsWith('No se pudo asignar la ubicación')]),
      ],
      verify: (_) => verify(() => repository.assignCustody(1, 9)).called(1),
    );

    blocTest<CreateEquipmentBloc, CreateEquipmentState>(
      'un fallo del alta trae el motivo y no asigna nada',
      build: () {
        when(() => repository.create(withAssignments)).thenThrow(const ConflictFailure(code: 'equipment_identifier_taken'));
        return CreateEquipmentBloc(repository: repository);
      },
      act: (bloc) => bloc.add(const CreateEquipmentSubmitted(withAssignments)),
      expect: () => [
        const CreateEquipmentState(status: CreateEquipmentStatus.submitting),
        const CreateEquipmentState(status: CreateEquipmentStatus.failure, failure: ConflictFailure(code: 'equipment_identifier_taken')),
      ],
      verify: (_) {
        verifyNever(() => repository.assignLocation(any(), any()));
        verifyNever(() => repository.assignCustody(any(), any()));
      },
    );

    test('un segundo envío mientras el primero está en curso se ignora', () async {
      final pending = Completer<Equipment>();
      when(() => repository.create(form)).thenAnswer((_) => pending.future);
      final bloc = CreateEquipmentBloc(repository: repository);
      addTearDown(bloc.close);

      bloc
        ..add(const CreateEquipmentSubmitted(form))
        ..add(const CreateEquipmentSubmitted(form));
      await Future<void>.delayed(Duration.zero);
      pending.complete(_equipment);
      await bloc.stream.firstWhere((s) => s.status == CreateEquipmentStatus.success);

      verify(() => repository.create(form)).called(1);
    });
  });
}
