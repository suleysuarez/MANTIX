import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import 'maintenance_tones.dart';

/// El calendario de un mes en una tarjeta: flechas para cambiar de mes, la semana de lunes a
/// domingo y cada día con sus servicios marcados (un punto por tipo: vencido, programado o hecho).
/// Hoy va en un círculo navy y el día elegido con borde. Tocar un día llama a [onSelect] con su
/// clave. Mientras carga muestra una barra; si falla, el motivo con «Reintentar».
class MaintenanceCalendarCard extends StatelessWidget {
  const MaintenanceCalendarCard({
    super.key,
    required this.anchor,
    required this.today,
    required this.byDay,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
    this.selectedKey,
    this.loading = false,
    this.truncated = false,
    this.errorMessage,
    this.onToday,
    this.onRetry,
  });

  final DateTime anchor;
  final DateTime today;
  final Map<String, List<CalendarEvent>> byDay;
  final String? selectedKey;
  final bool loading;

  /// El servidor llegó a su tope: puede haber más servicios de los que se ven.
  final bool truncated;
  final String? errorMessage;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onSelect;

  /// Vuelve al mes de hoy; el botón solo sale cuando se mira otro mes.
  final VoidCallback? onToday;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = monthGrid(anchor, today: today);
    final inThisMonth = anchor.year == today.year && anchor.month == today.month;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SizedBox(height: 3, child: loading ? const LinearProgressIndicator(minHeight: 3, color: AppColors.mustard, backgroundColor: AppColors.skyLight) : null),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, 0),
          child: Row(children: [
            IconButton(tooltip: 'Mes anterior', onPressed: onPrevious, color: AppColors.navy, icon: const Icon(Icons.chevron_left_rounded, size: 28)),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(header: true, child: FittedBox(fit: BoxFit.scaleDown, child: Text(monthTitle(anchor), style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
                if (!inThisMonth && onToday != null) TextButton(onPressed: onToday, style: TextButton.styleFrom(minimumSize: const Size(48, 32), padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('Ir a hoy')),
              ]),
            ),
            IconButton(tooltip: 'Mes siguiente', onPressed: onNext, color: AppColors.navy, icon: const Icon(Icons.chevron_right_rounded, size: 28)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.sm),
          child: Column(children: [
            Container(
              decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .45), borderRadius: AppRadius.smAll),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                for (final label in weekdayLabels)
                  Expanded(child: ExcludeSemantics(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))))),
              ]),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (var row = 0; row < days.length ~/ 7; row++)
              Row(children: [
                for (final day in days.sublist(row * 7, row * 7 + 7))
                  Expanded(child: _DayCell(day: day, events: byDay[day.key] ?? const [], selected: day.key == selectedKey, onTap: () => onSelect(day.key))),
              ]),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(children: [
                  const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(errorMessage!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
                  if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
                ]),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.slate),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Hay más servicios de los que se muestran en este mes.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
                ]),
              ),
            const SizedBox(height: AppSpacing.sm),
            const _Legend(),
          ]),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.events, required this.selected, required this.onTap});

  final CalendarDay day;
  final List<CalendarEvent> events;
  final bool selected;
  final VoidCallback onTap;

  static const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  String get _label {
    final date = '${day.date.day} de ${_months[day.date.month - 1]}';
    final count = events.length;
    return [if (day.today) 'Hoy', date, if (count == 0) 'sin servicios' else (count == 1 ? '1 servicio' : '$count servicios')].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = {for (final event in events) event.kind};
    final tint = day.inMonth ? dayTint(kinds) : null;
    final numberColor = day.today ? AppColors.white : (day.inMonth ? AppColors.navy : AppColors.slate.withValues(alpha: .7));
    return Semantics(
      button: true,
      selected: selected,
      label: _label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: Container(
          height: 48,
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: AppRadius.smAll,
            border: selected ? Border.all(color: AppColors.navy, width: 2) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              alignment: Alignment.center,
              decoration: day.today ? const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle) : null,
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('${day.date.day}', style: theme.textTheme.bodyMedium?.copyWith(color: numberColor, fontWeight: day.today || tint != null ? FontWeight.w800 : FontWeight.w600))),
            ),
            SizedBox(
              height: 7,
              child: kinds.isEmpty || !day.inMonth
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final kind in CalendarKind.values)
                        if (kinds.contains(kind)) Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: markerColor(kind), shape: BoxShape.circle)),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Qué significa cada punto del calendario.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w600);
    Widget item(CalendarKind kind, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: markerColor(kind), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: style),
        ]);
    return ExcludeSemantics(
      child: Wrap(alignment: WrapAlignment.center, spacing: AppSpacing.md, runSpacing: 4, children: [
        item(CalendarKind.planned, 'Programado'),
        item(CalendarKind.overdue, 'Vencido'),
        item(CalendarKind.done, 'Hecho'),
      ]),
    );
  }
}

/// Título de un día para los títulos de sección: «13 oct 2026».
String dayHeading(String key) => formatDate(DateTime.parse(key));
