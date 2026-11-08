import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/features/requests/presentation/equipment_picker_screen.dart';

import '../../support/fakes.dart';
import 'support.dart';

void main() {
  testWidgets('lista los equipos sin mostrar custodio ni ubicación', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([equipmentJson()]));
    await pumpScreen(tester, const EquipmentPickerScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Otra Persona'), findsNothing);
  });

  testWidgets('la búsqueda espera a que se deje de escribir y envía una sola petición', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([equipmentJson()]));
    await pumpScreen(tester, const EquipmentPickerScreen(debounce: Duration(milliseconds: 300)), adapter);
    await tester.pumpAndSettle();
    final before = adapter.requests.length;

    await tester.enterText(find.byType(TextField), 'E');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'EQ-00');
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests.length, before, reason: 'aún no pasó la espera');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final searches = adapter.requests.skip(before).toList();
    expect(searches, hasLength(1));
    expect(searches.single.queryParameters['search'], 'EQ-00');
  });

  testWidgets('sin resultados explica cómo seguir', (tester) async {
    final adapter = FakeAdapter((options) =>
        options.queryParameters.containsKey('search') ? pagedResponse([]) : pagedResponse([equipmentJson()]));
    await pumpScreen(tester, const EquipmentPickerScreen(debounce: Duration.zero), adapter);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No encontramos equipos'), findsOneWidget);
    expect(find.text('Prueba con otra etiqueta, serie, marca o modelo.'), findsOneWidget);
  });

  testWidgets('un error permite reintentar', (tester) async {
    var fail = true;
    final adapter = FakeAdapter((_) => fail ? errorResponse(500) : pagedResponse([equipmentJson()]));
    await pumpScreen(tester, const EquipmentPickerScreen(), adapter);
    await tester.pumpAndSettle();
    expect(find.text('Algo salió mal'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget);
  });

  testWidgets('al elegir un equipo se devuelve a quien abrió el selector', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([equipmentJson()]));
    EquipmentOption? picked;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await Navigator.of(context).push<EquipmentOption>(
            MaterialPageRoute(builder: (_) => const EquipmentPickerScreen()),
          ),
          child: const Text('abrir'),
        ),
      ),
      adapter,
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EQ-0012 · Dell Latitude'));
    await tester.pumpAndSettle();

    expect(picked?.id, 12);
    expect(picked?.assetTag, 'EQ-0012');
  });
}
