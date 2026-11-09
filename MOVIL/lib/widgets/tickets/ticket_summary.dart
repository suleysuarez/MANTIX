import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';

/// Banner azul con el título del módulo.
class TicketBanner extends StatelessWidget {
  const TicketBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: const BoxDecoration(
          borderRadius: AppRadius.lgAll,
          gradient: LinearGradient(colors: [AppColors.navy, AppColors.steel], begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: AppRadius.mdAll),
            child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GESTIÓN DE TICKETS', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: .4)),
              const SizedBox(height: 4),
              Text(
                'Registra, asigna, diagnostica y supervisa las incidencias técnicas y órdenes de trabajo activas.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: .85), height: 1.35),
              ),
            ]),
          ),
        ]),
      );
}

/// Cuatro contadores (total, enviados, en proceso, resueltos) de los tickets cargados.
class TicketStats extends StatelessWidget {
  const TicketStats({super.key, required this.items, required this.total});

  final List<TicketListItem> items;
  final int? total;

  @override
  Widget build(BuildContext context) {
    int count(List<String> codes) => items.where((item) => codes.contains(item.status)).length;
    final tiles = [
      _Stat('TOTAL', '${total ?? items.length}', 'Todas las órdenes', Icons.confirmation_number_outlined, StatusColors.submitted),
      _Stat('ENVIADOS', '${count(['submitted', 'triaged'])}', 'Pendientes de atender', Icons.send_rounded, StatusColors.triaged),
      _Stat('EN PROCESO', '${count(['assigned', 'in_progress', 'waiting'])}', 'Con el técnico', Icons.settings_outlined, StatusColors.inProgress),
      _Stat('RESUELTOS', '${count(['resolved', 'closed'])}', 'Solución aplicada', Icons.check_circle_outline_rounded, StatusColors.resolved),
    ];
    return Column(children: [
      for (var row = 0; row < tiles.length; row += 2) ...[
        if (row > 0) const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatTile(tiles[row])),
          const SizedBox(width: 10),
          Expanded(child: _StatTile(tiles[row + 1])),
        ]),
      ],
    ]);
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.caption, this.icon, this.colors);
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final ChipColors colors;
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.stat);
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: stat.colors.background, borderRadius: AppRadius.smAll),
          child: Icon(stat.icon, size: 18, color: stat.colors.foreground),
        ),
        const SizedBox(height: 8),
        Text(stat.label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w800, letterSpacing: .4)),
        Text(stat.value, style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, height: 1.15)),
        Text(stat.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
      ]),
    );
  }
}
