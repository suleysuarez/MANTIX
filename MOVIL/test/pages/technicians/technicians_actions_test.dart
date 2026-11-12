import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/technicians/technicians_screen.dart';
import 'package:mantix/widgets/technicians/technician_views.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

const _viewOnly = {'tecnicos:ver', 'dashboard:ver', 'tickets:ver'};
const _editor = {..._viewOnly, 'tecnicos:editar'};
const _supervisor = {..._editor, 'tecnicos:crear', 'equipos:asignar'};
const _admin = {..._supervisor, 'usuarios:cambiar_estado'};

void main() {
  late FakeAdapter adapter;
  late List<Map<String, Object?>> technicians;
  late ResponseBody Function(RequestOptions) writeHandler;

  setUp(() {
    technicians = [
      technicianJson(id: 1, name: 'Ana Demo', specialization: 'Redes', rate: '35.00'),
      technicianJson(id: 2, name: 'Luis Demo', specialization: 'Hardware', rate: '40.00'),
      technicianJson(id: 3, name: 'Marta Demo', specialization: 'Software', available: false),
    ];
    // Por defecto el servidor acepta: registra a «Zoe Nueva» o devuelve el técnico editado.
    writeHandler = (options) {
      if (options.method == 'POST') {
        final created = technicianJson(id: 9, name: 'Zoe Nueva', specialization: 'Redes', rate: '35.50');
        technicians = [...technicians, created];
        return jsonResponse(201, created);
      }
      return jsonResponse(200, technicians.first);
    };
    adapter = FakeAdapter((options) {
      if (options.method != 'GET') return writeHandler(options);
      return switch (options.path) {
        '/technicians' => pagedResponse(technicians),
        '/dashboard/workload' => jsonResponse(200, workloadJson({1: (1, 21), 2: (3, 15)})),
        '/dashboard/technicians' => jsonResponse(200, performanceJson([performanceRowJson(id: 1)])),
        '/maintenance/requests' => pagedResponse([ticketJson(id: 1)]),
        '/equipment/custodian-candidates' => jsonResponse(200, [
            {'id': 7, 'full_name': 'Zoe Nueva', 'email': 'zoe@mantix.test'},
            {'id': 8, 'full_name': 'Otra Persona', 'email': 'otra@mantix.test'},
          ]),
        _ => errorResponse(404),
      };
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _supervisor, Size size = const Size(1000, 3200), double textScale = 1}) async {
    await pumpScreen(tester, const TechniciansScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  List<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET').toList();
  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;
  List<String> cardNames(WidgetTester tester) => [for (final card in tester.widgetList<TechnicianCard>(find.byType(TechnicianCard))) card.technician.fullName];
  Finder field(String hint) => find.widgetWithText(TextField, hint);
  /// El botón de guardar del formulario (el último: la hoja va encima de la pantalla, que tiene
  /// otro «Registrar técnico» en el encabezado).
  Finder submit(String label) => find.widgetWithText(FilledButton, label).last;

  /// Desplaza la hoja abierta hasta que [finder] se vea (en pantallas bajas no cabe entera).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final sheetList = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(finder, 80, scrollable: sheetList);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar técnico'));
    await tester.pumpAndSettle();
  }

  Future<void> pickUser(WidgetTester tester) async {
    await tester.tap(find.text('Buscar usuario por nombre o correo…'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('zoe@mantix.test'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String name, {Set<String> permissions = _supervisor}) async {
    await open(tester, permissions: permissions);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('permisos', () {
    testWidgets('sin tecnicos:crear no hay botón de registrar', (tester) async {
      await open(tester, permissions: _editor);
      expect(find.text('Registrar técnico'), findsNothing);
    });

    testWidgets('con tecnicos:crear pero sin poder buscar usuarios tampoco', (tester) async {
      await open(tester, permissions: {..._editor, 'tecnicos:crear'});
      expect(find.text('Registrar técnico'), findsNothing);
    });

    testWidgets('sin tecnicos:editar la ficha es de solo lectura', (tester) async {
      await openDetail(tester, 'Ana Demo', permissions: _viewOnly);
      expect(find.text('Editar perfil'), findsNothing);
      expect(find.text('Marcar como no disponible'), findsNothing);
    });

    testWidgets('con tecnicos:editar la ficha ofrece editar y cambiar la disponibilidad', (tester) async {
      await openDetail(tester, 'Ana Demo', permissions: _editor);
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('Marcar como no disponible'), findsOneWidget);
    });
  });

  group('registrar', () {
    testWidgets('el formulario se abre en una hoja con sus tres campos', (tester) async {
      await open(tester);
      await openForm(tester);

      expect(find.text('Abre un perfil técnico a un usuario existente'), findsOneWidget);
      for (final title in ['Usuario', 'Especialización', 'Tarifa por hora']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Obligatorio'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('sin usuario elegido lo pide y no manda nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(submit('Registrar técnico'));
      await tester.pumpAndSettle();

      expect(find.text('Selecciona el usuario al que pertenece el perfil de técnico.'), findsOneWidget);
      expect(writes(), isEmpty);
    });

    testWidgets('una tarifa negativa o con tres decimales se explica bajo el campo y no manda nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await pickUser(tester);

      await tester.enterText(field('0,00'), '-5');
      await tester.pumpAndSettle();
      expect(find.text('La tarifa por hora debe ser un número igual o mayor a cero.'), findsOneWidget);
      await tester.tap(submit('Registrar técnico'));
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);

      await tester.enterText(field('0,00'), '35,123');
      await tester.pumpAndSettle();
      expect(find.text('La tarifa por hora admite como máximo dos decimales.'), findsOneWidget);

      await tester.enterText(field('0,00'), '35,5');
      await tester.pumpAndSettle();
      expect(find.text(r'Se guardará como $35,50 por hora.'), findsOneWidget);
    });

    testWidgets('con los datos válidos manda el alta, cierra la hoja y el técnico sale de primero y resaltado', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'ana');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(cardNames(tester), ['Ana Demo']);

      await openForm(tester);
      await pickUser(tester);
      expect(find.text('Zoe Nueva'), findsOneWidget);
      await tester.enterText(field('Ej: Hardware, Redes'), '  Redes ');
      await tester.enterText(field('0,00'), '35,5');
      await tester.pumpAndSettle();
      await tester.tap(submit('Registrar técnico'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'POST');
      expect(body(writes().single), {'user_id': 7, 'specialization': 'Redes', 'hourly_rate': '35.50'});
      expect(find.text('Abre un perfil técnico a un usuario existente'), findsNothing, reason: 'la hoja se cerró');
      expect(find.text('Técnico «Zoe Nueva» registrado.'), findsOneWidget);
      expect(cardNames(tester).first, 'Zoe Nueva');
      expect(cardNames(tester), hasLength(4), reason: 'sin la búsqueda que había');
      expect(tester.widget<TechnicianCard>(find.byType(TechnicianCard).first).highlighted, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.widgetList<TechnicianCard>(find.byType(TechnicianCard)).where((card) => card.highlighted), isEmpty, reason: 'el resaltado dura unos segundos');
    });

    testWidgets('409: si el usuario ya tiene perfil, el motivo sale en la hoja y lo escrito se conserva', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'technician_profile_exists');
      await open(tester);
      await openForm(tester);
      await pickUser(tester);
      await tester.enterText(field('Ej: Hardware, Redes'), 'Redes');
      await tester.tap(submit('Registrar técnico'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ese usuario ya tiene un perfil de técnico.'), findsWidgets);
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(find.text('Abre un perfil técnico a un usuario existente'), findsOneWidget, reason: 'la hoja sigue abierta');
      expect(find.text('Redes'), findsWidgets);
      expect(cardNames(tester), hasLength(3));
    });

    testWidgets('403: sin permiso lo dice en español', (tester) async {
      writeHandler = (_) => errorResponse(403, code: 'forbidden');
      await open(tester);
      await openForm(tester);
      await pickUser(tester);
      await tester.tap(submit('Registrar técnico'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No tienes permiso'), findsWidgets);
    });

    testWidgets('cancelar cierra la hoja sin mandar nada', (tester) async {
      await open(tester);
      await openForm(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Abre un perfil técnico a un usuario existente'), findsNothing);
      expect(writes(), isEmpty);
    });
  });

  group('editar', () {
    testWidgets('el formulario llega con los datos y solo manda lo que cambió', (tester) async {
      await openDetail(tester, 'Ana Demo');
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Redes'), findsOneWidget);
      expect(find.widgetWithText(TextField, '35,00'), findsOneWidget);
      expect(find.text('Buscar usuario por nombre o correo…'), findsNothing, reason: 'el usuario no se cambia');

      await tester.enterText(find.widgetWithText(TextField, '35,00'), '42.5');
      await tester.pumpAndSettle();
      await tester.tap(submit('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'PATCH');
      expect(writes().single.path, '/technicians/1');
      expect(body(writes().single), {'hourly_rate': '42.50'});
      expect(find.text('Ficha del técnico'), findsNothing, reason: 'el formulario y la ficha se cerraron');
      expect(find.text('Perfil de Ana Demo actualizado.'), findsOneWidget);
    });

    testWidgets('guardar sin cambios lo dice y no manda nada', (tester) async {
      await openDetail(tester, 'Ana Demo');
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(submit('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(find.text('No hay cambios que guardar.'), findsOneWidget);
      expect(writes(), isEmpty);
    });
  });

  group('disponibilidad', () {
    testWidgets('marcar como no disponible pide confirmación y avisa de los tickets abiertos', (tester) async {
      await openDetail(tester, 'Luis Demo');
      expect(find.textContaining('Tiene 3 tickets abiertos'), findsOneWidget);

      await tester.tap(find.text('Marcar como no disponible'));
      await tester.pumpAndSettle();
      expect(find.text('¿Marcar a Luis Demo como no disponible?'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Tiene 3 tickets abiertos: seguirán asignados a esta persona.')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
      expect(find.text('Ficha del técnico'), findsOneWidget);
    });

    testWidgets('al confirmar manda el cambio, cierra la ficha y avisa', (tester) async {
      await openDetail(tester, 'Luis Demo');
      await tester.tap(find.text('Marcar como no disponible'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar no disponible'));
      await tester.pumpAndSettle();

      expect(writes().single.path, '/technicians/2');
      expect(body(writes().single), {'is_available': false});
      expect(find.text('Ficha del técnico'), findsNothing);
      expect(find.text('Luis Demo ahora está no disponible.'), findsOneWidget);
    });

    testWidgets('sin tickets abiertos la confirmación no los menciona', (tester) async {
      technicians = [technicianJson(id: 5, name: 'Sin Carga')];
      await openDetail(tester, 'Sin Carga');
      expect(find.textContaining('seguirá'), findsNothing);
      await tester.tap(find.text('Marcar como no disponible'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('abierto')), findsNothing);
    });

    testWidgets('volver a marcar como disponible no pide confirmación', (tester) async {
      await openDetail(tester, 'Marta Demo');
      await tester.tap(find.text('Marcar como disponible'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(body(writes().single), {'is_available': true});
      expect(find.text('Marta Demo ahora está disponible.'), findsOneWidget);
    });

    testWidgets('si el servidor lo rechaza, el motivo sale en la ficha y sigue abierta', (tester) async {
      writeHandler = (_) => errorResponse(403, code: 'forbidden');
      await openDetail(tester, 'Marta Demo');
      await tester.tap(find.text('Marcar como disponible'));
      await tester.pumpAndSettle();

      expect(find.text('Ficha del técnico'), findsOneWidget);
      expect(find.textContaining('No se pudo marcar a Marta Demo como disponible:'), findsWidgets);
    });
  });

  group('desactivar la cuenta', () {
    testWidgets('sin usuarios:cambiar_estado no hay botón', (tester) async {
      await openDetail(tester, 'Luis Demo', permissions: _supervisor);
      expect(find.text('Desactivar cuenta'), findsNothing);
      expect(find.text('Activar cuenta'), findsNothing);
    });

    testWidgets('con solo ese permiso se ofrece, aunque no pueda editar el perfil', (tester) async {
      await openDetail(tester, 'Luis Demo', permissions: {..._viewOnly, 'usuarios:cambiar_estado'});
      expect(find.text('Desactivar cuenta'), findsOneWidget);
      expect(find.text('Editar perfil'), findsNothing);
      expect(find.text('Marcar como no disponible'), findsNothing);
    });

    testWidgets('pide confirmación, explica el alcance y avisa de los tickets abiertos', (tester) async {
      await openDetail(tester, 'Luis Demo', permissions: _admin);
      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();

      expect(find.text('¿Desactivar la cuenta de Luis Demo?'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('ni como técnico ni con ningún otro rol')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Tiene 3 tickets abiertos: seguirán asignados a esta persona hasta que los reasignes.')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
      await tester.pumpAndSettle();
      expect(writes(), isEmpty);
      expect(find.text('Ficha del técnico'), findsOneWidget);
    });

    testWidgets('al confirmar manda la desactivación, cierra la ficha y avisa', (tester) async {
      writeHandler = (_) => jsonResponse(200, {'id': 102});
      await openDetail(tester, 'Luis Demo', permissions: _admin);
      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Desactivar cuenta')));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'POST');
      expect(writes().single.path, '/admin/users/102/deactivate');
      expect(find.text('Ficha del técnico'), findsNothing);
      expect(find.text('La cuenta de Luis Demo fue desactivada.'), findsOneWidget);
    });

    testWidgets('una cuenta inactiva se reactiva sin confirmación', (tester) async {
      technicians = [technicianJson(id: 6, name: 'Inactivo Demo', active: false)];
      writeHandler = (_) => jsonResponse(200, {'id': 106});
      await openDetail(tester, 'Inactivo Demo', permissions: _admin);
      await tester.tap(find.text('Activar cuenta'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(writes().single.path, '/admin/users/106/activate');
      expect(find.text('La cuenta de Inactivo Demo fue activada.'), findsOneWidget);
    });

    testWidgets('la propia cuenta no se puede desactivar y lo dice', (tester) async {
      technicians = [technicianJson(id: 6, name: 'Ana Pérez', userId: 1)];
      await openDetail(tester, 'Ana Pérez', permissions: _admin);
      expect(find.text('Desactivar cuenta'), findsNothing);
      expect(find.text('No puedes desactivar tu propia cuenta.'), findsOneWidget);
    });

    testWidgets('409: el último administrador no se puede desactivar y el motivo sale en la ficha', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'last_admin_protected');
      await openDetail(tester, 'Luis Demo', permissions: _admin);
      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Desactivar cuenta')));
      await tester.pumpAndSettle();

      expect(find.text('Ficha del técnico'), findsOneWidget);
      expect(find.textContaining('No se pudo desactivar a Luis Demo:'), findsWidgets);
      expect(find.textContaining('detalle interno'), findsNothing);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';

      testWidgets('el encabezado con el botón y el formulario de alta con errores en $label', (tester) async {
        writeHandler = (_) => errorResponse(409, code: 'technician_profile_exists');
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await openForm(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(submit('Registrar técnico'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await pickUser(tester);
        expect(tester.takeException(), isNull);
        await reveal(tester, field('Ej: Hardware, Redes'));
        await tester.enterText(field('Ej: Hardware, Redes'), 'Redes, Hardware, Impresoras, Servidores y telefonía, Cableado estructurado');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(submit('Registrar técnico'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 4; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('la ficha con el botón de la cuenta y su confirmación en $label', (tester) async {
        await open(tester, permissions: _admin, size: size, textScale: 1.3);
        await tester.ensureVisible(find.text('Luis Demo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Luis Demo'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Desactivar cuenta'));
        await tester.tap(find.text('Desactivar cuenta'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('la ficha con sus acciones y el formulario de edición en $label', (tester) async {
        await open(tester, size: size, textScale: 1.3);
        await tester.ensureVisible(find.text('Luis Demo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Luis Demo'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await reveal(tester, find.text('Marcar como no disponible'));
        await tester.tap(find.text('Marcar como no disponible'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancelar')));
        await tester.pumpAndSettle();

        // Se subió para ver el otro botón: se vuelve arriba y se baja hasta el de editar.
        await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Editar perfil'));
        await tester.tap(find.text('Editar perfil'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(submit('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -200));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
