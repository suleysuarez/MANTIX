import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/domain/ticket_meta.dart';
import 'package:mantix/core/theme/app_colors.dart';

/// Relación de contraste WCAG entre dos colores.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('contraste WCAG AA (4.5:1)', () {
    test('el texto de cada chip se lee sobre su fondo', () {
      for (final colors in StatusColors.all) {
        expect(
          contrast(colors.foreground, colors.background),
          greaterThanOrEqualTo(4.5),
          reason: 'texto ${colors.foreground} sobre ${colors.background}',
        );
      }
    });

    test('texto blanco sobre los botones principales', () {
      expect(contrast(AppColors.white, AppColors.steel), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.white, AppColors.navy), greaterThanOrEqualTo(4.5));
    });

    test('texto navy sobre el color de acento y sobre el fondo', () {
      expect(contrast(AppColors.navy, AppColors.mustard), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.navy, AppColors.canvas), greaterThanOrEqualTo(4.5));
    });
  });

  group('estados', () {
    test('cada estado conocido tiene etiqueta en español', () {
      const expected = {
        'submitted': 'Enviado',
        'triaged': 'En triaje',
        'assigned': 'Asignado',
        'in_progress': 'En proceso',
        'waiting': 'En espera',
        'resolved': 'Resuelto',
        'closed': 'Cerrado',
        'cancelled': 'Cancelado',
      };
      expect(knownStatuses.toSet(), expected.keys.toSet());
      for (final entry in expected.entries) {
        expect(statusMeta(entry.key).label, entry.value);
      }
    });

    test('solo los cancelados se tachan', () {
      for (final code in knownStatuses) {
        expect(statusMeta(code).strikethrough, code == 'cancelled');
      }
    });

    test('un estado desconocido se muestra tal cual, en neutro', () {
      final meta = statusMeta('estado_nuevo');
      expect(meta.label, 'estado_nuevo');
      expect(meta.colors, StatusColors.unknown);
    });
  });

  group('prioridades', () {
    test('cada prioridad conocida tiene etiqueta en español', () {
      expect([for (final c in knownPriorities) priorityMeta(c).label], ['Crítica', 'Alta', 'Media', 'Baja']);
    });

    test('una prioridad desconocida no rompe', () {
      expect(priorityMeta('urgente').label, 'urgente');
    });
  });
}
