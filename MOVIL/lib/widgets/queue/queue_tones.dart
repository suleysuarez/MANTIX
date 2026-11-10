
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

/// Variación contra el periodo anterior: buena, mala o neutra.
ChipColors changeColors(ChangeTone tone) => switch (tone) {
      ChangeTone.good => StatusColors.resolved,
      ChangeTone.bad => StatusColors.inProgress,
      ChangeTone.neutral => StatusColors.closed,
    };

/// Prioridad por su posición (0 la más urgente) entre las prioridades del servidor.
ChipColors priorityColors(int tone) => switch (tone) {
      0 => StatusColors.critical,
      1 => StatusColors.high,
      2 => StatusColors.medium,
      _ => StatusColors.low,
    };
