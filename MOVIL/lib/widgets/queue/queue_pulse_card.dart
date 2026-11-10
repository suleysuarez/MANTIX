import 'package:flutter/material.dart';

import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/queue/queue_models.dart';
import '../shared/skeleton.dart';
import 'queue_kpi_strip.dart';
import 'queue_tones.dart';

/// «Pulso de la cola»: cómo se está decidiendo en los últimos 30 días (primera respuesta,
/// aprobación y rechazo) y cómo se reparte lo pendiente por prioridad y por categoría.
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
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.grey)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PULSO DE LA COLA', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
        const SizedBox(height: 2),
        Text('Decisiones de los últimos 30 días', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
        const SizedBox(height: AppSpacing.lg),
        if (data == null)
          const _PulseSkeleton()
        else ...[
          _FirstResponse(time: data.triageTime),
          const Divider(height: AppSpacing.xl),
          _Decisions(decisions: data.decisions),
          const Divider(height: AppSpacing.xl),
          _Bars(
            title: 'POR PRIORIDAD',
            emptyText: 'No hay solicitudes pendientes.',
            total: data.pendingTotal,
            rows: [
              for (final item in data.byPriority)
                _BarRow(label: priorityName(item.key, priorities), count: item.count, colors: priorityColors(priorityTone(item.key, priorities))),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _Bars(
            title: 'POR CATEGORÍA',
            emptyText: 'No hay solicitudes pendientes.',
            total: data.pendingTotal,
            rows: [
              for (final item in data.byCategory) _BarRow(label: categoryLabel(item.key, categoryNames), count: item.count, colors: StatusColors.triaged),
            ],
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
        Skeleton(width: 120, height: 10),
        SizedBox(height: 10),
        Skeleton(width: 90, height: 28),
        SizedBox(height: 24),
        Skeleton(width: 140, height: 10),
        SizedBox(height: 10),
        Skeleton(width: 110, height: 28),
        SizedBox(height: 24),
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
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      const SizedBox(height: 4),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.sm, runSpacing: 4, children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
        ?chip,
        if (lowSample) const _Pill(text: 'pocos datos', colors: StatusColors.waiting),
      ]),
      const SizedBox(height: 2),
      Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.colors});

  final String text;
  final ChipColors colors;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: colors.background, borderRadius: AppRadius.pillAll),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w800)),
      );
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
  const _BarRow({required this.label, required this.count, required this.colors});

  final String label;
  final int count;
  final ChipColors colors;
}

/// Lista de barras proporcionales a lo pendiente, hechas con widgets simples.
class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.emptyText, required this.total, required this.rows});

  final String title;
  final String emptyText;
  final int total;
  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      const SizedBox(height: AppSpacing.sm),
      if (rows.isEmpty) Text(emptyText, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Semantics(
            label: '${row.label}: ${row.count}',
            excludeSemantics: true,
            child: Row(children: [
              Expanded(
                flex: 4,
                child: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: AppRadius.pillAll,
                  child: Container(
                    height: 8,
                    color: AppColors.canvas,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(widthFactor: share(row.count, total) / 100, child: Container(color: row.colors.dot)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(width: 28, child: Text('${row.count}', textAlign: TextAlign.right, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
            ]),
          ),
        ),
    ]);
  }
}
