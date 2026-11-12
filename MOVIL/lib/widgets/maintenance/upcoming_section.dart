import 'package:flutter/material.dart';

import '../../bloc/maintenance/upcoming_maintenance_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../shared/paginator.dart';
import 'maintenance_cards.dart';

/// «Próximos mantenimientos»: los primeros [limit] servicios (los vencidos primero) y el enlace
/// «Ver todos» a la lista de planes. Maneja cargando, vacío y error con reintento.
class UpcomingSection extends StatelessWidget {
  const UpcomingSection({super.key, required this.state, required this.onOpen, required this.onSeeAll, required this.onRetry, this.onRangeChanged, this.title = 'Próximos mantenimientos', this.limit = 3, this.page = 1, this.onPage});

  final UpcomingMaintenanceState state;
  final ValueChanged<CalendarEvent> onOpen;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;

  /// Si no se pasa, no se muestran los chips del rango.
  final ValueChanged<UpcomingRange>? onRangeChanged;

  /// El título de la sección; en el panel del técnico es «Mis mantenimientos».
  final String title;

  /// Cuántos servicios se ven a la vez (y, con [onPage], el tamaño de cada página).
  final int limit;

  /// Página actual (base 1). Solo cuenta si se pasa [onPage].
  final int page;

  /// Si se pasa, debajo de la lista sale el paginador numerado y esta función recibe la página elegida.
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = state.visibleItems;
    final paged = onPage != null;
    final totalPages = paged ? (all.length / limit).ceil() : 1;
    // Al cambiar el rango la lista se acorta: la página nunca queda más allá de la última.
    final current = paged && totalPages > 0 ? page.clamp(1, totalPages) : 1;
    final items = paged ? all.skip((current - 1) * limit).take(limit).toList() : all.take(limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.schedule_rounded, color: AppColors.navy),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Semantics(header: true, child: Text(title, maxLines: 2, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Ver todos'), Icon(Icons.chevron_right_rounded, size: 20)]),
        ),
      ]),
      if (onRangeChanged != null) ...[
        _RangeChips(range: state.range, onChanged: onRangeChanged!),
        const SizedBox(height: AppSpacing.sm),
      ] else
        const SizedBox(height: AppSpacing.sm),
      if (state.initialLoading)
        const MaintenanceListSkeleton(label: 'Cargando próximos mantenimientos', count: 2)
      else if (state.unavailable)
        _Message(icon: Icons.cloud_off_outlined, text: 'No pudimos cargar los próximos mantenimientos. ${state.failure?.message ?? ''}'.trim(), actionLabel: 'Reintentar', onAction: onRetry)
      else if (items.isEmpty)
        _Message(icon: Icons.event_available_outlined, text: state.range == UpcomingRange.all ? 'No hay mantenimientos próximos ni vencidos.' : 'No hay mantenimientos en este rango.')
      else
        for (final event in items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: MaintenanceEventCard(event: event, onTap: () => onOpen(event))),
      if (paged && !state.initialLoading && !state.unavailable && all.isNotEmpty) Paginator(page: current, pageSize: limit, total: all.length, totalPages: totalPages, onPage: onPage!),
    ]);
  }
}

/// «Servicios entre»: Todo, Hoy, Próx. 7 días y Próx. 30 días. El elegido va en navy.
class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.range, required this.onChanged});

  final UpcomingRange range;
  final ValueChanged<UpcomingRange> onChanged;

  static const _labels = {
    UpcomingRange.all: 'Todo',
    UpcomingRange.today: 'Hoy',
    UpcomingRange.week: 'Próx. 7 días',
    UpcomingRange.month: 'Próx. 30 días',
  };

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Servicios entre',
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          for (final entry in _labels.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: range == entry.key,
              onSelected: (_) => onChanged(entry.key),
              showCheckmark: false,
              backgroundColor: AppColors.white,
              selectedColor: AppColors.navy,
              side: BorderSide(color: range == entry.key ? AppColors.navy : AppColors.skyLight),
              labelStyle: TextStyle(color: range == entry.key ? AppColors.white : AppColors.steel, fontWeight: FontWeight.w700, fontSize: 12.5),
              visualDensity: VisualDensity.compact,
            ),
        ]),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.actionLabel, this.onAction});

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .6))),
        child: Row(children: [
          Icon(icon, color: AppColors.slate),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}
