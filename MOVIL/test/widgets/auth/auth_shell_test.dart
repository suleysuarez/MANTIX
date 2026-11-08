import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/widgets/auth/auth_shell.dart';

void main() {
  Future<void> pumpAuthShell(
    WidgetTester tester, {
    required Size size,
    double keyboardInset = 0,
    double contentHeight = 760,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthShell(
          child: SizedBox(
            height: contentHeight,
            child: const Center(child: Text('Clerk sign-in content')),
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
  // login.webp mide 941 x 1672 y se pinta con BoxFit.cover, alineado arriba.
  double logoBottom(Size screen) {
    final scale = [screen.width / 941, screen.height / 1672].reduce((a, b) => a > b ? a : b);
    return 1672 * scale * AuthTokens.logoBottomFraction;
  }

  testWidgets('el contenido empieza debajo del logo y se recorta ahí', (tester) async {
    const screen = Size(393, 852);
    await pumpAuthShell(tester, size: screen);

    final scrollTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(scrollTop, greaterThanOrEqualTo(logoBottom(screen)));
    expect(
      find.ancestor(of: find.byType(SingleChildScrollView), matching: find.byType(ClipRect)),
      findsWidgets,
    );
  });

  testWidgets('arrastrar un contenido alto no sube la zona sobre el logo', (tester) async {
    const screen = Size(393, 852);
    await pumpAuthShell(tester, size: screen, contentHeight: 1200);
    final before = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byType(SingleChildScrollView)).dy, before);
    expect(before, greaterThanOrEqualTo(logoBottom(screen)));
  });

  testWidgets('si el contenido cabe, no se puede mover', (tester) async {
    await pumpAuthShell(tester, size: const Size(393, 852), contentHeight: 300);

    final scrollable = find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable)).first;
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, 0);
    final textBefore = tester.getTopLeft(find.text('Clerk sign-in content'));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Clerk sign-in content')), textBefore);
  });
}
