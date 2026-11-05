import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/features/auth/presentation/widgets/auth_shell.dart';

void main() {
  Future<void> pumpAuthShell(
    WidgetTester tester, {
    required Size size,
    double keyboardInset = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthShell(
          child: SizedBox(
            height: 760,
            child: Center(child: Text('Clerk sign-in content')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('does not overflow on a tall phone', (tester) async {
    await pumpAuthShell(tester, size: const Size(393, 852));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('does not overflow on a short phone', (tester) async {
    await pumpAuthShell(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('remains scrollable with the keyboard open on a tall phone', (
    tester,
  ) async {
    await pumpAuthShell(
      tester,
      size: const Size(393, 852),
      keyboardInset: 320,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('remains scrollable with the keyboard open on a short phone', (
    tester,
  ) async {
    await pumpAuthShell(
      tester,
      size: const Size(320, 640),
      keyboardInset: 300,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
