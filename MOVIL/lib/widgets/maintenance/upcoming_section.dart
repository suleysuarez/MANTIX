import 'package:flutter/material.dart';

import '../../bloc/maintenance/upcoming_maintenance_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import 'maintenance_cards.dart';

/// «Próximos mantenimientos»: los primeros [limit] servicios (los vencidos primero) y el enlace
/// «Ver todos» a la lista de planes. Maneja cargando, vacío y error con reintento.
class UpcomingSection extends StatelessWidget {
  const UpcomingSection({super.key, required this.state, required this.onOpen, required this.onSeeAll, required this.onRetry, this.limit = 3});

  final UpcomingMaintenanceState state;
  final ValueChanged<CalendarEvent> onOpen;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = state.items.take(limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.schedule_rounded, color: AppColors.navy),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Semantics(header: true, child: Text('Próximos mantenimientos', maxLines: 2, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Ver todos'), Icon(Icons.chevron_right_rounded, size: 20)]),
        ),
      ]),
      const SizedBox(height: AppSpacing.sm),
      if (state.initialLoading)
        const MaintenanceListSkeleton(label: 'Cargando próximos mantenimientos', count: 2)
      else if (state.unavailable)
        _Message(icon: Icons.cloud_off_outlined, text: 'No pudimos cargar los próximos mantenimientos. ${state.failure?.message ?? ''}'.trim(), actionLabel: 'Reintentar', onAction: onRetry)
      else if (items.isEmpty)
        const _Message(icon: Icons.event_available_outlined, text: 'No hay mantenimientos próximos ni vencidos.')
      else
        for (final event in items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: MaintenanceEventCard(event: event, onTap: () => onOpen(event))),
    ]);
  }
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
