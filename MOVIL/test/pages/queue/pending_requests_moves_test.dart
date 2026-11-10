import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/queue/pending_requests_screen.dart';
import 'package:mantix/widgets/queue/queue_card.dart';

import '../../models/queue/queue_models_test.dart' show summaryJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

Map<String, Object?> _state(String status, {bool canEnterTriaged = true, bool canEnterCancelled = true}) => {
      'submitted': {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled'], 'requires': [], 'can_enter': true, 'in_queue': true},
      'triaged': {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': canEnterTriaged, 'in_queue': true},
      'assigned': {'status': 'assigned', 'order': 3, 'allowed_targets': ['cancelled'], 'requires': ['technician'], 'can_enter': true, 'in_queue': true},
      'cancelled': {'status': 'cancelled', 'order': 9, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': canEnterCancelled, 'in_queue': false},
    }[status]!;

Map<String, Object?> _technician(int id, String name, {bool active = true}) => {
      'id': id,
      'user_id': id + 100,
      'full_name': name,
      'email': '${name.split(' ').first.toLowerCase()}@x.co',
      'specialization': 'Redes',
      'is_available': true,
      'is_active': active,
      'created_at': '2026-10-01T10:00:00Z',
    };

const _titles = {1: 'Laptop sin encender', 2: 'Teclado sin respuesta', 3: 'Proyector parpadea'};

void main() {
  late FakeAdapter adapter;

  /// Estado de cada solicitud en el «servidor»: los movimientos aceptados lo cambian y el
  /// listado lo refleja. `null` es una solicitud que ya no está en la cola.
  late Map<int, String?> statusOf;
  late Map<int, bool> canAct;
  late bool canEnterTriaged;
  late bool canEnterCancelled;
  late ResponseBody Function(RequestOptions) postHandler;

  setUp(() {
    statusOf = {1: 'submitted', 2: 'submitted', 3: 'triaged'};
    canAct = {1: true, 2: true, 3: true};
    canEnterTriaged = true;
    canEnterCancelled = true;
    postHandler = (_) => jsonResponse(200, detailJson());
    adapter = FakeAdapter((options) {
      switch (options.path) {
        case '/maintenance/queue/summary':
          return jsonResponse(200, summaryJson);
        case '/maintenance/requests/workflow':
          return jsonResponse(200, [for (final s in ['submitted', 'triaged', 'assigned', 'cancelled']) _state(s, canEnterTriaged: canEnterTriaged, canEnterCancelled: canEnterCancelled)]);
        case '/maintenance/categories':
          return jsonResponse(200, [
            {'code': 'software', 'name': 'Software'},
            {'code': 'network', 'name': 'Red'},
          ]);
        case '/priorities':
          return jsonResponse(200, [
            {'id': 1, 'code': 'low', 'name': 'Baja', 'level': 1},
            {'id': 2, 'code': 'high', 'name': 'Alta', 'level': 3},
          ]);
        case '/technicians':
          return pagedResponse([_technician(5, 'Luis Técnico'), _technician(6, 'Ana Inactiva', active: false)]);
        case '/maintenance/requests/1':
          return jsonResponse(200, detailJson());
        case '/maintenance/requests/1/attachments':
          return jsonResponse(200, <Object?>[]);
        case '/maintenance/requests':
          final status = options.queryParameters['status'];
          final items = [
            for (final entry in statusOf.entries)
              if (entry.value == status) {...ticketJson(id: entry.key, status: entry.value!, priority: 'high', title: _titles[entry.key]!, canAct: canAct[entry.key]!), 'created_at': '2020-01-01T00:00:00Z'},
          ];
          return pagedResponse(items);
        default:
          if (options.method == 'POST') {
            final response = postHandler(options);
            return response;
          }
          return errorResponse(404);
      }
    });
  });

  Future<void> open(WidgetTester tester, {Size size = const Size(1400, 2400), double textScale = 1}) async {
    await pumpScreen(tester, const PendingRequestsScreen(), adapter, permissions: {'solicitudes:ver_todos', 'tickets:ver', 'tecnicos:ver'}, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  Iterable<RequestOptions> posts() => adapter.requests.where((r) => r.method == 'POST');

  /// Abre el menú «Mover a…» de la tarjeta con ese título y elige [target].
  Future<void> move(WidgetTester tester, String title, String target) async {
    final card = find.ancestor(of: find.text(title), matching: find.byType(QueueCard));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('Mover a…')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text(target)));
    await tester.pumpAndSettle();
  }

  /// Los títulos de las tarjetas de una columna, de arriba abajo.
  List<String> inColumn(WidgetTester tester, String column) {
    final header = find.text(column);
    final box = tester.getRect(find.ancestor(of: header, matching: find.byType(AnimatedContainer)).first);
    return [
      for (final title in _titles.values)
        if (find.text(title).evaluate().isNotEmpty && box.contains(tester.getCenter(find.text(title)))) title,
    ];
  }

  group('menú «Mover a…»', () {
    testWidgets('ofrece los destinos que el servidor permite, con los nombres de las columnas, y rechazar', (tester) async {
      await open(tester);

      final card = find.ancestor(of: find.text('Laptop sin encender'), matching: find.byType(QueueCard));
      await tester.tap(find.descendant(of: card, matching: find.byTooltip('Mover a…')));
      await tester.pumpAndSettle();

      final items = find.byType(PopupMenuItem<String>);
      expect(find.descendant(of: items, matching: find.text('Clasificadas')), findsOneWidget);
      expect(find.descendant(of: items, matching: find.text('Asignadas')), findsOneWidget);
      expect(find.descendant(of: items, matching: find.text('Rechazar')), findsOneWidget);
      expect(find.descendant(of: items, matching: find.text('Recibidas')), findsNothing, reason: 'ya está ahí');
    });

    testWidgets('sin permiso para entrar en un estado, ese destino no se ofrece', (tester) async {
      canEnterTriaged = false;
      canEnterCancelled = false;
      await open(tester);

      final card = find.ancestor(of: find.text('Laptop sin encender'), matching: find.byType(QueueCard));
      await tester.tap(find.descendant(of: card, matching: find.byTooltip('Mover a…')));
      await tester.pumpAndSettle();

      final items = find.byType(PopupMenuItem<String>);
      expect(find.descendant(of: items, matching: find.text('Asignadas')), findsOneWidget);
      expect(find.descendant(of: items, matching: find.text('Clasificadas')), findsNothing);
      expect(find.descendant(of: items, matching: find.text('Rechazar')), findsNothing);
    });

    testWidgets('una solicitud sobre la que no se puede actuar no tiene menú ni se arrastra', (tester) async {
      canAct[2] = false;
      await open(tester);

      final card = find.ancestor(of: find.text('Teclado sin respuesta'), matching: find.byType(QueueCard));
      expect(find.descendant(of: card, matching: find.byTooltip('Mover a…')), findsNothing);
      expect(find.ancestor(of: card, matching: find.byType(LongPressDraggable<Object>)), findsNothing);
    });
  });

  group('clasificar', () {
    testWidgets('pide categoría y prioridad, manda classify, mueve la tarjeta y refresca las cifras', (tester) async {
      postHandler = (options) {
        statusOf[1] = 'triaged';
        return jsonResponse(200, detailJson(status: 'triaged'));
      };
      await open(tester);
      adapter.requests.clear();

      await move(tester, 'Laptop sin encender', 'Clasificadas');
      expect(find.text('Clasificar solicitud'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar triaje')).onPressed, isNull, reason: 'falta la categoría');
      await tester.tap(find.byKey(const Key('field-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Software'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Alta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar triaje'));
      await tester.pumpAndSettle();

      final post = posts().single;
      expect(post.path, '/maintenance/requests/1/classify');
      expect(post.data, {'category': 'software', 'priority': 'high'});
      expect(find.text('TCK-0001 pasó a «Clasificadas».'), findsOneWidget);
      expect(inColumn(tester, 'Clasificadas'), contains('Laptop sin encender'));
      expect(inColumn(tester, 'Recibidas'), isNot(contains('Laptop sin encender')));
      expect(adapter.requests.where((r) => r.path == '/maintenance/queue/summary'), hasLength(1), reason: 'las cifras se recargan');
    });

    testWidgets('cancelar la hoja deja la tarjeta donde estaba y no pide nada', (tester) async {
      await open(tester);
      adapter.requests.clear();

      await move(tester, 'Laptop sin encender', 'Clasificadas');
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(posts(), isEmpty);
      expect(adapter.requests.where((r) => r.path == '/maintenance/queue/summary'), isEmpty);
      expect(inColumn(tester, 'Recibidas'), contains('Laptop sin encender'));
    });
  });

  group('asignar', () {
    testWidgets('ofrece solo técnicos activos y manda assignment', (tester) async {
      postHandler = (_) {
        statusOf[2] = 'assigned';
        return jsonResponse(200, detailJson(status: 'assigned'));
      };
      await open(tester);

      await move(tester, 'Teclado sin respuesta', 'Asignadas');
      expect(find.text('Asignar técnico'), findsWidgets);
      expect(find.text('Luis Técnico'), findsOneWidget);
      expect(find.text('Ana Inactiva'), findsNothing);
      await tester.tap(find.text('Luis Técnico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar a Luis Técnico'));
      await tester.pumpAndSettle();

      expect(posts().single.path, '/maintenance/requests/2/assignment');
      expect(posts().single.data, {'technician_id': 5});
      expect(find.text('TCK-0002 pasó a «Asignadas».'), findsOneWidget);
      expect(inColumn(tester, 'Asignadas'), contains('Teclado sin respuesta'));
    });

    testWidgets('si el técnico resulta inactivo en el servidor la tarjeta vuelve a su columna y se explica', (tester) async {
      postHandler = (_) => errorResponse(409, code: 'technician_inactive');
      await open(tester);

      await move(tester, 'Teclado sin respuesta', 'Asignadas');
      await tester.tap(find.text('Luis Técnico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar a Luis Técnico'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ese técnico está inactivo'), findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(inColumn(tester, 'Recibidas'), contains('Teclado sin respuesta'));
      expect(inColumn(tester, 'Asignadas'), isEmpty);
    });
  });

  group('rechazar', () {
    testWidgets('pide el motivo: sin motivo o muy corto no se manda; con motivo usa reject y la tarjeta sale', (tester) async {
      postHandler = (_) {
        statusOf[1] = null;
        return jsonResponse(200, detailJson(status: 'cancelled'));
      };
      await open(tester);

      await move(tester, 'Laptop sin encender', 'Rechazar');
      expect(find.text('Rechazar solicitud'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe el motivo del rechazo.'), findsOneWidget);
      expect(posts(), isEmpty);

      await tester.enterText(find.byType(TextField).last, ' abc ');
      await tester.pumpAndSettle();
      expect(find.text('El motivo debe tener al menos 5 caracteres.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
      await tester.pumpAndSettle();
      expect(posts(), isEmpty);

      await tester.enterText(find.byType(TextField).last, '  Duplicada de TCK-0009 ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
      await tester.pumpAndSettle();

      expect(posts().single.path, '/maintenance/requests/1/reject');
      expect(posts().single.data, {'reason': 'Duplicada de TCK-0009'});
      expect(find.text('TCK-0001 fue rechazada.'), findsOneWidget);
      expect(find.text('Laptop sin encender'), findsNothing);
    });

    testWidgets('si el servidor lo niega, la tarjeta vuelve a su sitio con el aviso', (tester) async {
      postHandler = (_) => errorResponse(403, code: 'forbidden');
      await open(tester);

      await move(tester, 'Laptop sin encender', 'Rechazar');
      await tester.enterText(find.byType(TextField).last, 'Motivo suficiente');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No tienes permiso'), findsOneWidget);
      expect(inColumn(tester, 'Recibidas'), contains('Laptop sin encender'));
    });

    testWidgets('sin red avisa y no pierde la tarjeta', (tester) async {
      postHandler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      await open(tester);

      await move(tester, 'Laptop sin encender', 'Rechazar');
      await tester.enterText(find.byType(TextField).last, 'Motivo suficiente');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No pudimos conectar'), findsOneWidget);
      expect(inColumn(tester, 'Recibidas'), contains('Laptop sin encender'));
    });
  });

  group('arrastrar', () {
    /// Pulsación larga sobre la tarjeta [title] y suelta sobre el encabezado de [column].
    Future<void> drag(WidgetTester tester, String title, String column) async {
      final target = find.text(column);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(find.text(title)));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('soltar en una columna válida pide los datos que esa columna exige', (tester) async {
      await open(tester);

      await drag(tester, 'Laptop sin encender', 'Asignadas');

      expect(find.text('Asignar técnico'), findsWidgets);
      expect(find.text('Luis Técnico'), findsOneWidget);
      expect(posts(), isEmpty, reason: 'todavía no se confirmó');
    });

    testWidgets('mientras se arrastra, las columnas válidas muestran «Suelta aquí» y las otras no', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Laptop sin encender')));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Suelta aquí'), findsOneWidget, reason: 'Asignadas está vacía y es un destino válido');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Suelta aquí'), findsNothing);
    });

    testWidgets('soltar donde el rol no puede entrar devuelve la tarjeta y lo explica, sin pedir nada', (tester) async {
      canEnterTriaged = false;
      await open(tester);

      await drag(tester, 'Laptop sin encender', 'Clasificadas');

      expect(find.text('Tu rol no puede pasar solicitudes a «Clasificadas».'), findsOneWidget);
      expect(find.text('Clasificar solicitud'), findsNothing);
      expect(posts(), isEmpty);
      expect(inColumn(tester, 'Recibidas'), contains('Laptop sin encender'));
    });

    testWidgets('soltar en una columna a la que el flujo no permite pasar lo explica', (tester) async {
      await open(tester);

      // De Asignadas no se vuelve a Clasificadas: se prueba con la clasificada, que no puede ir a Recibidas.
      await drag(tester, 'Proyector parpadea', 'Recibidas');

      expect(find.text('Ese cambio de estado no está permitido para esta solicitud.'), findsOneWidget);
      expect(posts(), isEmpty);
      expect(inColumn(tester, 'Clasificadas'), contains('Proyector parpadea'));
    });

    testWidgets('soltar en la misma columna no hace nada', (tester) async {
      await open(tester);

      await drag(tester, 'Laptop sin encender', 'Recibidas');

      expect(posts(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('tocar una tarjeta abre el detalle de esa solicitud', (tester) async {
    await open(tester);
    adapter.requests.clear();

    await tester.tap(find.text('Laptop sin encender'));
    await tester.pumpAndSettle();

    expect(adapter.requests.any((r) => r.path == '/maintenance/requests/1'), isTrue);
    expect(find.text('Detalle del ticket'), findsOneWidget);
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('menú y hoja de rechazo en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);
        final page = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('Laptop sin encender'), 300, scrollable: page);
        await tester.pumpAndSettle();

        await move(tester, 'Laptop sin encender', 'Rechazar');
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(FilledButton, 'Rechazar solicitud'));
        await tester.pumpAndSettle();
        expect(find.text('Escribe el motivo del rechazo.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('hojas de clasificar y asignar en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);
        final page = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('Laptop sin encender'), 300, scrollable: page);
        await tester.pumpAndSettle();

        await move(tester, 'Laptop sin encender', 'Clasificadas');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pumpAndSettle();
        await move(tester, 'Laptop sin encender', 'Asignadas');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
