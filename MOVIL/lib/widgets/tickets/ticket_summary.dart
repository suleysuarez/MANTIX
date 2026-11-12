import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';

/// Cuatro contadores (total, enviados, en proceso, resueltos) de los tickets cargados.
class TicketStats extends StatelessWidget {
  const TicketStats({super.key, required this.items, required this.total});

  final List<TicketListItem> items;
  final int? total;

  @override
  Widget build(BuildContext context) {
    int count(List<String> codes) => items.where((item) => codes.contains(item.status)).length;
    final tiles = [
      _Stat('TOTAL', '${total ?? items.length}', Icons.confirmation_number_outlined, StatusColors.submitted),
      _Stat('ENVIADOS', '${count(['submitted', 'triaged'])}', Icons.send_rounded, StatusColors.triaged),
      _Stat('EN PROCESO', '${count(['assigned', 'in_progress', 'waiting'])}', Icons.settings_outlined, StatusColors.inProgress),
      _Stat('RESUELTOS', '${count(['resolved', 'closed'])}', Icons.check_circle_outline_rounded, StatusColors.resolved),
    ];
    return Column(children: [
      for (var row = 0; row < tiles.length; row += 2) ...[
        if (row > 0) const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(child: _StatTile(tiles[row])),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _StatTile(tiles[row + 1])),
        ]),
      ],
    ]);
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.colors);
  final String label;
  final String value;
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .5))),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: stat.colors.background, borderRadius: AppRadius.smAll),
          child: Icon(stat.icon, size: 16, color: stat.colors.foreground),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stat.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w800, letterSpacing: .4)),
            Text(stat.value, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, height: 1.1)),
          ]),
        ),
      ]),
    );
  }
}
