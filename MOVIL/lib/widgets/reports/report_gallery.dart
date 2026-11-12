import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import 'reports_header.dart';

/// La galería: una fila de reportes que se desplaza de lado (el elegido va en mostaza con texto
/// navy) y, debajo, qué contiene el elegido.
class ReportGallery extends StatelessWidget {
  const ReportGallery({super.key, required this.reports, required this.selectedKey, required this.onSelect});

  final List<ReportDefinition> reports;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    ReportDefinition? selected;
    for (final report in reports) {
      if (report.key == selectedKey) selected = report;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: reports.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
            final report = reports[index];
            final on = report.key == selectedKey;
            return Semantics(
              button: true,
              selected: on,
              label: report.title,
              excludeSemantics: true,
              child: Material(
                color: on ? AppColors.mustard : AppColors.white,
                shape: StadiumBorder(side: BorderSide(color: on ? AppColors.mustard : AppColors.grey)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(report.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(reportIcon(report.key), size: 20, color: on ? AppColors.navy : AppColors.steel),
                      const SizedBox(width: AppSpacing.sm),
                      Text(report.title, maxLines: 1, style: TextStyle(color: on ? AppColors.navy : AppColors.steel, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (selected != null && selected.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Text(selected.description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
        ),
    ]);
  }
}
