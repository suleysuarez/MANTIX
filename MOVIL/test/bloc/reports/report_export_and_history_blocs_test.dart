import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/reports/report_export_bloc.dart';
import 'package:mantix/bloc/reports/report_history_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/format/report_format.dart';
import 'package:mantix/models/reports/report_models.dart';
import 'package:mantix/repositories/reports/reports_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/device_fakes.dart';
import '../../support/fakes.dart';
import '../../support/reports_support.dart';
import '../../support/requests_support.dart';

class _MockReportsRepository extends Mock implements ReportsRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(ReportFormat.xlsx);
    registerFallbackValue(<String, Object?>{});
  });

  group('exportar un reporte', () {
    late _MockReportsRepository repository;
    late FakeShare share;
    late FakeTempFiles temp;

    setUp(() {
      repository = _MockReportsRepository();
      share = FakeShare();
      temp = FakeTempFiles();
    });

    void stubDownload({Object? error, Future<void> Function()? wait}) => when(
          () => repository.download(report: any(named: 'report'), format: any(named: 'format'), filters: any(named: 'filters'), savePath: any(named: 'savePath'), onProgress: any(named: 'onProgress')),
        ).thenAnswer((invocation) async {
          if (wait != null) await wait();
          if (error != null) throw error;
          final onProgress = invocation.namedArguments[#onProgress] as void Function(double)?;
          onProgress?.call(0.5);
          onProgress?.call(1);
        });

    ReportExportBloc newBloc() {
      final bloc = ReportExportBloc(repository: repository, share: share, tempFiles: temp, clock: () => DateTime(2026, 11, 11, 10));
      addTearDown(bloc.close);
      return bloc;
    }

    ReportExportRequested request({String key = 'tickets', ReportFormat format = ReportFormat.xlsx, ReportFilterValues values = const ReportFilterValues()}) => ReportExportRequested(definition: reportOf(key), format: format, values: values);

    Future<ReportExportState> export(ReportExportBloc bloc, ReportExportRequested event) async {
      bloc.add(event);
      return bloc.stream.firstWhere((s) => s.status != ExportStatus.working && s.status != ExportStatus.idle);
    }

    test('descarga a un temporal, lo comparte con el nombre del servidor y lo borra', () async {
      stubDownload();
      final bloc = newBloc();

      final result = await export(bloc, request(values: const ReportFilterValues(statuses: {'resolved'})));

      expect(result.status, ExportStatus.shared);
      expect(result.fileName, 'mantix_tickets_2026-11-11.xlsx');
      expect(result.format, ReportFormat.xlsx);
      expect(temp.created.single, '/tmp/mantix_test/mantix_tickets_2026-11-11.xlsx');
      verify(() => repository.download(report: 'tickets', format: ReportFormat.xlsx, filters: {'statuses': ['resolved']}, savePath: temp.created.single, onProgress: any(named: 'onProgress'))).called(1);
      expect(share.shared.single.path, temp.created.single);
      expect(share.shared.single.mimeType, ReportFormat.xlsx.mimeType);
      expect(share.shared.single.subject, 'Tickets de mantenimiento');
      expect(temp.deleted, [temp.created.single]);
    });

    test('un PDF sale con su tipo y su extensión', () async {
      stubDownload();
      final bloc = newBloc();

      final result = await export(bloc, request(key: 'summary', format: ReportFormat.pdf));

      expect(result.fileName, 'mantix_summary_2026-11-11.pdf');
      expect(share.shared.single.mimeType, 'application/pdf');
      verify(() => repository.download(report: 'summary', format: ReportFormat.pdf, filters: {'days': 30}, savePath: any(named: 'savePath'), onProgress: any(named: 'onProgress'))).called(1);
    });

    test('mientras descarga informa el avance', () async {
      stubDownload();
      final bloc = newBloc();
      final progress = <double?>[];
      final subscription = bloc.stream.where((s) => s.working).listen((s) => progress.add(s.progress));
      addTearDown(subscription.cancel);

      await export(bloc, request());

      expect(progress, containsAllInOrder([null, 0.5, 1.0]));
    });

    test('un 403 dice que no tiene permiso, no comparte y borra el temporal', () async {
      stubDownload(error: const ForbiddenFailure());
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.status, ExportStatus.failure);
      expect(result.message, 'No tienes permiso para exportar reportes.');
      expect(share.shared, isEmpty);
      expect(temp.deleted, [temp.created.single]);
    });

    test('un 422 pide acotar los filtros sin enseñar detalles del servidor', () async {
      stubDownload(error: const ValidationFailure());
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.message, 'No se pudo generar el reporte con estos filtros. Acótalos e inténtalo de nuevo.');
    });

    test('sin red lo dice', () async {
      stubDownload(error: const NetworkFailure());
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.status, ExportStatus.failure);
      expect(result.message, const NetworkFailure().message);
    });

    test('un archivo vacío no se comparte', () async {
      stubDownload();
      temp.size = 0;
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.status, ExportStatus.empty);
      expect(result.message, 'No hay datos para exportar con estos filtros.');
      expect(share.shared, isEmpty);
      expect(temp.deleted, hasLength(1));
    });

    test('si no se puede abrir la hoja de compartir lo dice y borra el temporal', () async {
      stubDownload();
      share.error = Exception('sin app');
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.status, ExportStatus.failure);
      expect(result.message, 'No pudimos abrir la hoja de compartir.');
      expect(temp.deleted, hasLength(1));
    });

    test('si no se puede borrar el temporal no es un fallo', () async {
      stubDownload();
      temp.deleteError = Exception('bloqueado');
      final bloc = newBloc();

      final result = await export(bloc, request());

      expect(result.status, ExportStatus.shared);
    });

    test('mientras exporta no empieza otra exportación', () async {
      final release = Completer<void>();
      stubDownload(wait: () => release.future);
      final bloc = newBloc();

      bloc
        ..add(request())
        ..add(request(key: 'equipment'));
      await pumpEventQueue();
      release.complete();
      await bloc.stream.firstWhere((s) => s.status == ExportStatus.shared);

      verify(() => repository.download(report: any(named: 'report'), format: any(named: 'format'), filters: any(named: 'filters'), savePath: any(named: 'savePath'), onProgress: any(named: 'onProgress'))).called(1);
    });

    test('cerrar el aviso vuelve al estado inicial, pero no mientras exporta', () async {
      final release = Completer<void>();
      stubDownload(wait: () => release.future);
      final bloc = newBloc();

      bloc.add(request());
      await pumpEventQueue();
      bloc.add(const ReportExportDismissed());
      await pumpEventQueue();
      expect(bloc.state.working, isTrue, reason: 'no se cierra mientras exporta');

      release.complete();
      await bloc.stream.firstWhere((s) => s.status == ExportStatus.shared);
      bloc.add(const ReportExportDismissed());
      await pumpEventQueue();
      expect(bloc.state.status, ExportStatus.idle);
    });
  });

  group('exportaciones recientes', () {
    late FakeAdapter adapter;
    late ResponseBody Function(RequestOptions) handler;
    late ReportsRepository repository;

    setUp(() {
      handler = (_) => pagedResponse([runJson(), runJson(id: 2, format: 'pdf')], total: 2);
      adapter = FakeAdapter((options) => handler(options));
      repository = ReportsRepository(dioWith(adapter));
    });

    ReportHistoryBloc build({int pageSize = 8}) => ReportHistoryBloc(repository: repository, pageSize: pageSize);

    Future<ReportHistoryBloc> loaded({int pageSize = 8}) async {
      final bloc = build(pageSize: pageSize)..add(const ReportHistoryStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == HistoryStatus.success);
      return bloc;
    }

    test('pide la primera página con el tamaño elegido', () async {
      final bloc = await loaded(pageSize: 5);

      expect(adapter.requests.single.queryParameters, {'page': 1, 'size': 5});
      expect(bloc.state.items.map((r) => r.id), [1, 2]);
      expect(bloc.state.total, 2);
      expect(bloc.state.totalPages, 1);
    });

    test('moverse de página pide esa página y mientras llega sigue la anterior', () async {
      handler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([runJson(id: page)], page: page, totalPages: 3, total: 21);
      };
      final bloc = await loaded();
      final states = <ReportHistoryState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);

      bloc.add(const ReportHistoryPageSelected(2));
      await bloc.stream.firstWhere((state) => state.page == 2 && !state.loadingPage);

      expect(states.first.loadingPage, isTrue);
      expect(states.first.items.single.id, 1);
      expect(bloc.state.items.single.id, 2);
      expect(bloc.state.totalPages, 3);
    });

    test('sin exportaciones queda lista y vacía', () async {
      handler = (_) => pagedResponse(const []);
      final bloc = await loaded();
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.total, 0);
    });

    test('si falla, queda en error con el motivo', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const ReportHistoryStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == HistoryStatus.failure);
      expect(bloc.state.failure, isA<ServerFailure>());
    });

    test('una recarga que falla conserva lo que ya se veía', () async {
      final bloc = await loaded();
      handler = (_) => errorResponse(500);
      final done = Completer<void>();
      bloc.add(ReportHistoryRefreshed(done: done));
      await done.future;

      expect(bloc.state.items, hasLength(2));
      expect(bloc.state.status, HistoryStatus.success);
      expect(bloc.state.failure, isA<ServerFailure>());
      expect(bloc.state.loadingPage, isFalse);
    });

    test('tirar para refrescar vuelve a pedir la página actual y espera', () async {
      final bloc = await loaded();
      final before = adapter.requests.length;
      final done = Completer<void>();
      bloc.add(ReportHistoryRefreshed(done: done));
      await done.future;
      expect(adapter.requests.length, before + 1);
    });

    test('al exportar un reporte vuelve a la página 1 y lo muestra', () async {
      handler = (options) {
        if (options.method == 'POST') return ResponseBody.fromBytes([1, 2, 3], 200, headers: {'content-length': ['3']});
        final page = options.queryParameters['page'] as int;
        return pagedResponse([runJson(id: page == 1 ? 99 : 5)], page: page, totalPages: 3, total: 21);
      };
      final bloc = await loaded();
      bloc.add(const ReportHistoryPageSelected(2));
      await bloc.stream.firstWhere((state) => state.page == 2 && !state.loadingPage);

      final directory = Directory.systemTemp.createTempSync('mantix_history_test_');
      addTearDown(() {
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          // Se limpia con la carpeta temporal del sistema.
        }
      });
      await repository.download(report: 'tickets', format: ReportFormat.xlsx, filters: const {}, savePath: '${directory.path}/a.xlsx');
      await bloc.stream.firstWhere((state) => state.page == 1 && state.items.isNotEmpty && state.items.first.id == 99);

      expect(adapter.requests.last.queryParameters['page'], 1);
    });
  });
}
