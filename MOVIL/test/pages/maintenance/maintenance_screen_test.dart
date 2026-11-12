import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/formatters.dart';
import 'package:mantix/pages/maintenance/maintenance_screen.dart';
import 'package:mantix/widgets/maintenance/maintenance_calendar_card.dart';
import 'package:mantix/widgets/maintenance/maintenance_cards.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';
import 'package:mantix/widgets/shared/multi_select_sheet.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/paginator_support.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

const _viewOnly = {'mantenimiento:ver'};
const _withTechnicians = {'mantenimiento:ver', 'tecnicos:ver'};

String _utc(DateTime local) => local.toUtc().toIso8601String();

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) calendarHandler;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) planHandler;
  late ResponseBody Function(RequestOptions) historyHandler;
  final today = DateTime(2026, 10, 25, 10);

  List<Map<String, Object?>> events() => [
        calendarEventJson(id: 4, title: 'Revisión de UPS', kind: 'overdue', at: _utc(DateTime(2026, 10, 6, 12))),
        calendarEventJson(id: 5, title: 'Limpieza de servidor', at: _utc(DateTime(2026, 10, 13, 12)), tag: 'SRV-0001'),
        calendarEventJson(id: 6, title: 'Mantenimiento Preventivo', at: _utc(DateTime(2026, 10, 28, 12)), tag: 'SRV-0009'),
        calendarEventJson(id: 7, title: 'Cambio de baterías', kind: 'done', at: _utc(DateTime(2026, 10, 1, 12))),
      ];

  setUp(() {
    calendarHandler = (_) => calendarResponse(events());
    listHandler = (_) => pagedResponse([
          scheduleJson(id: 4, title: 'Revisión de UPS', due: _utc(DateTime(2026, 10, 6, 12))),
          scheduleJson(id: 5, title: 'Limpieza de servidor', due: _utc(DateTime(2026, 12, 1, 12)), technician: null, active: false),
        ]);
    planHandler = (options) => jsonResponse(200, scheduleJson(id: int.parse(options.path.split('/').last), due: _utc(DateTime(2026, 10, 6, 12))));
    historyHandler = (_) => jsonResponse(200, historyJson());
    adapter = FakeAdapter((options) {
      final path = options.path;
      if (path == '/maintenance/calendar') return calendarHandler(options);
      if (path == '/maintenance/schedules') return listHandler(options);
      if (path.endsWith('/history')) return historyHandler(options);
      if (path.startsWith('/maintenance/schedules/')) return planHandler(options);
      if (path == '/technicians') return pagedResponse([technicianJson(id: 2, name: 'Luis Mora')]);
      return errorResponse(404);
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _viewOnly, Size size = const Size(1000, 3000), double textScale = 1}) async {
    await pumpScreen(tester, MaintenanceScreen(clock: () => today), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  Finder inCalendar(Finder finder) => find.descendant(of: find.byType(MaintenanceCalendarCard), matching: finder);
  List<String> cardTitles(WidgetTester tester) => [for (final card in tester.widgetList<MaintenanceEventCard>(find.byType(MaintenanceEventCard))) card.event.title];
  List<RequestOptions> calendarCalls() => adapter.requests.where((r) => r.path == '/maintenance/calendar').toList();
  List<RequestOptions> listCalls() => adapter.requests.where((r) => r.path == '/maintenance/schedules').toList();

  Future<void> goToList(WidgetTester tester) async {
    await tester.tap(find.text('Lista'));
    await tester.pumpAndSettle();
  }

  group('calendario', () {
    testWidgets('encabezado, conmutador, mes, semana y leyenda', (tester) async {
      await open(tester);

      expect(find.text('Mantenimientos'), findsOneWidget);
      expect(find.text('Gestiona y consulta los mantenimientos de tus equipos.'), findsOneWidget);
      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('Lista'), findsOneWidget);
      expect(find.text('Octubre 2026'), findsOneWidget);
      for (final day in ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM']) {
        expect(inCalendar(find.text(day)), findsOneWidget, reason: day);
      }
      for (final label in ['Programado', 'Vencido', 'Hecho']) {
        expect(inCalendar(find.text(label)), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Pendiente'), findsNothing, reason: 'la API no tiene ese estado: es «Vencido»');
    });

    testWidgets('pide la cuadrícula de octubre y no marca días de otros meses', (tester) async {
      await open(tester);

      final query = calendarCalls().first.queryParameters;
      expect(query['start'], _utc(DateTime(2026, 9, 28)));
      expect(query['end'], _utc(DateTime(2026, 11, 2)));
      expect(inCalendar(find.byType(InkWell)), findsNWidgets(35 + 2), reason: '35 días y las dos flechas');
    });

    testWidgets('cada día dice cuántos servicios tiene', (tester) async {
      await open(tester);
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsLabel('6 de octubre, 1 servicio'), findsOneWidget);
      expect(find.bySemanticsLabel('Hoy, 25 de octubre, sin servicios'), findsOneWidget);
      expect(find.bySemanticsLabel('20 de octubre, sin servicios'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('moverse de mes pide el nuevo mes y «Ir a hoy» vuelve', (tester) async {
      await open(tester);
      expect(find.text('Ir a hoy'), findsNothing);

      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Noviembre 2026'), findsOneWidget);
      expect(calendarCalls().last.queryParameters['start'], _utc(DateTime(2026, 10, 26)));

      await tester.tap(find.text('Ir a hoy'));
      await tester.pumpAndSettle();
      expect(find.text('Octubre 2026'), findsOneWidget);
      expect(find.text('Servicios del 25 oct 2026'), findsOneWidget, reason: 'hoy queda elegido');

      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre 2026'), findsOneWidget);
    });

    testWidgets('tocar un día enseña sus servicios, tocarlo otra vez los oculta', (tester) async {
      await open(tester);
      await tester.tap(inCalendar(find.text('6')));
      await tester.pumpAndSettle();

      expect(find.text('Servicios del 6 oct 2026'), findsOneWidget);
      expect(cardTitles(tester), contains('Revisión de UPS'));

      await tester.tap(inCalendar(find.text('6')));
      await tester.pumpAndSettle();
      expect(find.text('Servicios del 6 oct 2026'), findsNothing);
    });

    testWidgets('un día sin servicios lo dice', (tester) async {
      await open(tester);
      await tester.tap(inCalendar(find.text('20')));
      await tester.pumpAndSettle();
      expect(find.text('Servicios del 20 oct 2026'), findsOneWidget);
      expect(find.text('No hay servicios este día.'), findsOneWidget);
    });

    testWidgets('si falla el calendario sale el motivo con reintento y lo demás sigue', (tester) async {
      calendarHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.textContaining('No pudimos cargar el calendario.'), findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(find.text('Próximos mantenimientos'), findsOneWidget);

      calendarHandler = (_) => calendarResponse(events());
      await tester.tap(find.descendant(of: find.byType(MaintenanceCalendarCard), matching: find.text('Reintentar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos cargar el calendario.'), findsNothing);
    });

    testWidgets('avisa si el servidor llegó a su tope', (tester) async {
      calendarHandler = (_) => calendarResponse(events(), truncated: true);
      await open(tester);
      expect(find.text('Hay más servicios de los que se muestran en este mes.'), findsOneWidget);
    });

    testWidgets('tirar hacia abajo vuelve a pedir el calendario y los próximos', (tester) async {
      await open(tester, size: const Size(400, 900));
      final before = calendarCalls().length;
      await tester.fling(find.byType(ListView).first, const Offset(0, 500), 1000);
      await tester.pumpAndSettle();
      expect(calendarCalls().length, before + 2);
    });
  });

  group('próximos mantenimientos', () {
    testWidgets('salen los vencidos primero, con su estado escrito, y lo hecho no cuenta', (tester) async {
      await open(tester);

      expect(find.text('Próximos mantenimientos'), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      expect(cardTitles(tester), ['Revisión de UPS', 'Limpieza de servidor', 'Mantenimiento Preventivo']);
      expect(find.text('Vencido'), findsNWidgets(2), reason: 'la tarjeta y la leyenda del calendario');
      expect(find.text('Programado'), findsNWidgets(3), reason: 'dos tarjetas y la leyenda');
      expect(find.text('SRV-0009'), findsOneWidget, reason: 'en vez de un lugar, la etiqueta del equipo');
    });

    testWidgets('sin servicios lo dice', (tester) async {
      calendarHandler = (_) => calendarResponse([]);
      await open(tester);
      expect(find.text('No hay mantenimientos próximos ni vencidos.'), findsOneWidget);
    });

    testWidgets('si fallan, sale el motivo con reintento sin tumbar el calendario', (tester) async {
      var fail = true;
      calendarHandler = (options) {
        // El calendario del mes pide desde el 28 de septiembre; los próximos, desde el 25.
        final start = DateTime.parse(options.queryParameters['start'] as String);
        return fail && start.isBefore(DateTime(2026, 9, 27).toUtc()) ? errorResponse(500) : calendarResponse(events());
      };
      await open(tester);

      expect(find.textContaining('No pudimos cargar los próximos mantenimientos.'), findsOneWidget);
      expect(find.text('Octubre 2026'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(cardTitles(tester), hasLength(3));
    });

    testWidgets('«Ver todos» lleva a la lista de planes', (tester) async {
      await open(tester);
      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleCard), findsNWidgets(2));
      expect(find.byType(MaintenanceCalendarCard), findsNothing);
    });
  });

  group('lista de planes', () {
    testWidgets('muestra cada plan con su equipo, técnico, próxima fecha y estado', (tester) async {
      await open(tester);
      await goToList(tester);

      expect(listCalls().single.queryParameters, {'page': 1, 'size': 20, 'sort': 'next_due_at'});
      expect(find.text('Revisión de UPS'), findsOneWidget);
      expect(find.text('Limpieza de servidor'), findsOneWidget);
      expect(find.textContaining('SRV-0003 · Dell PowerEdge'), findsNWidgets(2));
      expect(find.text('Luis Mora'), findsOneWidget);
      expect(find.text('Sin técnico asignado'), findsOneWidget);
      expect(find.text('Vencido'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);
      expect(find.textContaining('Cada 30 días'), findsNWidgets(2));
    });

    testWidgets('con una sola página no hay flechas del paginador', (tester) async {
      await open(tester);
      await goToList(tester);
      expect(find.byTooltip('Página siguiente'), findsNothing);
      expect(selectedPage(tester), 1);
    });

    testWidgets('reparte en páginas y pide la siguiente al servidor', (tester) async {
      listHandler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([scheduleJson(id: page, title: 'Plan $page')], page: page, totalPages: 3, total: 41);
      };
      await open(tester);
      await goToList(tester);
      expect(find.text('Plan 1'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(listCalls().last.queryParameters['page'], 2);
      expect(find.text('Plan 2'), findsOneWidget);
      expect(selectedPage(tester), 2);
    });

    testWidgets('la búsqueda pide al servidor el texto recortado', (tester) async {
      await open(tester);
      await goToList(tester);
      await tester.enterText(find.byType(TextField), '  ups ');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(listCalls().last.queryParameters['search'], 'ups');
    });

    testWidgets('el filtro de estado pide al servidor los vencidos y sale como chip que se quita', (tester) async {
      await open(tester);
      await goToList(tester);
      await tester.tap(find.byType(FilterButton));
      await tester.pumpAndSettle();
      expect(find.text('Técnico responsable'), findsNothing, reason: 'sin tecnicos:ver no se ofrece');

      await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Todos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vencidos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Aplicar')));
      await tester.pumpAndSettle();

      expect(listCalls().last.queryParameters['overdue'], true);
      expect(find.widgetWithText(ActiveFilterChip, 'Vencidos'), findsOneWidget);

      await tester.tap(find.descendant(of: find.widgetWithText(ActiveFilterChip, 'Vencidos'), matching: find.byTooltip('Quitar filtro')));
      await tester.pumpAndSettle();
      expect(listCalls().last.queryParameters.containsKey('overdue'), isFalse);
    });

    testWidgets('con tecnicos:ver se puede filtrar por técnico', (tester) async {
      await open(tester, permissions: _withTechnicians);
      await goToList(tester);
      await tester.tap(find.byType(FilterButton));
      await tester.pumpAndSettle();
      expect(find.text('Técnico responsable'), findsOneWidget);
      await tester.tap(find.text('Todas'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Luis Mora'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Aplicar')));
      await tester.pumpAndSettle();

      expect(listCalls().last.queryParameters['technician_id'], 2);
      expect(find.widgetWithText(ActiveFilterChip, 'Luis Mora'), findsOneWidget);
    });

    testWidgets('cerrar la hoja de filtros sin aplicar no cambia nada', (tester) async {
      await open(tester);
      await goToList(tester);
      final before = listCalls().length;
      await tester.tap(find.byType(FilterButton));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(FilterSheet))).pop();
      await tester.pumpAndSettle();

      expect(listCalls().length, before);
      expect(find.byType(ActiveFilterChip), findsNothing);
    });

    testWidgets('sin planes lo dice, y con filtros ofrece quitarlos', (tester) async {
      listHandler = (_) => pagedResponse(const []);
      await open(tester);
      await goToList(tester);
      expect(find.text('Aún no hay mantenimientos programados'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nada');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Ningún mantenimiento coincide con los filtros'), findsOneWidget);
      await tester.tap(find.text('Quitar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay mantenimientos programados'), findsOneWidget);
    });

    testWidgets('si falla sale el error con reintento', (tester) async {
      listHandler = (_) => errorResponse(500);
      await open(tester);
      await goToList(tester);
      expect(find.text('No pudimos cargar los mantenimientos'), findsOneWidget);

      listHandler = (_) => pagedResponse([scheduleJson()]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleCard), findsOneWidget);
    });
  });

  group('ficha del plan', () {
    testWidgets('se abre desde un servicio con sus datos y su historial', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();

      expect(find.text('Plan de mantenimiento'), findsOneWidget);
      expect(find.text('Datos del plan'), findsOneWidget);
      expect(find.text('SRV-0003 · Dell PowerEdge'), findsOneWidget);
      expect(find.text('Cada 30 días'), findsOneWidget);
      expect(find.text('3 días antes'), findsOneWidget);
      expect(find.text('Luis Mora'), findsOneWidget);
      expect(find.text('1,5 h'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.textContaining('Con retraso'), findsOneWidget);
      expect(find.textContaining('2 h reales'), findsOneWidget);
      expect(find.textContaining('Equipo en uso'), findsOneWidget);
      expect(adapter.requests.map((r) => r.path), containsAll(['/maintenance/schedules/4', '/maintenance/schedules/4/history']));
    });

    testWidgets('se abre también desde la lista', (tester) async {
      await open(tester);
      await goToList(tester);
      await tester.tap(find.widgetWithText(ScheduleCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();
      expect(find.text('Plan de mantenimiento'), findsOneWidget);
      expect(find.text('Datos del plan'), findsOneWidget);
    });

    testWidgets('si el historial falla, el plan se ve y el historial se reintenta solo', (tester) async {
      historyHandler = (_) => errorResponse(500);
      await open(tester);
      await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();

      expect(find.text('Datos del plan'), findsOneWidget);
      expect(find.textContaining('No pudimos cargar el historial.'), findsOneWidget);

      historyHandler = (_) => jsonResponse(200, historyJson());
      final before = adapter.requests.length;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, before + 1);
      expect(find.textContaining('Equipo en uso'), findsOneWidget);
    });

    testWidgets('si el plan ya no existe lo dice con reintento', (tester) async {
      planHandler = (_) => errorResponse(404, code: 'schedule_not_found');
      await open(tester);
      await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ese plan de mantenimiento ya no existe.'), findsOneWidget);
      expect(find.text('Datos del plan'), findsNothing);
    });

    testWidgets('un plan sin historial ni técnico lo explica', (tester) async {
      planHandler = (_) => jsonResponse(200, scheduleJson(technician: null, hours: null, description: null));
      historyHandler = (_) => jsonResponse(200, historyJson(runs: [], reschedules: []));
      await open(tester);
      await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin asignar'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('Plan creado el'), findsOneWidget);
      expect(find.text('Este plan aún no tiene servicios hechos ni cambios de fecha.'), findsNothing);
    });

    testWidgets('las fechas salen en español', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
      await tester.pumpAndSettle();
      expect(find.text(formatDateTime(DateTime(2026, 10, 6, 12))), findsOneWidget);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('calendario con servicios, día elegido y próximos en $label', (tester) async {
        calendarHandler = (_) => calendarResponse([
              for (var i = 0; i < 6; i++) calendarEventJson(id: i + 1, title: 'Un mantenimiento con un título muy largo que no cabe en una línea número $i', kind: i.isEven ? 'overdue' : 'planned', at: _utc(DateTime(2026, 10, 6, 8 + i)), tag: 'SRV-LARGO-0000$i'),
              calendarEventJson(id: 9, kind: 'done', at: _utc(DateTime(2026, 10, 6, 20))),
            ]);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(inCalendar(find.text('6')));
        await tester.tap(inCalendar(find.text('6')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('con el calendario y los próximos caídos en $label', (tester) async {
        calendarHandler = (_) => errorResponse(500);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('lista, filtros con chips y ficha en $label', (tester) async {
        listHandler = (_) => pagedResponse([
              scheduleJson(id: 1, title: 'Un plan con un título muy largo que no cabe en una sola línea de la tarjeta', due: _utc(DateTime(2026, 10, 6, 12))),
              ...[for (var i = 2; i < 5; i++) scheduleJson(id: i, title: 'Plan $i', technician: {'id': i, 'user_id': i, 'full_name': 'Una persona con un nombre muy largo que no cabe'})],
            ], totalPages: 99, total: 1980);
        await open(tester, permissions: _withTechnicians, size: size, textScale: 1.3);
        await goToList(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(FilterButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Todos')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vencidos').last);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Aplicar')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byType(ScheduleCard).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ScheduleCard).first);
        await tester.pumpAndSettle();
        expect(find.text('Plan de mantenimiento'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('lista vacía, lista caída y ficha caída en $label', (tester) async {
        listHandler = (_) => errorResponse(500);
        planHandler = (_) => errorResponse(500);
        await open(tester, size: size, textScale: 1.3);
        await goToList(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
