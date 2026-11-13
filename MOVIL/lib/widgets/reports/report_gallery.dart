import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import 'reports_header.dart';

/// La lista de reportes: una fila por reporte, con su icono, su nombre y qué contiene. El elegido va
/// con borde mostaza y una marca; tocar otro lo elige. Con pocos reportes (hoy 4) caben todos sin
/// desplazarse de lado.
class ReportGallery extends StatelessWidget {
  const ReportGallery({super.key, required this.reports, required this.selectedKey, required this.onSelect});

  final List<ReportDefinition> reports;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final report in reports)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ReportRow(report: report, selected: report.key == selectedKey, onTap: () => onSelect(report.key)),
          ),
      ]);
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.selected, required this.onTap});

  final ReportDefinition report;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: report.description.isEmpty ? report.title : '${report.title}. ${report.description}',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.mustard.withValues(alpha: .24) : AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: selected ? AppColors.mustard : AppColors.mustard.withValues(alpha: .35), width: selected ? 2.5 : 1)),
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: selected ? AppColors.mustard : AppColors.mustard.withValues(alpha: .22), borderRadius: AppRadius.mdAll),
                child: Icon(reportIcon(report.key), color: AppColors.navy, size: 25),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(report.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, height: 1.2)),
                  if (report.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(report.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? AppColors.mustard : AppColors.slate),
            ]),
          ),
        ),
      ),
    );
  }
}
