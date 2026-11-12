import 'package:flutter/painting.dart';

import '../../core/theme/app_colors.dart';
import '../../models/maintenance/maintenance_models.dart';

export '../../core/theme/app_colors.dart' show ChipColors;

/// Colores de mantenimiento, todos de la paleta de la marca: lo programado en azul y acero, lo
/// vencido (que pide atención) en mostaza con texto navy, lo hecho en verde y lo inactivo en gris.
/// Texto contra fondo con contraste AA, y el color nunca es la única señal: siempre va el nombre.
ChipColors get plannedTone => ChipColors(background: Color.alphaBlend(AppColors.skyLight.withValues(alpha: .55), AppColors.white), foreground: AppColors.navy, dot: AppColors.steel);

ChipColors get overdueTone => ChipColors(background: Color.alphaBlend(AppColors.mustard.withValues(alpha: .38), AppColors.white), foreground: AppColors.navy, dot: AppColors.mustard);

ChipColors get inactiveTone => ChipColors(background: Color.alphaBlend(AppColors.grey.withValues(alpha: .45), AppColors.white), foreground: AppColors.steel, dot: AppColors.slate);

ChipColors eventTone(CalendarEvent event) => switch (event.kind) {
      CalendarKind.overdue => overdueTone,
      CalendarKind.planned => plannedTone,
      CalendarKind.done => event.onTime == false ? StatusColors.inProgress : StatusColors.resolved,
    };

ChipColors scheduleTone(ScheduleState state) => switch (state) {
      ScheduleState.planned => plannedTone,
      ScheduleState.overdue => overdueTone,
      ScheduleState.inactive => inactiveTone,
    };

/// El punto que marca un día del calendario según el tipo de servicio.
Color markerColor(CalendarKind kind) => switch (kind) {
      CalendarKind.overdue => AppColors.mustard,
      CalendarKind.planned => AppColors.steel,
      CalendarKind.done => StatusColors.resolved.dot,
    };

/// El fondo suave de un día con servicios: manda lo vencido, luego lo programado y luego lo hecho.
Color? dayTint(Iterable<CalendarKind> kinds) {
  if (kinds.contains(CalendarKind.overdue)) return AppColors.mustard.withValues(alpha: .32);
  if (kinds.contains(CalendarKind.planned)) return AppColors.skyLight.withValues(alpha: .55);
  if (kinds.contains(CalendarKind.done)) return StatusColors.resolved.background;
  return null;
}
