import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/reports/report_preview_bloc.dart';
import 'package:mantix/bloc/reports/reports_catalog_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/format/report_format.dart';
import 'package:mantix/repositories/reports/reports_repository.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart' show GatedAdapter;
import '../../support/reports_support.dart';
import '../../support/requests_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late ReportsRepository repository;

  setUp(() {
    handler = (_) => jsonResponse(200, catalogJson());
    adapter = FakeAdapter((options) => handler(options));
    repository = ReportsRepository(dioWith(adapter));
  });

  group('galería de reportes', () {
    ReportsCatalogBloc build() => ReportsCatalogBloc(repository: repository);

    Future<ReportsCatalogBloc> loaded() async {
      final bloc = build()..add(const ReportsCatalogRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CatalogStatus.ready);
      return bloc;
    }

    test('carga el catálogo, deja solo los 4 reportes de la app en su orden y elige el primero', () async {
      final bloc = await loaded();

      expect(bloc.state.reports.map((r) => r.key), ['tickets', 'maintenance_plans', 'equipment', 'summary']);
      expect(bloc.state.selectedKey, 'tickets');
      expect(bloc.state.selected?.title, 'Tickets de mantenimiento');
      expect(bloc.state.maxRows, 10000);
      expect(bloc.state.initialLoading, isFalse);
    });

    test('se puede elegir otro reporte de la galería', () async {
      final bloc = await loaded();
      bloc.add(const ReportSelected('equipment'));
      await pumpEventQueue();
      expect(bloc.state.selected?.key, 'equipment');
    });

    test('un reporte que no está en la galería no se puede elegir', () async {
      final bloc = await loaded();
      bloc.add(const ReportSelected('inventory_items'));
      bloc.add(const ReportSelected('no_existe'));
      await pumpEventQueue();
      expect(bloc.state.selectedKey, 'tickets');
    });

    test('al recargar se conserva el reporte elegido', () async {
      final bloc = await loaded();
      bloc.add(const ReportSelected('summary'));
      final done = Completer<void>();
      bloc.add(ReportsCatalogRequested(done: done));
      await done.future;
      expect(bloc.state.selectedKey, 'summary');
    });

    test('si el elegido desaparece del catálogo vuelve al primero', () async {
      final bloc = await loaded();
      bloc.add(const ReportSelected('equipment'));
      handler = (_) => jsonResponse(200, catalogJson(reports: [ticketsReport(), summaryReport()]));
      final done = Completer<void>();
      bloc.add(ReportsCatalogRequested(done: done));
      await done.future;

      expect(bloc.state.reports.map((r) => r.key), ['tickets', 'summary']);
      expect(bloc.state.selectedKey, 'tickets');
    });

    test('si el catálogo no trae ninguno de los 4, no hay galería ni reporte elegido', () async {
      handler = (_) => jsonResponse(200, catalogJson(reports: [inventoryReport()]));
      final bloc = await loaded();
      expect(bloc.state.reports, isEmpty);
      expect(bloc.state.selected, isNull);
    });

    test('si falla queda en error con el motivo y se puede reintentar', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const ReportsCatalogRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CatalogStatus.failure);
      expect(bloc.state.unavailable, isTrue);
      expect(bloc.state.failure, isA<ServerFailure>());

      handler = (_) => jsonResponse(200, catalogJson());
      bloc.add(const ReportsCatalogRequested());
      await bloc.stream.firstWhere((state) => state.status == CatalogStatus.ready);
      expect(bloc.state.failure, isNull);
    });

    test('una recarga que falla conserva la galería', () async {
      final bloc = await loaded();
      handler = (_) => errorResponse(500);
      final done = Completer<void>();
      bloc.add(ReportsCatalogRequested(done: done));
      await done.future;

      expect(bloc.state.status, CatalogStatus.failure);
      expect(bloc.state.unavailable, isFalse);
      expect(bloc.state.reports, hasLength(4));
    });

    test('sin permiso para ver reportes llega un ForbiddenFailure', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = build()..add(const ReportsCatalogRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CatalogStatus.failure);
      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });
  });

  group('vista previa', () {
    ReportPreviewBloc build(String key) => ReportPreviewBloc(repository: repository, definition: reportOf(key));

    Future<ReportPreviewBloc> previewed(String key, [ReportFilterValues values = const ReportFilterValues()]) async {
      final bloc = build(key)..add(ReportPreviewRequested(values));
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PreviewStatus.ready || state.status == PreviewStatus.failure || state.status == PreviewStatus.invalid);
      return bloc;
    }

    setUp(() => handler = (_) => jsonResponse(200, previewJson(total: 25)));

    test('empieza sin pedir nada', () {
      final bloc = build('tickets');
      addTearDown(bloc.close);
      expect(bloc.state.status, PreviewStatus.idle);
      expect(bloc.state.canExport, isFalse);
    });

    test('pide la vista previa con los filtros que el reporte admite', () async {
      final bloc = await previewed('tickets', const ReportFilterValues(statuses: {'resolved'}, categories: {'cables'}));

      final sent = adapter.requests.single.data as Map;
      expect(sent['report'], 'tickets');
      expect(sent['filters'], {'statuses': ['resolved']}, reason: 'las categorías no son un filtro de tickets');
      expect(sent['compare'], false);
      expect(bloc.state.preview?.totalRows, 25);
      expect(bloc.state.canExport, isTrue);
    });

    test('con las dos fechas y un reporte que lo admite, puede comparar con el periodo anterior', () async {
      handler = (_) => jsonResponse(200, previewJson(total: 12, comparison: comparisonJson()));
      final values = ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31), compare: true);
      final bloc = await previewed('tickets', values);

      expect((adapter.requests.single.data as Map)['compare'], true);
      expect(bloc.state.preview?.comparison?.previousTotal, 10);
    });

    test('el comparativo no se pide sin las dos fechas ni en un reporte que no lo admite', () async {
      await previewed('tickets', ReportFilterValues(dateFrom: DateTime(2026, 10, 1), compare: true));
      expect((adapter.requests.last.data as Map)['compare'], false);

      await previewed('equipment', ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 31), compare: true));
      expect((adapter.requests.last.data as Map)['compare'], false);
    });

    test('un rango de fechas inválido no pide nada y explica el problema', () async {
      final bloc = await previewed('tickets', ReportFilterValues(dateFrom: DateTime(2026, 10, 5), dateTo: DateTime(2026, 10, 1)));

      expect(adapter.requests, isEmpty);
      expect(bloc.state.status, PreviewStatus.invalid);
      expect(bloc.state.rangeError, 'La fecha final no puede ser anterior a la inicial.');
      expect(bloc.state.canExport, isFalse);
    });

    test('corregir el rango vuelve a pedir y quita el error', () async {
      final bloc = await previewed('tickets', ReportFilterValues(dateFrom: DateTime(2026, 10, 5), dateTo: DateTime(2026, 10, 1)));
      bloc.add(ReportPreviewRequested(ReportFilterValues(dateFrom: DateTime(2026, 10, 1), dateTo: DateTime(2026, 10, 5))));
      await bloc.stream.firstWhere((state) => state.status == PreviewStatus.ready);

      expect(bloc.state.rangeError, isNull);
      expect(adapter.requests, hasLength(1));
    });

    test('sin filas no se puede exportar', () async {
      handler = (_) => jsonResponse(200, previewJson(total: 0, rows: const []));
      final bloc = await previewed('tickets');
      expect(bloc.state.preview?.totalRows, 0);
      expect(bloc.state.canExport, isFalse);
    });

    test('con más filas que el límite no se puede exportar', () async {
      handler = (_) => jsonResponse(200, previewJson(total: 10001, truncated: true));
      final bloc = await previewed('tickets');
      expect(bloc.state.preview?.truncated, isTrue);
      expect(bloc.state.canExport, isFalse);
    });

    test('si falla, queda el error y se conserva la vista anterior', () async {
      final bloc = await previewed('tickets');
      handler = (_) => errorResponse(500);
      bloc.add(const ReportPreviewRequested(ReportFilterValues(statuses: {'resolved'})));
      await bloc.stream.firstWhere((state) => state.status == PreviewStatus.failure);

      expect(bloc.state.failure, isA<ServerFailure>());
      expect(bloc.state.preview?.totalRows, 25, reason: 'la vista anterior sigue a la vista');
      expect(bloc.state.canExport, isFalse);
    });

    test('mientras llega la vista nueva, la anterior sigue visible', () async {
      final bloc = await previewed('tickets');
      final states = <ReportPreviewState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);
      bloc.add(const ReportPreviewRequested(ReportFilterValues(statuses: {'resolved'})));
      await bloc.stream.firstWhere((state) => state.status == PreviewStatus.ready);

      expect(states.first.loading, isTrue);
      expect(states.first.preview?.totalRows, 25);
    });

    test('una respuesta que llega tarde de una petición anterior se descarta', () async {
      final gated = GatedAdapter((options) {
        final filters = (options.data as Map)['filters'] as Map;
        return jsonResponse(200, previewJson(total: filters.containsKey('statuses') ? 7 : 99));
      });
      final bloc = ReportPreviewBloc(repository: ReportsRepository(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = gated), definition: reportOf('tickets'))
        ..add(const ReportPreviewRequested(ReportFilterValues()));
      addTearDown(bloc.close);
      await pumpEventQueue();
      bloc.add(const ReportPreviewRequested(ReportFilterValues(statuses: {'resolved'})));
      await pumpEventQueue();
      expect(gated.pending, 2);

      gated.releaseNext(); // llega la primera, que ya no es la última pedida
      await pumpEventQueue();
      expect(bloc.state.preview, isNull);
      expect(bloc.state.loading, isTrue);

      gated.releaseNext();
      await bloc.stream.firstWhere((state) => state.status == PreviewStatus.ready);
      expect(bloc.state.preview?.totalRows, 7);
    });

    test('sin permiso para ver reportes llega un ForbiddenFailure', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = await previewed('tickets');
      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });

    test('un 422 del servidor llega como ValidationFailure', () async {
      handler = (_) => errorResponse(422, code: 'validation_error');
      final bloc = await previewed('tickets');
      expect(bloc.state.failure, isA<ValidationFailure>());
    });

    test('sin red llega un NetworkFailure', () async {
      handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      final bloc = await previewed('tickets');
      expect(bloc.state.failure, isA<NetworkFailure>());
    });
  });
}
