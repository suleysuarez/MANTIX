import 'package:flutter/material.dart';

import '../../bloc/reports/report_preview_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/report_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import '../shared/skeleton.dart';

/// La vista previa del reporte con los filtros puestos: cuántos registros hay, el aviso de lo que
/// se exportará, el comparativo si se pidió y las primeras filas como tarjetas. Cada tarjeta enseña
/// sus dos primeras columnas y despliega el resto.
class ReportPreviewSection extends StatelessWidget {
  const ReportPreviewSection({super.key, required this.state, required this.maxRows, required this.onRetry});

  final ReportPreviewState state;
  final int maxRows;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      if (preview.rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text('Vista previa · primeras ${preview.rows.length} de ${preview.totalRows}', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
        const SizedBox(height: AppSpacing.sm),
        for (final row in preview.rows) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _RowCard(columns: preview.columns, row: row)),
      ],
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

class _RowCard extends StatelessWidget {
  const _RowCard({required this.columns, required this.row});

  final List<PreviewColumn> columns;
  final Map<String, String> row;

  String _value(PreviewColumn column) {
    final value = row[column.key] ?? '';
    return value.isEmpty ? '—' : value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (columns.isEmpty) return const SizedBox.shrink();
    final rest = columns.skip(2).toList();
    return Material(
      color: AppColors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .6))),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          enabled: rest.isNotEmpty,
          title: Text(_value(columns.first), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
          subtitle: columns.length > 1 ? Text('${columns[1].header}: ${_value(columns[1])}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)) : null,
          children: [
            for (final column in rest)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${column.header}: ', style: const TextStyle(color: AppColors.slate, fontWeight: FontWeight.w700)),
                  TextSpan(text: _value(column), style: const TextStyle(color: AppColors.navy)),
                ])),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Cargando vista previa',
        child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Skeleton(height: 52, radius: AppRadius.md),
          SizedBox(height: AppSpacing.lg),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
        ]),
      );
}
