import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_colors.dart';

/// La página marcada en el paginador: el número dentro del círculo mostaza, o `null` si no hay.
int? selectedPage(WidgetTester tester) {
  final circle = find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration && decoration.color == AppColors.mustard && decoration.shape == BoxShape.circle;
  });
  if (circle.evaluate().isEmpty) return null;
  final text = find.descendant(of: circle.first, matching: find.byType(Text));
  return int.tryParse(tester.widget<Text>(text).data ?? '');
}
