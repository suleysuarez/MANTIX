import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/domain/ticket_meta.dart';
import 'package:mantix/features/dev/presentation/components_gallery_screen.dart';

import '../support/pump_app.dart';

void main() {
  Future<void> useSmallPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('la galería muestra los estados y prioridades conocidos', (tester) async {
    await useSmallPhone(tester);
    await pumpApp(tester, const ComponentsGalleryScreen(), disableAnimations: true);

    for (final code in knownStatuses) {
      expect(find.text(statusMeta(code).label), findsOneWidget, reason: code);
    }
    expect(find.text('estado_nuevo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con la fuente del sistema al doble de tamaño no se desborda', (tester) async {
    await useSmallPhone(tester);
    await pumpApp(tester, const ComponentsGalleryScreen(), disableAnimations: true, textScale: 2);

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('el diálogo de confirmación se abre desde la galería', (tester) async {
    await useSmallPhone(tester);
    await pumpApp(tester, const ComponentsGalleryScreen(), disableAnimations: true);

    await tester.scrollUntilVisible(find.text('Abrir diálogo de confirmación'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Abrir diálogo de confirmación'));
    await tester.pumpAndSettle();

    expect(find.text('Cerrar ticket'), findsWidgets);
    expect(find.text('Cancelar'), findsOneWidget);
  });
}
