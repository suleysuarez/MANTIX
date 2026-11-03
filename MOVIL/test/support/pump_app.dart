import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_theme.dart';

/// Monta un widget dentro de `MaterialApp` con el tema real de la app.
/// [disableAnimations] imita «reducir movimiento»; [textScale] imita una
/// fuente del sistema más grande.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
  double textScale = 1,
  bool settle = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
