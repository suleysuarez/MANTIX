import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/maintenance_format.dart';
import 'package:mantix/pages/maintenance/maintenance_screen.dart';
import 'package:mantix/widgets/maintenance/maintenance_cards.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

const _viewOnly = {'mantenimiento:ver'};
const _editor = {'mantenimiento:ver', 'mantenimiento:editar'};
const _supervisor = {'mantenimiento:ver', 'mantenimiento:crear', 'mantenimiento:editar', 'equipos:ver', 'tecnicos:ver'};

String _utc(DateTime local) => local.toUtc().toIso8601String();

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) writeHandler;
  late ResponseBody Function(RequestOptions) planHandler;
  final today = DateTime(2026, 10, 25, 10);

  setUp(() {
    writeHandler = (options) => options.method == 'POST' && options.path == '/maintenance/schedules' ? jsonResponse(201, scheduleJson(id: 9, title: 'Limpieza')) : jsonResponse(200, scheduleJson());
    planHandler = (options) => jsonResponse(200, scheduleJson(due: _utc(DateTime(2026, 10, 6, 12))));
    adapter = FakeAdapter((options) {
      if (options.method != 'GET') return writeHandler(options);
      final path = options.path;
      if (path == '/maintenance/calendar') return calendarResponse([calendarEventJson(id: 4, title: 'Revisión de UPS', kind: 'overdue', at: _utc(DateTime(2026, 10, 6, 12)))]);
      if (path == '/maintenance/schedules') return pagedResponse([scheduleJson()]);
      if (path.endsWith('/history')) return jsonResponse(200, historyJson());
      if (path.startsWith('/maintenance/schedules/')) return planHandler(options);
      if (path == '/equipment') return pagedResponse([equipmentJson(id: 12, tag: 'SRV-0003')]);
      if (path == '/technicians') return pagedResponse([technicianJson(id: 2, name: 'Luis Mora')]);
      return errorResponse(404);
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _supervisor, Size size = const Size(1000, 3000), double textScale = 1}) async {
    await pumpScreen(tester, MaintenanceScreen(clock: () => today), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  List<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET').toList();
  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;
  Finder field(String text) => find.widgetWithText(TextField, text);
  Finder submit() => find.widgetWithText(FilledButton, 'Programar');

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Programar mantenimiento'));
    await tester.pumpAndSettle();
  }

  Future<void> pickEquipment(WidgetTester tester) async {
    await tester.tap(find.text('Selecciona un equipo...'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'SRV-0003'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, {Set<String> permissions = _editor}) async {
    await open(tester, permissions: permissions);
    await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
    await tester.pumpAndSettle();
  }

  /// Desplaza la hoja de arriba hasta que [finder] se vea (en pantallas bajas no cabe entera).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 80, scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
  }

  group('permisos', () {
    testWidgets('sin mantenimiento:crear no hay botón de programar', (tester) async {
      await open(tester, permissions: _editor);
      expect(find.text('Programar mantenimiento'), findsNothing);
    });

    testWidgets('con mantenimiento:crear pero sin poder buscar equipos tampoco', (tester) async {
      await open(tester, permissions: {..._editor, 'mantenimiento:crear'});
      expect(find.text('Programar mantenimiento'), findsNothing);
    });

    testWidgets('con los dos permisos sale el botón mostaza del encabezado', (tester) async {
      await open(tester);
      expect(find.widgetWithText(FilledButton, 'Programar mantenimiento'), findsOneWidget);
    });

    testWidgets('sin mantenimiento:editar la ficha es de solo lectura', (tester) async {
      await openDetail(tester, permissions: _viewOnly);
      expect(find.text('Datos del plan'), findsOneWidget);
      expect(find.text('Marcar como hecho'), findsNothing);
      expect(find.text('Desactivar plan'), findsNothing);
    });

    testWidgets('con mantenimiento:editar la ficha ofrece marcar como hecho y desactivar', (tester) async {
      await openDetail(tester);
      expect(find.text('Marcar como hecho'), findsOneWidget);
      expect(find.text('Desactivar plan'), findsOneWidget);
    });
  });

  group('programar', () {
    testWidgets('el formulario trae lo de la imagen: sus campos, 30 días, 3 de antelación y mañana a las 9:00', (tester) async {
      await open(tester);
      await openForm(tester);

      expect(find.text('Completa la información del servicio para agendar el mantenimiento.'), findsOneWidget);
      for (final label in ['Equipo', 'Título', 'Descripción', 'Cada cuántos días', 'Recordar en (días de antelación)', 'Primer servicio', 'Horas estimadas', 'Técnico responsable']) {
        expect(find.textContaining(label), findsWidgets, reason: label);
      }
      expect(find.text('Selecciona un equipo...'), findsOneWidget);
      expect(field('30'), findsOneWidget);
      expect(field('3'), findsOneWidget);
      expect(find.text('26/10/2026 09:00 a. m.'), findsOneWidget);
      expect(find.text('Sin asignar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Este campo es obligatorio.'), findsNothing, reason: 'los errores salen al tocar o al programar');
    });

    testWidgets('sin tecnicos:ver no se ofrece el técnico', (tester) async {
      await open(tester, permissions: {'mantenimiento:ver', 'mantenimiento:crear', 'equipos:ver'});
      await openForm(tester);
      expect(find.text('Sin asignar'), findsNothing);
      expect(find.textContaining('Técnico responsable'), findsNothing);
    });

    testWidgets('programar con todo vacío marca lo obligatorio y no manda nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.text('Este campo es obligatorio.'), findsNWidgets(2), reason: 'el equipo y el título');
      expect(writes(), isEmpty);
    });

    testWidgets('cada valor inválido se explica bajo su campo y no manda nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      await tester.enterText(field('Ingresa el título del mantenimiento'), 'ab');
      await tester.enterText(field('30'), '0');
      await tester.enterText(field('3'), '40');
      await tester.enterText(field('Ej. 1.5'), '-2');
      await tester.enterText(field('Describe el mantenimiento...'), '   ');
      await tester.pumpAndSettle();

      expect(find.text('Debe tener al menos 3 caracteres.'), findsOneWidget);
      expect(find.text('Debe ser al menos 1.'), findsOneWidget);
      expect(find.text('Escribe un número válido.'), findsOneWidget);
      expect(find.text('No puede contener solo espacios.'), findsOneWidget);

      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
    });

    testWidgets('un recordatorio mayor que el intervalo se explica', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.enterText(field('30'), '10');
      await tester.enterText(field('3'), '11');
      await tester.pumpAndSettle();
      expect(find.text('El recordatorio no puede superar el intervalo entre servicios.'), findsOneWidget);
    });

    testWidgets('con los datos válidos manda el plan, cierra la hoja y avisa', (tester) async {
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      expect(find.text('SRV-0003 · Dell Latitude'), findsOneWidget);
      await tester.enterText(field('Ingresa el título del mantenimiento'), '  Limpieza  ');
      await tester.enterText(field('Describe el mantenimiento...'), 'Filtros y ventiladores');
      await tester.enterText(field('30'), '10');
      await tester.enterText(field('3'), '2');
      await tester.enterText(field('Ej. 1.5'), '1,5');
      await tester.tap(find.text('Sin asignar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Luis Mora'));
      await tester.pumpAndSettle();
      expect(find.text('Luis Mora'), findsOneWidget);
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(writes().single.method, 'POST');
      expect(writes().single.path, '/maintenance/schedules');
      expect(body(writes().single), {
        'equipment_id': 12,
        'technician_id': 2,
        'title': 'Limpieza',
        'description': 'Filtros y ventiladores',
        'interval_days': 10,
        'estimated_hours': '1.50',
        'remind_days_before': 2,
        'first_due_at': DateTime(2026, 10, 26, 9).toUtc().toIso8601String(),
      });
      expect(find.text('Completa la información del servicio para agendar el mantenimiento.'), findsNothing, reason: 'la hoja se cerró');
      expect(find.text('Mantenimiento programado.'), findsOneWidget);
    });

    testWidgets('sin técnico, descripción ni horas no manda el técnico y manda null en lo demás', (tester) async {
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      await tester.enterText(field('Ingresa el título del mantenimiento'), 'Limpieza');
      await tester.tap(submit());
      await tester.pumpAndSettle();

      final sent = body(writes().single)! as Map;
      expect(sent.containsKey('technician_id'), isFalse);
      expect(sent['description'], isNull);
      expect(sent['estimated_hours'], isNull);
    });

    testWidgets('el técnico elegido se puede quitar', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(find.text('Sin asignar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Luis Mora'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quitar'));
      await tester.pumpAndSettle();
      expect(find.text('Sin asignar'), findsOneWidget);
    });

    testWidgets('el selector de fecha y hora se abre y conserva la fecha al aceptar', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(find.text('26/10/2026 09:00 a. m.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('26/10/2026 09:00 a. m.'), findsOneWidget);
    });

    testWidgets('409: un equipo que no admite planes se explica en la hoja y lo escrito se conserva', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'schedule_equipment_unavailable');
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      await tester.enterText(field('Ingresa el título del mantenimiento'), 'Limpieza');
      await tester.tap(submit());
      await tester.pumpAndSettle();

      expect(find.textContaining('No se puede programar mantenimiento para un equipo en ese estado.'), findsWidgets, reason: 'en la hoja y en el aviso');
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(find.text('Completa la información del servicio para agendar el mantenimiento.'), findsOneWidget, reason: 'la hoja sigue abierta');
      expect(find.text('Limpieza'), findsOneWidget);
    });

    testWidgets('403: sin permiso lo dice en español', (tester) async {
      writeHandler = (_) => errorResponse(403, code: 'forbidden');
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      await tester.enterText(field('Ingresa el título del mantenimiento'), 'Limpieza');
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(find.textContaining('No tienes permiso'), findsWidgets);
    });

    testWidgets('sin red lo dice y se puede volver a intentar', (tester) async {
      writeHandler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      await open(tester);
      await openForm(tester);
      await pickEquipment(tester);
      await tester.enterText(field('Ingresa el título del mantenimiento'), 'Limpieza');
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos conectar con el servidor'), findsWidgets);
      expect(submit(), findsOneWidget);
    });

    testWidgets('cancelar cierra la hoja sin mandar nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Completa la información del servicio para agendar el mantenimiento.'), findsNothing);
      expect(writes(), isEmpty);
    });
  });

  group('marcar como hecho', () {
    testWidgets('pide las horas reales, manda el servicio, cierra la ficha y avisa', (tester) async {
      await openDetail(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Marcar como hecho'));
      await tester.pumpAndSettle();
      expect(find.text('¿Marcar como hecho?'), findsOneWidget);

      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '2,5');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Marcar como hecho')));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'POST');
      expect(writes().single.path, '/maintenance/schedules/4/complete');
      expect(body(writes().single), {'actual_hours': '2.50'});
      expect(find.text('Plan de mantenimiento'), findsNothing, reason: 'la ficha se cerró');
      expect(find.text('Servicio «Revisión de UPS» registrado como hecho.'), findsOneWidget);
    });

    testWidgets('las horas son opcionales', (tester) async {
      await openDetail(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Marcar como hecho'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Marcar como hecho')));
      await tester.pumpAndSettle();
      expect(body(writes().single), {'actual_hours': null});
    });

    testWidgets('unas horas inválidas se explican y no se puede confirmar', (tester) async {
      await openDetail(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Marcar como hecho'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '-3');
      await tester.pumpAndSettle();

      expect(find.text('Escribe un número válido.'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Marcar como hecho')));
      expect(confirm.onPressed, isNull);
      expect(writes(), isEmpty);
    });

    testWidgets('cancelar el diálogo no manda nada', (tester) async {
      await openDetail(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Marcar como hecho'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
      expect(find.text('Plan de mantenimiento'), findsOneWidget);
    });

    testWidgets('si el servidor lo rechaza, el motivo sale en la ficha y sigue abierta', (tester) async {
      writeHandler = (_) => errorResponse(404, code: 'schedule_not_found');
      await openDetail(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Marcar como hecho'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Marcar como hecho')));
      await tester.pumpAndSettle();

      expect(find.text('Plan de mantenimiento'), findsOneWidget);
      expect(find.textContaining('No se pudo registrar el servicio: Ese plan de mantenimiento ya no existe.'), findsWidgets);
    });
  });

  group('desactivar y activar', () {
    testWidgets('desactivar pide confirmación y explica el alcance', (tester) async {
      await openDetail(tester);
      await tester.tap(find.text('Desactivar plan'));
      await tester.pumpAndSettle();

      expect(find.text('¿Desactivar el plan «Revisión de UPS»?'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('dejará de verse en el calendario')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
    });

    testWidgets('al confirmar manda is_active false, cierra la ficha y avisa', (tester) async {
      writeHandler = (_) => jsonResponse(200, scheduleJson(active: false));
      await openDetail(tester);
      await tester.tap(find.text('Desactivar plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Desactivar plan')));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'PATCH');
      expect(writes().single.path, '/maintenance/schedules/4');
      expect(body(writes().single), {'is_active': false});
      expect(find.text('Plan de mantenimiento'), findsNothing);
      expect(find.text('El plan «Revisión de UPS» fue desactivado.'), findsOneWidget);
    });

    testWidgets('un plan inactivo solo ofrece activar y no pide confirmación', (tester) async {
      planHandler = (_) => jsonResponse(200, scheduleJson(active: false));
      writeHandler = (_) => jsonResponse(200, scheduleJson());
      await openDetail(tester);

      expect(find.text('Marcar como hecho'), findsNothing, reason: 'el servidor no deja completar un plan inactivo');
      expect(find.text('Desactivar plan'), findsNothing);
      await tester.tap(find.text('Activar plan'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(body(writes().single), {'is_active': true});
      expect(find.text('El plan «Revisión de UPS» fue activado.'), findsOneWidget);
    });

    testWidgets('403: sin permiso el motivo sale en la ficha', (tester) async {
      writeHandler = (_) => errorResponse(403, code: 'forbidden');
      await openDetail(tester);
      await tester.tap(find.text('Desactivar plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Desactivar plan')));
      await tester.pumpAndSettle();

      expect(find.text('Plan de mantenimiento'), findsOneWidget);
      expect(find.textContaining('No se pudo desactivar el plan:'), findsWidgets);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('el botón del encabezado y el formulario con errores en $label', (tester) async {
        writeHandler = (_) => errorResponse(409, code: 'schedule_technician_inactive');
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Programar mantenimiento'));
        await openForm(tester);
        expect(tester.takeException(), isNull);
        await reveal(tester, submit());
        await tester.tap(submit());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.enterText(field('Ingresa el título del mantenimiento'), 'Un mantenimiento con un título muy largo que no cabe en una sola línea del formulario');
        await tester.enterText(field('30'), '0');
        await tester.enterText(field('3'), '9999');
        await tester.enterText(field('Ej. 1.5'), 'mucho');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('el formulario con equipo, técnico y error del servidor en $label', (tester) async {
        writeHandler = (_) => errorResponse(409, code: 'schedule_technician_inactive');
        await open(tester, size: size, textScale: 1.3);
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Programar mantenimiento'));
        await openForm(tester);

        await reveal(tester, find.text('Selecciona un equipo...'));
        await pickEquipment(tester);
        await reveal(tester, find.text('Sin asignar'));
        await tester.tap(find.text('Sin asignar'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Luis Mora'));
        await tester.pumpAndSettle();
        await reveal(tester, field('Ingresa el título del mantenimiento'));
        await tester.enterText(field('Ingresa el título del mantenimiento'), 'Limpieza');
        await reveal(tester, submit());
        await tester.tap(submit());
        await tester.pumpAndSettle();
        expect(find.textContaining('Ese técnico está inactivo'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('la ficha con sus acciones y sus diálogos en $label', (tester) async {
        await open(tester, permissions: _editor, size: size, textScale: 1.3);
        await tester.ensureVisible(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MaintenanceEventCard, 'Revisión de UPS'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await reveal(tester, find.text('Marcar como hecho'));
        await tester.tap(find.text('Marcar como hecho'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'no es un número');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
        await tester.pumpAndSettle();

        await reveal(tester, find.text('Desactivar plan'));
        await tester.tap(find.text('Desactivar plan'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('formato del formulario', () {
    test('la fecha se escribe como en la imagen', () {
      expect(formatFormDateTime(DateTime(2026, 11, 26, 9)), '26/11/2026 09:00 a. m.');
      expect(formatFormDateTime(DateTime(2026, 11, 6, 15, 5)), '06/11/2026 03:05 p. m.');
      expect(formatFormDateTime(DateTime(2026, 11, 6, 0, 30)), '06/11/2026 12:30 a. m.');
      expect(formatFormDateTime(DateTime(2026, 11, 6, 12)), '06/11/2026 12:00 p. m.');
    });

    test('el primer servicio que se propone es mañana a las 9:00, también a fin de mes', () {
      expect(defaultFirstDue(DateTime(2026, 10, 25, 22)), DateTime(2026, 10, 26, 9));
      expect(defaultFirstDue(DateTime(2026, 12, 31, 8)), DateTime(2027, 1, 1, 9));
    });
  });
}
