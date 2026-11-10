import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Un hecho de una línea de tiempo (creación, cambio de estado, mantenimiento…).
class TimelineEntry {
  const TimelineEntry({required this.title, required this.at, this.subtitle, this.icon = Icons.circle, this.color = AppColors.steel, this.onTap});

  final String title;
  final String? subtitle;
  final DateTime at;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

/// Línea de tiempo vertical: el hecho más reciente arriba. La fecha va debajo del título para
/// que nada se superponga con textos largos ni con escalas de letra grandes.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
    final theme = Theme.of(context);
    return Column(children: [
      for (var i = 0; i < sorted.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 32,
              child: Column(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: sorted[i].color.withValues(alpha: .15), shape: BoxShape.circle),
                  child: Icon(sorted[i].icon, size: 15, color: sorted[i].color),
                ),
                if (i < sorted.length - 1) Expanded(child: Container(width: 2, color: AppColors.grey.withValues(alpha: .6))),
              ]),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: InkWell(
                onTap: sorted[i].onTap,
                borderRadius: AppRadius.smAll,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sorted[i].title, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700)),
                    if (sorted[i].subtitle != null) Text(sorted[i].subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                    Text(formatDateTime(sorted[i].at.toLocal()), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}
