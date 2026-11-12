import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/queue/queue_models.dart';
import '../shared/skeleton.dart';
import 'queue_kpi_grid.dart';
import 'queue_tones.dart';

/// «Pulso de la cola»: cómo se está decidiendo en los últimos 30 días (primera respuesta,
/// aprobación y rechazo, una al lado de la otra) y cómo se reparte lo pendiente por prioridad y
/// por categoría (también en dos columnas). Todo sale del resumen del servidor.
class QueuePulseCard extends StatelessWidget {
  const QueuePulseCard({super.key, required this.summary, required this.unavailable, required this.priorities, required this.categoryNames, required this.onRetry});

  final QueueSummary? summary;
  final bool unavailable;
  final List<PriorityOption> priorities;
  final Map<String, String> categoryNames;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = summary;
    if (data == null && unavailable) {
      return QueueUnavailable(message: 'El pulso de la cola no está disponible.', onRetry: onRetry);
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.skyLight.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('PULSO DE LA COLA', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, letterSpacing: 0.4))),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(periodLabel(data?.period) == null ? 'Decisiones recientes' : 'Decisiones de los últimos ${periodLabel(data?.period)}', textAlign: TextAlign.right, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel))),
        ]),
        const SizedBox(height: AppSpacing.lg),
        if (data == null)
          const _PulseSkeleton()
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _FirstResponse(time: data.triageTime)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _Decisions(decisions: data.decisions)),
          ]),
          const Divider(height: AppSpacing.xl, color: AppColors.skyLight),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: _Bars(
                  title: 'POR PRIORIDAD',
                  emptyText: 'Sin pendientes.',
                  total: data.pendingTotal,
                  color: AppColors.mustard,
                  rows: [for (final item in data.byPriority) _BarRow(label: priorityName(item.key, priorities), count: item.count)],
                ),
              ),
              const VerticalDivider(width: AppSpacing.xl, color: AppColors.skyLight),
              Expanded(
                child: _Bars(
                  title: 'POR CATEGORÍA',
                  emptyText: 'Sin pendientes.',
                  total: data.pendingTotal,
                  color: AppColors.steel,
                  rows: [for (final item in data.byCategory) _BarRow(label: categoryLabel(item.key, categoryNames), count: item.count)],
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _PulseSkeleton extends StatelessWidget {
  const _PulseSkeleton();

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 90, height: 10), SizedBox(height: 10), Skeleton(width: 70, height: 28), SizedBox(height: 10), Skeleton(width: 100, height: 10)])),
          SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(width: 90, height: 10), SizedBox(height: 10), Skeleton(width: 90, height: 28), SizedBox(height: 10), Skeleton(width: 100, height: 10)])),
        ]),
        SizedBox(height: AppSpacing.xl),
        Skeleton(height: 10),
        SizedBox(height: 8),
        Skeleton(height: 10),
        SizedBox(height: 8),
        Skeleton(height: 10),
      ]);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.caption, this.chip, this.lowSample = false});

  final String label;
  final String value;
  final String caption;
  final Widget? chip;
  final bool lowSample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      const SizedBox(height: 6),
      // El valor se encoge en vez de desbordar la media columna.
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
      if (chip != null || lowSample) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [?chip, if (lowSample) const _Pill(text: 'pocos datos', mustard: true)]),
      ],
      const SizedBox(height: 4),
      Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.colors, this.mustard = false});

  final String text;
  final ChipColors? colors;
  final bool mustard;

  @override
  Widget build(BuildContext context) {
    final palette = colors ?? (mustard ? mustardChip : skyChip);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: palette.background, borderRadius: AppRadius.pillAll),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.foreground, fontWeight: FontWeight.w800)),
    );
  }
}

class _FirstResponse extends StatelessWidget {
  const _FirstResponse({required this.time});

  final TriageTime time;

  @override
  Widget build(BuildContext context) {
    final change = formatChange(time.changePct);
    return _Metric(
      label: 'PRIMERA RESPUESTA (MEDIA)',
      value: formatHours(time.meanHours),
      // La respuesta es mejor cuanto más baja.
      chip: change.isEmpty ? null : _Pill(text: change, colors: changeColors(changeTone(time.changePct, betterWhenHigher: false))),
      lowSample: time.lowSample,
      caption: 'mediana ${formatHours(time.medianHours)} · n = ${time.sampleSize}',
    );
  }
}

class _Decisions extends StatelessWidget {
  const _Decisions({required this.decisions});

  final QueueDecisions decisions;

  @override
  Widget build(BuildContext context) {
    final change = formatChange(decisions.changePct);
    return _Metric(
      label: 'APROBACIÓN / RECHAZO',
      value: '${formatPct(decisions.approvalRatePct)} / ${formatPct(decisions.rejectionRatePct)}',
      // Aprobar más o menos no es bueno ni malo por sí solo: el chip es siempre neutro.
      chip: change.isEmpty ? null : _Pill(text: change, colors: changeColors(ChangeTone.neutral)),
      lowSample: decisions.lowSample,
      caption: '${decisions.approved} ${decisions.approved == 1 ? 'aprobada' : 'aprobadas'} · ${decisions.rejected} ${decisions.rejected == 1 ? 'rechazada' : 'rechazadas'} · n = ${decisions.sampleSize}',
    );
  }
}

class _BarRow {
  const _BarRow({required this.label, required this.count});

  final String label;
  final int count;
}

/// Lista de barras proporcionales a lo pendiente, hechas con widgets simples: el nombre y la
/// cuenta arriba y la barra debajo, como en el diseño.
class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.emptyText, required this.total, required this.color, required this.rows});

  final String title;
  final String emptyText;
  final int total;
  final Color color;
  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      const SizedBox(height: AppSpacing.sm),
      if (rows.isEmpty) Text(emptyText, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Semantics(
            label: '${row.label}: ${row.count}',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600))),
                const SizedBox(width: AppSpacing.xs),
                Text('${row.count}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: Container(
                  height: 6,
                  color: AppColors.skyLight.withValues(alpha: .4),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: share(row.count, total) / 100, child: Container(color: color)),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
