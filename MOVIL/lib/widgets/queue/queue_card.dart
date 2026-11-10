import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/requests/request_models.dart';
import 'queue_tones.dart';

/// Tarjeta de una solicitud en una columna: número, cuánto lleva esperando, título, equipo,
/// prioridad y categoría. Los nombres salen de las tablas del servidor.
class QueueCard extends StatelessWidget {
  const QueueCard({super.key, required this.ticket, required this.now, required this.priorities, required this.categoryNames, this.dimmed = false, this.onTap, this.moveTargets = const [], this.onMove});

  final TicketListItem ticket;

  /// Hora con la que se calcula la espera (se inyecta para poder probarla).
  final DateTime now;
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;

  /// Con un movimiento en curso la tarjeta se ve atenuada.
  final bool dimmed;
  final VoidCallback? onTap;

  /// Destinos del menú «Mover a…» (estado y nombre); sin ellos no hay menú.
  final List<({String status, String label})> moveTargets;
  final ValueChanged<String>? onMove;

  String? get _equipment {
    final equipment = ticket.equipment;
    if (equipment != null) return equipment.label;
    return ticket.equipmentId == null ? null : 'Equipo #${ticket.equipmentId}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = waitHours(ticket.createdAt, now);
    final wait = waitColors(waitTone(hours));
    final priority = priorityColors(priorityTone(ticket.priority, priorities));
    final equipment = _equipment;
    final category = categoryLabel(ticket.category, categoryNames);
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.grey)),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(ticket.ticketNumber, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800))),
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  label: 'Espera: ${formatHours(hours)}',
                  excludeSemantics: true,
                  child: _Chip(text: formatHours(hours), colors: wait, icon: Icons.schedule_rounded),
                ),
                if (moveTargets.isNotEmpty && onMove != null)
                  PopupMenuButton<String>(
                    tooltip: 'Mover a…',
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.steel),
                    padding: EdgeInsets.zero,
                    onSelected: onMove,
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(enabled: false, height: 32, child: Text('Mover a…', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700))),
                      for (final target in moveTargets) PopupMenuItem<String>(value: target.status, child: Text(target.label)),
                    ],
                  ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(ticket.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
              if (equipment != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  const Icon(Icons.desktop_windows_outlined, size: 14, color: AppColors.slate),
                  const SizedBox(width: 6),
                  Expanded(child: Text(equipment, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
                ]),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _Chip(text: priorityName(ticket.priority, priorities), colors: priority),
                _Chip(text: category, colors: StatusColors.closed, icon: Icons.sell_outlined),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.colors, this.icon});

  final String text;
  final ChipColors colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: colors.foreground), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800))),
        ]),
      );
}
