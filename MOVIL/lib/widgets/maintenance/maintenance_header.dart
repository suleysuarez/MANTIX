import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Encabezado claro de la pantalla de mantenimientos: el icono del calendario con reloj, una línea
/// mostaza, el título y la explicación. [action] es el botón del encabezado (por ejemplo
/// «Programar mantenimiento») y solo se pasa a quien puede usarlo.
class MaintenanceHeader extends StatelessWidget {
  const MaintenanceHeader({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 56,
                alignment: Alignment.center,
                child: const Icon(Icons.edit_calendar_outlined, size: 44, color: AppColors.navy),
              ),
              Container(width: 3, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2), decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Mantenimientos', style: TextStyle(color: AppColors.navy, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1))),
                  const SizedBox(height: 4),
                  Text('Gestiona y consulta los mantenimientos de tus equipos.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
                ]),
              ),
            ]),
          ),
          if (action != null) ...[const SizedBox(height: AppSpacing.md), Align(alignment: Alignment.centerLeft, child: action)],
        ]),
      );
}
