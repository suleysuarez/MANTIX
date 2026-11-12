import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Tarjeta de una hoja de detalle: icono con acento mostaza, título y contenido.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .25), borderRadius: AppRadius.smAll),
              child: Icon(icon, size: 17, color: AppColors.navy),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ]),
      );
}

/// Etiqueta arriba y valor debajo, con ajuste de línea: nunca se superponen.
class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Cabecera oscura de una ficha con el acento mostaza: [leading] (icono), [pill] (etiqueta o
/// número en mostaza), [title] y [chips] debajo.
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.icon, this.pill, required this.title, this.chips = const []});
  final IconData icon;

  /// Etiqueta mostaza junto al título; sin ella, solo salen los chips.
  final String? pill;
  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: AppRadius.lgAll,
        border: Border(bottom: BorderSide(color: AppColors.mustard, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: AppRadius.mdAll),
          child: Icon(icon, color: AppColors.mustard, size: 26),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (pill != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll),
                child: Text(pill!, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
              ),
              ...chips,
            ]),
          ]),
        ),
      ]),
    );
  }
}
