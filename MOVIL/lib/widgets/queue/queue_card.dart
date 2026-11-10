import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/requests/request_models.dart';
import 'queue_tones.dart';

/// Tarjeta de una solicitud en una columna: número, cuánto lleva esperando, título, equipo,
/// prioridad y categoría. Los nombres salen de las tablas del servidor. Es compacta: con tres
/// columnas en una pantalla de teléfono cada una mide un tercio del ancho, así que todo se
/// apila y se acorta con puntos suspensivos en vez de desbordar.
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
    final hasMenu = moveTargets.isNotEmpty && onMove != null;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: wait.dot.withValues(alpha: .55), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 4, 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(ticket.ticketNumber, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800))),
                if (hasMenu)
                  PopupMenuButton<String>(
                    tooltip: 'Mover a…',
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.steel),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    // Solo el botón es pequeño: `constraints` también achicaría el menú desplegado.
                    style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), maximumSize: const Size(32, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onSelected: onMove,
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(enabled: false, height: 32, child: Text('Mover a…', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700))),
                      for (final target in moveTargets) PopupMenuItem<String>(value: target.status, child: Text(target.label)),
                    ],
                  )
                else
                  const SizedBox(height: 32),
              ]),
              Semantics(
                label: 'Espera: ${formatHours(hours)}',
                excludeSemantics: true,
                child: _Chip(text: formatHours(hours), colors: wait, icon: Icons.schedule_rounded),
              ),
              const SizedBox(height: 6),
              Text(ticket.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
              if (equipment != null) ...[
                const SizedBox(height: 4),
                Text(equipment, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel)),
              ],
              const SizedBox(height: 6),
              _Chip(text: priorityName(ticket.priority, priorities), colors: priority),
              const SizedBox(height: 4),
              _Chip(text: category, colors: skyChip, icon: Icons.sell_outlined),
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
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 11, color: colors.foreground), const SizedBox(width: 3)],
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800))),
          ]),
        ),
      );
}
