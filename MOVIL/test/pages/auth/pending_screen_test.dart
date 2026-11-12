import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/pages/auth/pending_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/header_support.dart';
import '../../support/pump_app.dart';

void main() {
  late MockAuthBloc bloc;

  setUp(() {
    bloc = MockAuthBloc();
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthPending(testProfile()));
  });

  Future<void> open(WidgetTester tester, {Size size = const Size(900, 2000), double textScale = 1}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    await pumpApp(tester, BlocProvider<AuthBloc>.value(value: bloc, child: const PendingScreen()), textScale: textScale);
    await tester.pumpAndSettle();
  }

  testWidgets('dice que la cuenta ya está creada, a nombre de quién y que espera aprobación', (tester) async {
    await open(tester);

    expect(find.text('Cuenta pendiente de aprobación'), findsOneWidget);
    expect(find.text('¡Tu cuenta ya está creada!'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('ana@mantix.test'), findsOneWidget);
  });

  testWidgets('muestra el avance en tres pasos', (tester) async {
    await open(tester);

    expect(find.text('Cuenta creada'), findsOneWidget);
    expect(find.text('Un administrador te asigna un rol'), findsOneWidget);
    expect(find.text('Empiezas a usar Mantix'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: 'solo el primer paso está hecho');
    expect(find.byIcon(Icons.timelapse_rounded), findsOneWidget, reason: 'el segundo está en curso');
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget, reason: 'el tercero aún no llega');
  });

  testWidgets('no promete un aviso que la app no envía: explica cómo comprobar', (tester) async {
    await open(tester);

    expect(find.textContaining('Te avisaremos'), findsNothing);
    expect(find.textContaining('Volver a comprobar'), findsWidgets);
  });

  testWidgets('«Volver a comprobar» pide cargar la sesión de nuevo y «Cerrar sesión» la cierra', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Volver a comprobar'));
    verify(() => bloc.add(const AuthRefreshRequested())).called(1);

    await tester.tap(find.text('Cerrar sesión'));
    verify(() => bloc.add(const AuthSignOutRequested())).called(1);
  });

  testWidgets('los botones táctiles miden al menos 48 px', (tester) async {
    await open(tester);

    expect(tester.getSize(find.widgetWithText(FilledButton, 'Volver a comprobar')).height, greaterThanOrEqualTo(48));
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);

        expect(tester.takeException(), isNull);
        expect(find.text('Cuenta pendiente de aprobación'), findsOneWidget);
      });
    }
  });
}
