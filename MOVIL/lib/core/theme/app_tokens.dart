import 'package:flutter/widgets.dart';

/// Medidas compartidas. Los widgets no usan números sueltos para espaciado ni radios.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Margen lateral de las pantallas.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg, vertical: lg);
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Medidas de la pantalla de acceso (imagen única de fondo con el logo dentro).
abstract final class AuthLayout {
  /// Ancho máximo del contenido (tablets).
  static const double maxWidth = 420;

  /// Tamaño en píxeles de `login.webp`; da la proporción para ubicar el logo.
  static const double imageWidth = 941;
  static const double imageHeight = 1672;

  /// El logo de la imagen termina al 38 % de su altura; la tarjeta empieza debajo.
  static const double logoBottomFraction = 0.38;

  /// Aire entre el logo y la tarjeta.
  static const double logoGap = AppSpacing.lg;

  /// Parte inferior de la pantalla que cubre el degradado.
  static const double scrimHeightFraction = 0.6;
}
