import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../shared/skeleton.dart';
import 'users_tones.dart';

/// Las cifras de las cuentas en tres tarjetas: total, activas e inactivas. Con [summary] en `null`
/// muestra esqueletos, o «no disponible» con reintento si [unavailable]: la lista de abajo sigue
/// funcionando.
class UsersSummaryCard extends StatelessWidget {
  const UsersSummaryCard({super.key, required this.summary, required this.unavailable, required this.onRetry});

  final UsersSummary? summary;
  final bool unavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    final theme = Theme.of(context);
    if (data == null && unavailable) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .7))),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.slate),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Las cifras de las cuentas no están disponibles.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      );
    }
    final cards = data == null
        ? [for (var i = 0; i < 3; i++) const _StatCard.loading()]
        : [
            _StatCard(label: 'Total', value: '${data.total}', icon: Icons.groups_rounded, iconColor: AppColors.steel, iconBackground: AppColors.skyLight.withValues(alpha: .6), tinted: true),
            _StatCard(label: 'Activos', value: '${data.active}', icon: Icons.check_circle_rounded, iconColor: StatusColors.resolved.dot, iconBackground: StatusColors.resolved.background),
            _StatCard(label: 'Inactivos', value: '${data.inactive}', icon: Icons.pause_circle_filled_rounded, iconColor: AppColors.slate, iconBackground: greyTone.background),
          ];
    return Semantics(
      container: true,
      label: data == null ? 'Cargando cifras de las cuentas' : 'Cuentas: ${data.total} en total, ${data.active} activas, ${data.inactive} inactivas',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards[i]),
          ],
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.iconColor, required this.iconBackground, this.tinted = false})
      : loading = false;

  const _StatCard.loading()
      : label = '',
        value = '',
        icon = Icons.circle,
        iconColor = AppColors.slate,
        iconBackground = AppColors.grey,
        tinted = false,
        loading = true;

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  /// La primera tarjeta lleva un fondo azul claro.
  final bool tinted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tinted ? Color.alphaBlend(AppColors.skyLight.withValues(alpha: .3), AppColors.white) : AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: loading
          ? const Column(mainAxisSize: MainAxisSize.min, children: [Skeleton(width: 30, height: 30, radius: 15), SizedBox(height: 6), Skeleton(width: 30, height: 18), SizedBox(height: 4), Skeleton(width: 42, height: 10)])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle), child: Icon(icon, size: 18, color: iconColor)),
              const SizedBox(height: 4),
              // El número y el nombre se encogen en una tarjeta estrecha en vez de desbordar.
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700))),
            ]),
    );
  }
}
