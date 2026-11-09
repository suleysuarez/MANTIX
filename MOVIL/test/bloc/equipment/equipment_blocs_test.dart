import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/equipment_list_bloc.dart';
import 'package:mantix/bloc/equipment/equipment_summary_bloc.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/models/page_info.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockEquipmentRepository extends Mock implements EquipmentRepository {}

const _equipment = Equipment(id: 1, assetTag: 'DEMO-001', brand: 'Dell', model: 'Latitude', status: 'assigned', typeCode: 'LAPTOP', typeName: 'Laptop');
const _summary = EquipmentSummary(total: 3, byStatus: {'assigned': 2, 'in_repair': 1});

void main() {
  late _MockEquipmentRepository repository;

  setUp(() => repository = _MockEquipmentRepository());

  group('EquipmentListBloc', () {
    test('pide la primera página con los filtros con los que se creó', () async {
      when(() => repository.listEquipment(page: any(named: 'page'), statuses: any(named: 'statuses'), search: any(named: 'search')))
          .thenAnswer((_) async => const PagedResult(items: [_equipment], info: null));
      final bloc = EquipmentListBloc(repository: repository, statuses: 'in_repair', search: 'dell')..add(const PagedStarted());
      addTearDown(bloc.close);

      await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      verify(() => repository.listEquipment(page: 1, statuses: 'in_repair', search: 'dell')).called(1);
      expect(bloc.state.items, [_equipment]);
    });

    test('sin filtros pide todo el catálogo', () async {
      when(() => repository.listEquipment(page: any(named: 'page'), statuses: any(named: 'statuses'), search: any(named: 'search')))
          .thenAnswer((_) async => const PagedResult(items: [], info: null));
      final bloc = EquipmentListBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);

      await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      verify(() => repository.listEquipment(page: 1, statuses: null, search: '')).called(1);
    });

    test('si falla la primera página el estado es de error', () async {
      when(() => repository.listEquipment(page: any(named: 'page'), statuses: any(named: 'statuses'), search: any(named: 'search')))
          .thenThrow(const NetworkFailure());
      final bloc = EquipmentListBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);

      await bloc.stream.firstWhere((s) => s.status == PagedStatus.failure);

      expect(bloc.state.failure, isA<NetworkFailure>());
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

    test('refresh() espera a que termine', () async {
      when(() => repository.summary()).thenAnswer((_) async => _summary);
      final bloc = EquipmentSummaryBloc(repository: repository);
      addTearDown(bloc.close);

      await bloc.refresh();

      expect(bloc.state.summary, _summary);
    });
  });
}
