import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../shared/skeleton.dart';

/// Las cifras de las cuentas en una sola tarjeta baja: total, activos, inactivos y los que aún
/// no han entrado. Con [summary] en `null` muestra un esqueleto, o «no disponible» con reintento
/// si [unavailable]: las listas de abajo siguen funcionando.
class UsersSummaryCard extends StatelessWidget {
  const UsersSummaryCard({super.key, required this.summary, required this.unavailable, required this.onRetry});

  final UsersSummary? summary;
  final bool unavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: AppColors.white,
      borderRadius: AppRadius.lgAll,
      border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
      boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 12, offset: const Offset(0, 4))],
    );
    if (data == null && unavailable) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: decoration,
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.slate),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Las cifras de las cuentas no están disponibles.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      );
    }
    final cells = data == null
        ? [for (var i = 0; i < 4; i++) const _Cell.loading()]
        : [
            _Cell(label: 'Total', value: '${data.total}'),
            _Cell(label: 'Activos', value: '${data.active}'),
            _Cell(label: 'Inactivos', value: '${data.inactive}'),
            _Cell(label: 'Sin ingresar', value: '${data.neverSignedIn}'),
          ];
    return Semantics(
      container: true,
      label: data == null ? 'Cargando cifras de las cuentas' : 'Cuentas: ${data.total} en total, ${data.active} activas, ${data.inactive} inactivas, ${data.neverSignedIn} sin ingresar',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: decoration,
        child: IntrinsicHeight(
          child: Row(children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: AppColors.skyLight.withValues(alpha: .8)),
              Expanded(child: cells[i]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  const _Cell.loading()
      : label = null,
        value = null;

  final String? label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: label == null
          ? const Column(mainAxisSize: MainAxisSize.min, children: [Skeleton(width: 34, height: 22), SizedBox(height: 6), Skeleton(width: 46, height: 10)])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              // El número y el nombre se encogen en una celda estrecha en vez de desbordar.
              FittedBox(fit: BoxFit.scaleDown, child: Text(value!, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(label!, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700))),
            ]),
    );
  }
}
