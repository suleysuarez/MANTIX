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

  testWidgets('envía los datos recortados y abre el detalle del ticket creado', (tester) async {
    final adapter = server(onCreate: (_) => jsonResponse(201, detailJson(id: 7, status: 'submitted')));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
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
    expect(find.text('detalle 7'), findsOneWidget);
  });

  testWidgets('la prioridad elegida viaja en el cuerpo', (tester) async {
    final adapter = server(onCreate: (_) => jsonResponse(201, detailJson(id: 8, status: 'submitted')));
    await pumpScreen(tester, const CreateRequestScreen(), adapter);
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
}
