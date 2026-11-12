import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../core/format/maintenance_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../shared/app_chip.dart';
import '../shared/skeleton.dart';
import 'maintenance_tones.dart';

IconData _kindIcon(CalendarKind kind) => switch (kind) {
      CalendarKind.overdue => Icons.build_rounded,
      CalendarKind.planned => Icons.settings_rounded,
      CalendarKind.done => Icons.check_circle_outline_rounded,
    };

/// Un servicio del calendario: icono, título, la etiqueta del equipo, la fecha y su estado
/// (Programado, Vencido, A tiempo o Con retraso). Una barra de color a la izquierda sigue el
/// estado; el nombre del estado siempre va escrito. Tocarlo abre el plan.
class MaintenanceEventCard extends StatelessWidget {
  const MaintenanceEventCard({super.key, required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = eventTone(event);
    final label = eventLabel(event);
    return Semantics(
      button: true,
      label: '${event.title}. Equipo ${event.assetTag}. ${formatDate(event.at)}. $label',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .6))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: tone.dot),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: tone.background, shape: BoxShape.circle),
                      child: Icon(_kindIcon(event.kind), color: AppColors.navy, size: 23),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        _Meta(icon: Icons.computer_outlined, text: event.assetTag),
                        const SizedBox(height: 2),
                        _Meta(icon: Icons.calendar_today_outlined, text: formatDate(event.at)),
                        const SizedBox(height: AppSpacing.sm),
                        AppChip(label: label, colors: tone, semanticPrefix: 'Estado'),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 14, color: AppColors.slate),
        const SizedBox(width: 5),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel))),
      ]);
}

/// Un plan en la lista: título, equipo, técnico, próximo servicio, cada cuánto se repite y su
/// estado (Programado, Vencido o Inactivo).
class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key, required this.schedule, required this.now, required this.onTap});

  final MaintenanceSchedule schedule;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = schedule.stateAt(now);
    final tone = scheduleTone(state);
    final label = scheduleStateLabel(state);
    final equipment = schedule.equipment;
    return Semantics(
      button: true,
      label: '${schedule.title}. Equipo ${equipment.assetTag}. Próximo servicio ${formatDate(schedule.nextDueAt)}. ${intervalText(schedule.intervalDays)}. $label',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .6))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: tone.dot),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: tone.background, shape: BoxShape.circle),
                      child: Icon(state == ScheduleState.overdue ? Icons.build_rounded : Icons.settings_rounded, color: AppColors.navy, size: 23),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(schedule.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        _Meta(icon: Icons.computer_outlined, text: '${equipment.assetTag} · ${equipment.brand} ${equipment.model}'),
                        const SizedBox(height: 2),
                        _Meta(icon: Icons.person_outline_rounded, text: schedule.technician?.fullName ?? 'Sin técnico asignado'),
                        const SizedBox(height: 2),
                        _Meta(icon: Icons.calendar_today_outlined, text: '${formatDate(schedule.nextDueAt)} · ${intervalText(schedule.intervalDays)}'),
                        const SizedBox(height: AppSpacing.sm),
                        AppChip(label: label, colors: tone, semanticPrefix: 'Estado'),
                      ]),
                    ),
                    const Padding(padding: EdgeInsets.only(top: 12), child: Icon(Icons.chevron_right_rounded, color: AppColors.slate)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Esqueleto de una lista de tarjetas mientras carga.
class MaintenanceListSkeleton extends StatelessWidget {
  const MaintenanceListSkeleton({super.key, required this.label, this.count = 3});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: label,
        child: Column(children: [for (var i = 0; i < count; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 112, radius: AppRadius.lg))]),
      );
}
