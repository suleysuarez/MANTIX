import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/create_equipment_type_bloc.dart';
import 'package:mantix/bloc/equipment/equipment_catalog_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  late ResponseBody Function(RequestOptions) handler;
  late FakeAdapter adapter;

  setUp(() {
    handler = (_) => jsonResponse(201, {'id': 9, 'code': 'PROYECTOR_HD', 'name': 'Proyector HD'});
    adapter = FakeAdapter((options) => handler(options));
  });

  CreateEquipmentTypeBloc build() => CreateEquipmentTypeBloc(repository: EquipmentRepository(dioWith(adapter)));

  group('CreateEquipmentTypeBloc', () {
    test('crea la categoría y avisa con la categoría creada', () async {
      final bloc = build()..add(const EquipmentTypeSubmitted('Proyector HD'));
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CreateTypeStatus.success);

      expect(bloc.state.created, const EquipmentType(id: 9, code: 'PROYECTOR_HD', name: 'Proyector HD'));
      expect(adapter.requests.single.data, {'name': 'Proyector HD'});
    });

    test('pasa por «enviando» y no manda dos veces mientras espera', () async {
      final bloc = build();
      addTearDown(bloc.close);
      final states = <CreateTypeStatus>[];
      final sub = bloc.stream.listen((state) => states.add(state.status));
      addTearDown(sub.cancel);

      bloc
        ..add(const EquipmentTypeSubmitted('Proyector HD'))
        ..add(const EquipmentTypeSubmitted('Proyector HD'));
      await bloc.stream.firstWhere((state) => state.status == CreateTypeStatus.success);

      expect(states.first, CreateTypeStatus.submitting);
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('un 409 equipment_type_name_taken es el caso «ya existe», no un fallo, y recuerda el nombre', () async {
      handler = (_) => errorResponse(409, code: equipmentTypeNameTaken);
      final bloc = build()..add(const EquipmentTypeSubmitted('laptop'));
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status != CreateTypeStatus.submitting);

      expect(bloc.state.status, CreateTypeStatus.conflict);
      expect(bloc.state.name, 'laptop');
      expect(bloc.state.failure, isA<ConflictFailure>());
    });

    test('un 409 con otro código es un fallo, no «ya existe»', () async {
      handler = (_) => errorResponse(409, code: 'conflict');
      final bloc = build()..add(const EquipmentTypeSubmitted('Proyector'));
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status != CreateTypeStatus.submitting);

      expect(bloc.state.status, CreateTypeStatus.failure);
    });

    test('un 403, un 422 y un error de red terminan en fallo con el motivo y se puede reintentar', () async {
      for (final response in [errorResponse(403, code: 'forbidden'), errorResponse(422, code: 'validation_error')]) {
        handler = (_) => response;
        final bloc = build()..add(const EquipmentTypeSubmitted('Proyector'));
        await bloc.stream.firstWhere((state) => state.status != CreateTypeStatus.submitting);
        expect(bloc.state.status, CreateTypeStatus.failure);
        expect(bloc.state.failure, isNotNull);
        await bloc.close();
      }

      final bloc = build();
      addTearDown(bloc.close);
      handler = (_) => errorResponse(500);
      bloc.add(const EquipmentTypeSubmitted('Proyector HD'));
      await bloc.stream.firstWhere((state) => state.status == CreateTypeStatus.failure);
      handler = (_) => jsonResponse(201, {'id': 9, 'code': 'PROYECTOR_HD', 'name': 'Proyector HD'});
      bloc.add(const EquipmentTypeSubmitted('Proyector HD'));
      await bloc.stream.firstWhere((state) => state.status == CreateTypeStatus.success);
    });
  });

  group('EquipmentCatalogBloc.EquipmentTypeAdded', () {
    test('añade la categoría creada sin volver a pedir el catálogo y la deja ordenada por nombre', () async {
      adapter = FakeAdapter((options) => options.path == '/locations'
          ? jsonResponse(200, [])
          : jsonResponse(200, [
              {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
              {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
            ]));
      final bloc = EquipmentCatalogBloc(repository: EquipmentRepository(dioWith(adapter)))..add(const EquipmentCatalogStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CatalogStatus.success);
      final requests = adapter.requests.length;

      bloc.add(const EquipmentTypeAdded(EquipmentType(id: 9, code: 'PROYECTOR', name: 'Proyector')));
      await bloc.stream.firstWhere((state) => state.types.length == 3);

      expect(bloc.state.types.map((t) => t.name), ['Impresora', 'Laptop', 'Proyector']);
      expect(adapter.requests, hasLength(requests));

      bloc.add(const EquipmentTypeAdded(EquipmentType(id: 9, code: 'PROYECTOR', name: 'Proyector')));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.types, hasLength(3), reason: 'una categoría que ya está no se repite');
    });
  });
}
