import 'package:flutter/material.dart';

import '../../bloc/reports/report_preview_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/report_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import '../shared/skeleton.dart';

/// La vista previa del reporte con los filtros puestos, en pocas líneas: cuántos registros se
/// exportarán (con el aviso si son muchos o ninguno) y el comparativo si se pidió. No lista filas:
/// el detalle está en el archivo exportado.
class ReportPreviewSection extends StatelessWidget {
  const ReportPreviewSection({super.key, required this.state, required this.maxRows, required this.onRetry});

  final ReportPreviewState state;
  final int maxRows;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    if (state.status == PreviewStatus.invalid) {
      return _Notice(icon: Icons.event_busy_outlined, text: state.rangeError ?? 'Revisa el rango de fechas.', tone: CountTone.error);
    }
    if (preview == null) {
      if (state.status == PreviewStatus.failure && state.failure != null) {
        return _Notice(icon: Icons.error_outline, text: 'No pudimos cargar la vista previa. ${state.failure!.message}', tone: CountTone.error, action: TextButton(onPressed: onRetry, child: const Text('Reintentar')));
      }
      return const _PreviewSkeleton();
    }
    final count = countMessage(preview.totalRows, maxRows);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.status == PreviewStatus.failure && state.failure != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _Notice(icon: Icons.error_outline, text: 'No pudimos actualizar la vista previa. ${state.failure!.message}', tone: CountTone.error, action: TextButton(onPressed: onRetry, child: const Text('Reintentar'))),
        ),
      if (state.loading) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: LinearProgressIndicator(minHeight: 3, color: AppColors.mustard, backgroundColor: AppColors.skyLight)),
      _Notice(icon: switch (count.tone) { CountTone.ok => Icons.check_circle_outline, CountTone.warn => Icons.hourglass_bottom_rounded, CountTone.error => Icons.info_outline }, text: count.text, tone: count.tone),
      if (preview.comparison != null) ...[const SizedBox(height: AppSpacing.sm), _ComparisonCard(comparison: preview.comparison!)],
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.tone, this.action});

  final IconData icon;
  final String text;
  final CountTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) { CountTone.ok => AppColors.steel, CountTone.warn => AppColors.navy, CountTone.error => AppColors.error };
    final background = switch (tone) { CountTone.ok => AppColors.skyLight.withValues(alpha: .3), CountTone.warn => AppColors.mustard.withValues(alpha: .3), CountTone.error => AppColors.error.withValues(alpha: .08) };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: background, borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600, height: 1.3))),
          ?action,
        ]),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.comparison});

  final ReportComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = comparison.changePct;
    final text = change == null ? 'Sin datos en el periodo anterior' : '${change > 0 ? '+' : ''}${change.toStringAsFixed(change == change.roundToDouble() ? 0 : 1)} %';
    final period = comparison.previousFrom == null || comparison.previousTo == null ? 'Periodo anterior' : 'Periodo anterior: ${formatDate(comparison.previousFrom!)} a ${formatDate(comparison.previousTo!)}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.grey)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.compare_arrows_rounded, size: 20, color: AppColors.steel),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Comparativo', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
          Text(text, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text('Ahora: ${comparison.currentTotal} · Antes: ${comparison.previousTotal}', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel)),
        Text(period, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
      ]),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Cargando vista previa',
        child: const Skeleton(height: 52, radius: AppRadius.md),
      );
}
