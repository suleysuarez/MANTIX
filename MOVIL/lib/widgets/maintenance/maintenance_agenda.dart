import 'package:flutter/material.dart';

import '../../core/format/maintenance_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import 'maintenance_cards.dart';

/// Agenda de un periodo (un mes o una semana): una tarjeta con flechas para cambiar de periodo y,
/// debajo, los días con sus servicios. Con [hideEmptyDays] (el mes) solo salen los días con
/// servicios; sin él (la semana) salen los siete, con «Sin servicios» en los vacíos.
///
/// Mientras carga muestra una barra; si falla, el motivo con «Reintentar». [onToday] solo se
/// ofrece cuando se mira otro periodo ([isCurrent] falso).
class MaintenanceAgenda extends StatelessWidget {
  const MaintenanceAgenda({
    super.key,
    required this.title,
    required this.days,
    required this.byDay,
    required this.today,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
    required this.previousLabel,
    required this.nextLabel,
    this.hideEmptyDays = false,
    this.isCurrent = true,
    this.loading = false,
    this.errorMessage,
    this.onToday,
    this.onRetry,
  });

  final String title;
  final List<DateTime> days;
  final Map<String, List<CalendarEvent>> byDay;
  final DateTime today;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onOpen;
  final String previousLabel;
  final String nextLabel;
  final bool hideEmptyDays;
  final bool isCurrent;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onToday;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [for (final day in days) if (!hideEmptyDays || (byDay[dayKey(day)] ?? const []).isNotEmpty) day];
    final empty = shown.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 3, child: loading ? const LinearProgressIndicator(minHeight: 3, color: AppColors.mustard, backgroundColor: AppColors.skyLight) : null),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, 0),
          child: Row(children: [
            IconButton(tooltip: previousLabel, onPressed: onPrevious, color: AppColors.navy, icon: const Icon(Icons.chevron_left_rounded, size: 28)),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(header: true, child: FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
                if (!isCurrent && onToday != null) TextButton(onPressed: onToday, style: TextButton.styleFrom(minimumSize: const Size(48, 32), padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('Ir a hoy')),
              ]),
            ),
            IconButton(tooltip: nextLabel, onPressed: onNext, color: AppColors.navy, icon: const Icon(Icons.chevron_right_rounded, size: 28)),
          ]),
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.sm, AppSpacing.sm),
            child: Row(children: [
              const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(errorMessage!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
              if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
            ]),
          )
        else if (empty && !loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
            child: Row(children: [
              const Icon(Icons.event_available_outlined, color: AppColors.slate),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('No hay servicios en este periodo.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
            child: Column(children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: AppSpacing.lg, color: AppColors.skyLight.withValues(alpha: .6)),
                _DayRow(day: shown[i], isToday: sameDay(shown[i], today), events: byDay[dayKey(shown[i])] ?? const [], onOpen: onOpen),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Un día de la agenda: a la izquierda su letra y número (hoy va en un círculo navy) y a la
/// derecha sus servicios.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.isToday, required this.events, required this.onOpen});

  final DateTime day;
  final bool isToday;
  final List<CalendarEvent> events;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = weekdayLabels[day.weekday - 1];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 44,
        child: Semantics(
          label: '${isToday ? 'Hoy, ' : ''}$label ${day.day}, ${events.isEmpty ? 'sin servicios' : events.length == 1 ? '1 servicio' : '${events.length} servicios'}',
          excludeSemantics: true,
          child: Column(children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: isToday ? const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle) : null,
              child: Text('${day.day}', style: theme.textTheme.titleSmall?.copyWith(color: isToday ? AppColors.white : AppColors.navy, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: events.isEmpty
            ? Padding(padding: const EdgeInsets.only(top: 10), child: Text('Sin servicios', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)))
            : Column(children: [for (final event in events) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: MaintenanceEventCard(event: event, onTap: () => onOpen(event.scheduleId)))]),
      ),
    ]);
  }
}

/// «6 – 12 oct 2026» o «28 sep – 4 oct 2026»: el rango de la semana que empieza en [monday].
String weekTitle(DateTime monday) {
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final sunday = addDays(monday, 6);
  final start = monday.month == sunday.month ? '${monday.day}' : '${monday.day} ${months[monday.month - 1]}';
  final end = '${sunday.day} ${months[sunday.month - 1]}';
  return monday.year == sunday.year ? '$start – $end ${sunday.year}' : '${monday.day} ${months[monday.month - 1]} ${monday.year} – $end ${sunday.year}';
}
