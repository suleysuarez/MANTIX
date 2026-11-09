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

  /// Base de la pantalla de acceso: fondo si falta la imagen y final del degradado
  /// que da legibilidad a la tarjeta.
  static const Color authBase = navy;

  /// Opacidad máxima del degradado inferior de la pantalla de acceso.
  static const double authScrimOpacity = 0.7;
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


abstract final class AuthTokens {
  static const Color bgDeep = Color(0xFF050B1A);
  static const Color glassFillTop = Color(0xFF0B2F6B);
  static const Color glassFillBottom = Color(0xFF071A3D);
  static const Color glassBorder = Color(0xFF38D6FF);
  static const Color accent = Color(0xFF22D3EE);
  static const Color buttonFill = Color(0xCC061B3A);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Color(0xB3FFFFFF);
  static const Color error = Color(0xFFFF8A80);
  static const Color glassBorderSoft = Color(0x5938D6FF);

  static const double maxCardWidth = 420;
  // Measured fraction of login.webp occupied by the logo, through its baseline.
  static const double logoBottomFraction = 0.31;
  static const double logoClearance = 16;
  static const double cardRadius = 28;
}


/// Tonos del catálogo de equipos (los mismos cuatro que la web) más uno informativo.
abstract final class EquipmentColors {
  static const ChipColors ok = ChipColors(background: Color(0xFFECFDF5), foreground: Color(0xFF047857), dot: Color(0xFF10B981));
  static const ChipColors warn = ChipColors(background: Color(0xFFFFFBEB), foreground: Color(0xFFB45309), dot: AppColors.mustard);
  static const ChipColors bad = ChipColors(background: Color(0xFFFFF1F2), foreground: Color(0xFFBE123C), dot: Color(0xFFF43F5E));
  static const ChipColors neutral = ChipColors(background: Color(0xFFF1F5F9), foreground: Color(0xFF475569), dot: Color(0xFF94A3B8));
  static const ChipColors info = ChipColors(background: Color(0xFFF0F9FF), foreground: Color(0xFF0369A1), dot: Color(0xFF0EA5E9));
}
