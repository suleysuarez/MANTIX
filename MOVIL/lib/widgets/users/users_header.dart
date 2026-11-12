import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Encabezado de cada pestaña de Usuarios y roles: el icono en su caja azul claro, la línea
/// mostaza, el título y la explicación.
class UsersHeader extends StatelessWidget {
  const UsersHeader({super.key, required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: AppColors.navy, size: 32),
            ),
            Container(width: 3, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2), decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Semantics(header: true, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)))),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
              ]),
            ),
          ]),
        ),
      );
}
