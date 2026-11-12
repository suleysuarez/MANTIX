import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/reports/report_models.dart';
import 'package:mantix/repositories/reports/reports_repository.dart';

import '../../support/fakes.dart';
import '../../support/reports_support.dart';
import '../../support/requests_support.dart';

void main() {
  ReportsRepository repo(FakeAdapter adapter) => ReportsRepository(dioWith(adapter));
  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;

  group('modelos', () {
    test('un reporte lee sus filtros con sus opciones y si admite comparativo', () {
      final report = ReportDefinition.fromJson(ticketsReport());

      expect(report.key, 'tickets');
      expect(report.title, 'Tickets de mantenimiento');
      expect(report.supportsCompare, isTrue);
      expect(report.filters.map((f) => f.key), ['statuses', 'priorities', 'dates']);
      expect(report.filters.map((f) => f.kind), [ReportFilterKind.multiselect, ReportFilterKind.multiselect, ReportFilterKind.dates]);
      expect(report.filter('statuses')!.labelOf('in_progress'), 'En proceso');
      expect(report.filter('statuses')!.labelOf('otro'), 'otro', reason: 'un valor desconocido se muestra tal cual');
      expect(report.filter('days'), isNull);
    });

    test('el filtro de ventana es de tipo days', () {
      expect(ReportDefinition.fromJson(summaryReport()).filters.single.kind, ReportFilterKind.days);
    });

    test('la vista previa vuelve cada celda un texto y lee el comparativo', () {
      final preview = ReportPreview.fromJson(previewJson(total: 12, truncated: true, rows: [
        {'ticket_number': 'TCK-1', 'title': 'Uno', 'status': 'Abierto'},
      ], comparison: comparisonJson()));

      expect(preview.totalRows, 12);
      expect(preview.truncated, isTrue);
      expect(preview.columns.map((c) => c.header), ['Ticket', 'Título', 'Estado']);
      expect(preview.rows.single['title'], 'Uno');
      expect(preview.comparison?.currentTotal, 12);
      expect(preview.comparison?.previousTotal, 10);
      expect(preview.comparison?.changePct, 20);
      expect(preview.comparison?.previousFrom, isNotNull);
    });

    test('una celda vacía llega como texto vacío y sin comparativo no hay comparación', () {
      final preview = ReportPreview.fromJson({
        ...previewJson(),
        'rows': [
          {'ticket_number': null, 'title': 5}
        ],
      });
      expect(preview.rows.single, {'ticket_number': '', 'title': '5'});
      expect(preview.comparison, isNull);
    });

    test('un comparativo sin variación (periodo anterior vacío) deja la variación en null', () {
      expect(ReportComparison.fromJson(comparisonJson(previous: 0, change: null)).changePct, isNull);
    });

    test('una exportación del historial dice su formato en español', () {
      expect(ReportRun.fromJson(runJson(format: 'xlsx')).formatLabel, 'Excel');
      expect(ReportRun.fromJson(runJson(format: 'pdf')).formatLabel, 'PDF');
      expect(ReportRun.fromJson(runJson(format: 'csv')).formatLabel, 'CSV', reason: 'la web también exporta CSV');
      expect(ReportRun.fromJson(runJson(by: null)).by, isNull);
      expect(ReportRun.fromJson(runJson(rows: 7)).rowCount, 7);
    });
  });

  group('catalog', () {
    test('lee los reportes y los límites', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, catalogJson(maxRows: 5000)));
      final catalog = await repo(adapter).catalog();

      expect(adapter.requests.single.path, '/reports/catalog');
      expect(catalog.reports, hasLength(5));
      expect(catalog.maxRows, 5000);
      expect(catalog.maxRangeDays, 366);
    });

    test('sin permiso llega un ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403, code: 'forbidden'));
      await expectLater(repo(adapter).catalog(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('preview', () {
    test('manda el reporte, los filtros y si compara', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, previewJson()));
      final preview = await repo(adapter).preview('tickets', {'statuses': ['resolved']}, compare: true);

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/reports/preview');
      expect(body(adapter.requests.single), {'report': 'tickets', 'filters': {'statuses': ['resolved']}, 'compare': true});
      expect(preview.totalRows, 3);
    });

    test('por defecto no compara', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, previewJson()));
      await repo(adapter).preview('equipment', const {});
      expect((body(adapter.requests.single)! as Map)['compare'], false);
    });

    test('un 422 llega por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, code: 'validation_error', errors: [
            {'field': 'body.filters.date_to', 'message': 'rango inválido', 'type': 'value_error'},
          ]));
      await expectLater(repo(adapter).preview('tickets', const {}), throwsA(isA<ValidationFailure>()));
    });
  });

  group('history', () {
    test('pide la página y el tamaño y lee la paginación', () async {
      final adapter = FakeAdapter((_) => pagedResponse([runJson(), runJson(id: 2, format: 'pdf')], page: 2, totalPages: 3, total: 21));
      final result = await repo(adapter).history(page: 2, size: 8);

      expect(adapter.requests.single.path, '/reports/history');
      expect(adapter.requests.single.queryParameters, {'page': 2, 'size': 8});
      expect(result.items.map((r) => r.id), [1, 2]);
      expect(result.info?.total, 21);
      expect(result.info?.page, 2);
    });

    test('sin cabeceras de paginación es una sola página', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [runJson()]));
      final result = await repo(adapter).history();
      expect(result.items, hasLength(1));
      expect(result.info, isNull);
    });
  });

  group('download', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('mantix_report_test_'));
    tearDown(() {
      // En Windows el adaptador simulado puede dejar abierto el archivo; no es un fallo de la prueba.
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Se limpia con la carpeta temporal del sistema.
      }
    });

    ResponseBody bytes(List<int> data) => ResponseBody.fromBytes(data, 200, headers: {'content-length': ['${data.length}']});

    test('genera con POST y baja el archivo al camino indicado', () async {
      final adapter = FakeAdapter((_) => bytes(List.filled(1000, 7)));
      final path = '${directory.path}/tickets.xlsx';

      await repo(adapter).download(report: 'tickets', format: ReportFormat.xlsx, filters: {'statuses': ['resolved']}, savePath: path);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/reports/generate');
      expect(body(request), {'report': 'tickets', 'format': 'xlsx', 'filters': {'statuses': ['resolved']}});
      expect(File(path).lengthSync(), 1000);
      expect(request.receiveTimeout, const Duration(seconds: 120));
    });

    test('pide el PDF con su formato', () async {
      final adapter = FakeAdapter((_) => bytes([1, 2, 3]));
      await repo(adapter).download(report: 'summary', format: ReportFormat.pdf, filters: const {'days': 30}, savePath: '${directory.path}/r.pdf');
      expect((body(adapter.requests.single)! as Map)['format'], 'pdf');
    });

    test('informa el avance hasta el 100 %', () async {
      final adapter = FakeAdapter((_) => bytes(List.filled(2000, 1)));
      final progress = <double>[];

      await repo(adapter).download(report: 'equipment', format: ReportFormat.pdf, filters: const {}, savePath: '${directory.path}/e.pdf', onProgress: progress.add);

      expect(progress.last, 1);
    });

    test('al terminar bien avisa de un cambio, para recargar el historial', () async {
      final adapter = FakeAdapter((_) => bytes([1, 2, 3]));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);

      await repository.download(report: 'tickets', format: ReportFormat.xlsx, filters: const {}, savePath: '${directory.path}/a.xlsx');
      await pumpEventQueue();

      expect(changes, hasLength(1));
    });

    test('un 403 sale como ForbiddenFailure, no deja el archivo a medias y no avisa de cambios', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);
      final path = '${directory.path}/e.xlsx';

      await expectLater(repository.download(report: 'tickets', format: ReportFormat.xlsx, filters: const {}, savePath: path), throwsA(isA<ForbiddenFailure>()));
      await pumpEventQueue();

      expect(File(path).existsSync(), isFalse);
      expect(changes, isEmpty);
    });

    test('un 422 sale como ValidationFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(422));
      await expectLater(
        repo(adapter).download(report: 'tickets', format: ReportFormat.xlsx, filters: const {}, savePath: '${directory.path}/e.xlsx'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('sin conexión sale como NetworkFailure', () async {
      final adapter = FakeAdapter((options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError));
      await expectLater(
        repo(adapter).download(report: 'tickets', format: ReportFormat.xlsx, filters: const {}, savePath: '${directory.path}/e.xlsx'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
