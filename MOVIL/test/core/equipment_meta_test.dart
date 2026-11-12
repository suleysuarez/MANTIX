import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/equipment_meta.dart';
import 'package:mantix/core/theme/app_colors.dart';

double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('los estados normales usan azul claro y acero; solo el que requiere atención usa mostaza y lo que está fuera de servicio, alerta', () {
    for (final code in ['in_storage', 'assigned']) {
      final colors = equipmentStatusMeta(code).colors;
      expect(colors.dot, AppColors.steel, reason: code);
      expect(colors.foreground, AppColors.navy, reason: code);
    }
    expect(equipmentStatusMeta('in_repair').colors.dot, AppColors.mustard);
    for (final code in ['lost', 'retired', 'disposed']) {
      expect(equipmentStatusMeta(code).colors.dot, AppColors.error, reason: code);
    }
  });

  test('un estado desconocido se muestra neutro y con su código', () {
    final meta = equipmentStatusMeta('nuevo_estado');
    expect(meta.label, 'nuevo_estado');
    expect(meta.colors.dot, EquipmentColors.neutral.dot);
  });

  test('el texto de cada tono se lee sobre su fondo (contraste AA, 4,5:1)', () {
    for (final entry in {
      'ok': EquipmentColors.ok,
      'warn': EquipmentColors.warn,
      'bad': EquipmentColors.bad,
      'neutral': EquipmentColors.neutral,
      'info': EquipmentColors.info,
    }.entries) {
      expect(_contrast(entry.value.foreground, entry.value.background), greaterThanOrEqualTo(4.5), reason: entry.key);
    }
  });
}
