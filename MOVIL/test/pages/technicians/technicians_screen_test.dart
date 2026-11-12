import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/technicians/technician_filters.dart';
import 'package:mantix/pages/technicians/technicians_screen.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';
import 'package:mantix/widgets/shared/multi_select_sheet.dart';
import 'package:mantix/widgets/technicians/technician_views.dart';

import '../../support/fakes.dart';
import '../../support/paginator_support.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

const _viewOnly = {'tecnicos:ver', 'dashboard:ver', 'tickets:ver'};
const _manager = {..._viewOnly, 'tecnicos:editar'};

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) techniciansHandler;
  late ResponseBody Function(RequestOptions) workloadHandler;
  late ResponseBody Function(RequestOptions) performanceHandler;
  late ResponseBody Function(RequestOptions) ticketsHandler;

  // Los cuatro técnicos de la maqueta, con su carga.
  List<Map<String, Object?>> four() => [
        technicianJson(id: 1, name: 'Ana Demo', specialization: 'Redes', rate: '35.00', code: 'TEC-01'),
        technicianJson(id: 2, name: 'Luis Demo', specialization: 'Hardware', rate: '40.00'),
        technicianJson(id: 3, name: 'Marta Demo', specialization: 'Software', available: false),
        technicianJson(id: 4, name: 'Suley Suárez', specialization: 'Redes, Impresoras', active: false),
      ];

  setUp(() {
    techniciansHandler = (_) => pagedResponse(four());
    workloadHandler = (_) => jsonResponse(200, workloadJson({1: (1, 21), 2: (3, 15), 3: (0, 2)}));
    performanceHandler = (_) => jsonResponse(200, performanceJson([performanceRowJson(id: 1, resolved: 3, mttr: 12.5, lowSample: true), performanceRowJson(id: 2)]));
    ticketsHandler = (_) => pagedResponse([ticketJson(id: 1), ticketJson(id: 2)], total: 14);
    adapter = FakeAdapter((options) => switch (options.path) {
          '/technicians' => techniciansHandler(options),
          '/dashboard/workload' => workloadHandler(options),
          '/maintenance/queue/summary' => jsonResponse(200, {'pending_total': 4, 'unassigned': 2}),
          '/dashboard/technicians' => performanceHandler(options),
          '/maintenance/requests' => ticketsHandler(options),
          _ => errorResponse(404),
        });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _viewOnly, Size size = const Size(1000, 3200), double textScale = 1}) async {
    await pumpScreen(tester, const TechniciansScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  /// Nombres de las tarjetas, en el orden en que salen.
  List<String> cardNames(WidgetTester tester) => [for (final card in tester.widgetList<TechnicianCard>(find.byType(TechnicianCard))) card.technician.fullName];

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  /// El campo que abre la multiselección del grupo [index] de la hoja de filtros (especialidad,
  /// disponibilidad, cuenta y carga, en ese orden).
  Finder tile(int index) => find.descendant(of: find.byType(FilterTile).at(index), matching: find.byType(InkWell));

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  group('contenido', () {
    testWidgets('encabezado, cifras del equipo y los técnicos ordenados por menor carga', (tester) async {
      await open(tester);

      expect(find.textContaining('PERSONAL', findRichText: true), findsOneWidget);
      expect(find.textContaining('BANDEJA DE TRIAJE'), findsNothing, reason: 'la etiqueta de la maqueta era de otra pantalla');
      for (final label in ['TÉCNICOS DISPONIBLES', 'SIN CARGA', 'CON SOBRECARGA', 'TICKETS SIN ASIGNAR']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('4 tickets abiertos'), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'tickets sin asignar en la bandeja');
      expect(find.text('4 técnicos registrados'), findsOneWidget);
      expect(cardNames(tester), ['Marta Demo', 'Suley Suárez', 'Ana Demo', 'Luis Demo']);
    });

    testWidgets('cada tarjeta dice el estado con palabras y marca la cuenta inactiva', (tester) async {
      await open(tester);

      expect(find.text('1 ticket activo'), findsOneWidget);
      expect(find.text('3 tickets activos'), findsOneWidget);
      expect(find.text('No disponible'), findsNWidgets(2), reason: 'una cuenta inactiva tampoco puede recibir tickets');
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('Cuenta inactiva'), findsOneWidget);
    });

    testWidgets('no expone tarifas por técnico en la interfaz móvil', (tester) async {
      await open(tester, permissions: _manager);
      expect(find.text('TARIFA POR HORA'), findsNothing);
      expect(find.text(r'$35,00'), findsNothing);
      expect(find.text(r'$40,00'), findsNothing);
    });

    testWidgets('la vista de tabla muestra las mismas personas con abiertos y resueltos', (tester) async {
      await open(tester);
      await tester.tap(find.text('Tabla'));
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianCard), findsNothing);
      expect(find.byType(TechniciansTable), findsOneWidget);
      for (final head in ['TÉCNICO', 'ESTADO', 'ABIERTOS', 'RESUELTOS']) {
        expect(find.descendant(of: find.byType(TechniciansTable), matching: find.text(head)), findsOneWidget, reason: head);
      }
      expect(find.descendant(of: find.byType(TechniciansTable), matching: find.text('Luis Demo')), findsOneWidget);
      expect(find.descendant(of: find.byType(TechniciansTable), matching: find.text('21')), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('si la carga falla, la lista sigue y las cifras de tickets dicen no disponible', (tester) async {
      workloadHandler = (_) => errorResponse(500);
      await open(tester);

      expect(cardNames(tester), hasLength(4));
      expect(find.text('—'), findsWidgets);
      expect(find.text('La carga de tickets no está disponible.'), findsOneWidget);

      workloadHandler = (_) => jsonResponse(200, workloadJson({2: (3, 15)}));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('La carga de tickets no está disponible.'), findsNothing);
      expect(find.text('3 tickets activos'), findsOneWidget);
    });

    testWidgets('si fallan los técnicos sale el error con reintento', (tester) async {
      techniciansHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('No pudimos cargar los técnicos'), findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);

      techniciansHandler = (_) => pagedResponse(four());
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(cardNames(tester), hasLength(4));
    });

    testWidgets('sin técnicos lo dice', (tester) async {
      techniciansHandler = (_) => pagedResponse(const []);
      await open(tester);
      expect(find.text('Aún no hay perfiles de técnico'), findsOneWidget);
    });

    testWidgets('tirar hacia abajo vuelve a pedir técnicos y carga', (tester) async {
      await open(tester, size: const Size(400, 800));
      final before = adapter.requests.length;
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(adapter.requests.length, before + 2);
    });
  });

  group('búsqueda, filtros y orden', () {
    testWidgets('la búsqueda filtra sin tildes y sin pedir nada al servidor', (tester) async {
      await open(tester);
      final before = adapter.requests.length;
      await search(tester, 'suarez');

      expect(cardNames(tester), ['Suley Suárez']);
      expect(find.text('1 de 4 técnicos coinciden con los filtros'), findsOneWidget);
      expect(adapter.requests.length, before);
    });

    testWidgets('una búsqueda sin resultados ofrece quitar los filtros', (tester) async {
      await open(tester);
      await search(tester, 'nadie');
      expect(find.text('Ningún técnico coincide con los filtros'), findsOneWidget);

      await tester.tap(find.text('Quitar filtros'));
      await tester.pumpAndSettle();
      expect(cardNames(tester), hasLength(4));
    });

    testWidgets('los KPI resumen capacidad y demanda sin alterar la lista', (tester) async {
      await open(tester);
      expect(find.text('TÉCNICOS DISPONIBLES'), findsOneWidget);
      expect(find.text('SIN CARGA'), findsOneWidget);
      expect(find.text('CON SOBRECARGA'), findsOneWidget);
      expect(find.text('TICKETS SIN ASIGNAR'), findsOneWidget);
      expect(cardNames(tester), hasLength(4));
    });

    testWidgets('la hoja de filtros es multiselección con Aplicar y Limpiar, y cada filtro sale como chip', (tester) async {
      await open(tester);
      await tester.tap(find.byType(FilterButton));
      await tester.pumpAndSettle();
      for (final group in ['Especialidad', 'Disponibilidad', 'Estado de la cuenta', 'Carga de tickets']) {
        expect(find.text(group), findsOneWidget, reason: group);
      }

      await tester.tap(tile(0));
      await tester.pumpAndSettle();
      final options = find.byType(MultiSelectSheet<String>);
      await tester.tap(find.descendant(of: options, matching: find.text('Redes')));
      await tester.tap(find.descendant(of: options, matching: find.text('Hardware')));
      await tester.pumpAndSettle();
      expect(options, findsOneWidget, reason: 'marcar no cierra la hoja');
      await tester.tap(find.descendant(of: find.byType(MultiSelectSheet<String>), matching: find.text('Aplicar')));
      await tester.pumpAndSettle();
      expect(find.text('Hardware, Redes'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(FilterSheet), matching: find.text('Aplicar')));
      await tester.pumpAndSettle();

      expect(cardNames(tester), ['Suley Suárez', 'Ana Demo', 'Luis Demo']);
      expect(find.byType(ActiveFilterChip), findsNWidgets(2));

      await tester.tap(find.descendant(of: find.widgetWithText(ActiveFilterChip, 'Redes'), matching: find.byTooltip('Quitar filtro')));
      await tester.pumpAndSettle();
      expect(cardNames(tester), ['Luis Demo']);
    });

    testWidgets('cerrar la hoja de filtros sin aplicar no cambia nada', (tester) async {
      await open(tester);
      await tester.tap(find.byType(FilterButton));
      await tester.pumpAndSettle();
      await tester.tap(tile(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 o más tickets'));
      await tester.tap(find.descendant(of: find.byType(MultiSelectSheet<LoadBucket>), matching: find.text('Aplicar')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(FilterSheet), matching: find.text('3 o más tickets')), findsOneWidget);
      Navigator.of(tester.element(find.byType(FilterSheet))).pop();
      await tester.pumpAndSettle();

      expect(cardNames(tester), hasLength(4));
      expect(find.byType(ActiveFilterChip), findsNothing);
    });

    testWidgets('se puede cambiar el orden; por defecto es menor carga', (tester) async {
      await open(tester);
      expect(find.text('Menor carga de tickets'), findsOneWidget);

      await tester.tap(find.text('Menor carga de tickets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nombre').last);
      await tester.pumpAndSettle();
      expect(cardNames(tester), ['Ana Demo', 'Luis Demo', 'Marta Demo', 'Suley Suárez']);
    });
  });

  group('paginación', () {
    List<Map<String, Object?>> many(int count) => [for (var i = 1; i <= count; i++) technicianJson(id: i, name: 'Técnico ${i.toString().padLeft(2, '0')}')];

    testWidgets('con una sola página no hay flechas ni «1 de 1»', (tester) async {
      await open(tester);
      expect(find.byTooltip('Página siguiente'), findsNothing);
      expect(find.byTooltip('Página anterior'), findsNothing);
      expect(find.textContaining('1 de 1'), findsNothing);
    });

    testWidgets('reparte en páginas, deja elegir el tamaño y vuelve a la página 1', (tester) async {
      techniciansHandler = (_) => pagedResponse(many(25));
      workloadHandler = (_) => jsonResponse(200, workloadJson({}));
      await open(tester, size: const Size(1000, 6000));
      expect(cardNames(tester), hasLength(20));
      expect(selectedPage(tester), 1);

      await scrollTo(tester, find.byTooltip('Página siguiente'));
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(cardNames(tester), hasLength(5));
      expect(selectedPage(tester), 2);

      await scrollTo(tester, find.text('20 por página'));
      await tester.tap(find.text('20 por página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 por página').last);
      await tester.pumpAndSettle();
      expect(cardNames(tester), hasLength(10));
      expect(selectedPage(tester), 1);
      expect(adapter.requests.where((r) => r.path == '/technicians'), hasLength(1), reason: 'paginar no vuelve a pedir');
    });
  });

  group('ficha del técnico', () {
    Future<void> openDetail(WidgetTester tester, String name, {Set<String> permissions = _viewOnly}) async {
      await open(tester, permissions: permissions);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('se abre en una hoja con datos, carga, indicadores y tickets abiertos', (tester) async {
      await openDetail(tester, 'Ana Demo');

      expect(find.text('Ficha del técnico'), findsOneWidget);
      expect(find.text('TEC-01'), findsOneWidget);
      expect(find.text('tech1@demo.mantix.co'), findsWidgets);
      expect(find.text('Resueltos en 30 días'), findsOneWidget);
      expect(find.text('Indicadores de los últimos 30 días'), findsOneWidget);
      expect(find.text('12,5 h'), findsOneWidget);
      expect(find.text('pocos datos'), findsOneWidget, reason: 'n < 5 lo marca el servidor');
      expect(find.text('86,7%'), findsOneWidget);
      expect(find.textContaining('3 sin SLA excluidos'), findsOneWidget);
      expect(find.textContaining('no para comparar personas'), findsOneWidget);
      expect(find.text('Tickets abiertos (14)'), findsOneWidget);
      expect(find.text('Y 12 tickets más.'), findsOneWidget);
      expect(find.text('Tarifa por hora'), findsNothing, reason: 'sin tecnicos:editar');

      final request = adapter.requests.singleWhere((r) => r.path == '/maintenance/requests');
      expect(request.queryParameters['technician_id'], [1]);
    });

    testWidgets('no expone la tarifa en la ficha móvil, tampoco a quien gestiona técnicos', (tester) async {
      await openDetail(tester, 'Ana Demo', permissions: _manager);
      expect(find.text('Tarifa por hora'), findsNothing);
    });

    testWidgets('permite cambiar el periodo de rendimiento entre 7 días, 30 días y 12 meses', (tester) async {
      await openDetail(tester, 'Ana Demo');
      await tester.tap(find.text('7 días'));
      await tester.pumpAndSettle();
      final performanceCalls = adapter.requests.where((r) => r.path == '/dashboard/technicians').toList();
      expect(performanceCalls.last.queryParameters['period'], '7d');
      expect(find.text('Indicadores de los últimos 7 días'), findsOneWidget);
    });

    testWidgets('si los indicadores fallan, los tickets siguen y se puede reintentar', (tester) async {
      performanceHandler = (_) => errorResponse(500);
      await openDetail(tester, 'Luis Demo');

      expect(find.textContaining('No pudimos cargar los indicadores'), findsOneWidget);
      expect(find.text('Tickets abiertos (14)'), findsOneWidget);

      performanceHandler = (_) => jsonResponse(200, performanceJson([performanceRowJson(id: 2)]));
      await scrollTo(tester, find.text('Reintentar').last);
      await tester.tap(find.text('Reintentar').last);
      await tester.pumpAndSettle();
      expect(find.text('12,5 h'), findsOneWidget);
    });

    testWidgets('un técnico sin indicadores ni tickets lo dice', (tester) async {
      ticketsHandler = (_) => pagedResponse(const []);
      await openDetail(tester, 'Marta Demo');

      expect(find.text('No hay indicadores disponibles para este técnico.'), findsOneWidget);
      expect(find.text('No tiene tickets abiertos.'), findsOneWidget);
    });

    testWidgets('sin permiso para ver tickets no se piden ni se muestra el bloque', (tester) async {
      await openDetail(tester, 'Ana Demo', permissions: const {'tecnicos:ver', 'dashboard:ver'});

      expect(find.textContaining('Tickets abiertos ('), findsNothing);
      expect(adapter.requests.where((r) => r.path == '/maintenance/requests'), isEmpty);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('tarjetas, tabla, hoja de filtros y ficha en $label', (tester) async {
        techniciansHandler = (_) => pagedResponse([
              technicianJson(id: 1, name: 'Una persona con un nombre muy largo que no cabe en una línea', email: 'un.correo.muy.largo.de.prueba@una-empresa-con-dominio-largo.com', specialization: 'Redes, Hardware, Impresoras, Servidores y telefonía', rate: '99999999.99', code: 'TEC-000001'),
              ...four().skip(1),
              for (var i = 5; i <= 30; i++) technicianJson(id: i, name: 'Técnico $i'),
            ]);
        workloadHandler = (_) => jsonResponse(200, workloadJson({1: (120, 9999), 2: (3, 15)}));
        await open(tester, permissions: _manager, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await search(tester, 'nombre muy largo');
        expect(tester.takeException(), isNull);

        await scrollTo(tester, find.text('Tabla'));
        await tester.tap(find.text('Tabla'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await scrollTo(tester, find.byType(FilterButton));
        await tester.tap(find.byType(FilterButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(FilterSheet))).pop();
        await tester.pumpAndSettle();

        final row = find.descendant(of: find.byType(TechniciansTable), matching: find.textContaining('nombre muy largo'));
        await scrollTo(tester, row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text('Ficha del técnico'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // La ficha entera, de arriba abajo: las secciones se construyen al desplazarse.
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.textContaining('Tickets abiertos ('), findsOneWidget);
      });

      testWidgets('con la carga caída, los técnicos caídos y la lista vacía en $label', (tester) async {
        workloadHandler = (_) => errorResponse(500);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await search(tester, 'nadie');
        expect(tester.takeException(), isNull);
      });

      testWidgets('con los técnicos caídos en $label', (tester) async {
        techniciansHandler = (_) => errorResponse(500);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
