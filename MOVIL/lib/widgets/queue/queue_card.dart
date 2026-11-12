import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import 'queue_tones.dart';

/// Tarjeta de una solicitud en una columna: solo el nombre del ticket y cuánto lleva
/// esperando. Lo demás (equipo, prioridad, categoría…) está en el detalle, que se abre al
/// tocarla. Es compacta: con tres columnas en un teléfono cada una mide un tercio del ancho.
class QueueCard extends StatelessWidget {
  const QueueCard({super.key, required this.ticket, required this.now, this.dimmed = false, this.onTap, this.moveTargets = const [], this.onMove});

  final TicketListItem ticket;

  /// Hora con la que se calcula la espera (se inyecta para poder probarla).
  final DateTime now;

  /// Con un movimiento en curso la tarjeta se ve atenuada.
  final bool dimmed;
  final VoidCallback? onTap;

  /// Destinos del menú «Mover a…» (estado y nombre); sin ellos no hay menú.
  final List<({String status, String label})> moveTargets;
  final ValueChanged<String>? onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = waitHours(ticket.createdAt, now);
    final wait = waitColors(waitTone(hours));
    final hasMenu = moveTargets.isNotEmpty && onMove != null;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .8))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 2, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(ticket.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
                  ),
                ),
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
                  ),
              ]),
              const SizedBox(height: 6),
              Semantics(
                label: 'Espera: ${formatHours(hours)}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: wait.background, borderRadius: AppRadius.pillAll),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, size: 11, color: wait.foreground),
                    const SizedBox(width: 3),
                    Flexible(child: Text(formatHours(hours), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: wait.foreground, fontWeight: FontWeight.w800))),
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
