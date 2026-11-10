import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/widgets/home/mantix_drawer.dart';

import '../../support/fakes.dart';
import '../../support/header_support.dart';
import '../../support/requests_support.dart';

void main() {
  Future<void> openMenu(WidgetTester tester, Set<String> permissions) async {
    final profile = testProfile(permissions: permissions);
    await pumpScreen(
      tester,
      Scaffold(drawer: MantixDrawer(profile: profile, selectedPath: '/inicio/dashboard-global'), body: const SizedBox()),
      FakeAdapter((_) => errorResponse(404)),
      permissions: permissions,
      size: const Size(400, 900),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('quien ve todas las solicitudes tiene «Solicitudes pendientes» y no «Mis solicitudes»', (tester) async {
    await openMenu(tester, {'solicitudes:ver', 'solicitudes:ver_todos'});

    expect(find.text('Solicitudes pendientes'), findsOneWidget);
    expect(find.text('Mis solicitudes'), findsNothing);
    expect(find.text('Solicitudes'), findsNothing);
  });

  testWidgets('quien solo ve las suyas tiene «Mis solicitudes» y no «Solicitudes pendientes»', (tester) async {
    await openMenu(tester, {'solicitudes:ver'});

    expect(find.text('Mis solicitudes'), findsOneWidget);
    expect(find.text('Solicitudes pendientes'), findsNothing);
  });

  testWidgets('sin permisos de solicitudes no sale ninguna de las dos', (tester) async {
    await openMenu(tester, {'tickets:ver'});

    expect(find.text('Mis solicitudes'), findsNothing);
    expect(find.text('Solicitudes pendientes'), findsNothing);
  });
}
