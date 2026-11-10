import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/requests/create_request_screen.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

/// Servidor de prueba: lista equipos y crea tickets según [onCreate].
FakeAdapter server({ResponseBody Function(RequestOptions)? onCreate}) => FakeAdapter((options) {
      if (options.path == '/equipment') return pagedResponse([equipmentJson()]);
      if (options.method == 'POST') return onCreate!(options);
      return pagedResponse([]);
    });

/// Abre el formulario en su hoja inferior desde una pantalla con un botón.
Future<void> openSheet(WidgetTester tester, FakeAdapter adapter) async {
  await pumpScreen(
    tester,
    Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => CreateRequestScreen.show(context), child: const Text('abrir'))))),
    adapter,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> chooseEquipment(WidgetTester tester) async {
  await tester.tap(find.text('Elegir equipo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('EQ-0012 · Dell Latitude'));
  await tester.pumpAndSettle();
}

Future<void> fillForm(WidgetTester tester, {String title = 'No enciende', String description = 'Pantalla negra'}) async {
  await tester.enterText(find.byType(TextFormField).at(0), title);
  await tester.enterText(find.byType(TextFormField).at(1), description);
}

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Enviar solicitud'));
  await tester.tap(find.text('Enviar solicitud'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('vacío no envía nada y marca lo que falta', (tester) async {
    final adapter = server(onCreate: (_) => fail('no debe enviar'));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
    await submit(tester);

    expect(find.text('Elige el equipo con el problema.'), findsOneWidget);
    expect(find.text('El título es obligatorio.'), findsOneWidget);
    expect(find.text('La descripción es obligatoria.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('un título de solo espacios cuenta como vacío', (tester) async {
    final adapter = server(onCreate: (_) => fail('no debe enviar'));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
    await chooseEquipment(tester);
    await fillForm(tester, title: '    ', description: 'algo');
    await submit(tester);

    expect(find.text('El título es obligatorio.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('envía los datos recortados, cierra la hoja y avisa', (tester) async {
    final adapter = server(onCreate: (_) => jsonResponse(201, detailJson(id: 7, status: 'submitted')));
    await openSheet(tester, adapter);
    expect(find.text('Nueva solicitud'), findsOneWidget);
    await chooseEquipment(tester);
    await fillForm(tester, title: '  No enciende  ', description: ' Pantalla negra ');
    await submit(tester);

    final post = adapter.requests.singleWhere((r) => r.method == 'POST');
    expect(post.data, {
      'equipment_id': 12,
      'title': 'No enciende',
      'description': 'Pantalla negra',
      'priority': 'medium',
    });
    expect(find.text('Nueva solicitud'), findsNothing, reason: 'la hoja se cierra');
    expect(find.text('Solicitud creada.'), findsOneWidget);
    expect(find.text('abrir'), findsOneWidget, reason: 'la pantalla de fondo sigue');
  });

  testWidgets('la prioridad elegida viaja en el cuerpo', (tester) async {
    final adapter = server(onCreate: (_) => jsonResponse(201, detailJson(id: 8, status: 'submitted')));
    await openSheet(tester, adapter);
    await chooseEquipment(tester);
    await fillForm(tester);
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crítica').last);
    await tester.pumpAndSettle();
    await submit(tester);

    expect(adapter.requests.singleWhere((r) => r.method == 'POST').data, containsPair('priority', 'critical'));
  });

  testWidgets('un 422 del servidor se muestra bajo el campo y se borra al editarlo', (tester) async {
    final adapter = server(
      onCreate: (_) => errorResponse(422, code: 'unprocessable', errors: [
        {'field': 'title', 'message': 'El título ya existe', 'type': 'value_error'},
      ]),
    );
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
    await chooseEquipment(tester);
    await fillForm(tester);
    await submit(tester);

    expect(find.text('El título ya existe'), findsOneWidget);
    expect(find.text('Enviar solicitud'), findsOneWidget, reason: 'el formulario sigue disponible');

    await tester.enterText(find.byType(TextFormField).at(0), 'Otro título');
    await tester.pump();
    expect(find.text('El título ya existe'), findsNothing);
  });

  testWidgets('un error de servidor muestra un aviso sin detalles internos y no pierde lo escrito', (tester) async {
    final adapter = server(onCreate: (_) => errorResponse(500));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
    await chooseEquipment(tester);
    await fillForm(tester);
    await submit(tester);

    expect(find.text('Algo salió mal en el servidor. Inténtalo más tarde.'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);
    expect(find.text('No enciende'), findsOneWidget);
  });

  testWidgets('un 404 de equipo borrado muestra el mensaje específico', (tester) async {
    final adapter = server(onCreate: (_) => errorResponse(404, code: 'equipment_not_found'));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
    await chooseEquipment(tester);
    await fillForm(tester);
    await submit(tester);

    expect(find.text('Ese equipo ya no existe.'), findsOneWidget);
  });

  group('selector de equipo en su hoja', () {
    testWidgets('lista por páginas con «Ver más resultados» y sin paginador numerado', (tester) async {
      final adapter = FakeAdapter((options) {
        if (options.path == '/equipment') {
          final page = options.queryParameters['page'] as int;
          return pagedResponse([equipmentJson(id: page, tag: 'EQ-000$page')], page: page, totalPages: 2, total: 2);
        }
        return pagedResponse([]);
      });
      await openSheet(tester, adapter);
      await tester.tap(find.text('Elegir equipo'));
      await tester.pumpAndSettle();

      expect(find.text('EQ-0001 · Dell Latitude'), findsOneWidget);
      expect(find.byTooltip('Página siguiente'), findsNothing, reason: 'el formulario no lleva paginación numerada');
      await tester.tap(find.text('Ver más resultados'));
      await tester.pumpAndSettle();
      expect(find.text('EQ-0002 · Dell Latitude'), findsOneWidget);
      expect(find.text('Ver más resultados'), findsNothing);
    });

    testWidgets('buscar vuelve a pedir con el texto y elegir cierra solo el selector', (tester) async {
      final adapter = server(onCreate: (_) => fail('no debe enviar'));
      await openSheet(tester, adapter);
      await tester.tap(find.text('Elegir equipo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'dell');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.path == '/equipment').last.queryParameters['search'], 'dell');

      await tester.tap(find.text('EQ-0012 · Dell Latitude'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Equipo tecnológico', findRichText: true), findsWidgets, reason: 'el formulario sigue abierto');
      expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget);
    });
  });

  group('la hoja del formulario sin overflow con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('en ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final adapter = server(onCreate: (_) => fail('no debe enviar'));
        await pumpScreen(
          tester,
          Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => CreateRequestScreen.show(context), child: const Text('abrir'))))),
          adapter,
          size: size,
          textScale: 1.3,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Nueva solicitud'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.drag(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(ListView)).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Enviar solicitud'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
