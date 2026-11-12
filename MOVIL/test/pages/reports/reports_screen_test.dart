import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/reports/reports_screen.dart';
import 'package:mantix/services/device_services.dart';
import 'package:mantix/services/temp_file_service.dart';
import 'package:mantix/widgets/reports/report_gallery.dart';

import '../../support/device_fakes.dart';
import '../../support/fakes.dart';
import '../../support/reports_support.dart';
import '../../support/requests_support.dart';

const _view = {'reportes:ver'};
const _export = {'reportes:ver', 'reportes:exportar'};

/// Archivos temporales reales en una carpeta del sistema, para que la descarga escriba de verdad.
class _DiskTempFiles implements TempFileService {
  _DiskTempFiles(this.directory);

  final Directory directory;
  final deleted = <String>[];

  @override
  Future<String> createPath(String fileName) async => '${directory.path}/$fileName';

  @override
  Future<int> length(String path) async => File(path).lengthSync();

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    File(path).deleteSync();
  }
}

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) catalogHandler;
  late ResponseBody Function(RequestOptions) previewHandler;
  late ResponseBody Function(RequestOptions) historyHandler;
  late ResponseBody Function(RequestOptions) generateHandler;
  late FakeShare share;
  late TempFileService temp;

  setUp(() {
    catalogHandler = (_) => jsonResponse(200, catalogJson());
    previewHandler = (_) => jsonResponse(200, previewJson(total: 3));
    historyHandler = (_) => pagedResponse([runJson(), runJson(id: 2, format: 'pdf', by: null)], total: 2);
    generateHandler = (_) => ResponseBody.fromBytes([1, 2, 3, 4], 200, headers: {'content-length': ['4']});
    share = FakeShare();
    temp = FakeTempFiles();
    adapter = FakeAdapter((options) {
      switch (options.path) {
        case '/reports/catalog':
          return catalogHandler(options);
        case '/reports/preview':
          return previewHandler(options);
        case '/reports/history':
          return historyHandler(options);
        case '/reports/generate':
          return generateHandler(options);
      }
      return errorResponse(404);
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _view, Size size = const Size(1000, 4000), double textScale = 1}) async {
    await pumpScreen(
      tester,
      RepositoryProvider<DeviceServices>.value(value: DeviceServices(share: share, tempFiles: temp), child: const ReportsScreen()),
      adapter,
      permissions: permissions,
      size: size,
      textScale: textScale,
    );
    await tester.pumpAndSettle();
  }

  /// La galería se desplaza de lado y construye solo lo visible: se lleva el chip a la vista.
  Future<void> tapReport(WidgetTester tester, String title) async {
    final scrollable = find.descendant(of: find.byType(ReportGallery), matching: find.byType(Scrollable)).first;
    final chip = find.descendant(of: find.byType(ReportGallery), matching: find.text(title));
    await tester.scrollUntilVisible(chip, 120, scrollable: scrollable);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// Deja correr el reloj real (descargas a disco) hasta que se cumpla [done].
  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    // El disco responde en tiempo real, pero el Bloc corre en el reloj simulado: se alternan.
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();
  }

  List<RequestOptions> calls(String path) => adapter.requests.where((r) => r.path == path).toList();

  group('galería', () {
    testWidgets('encabezado y solo los 4 reportes de la app, sin los de inventario', (tester) async {
      await open(tester);

      expect(find.text('Reportes'), findsOneWidget);
      expect(find.text('Elige un reporte, filtra y expórtalo en PDF o Excel.'), findsOneWidget);
      final scrollable = find.descendant(of: find.byType(ReportGallery), matching: find.byType(Scrollable)).first;
      for (final title in ['Tickets de mantenimiento', 'Planes de mantenimiento', 'Inventario de equipos', 'Resumen operativo']) {
        final chip = find.descendant(of: find.byType(ReportGallery), matching: find.text(title));
        await tester.scrollUntilVisible(chip, 120, scrollable: scrollable);
        expect(chip, findsOneWidget, reason: title);
      }
      expect(find.text('Existencias del inventario'), findsNothing);
    });

    testWidgets('abre con el primero elegido y pide su vista previa sin filtros', (tester) async {
      await open(tester);

      expect(calls('/reports/preview'), hasLength(1));
      final body = calls('/reports/preview').single.data as Map;
      expect(body['report'], 'tickets');
      expect(body['filters'], isEmpty);
      expect(find.text('Se exportarán 3 registros.'), findsOneWidget);
    });

    testWidgets('elegir otro reporte pide su vista previa, con los filtros limpios', (tester) async {
      await open(tester);
      await tapReport(tester, 'Inventario de equipos');

      final body = calls('/reports/preview').last.data as Map;
      expect(body['report'], 'equipment');
      expect(find.text('Sin filtros'), findsOneWidget);
    });

    testWidgets('si el catálogo falla muestra el error y reintenta', (tester) async {
      catalogHandler = (_) => errorResponse(500);
      await open(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byType(ReportGallery), findsNothing);

      catalogHandler = (_) => jsonResponse(200, catalogJson());
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportGallery), findsOneWidget);
    });

    testWidgets('sin ninguno de los reportes dice que no hay disponibles', (tester) async {
      catalogHandler = (_) => jsonResponse(200, catalogJson(reports: [inventoryReport()]));
      await open(tester);
      expect(find.text('No hay reportes disponibles'), findsOneWidget);
    });
  });

  group('vista previa', () {
    testWidgets('muestra las filas como tarjetas y despliega el resto de columnas', (tester) async {
      await open(tester);

      expect(find.textContaining('Vista previa · primeras 3 de 3'), findsOneWidget);
      expect(find.text('TCK-001'), findsOneWidget);
      expect(find.text('Título: Ticket 1'), findsOneWidget);
      expect(find.text('Estado: '), findsNothing, reason: 'la tercera columna está plegada');

      await tester.tap(find.text('TCK-001'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Estado: En proceso', findRichText: true), findsOneWidget);
    });

    testWidgets('sin registros avisa y no deja exportar', (tester) async {
      previewHandler = (_) => jsonResponse(200, previewJson(total: 0, rows: const []));
      await open(tester, permissions: _export);

      expect(find.textContaining('Ningún registro coincide'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Exportar PDF')).onPressed, isNull);
    });

    testWidgets('si falla la vista previa muestra el error con reintento', (tester) async {
      previewHandler = (_) => errorResponse(500);
      await open(tester);
      expect(find.text('Reintentar'), findsOneWidget);

      previewHandler = (_) => jsonResponse(200, previewJson(total: 3));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Se exportarán 3 registros.'), findsOneWidget);
    });
  });

  group('filtros', () {
    testWidgets('la hoja ofrece solo los filtros del reporte y aplicar vuelve a pedir la vista previa', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Filtros del reporte'), findsOneWidget);
      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('Prioridad'), findsOneWidget);
      expect(find.text('Desde'), findsOneWidget);
      expect(find.text('Hasta'), findsOneWidget);
      expect(find.text('Comparar con el periodo anterior'), findsOneWidget);

      await tester.tap(find.text('Todas').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resuelto'));
      await tester.tap(find.text('Aplicar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(((calls('/reports/preview').last.data as Map)['filters'] as Map)['statuses'], ['resolved']);
      expect(find.text('Estado: Resuelto'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('quitar el chip vuelve a pedir sin ese filtro', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resuelto'));
      await tester.tap(find.text('Aplicar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quitar filtro'));
      await tester.pumpAndSettle();

      expect(((calls('/reports/preview').last.data as Map)['filters'] as Map), isEmpty);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('el resumen solo ofrece la ventana de días', (tester) async {
      await open(tester);
      await tapReport(tester, 'Resumen operativo');
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Periodo'), findsOneWidget);
      expect(find.text('Estado'), findsNothing);
      expect(find.text('Comparar con el periodo anterior'), findsNothing);
    });

    testWidgets('el comparativo está deshabilitado sin las dos fechas', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
      expect(find.text('Elige las dos fechas para comparar.'), findsOneWidget);
    });
  });

  group('exportar', () {
    testWidgets('sin reportes:exportar no hay formatos ni botón de exportar', (tester) async {
      await open(tester);

      expect(find.text('Formato de exportación'), findsNothing);
      expect(find.textContaining('Exportar PDF'), findsNothing);
      expect(find.text('Exportaciones recientes'), findsOneWidget);
    });

    testWidgets('con permiso: los dos formatos con los textos de la web, PDF elegido', (tester) async {
      await open(tester, permissions: _export);

      expect(find.text('Documento para imprimir o compartir: tabla y resumen ejecutivo.'), findsOneWidget);
      expect(find.text('Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.'), findsOneWidget);
      expect(find.text('Exportar PDF'), findsOneWidget);

      await tester.tap(find.text('Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.'));
      await tester.pumpAndSettle();
      expect(find.text('Exportar Excel'), findsOneWidget);
    });

    testWidgets('exportar descarga, comparte con el tipo del archivo y borra el temporal', (tester) async {
      final directory = Directory.systemTemp.createTempSync('mantix_screen_test_');
      addTearDown(() {
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          // Se limpia con la carpeta temporal del sistema.
        }
      });
      final disk = _DiskTempFiles(directory);
      temp = disk;
      await open(tester, permissions: _export);
      await tester.tap(find.text('Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exportar Excel'));
      await waitUntil(tester, () => share.shared.isNotEmpty);

      expect(calls('/reports/generate'), hasLength(1));
      expect((calls('/reports/generate').single.data as Map)['format'], 'xlsx');
      expect(share.shared.single.mimeType, contains('spreadsheetml'));
      expect(disk.deleted, hasLength(1));
      expect(find.textContaining('Archivo generado: mantix_tickets_'), findsOneWidget);
    });

    testWidgets('un 403 al exportar explica que no tiene permiso', (tester) async {
      generateHandler = (_) => errorResponse(403, code: 'export_forbidden');
      final directory = Directory.systemTemp.createTempSync('mantix_screen_test_');
      addTearDown(() {
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          // Se limpia con la carpeta temporal del sistema.
        }
      });
      temp = _DiskTempFiles(directory);
      await open(tester, permissions: _export);

      await tester.tap(find.text('Exportar PDF'));
      await waitUntil(tester, () => calls('/reports/generate').isNotEmpty);
      await tester.pumpAndSettle();

      expect(find.text('No tienes permiso para exportar reportes.'), findsOneWidget);
      expect(share.shared, isEmpty);
    });
  });

  group('exportaciones recientes', () {
    testWidgets('lista formato, filas, quién y cuándo', (tester) async {
      await open(tester);

      expect(find.text('Exportaciones recientes'), findsOneWidget);
      expect(find.text('Excel · 25 registros'), findsOneWidget);
      expect(find.textContaining('Ana Pérez'), findsOneWidget);
      expect(find.text('PDF · 25 registros'), findsOneWidget);
      expect(find.textContaining('Sistema'), findsOneWidget);
    });

    testWidgets('sin exportaciones lo dice, y si falla ofrece reintentar', (tester) async {
      historyHandler = (_) => pagedResponse(const []);
      await open(tester);
      expect(find.text('Aún no has exportado reportes.'), findsOneWidget);
    });

    testWidgets('el historial puede fallar sin tumbar el resto de la pantalla', (tester) async {
      historyHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.textContaining('No pudimos cargar las exportaciones'), findsOneWidget);
      expect(find.text('Se exportarán 3 registros.'), findsOneWidget);
    });
  });

  group('tamaños', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('sin desbordes en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await open(tester, permissions: _export, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Filtros'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
