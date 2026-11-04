import 'package:flutter/material.dart';

/// Paleta de Mantix (docs/flutter-plan.md). Es el único lugar con colores
/// literales: los widgets leen `Theme.of(context)` o estas constantes.
abstract final class AppColors {
  static const Color skyLight = Color(0xFFADD7F6);
  static const Color sky = Color(0xFFA2D2FF);
  static const Color steel = Color(0xFF3E5C76);
  static const Color slate = Color(0xFF778DA9);
  static const Color grey = Color(0xFFCED4DA);
  static const Color mustard = Color(0xFFE4B363);
  static const Color navy = Color(0xFF0B172A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFBA1A1A);

  /// Fondo de las pantallas.
  static const Color canvas = Color(0xFFF4F8FC);
}

/// Colores de un chip: fondo, texto y punto indicador.
@immutable
class ChipColors {
  const ChipColors({required this.background, required this.foreground, required this.dot});

  final Color background;
  final Color foreground;
  final Color dot;
}

/// Colores semánticos de estados y prioridades de ticket, basados en los tonos de la
/// web, con el texto de cada chip comprobado contra su fondo (contraste AA, 4.5:1).
/// El punto de «En proceso» es más oscuro que el de la web para verse sobre fondo claro.
abstract final class StatusColors {
  static const ChipColors submitted = ChipColors(
    background: Color(0xFFDBEAFE),
    foreground: Color(0xFF1E40AF),
    dot: Color(0xFF2563EB),
  );
  static const ChipColors triaged = ChipColors(
    background: Color(0xFFE0E7FF),
    foreground: Color(0xFF3730A3),
    dot: Color(0xFF4F46E5),
  );
  static const ChipColors assigned = ChipColors(
    background: Color(0xFFCFFAFE),
    foreground: Color(0xFF155E75),
    dot: Color(0xFF0891B2),
  );
  static const ChipColors inProgress = ChipColors(
    background: Color(0xFFFEF3C7),
    foreground: Color(0xFF92400E),
    dot: Color(0xFFB45309),
  );
  static const ChipColors waiting = ChipColors(
    background: Color(0xFFF3E8FF),
    foreground: Color(0xFF6B21A8),
    dot: Color(0xFF9333EA),
  );
  static const ChipColors resolved = ChipColors(
    background: Color(0xFFD1FAE5),
    foreground: Color(0xFF065F46),
    dot: Color(0xFF10B981),
  );
  static const ChipColors closed = ChipColors(
    background: Color(0xFFE2E8F0),
    foreground: Color(0xFF334155),
    dot: Color(0xFF64748B),
  );
  static const ChipColors cancelled = ChipColors(
    background: Color(0xFFF1F5F9),
    foreground: Color(0xFF475569),
    dot: Color(0xFF94A3B8),
  );

  static const ChipColors critical = ChipColors(
    background: Color(0xFFFEE2E2),
    foreground: Color(0xFF991B1B),
    dot: Color(0xFFDC2626),
  );
  static const ChipColors high = ChipColors(
    background: Color(0xFFFFEDD5),
    foreground: Color(0xFF9A3412),
    dot: Color(0xFFEA580C),
  );
  static const ChipColors medium = ChipColors(
    background: Color(0xFFDBEAFE),
    foreground: Color(0xFF1E40AF),
    dot: Color(0xFF2563EB),
  );
  static const ChipColors low = ChipColors(
    background: Color(0xFFE2E8F0),
    foreground: Color(0xFF475569),
    dot: Color(0xFF94A3B8),
  );

  /// Estado o prioridad que la app no conoce (por ejemplo, uno nuevo del backend).
  static const ChipColors unknown = closed;

  static const List<ChipColors> all = [
    submitted, triaged, assigned, inProgress, waiting, resolved, closed, cancelled,
    critical, high, medium, low,
  ];
}
