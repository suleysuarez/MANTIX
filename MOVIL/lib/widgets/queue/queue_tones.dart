import 'package:flutter/painting.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';

/// Colores de la bandeja de triaje, todos tomados de los tonos de estado ya comprobados (texto
/// contra fondo con contraste AA). Ningún color suelto en los widgets.

/// Antigüedad de una solicitud: fresca, envejeciendo o vieja.
ChipColors waitColors(WaitTone tone) => switch (tone) {
      WaitTone.fresh => StatusColors.assigned,
      WaitTone.aging => StatusColors.inProgress,
      WaitTone.stale => StatusColors.critical,
    };

/// Mostaza suave de la paleta: texto navy sobre mostaza clara (contraste AA).
ChipColors get mustardChip => ChipColors(background: Color.alphaBlend(AppColors.mustard.withValues(alpha: .38), AppColors.white), foreground: AppColors.navy, dot: AppColors.mustard);

/// Azul claro de la paleta para lo neutro.
ChipColors get skyChip => ChipColors(background: Color.alphaBlend(AppColors.skyLight.withValues(alpha: .55), AppColors.white), foreground: AppColors.navy, dot: AppColors.steel);

/// Variación contra el periodo anterior: buena, mala (mostaza) o neutra (azul claro).
ChipColors changeColors(ChangeTone tone) => switch (tone) {
      ChangeTone.good => StatusColors.resolved,
      ChangeTone.bad => mustardChip,
      ChangeTone.neutral => skyChip,
    };

/// Prioridad por su posición (0 la más urgente) entre las prioridades del servidor.
ChipColors priorityColors(int tone) => switch (tone) {
      0 => StatusColors.critical,
      1 => StatusColors.high,
      2 => StatusColors.medium,
      _ => StatusColors.low,
    };
