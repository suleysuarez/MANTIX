import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Encabezado de la pantalla de reportes: icono, línea mostaza, título y explicación.
class ReportsHeader extends StatelessWidget {
  const ReportsHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 56, alignment: Alignment.center, child: const Icon(Icons.assessment_outlined, size: 44, color: AppColors.navy)),
            Container(width: 3, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2), decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Reportes', style: TextStyle(color: AppColors.navy, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1))),
                const SizedBox(height: 4),
                Text('Consulta y descarga la información que necesitas.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
              ]),
            ),
          ]),
        ),
      );
}

/// El icono de cada reporte de la app.
IconData reportIcon(String key) => switch (key) {
      'tickets' => Icons.confirmation_number_outlined,
      'maintenance_plans' => Icons.edit_calendar_outlined,
      'equipment' => Icons.devices_other_outlined,
      'summary' => Icons.insights_outlined,
      _ => Icons.description_outlined,
    };
