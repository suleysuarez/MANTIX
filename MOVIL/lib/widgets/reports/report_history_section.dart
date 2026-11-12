import 'package:flutter/material.dart';

import '../../bloc/reports/report_history_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import '../shared/paginator.dart';
import '../shared/skeleton.dart';

/// «Exportaciones recientes»: lo que ya se generó, con su formato, filas, quién y cuándo. Falla
/// por separado del resto de la pantalla; con error ofrece reintentar.
class ReportHistorySection extends StatelessWidget {
  const ReportHistorySection({super.key, required this.state, required this.pageSize, required this.onPage, required this.onRetry});

  final ReportHistoryState state;
  final int pageSize;
  final ValueChanged<int> onPage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.history_rounded, color: AppColors.navy),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Semantics(header: true, child: Text('Exportaciones recientes', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
      ]),
      const SizedBox(height: AppSpacing.sm),
      if (state.status == HistoryStatus.loading)
        const Column(children: [Skeleton(height: 60, radius: AppRadius.lg), SizedBox(height: AppSpacing.sm), Skeleton(height: 60, radius: AppRadius.lg)])
      else if (state.status == HistoryStatus.failure)
        _Box(child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('No pudimos cargar las exportaciones. ${state.failure?.message ?? ''}'.trim(), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]))
      else if (state.items.isEmpty)
        _Box(child: Text('Aún no has exportado reportes.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel)))
      else ...[
        for (final run in state.items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _RunCard(run: run)),
        Paginator(page: state.page, pageSize: pageSize, total: state.total, totalPages: state.totalPages, onPage: onPage, loading: state.loadingPage),
      ],
    ]);
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .6))),
        child: child,
      );
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run});

  final ReportRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = run.rowCount == 1 ? '1 registro' : '${run.rowCount} registros';
    return Semantics(
      container: true,
      child: _Box(
        child: Row(children: [
          Icon(run.format == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined, color: AppColors.steel, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(run.title.isEmpty ? reportTitleOf(run.report) : run.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${run.formatLabel} · $rows', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
              Text('${run.by == null ? 'Sistema' : run.by!} · ${formatDateTime(run.at)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Nombre del reporte cuando el historial no trae título.
String reportTitleOf(String key) => switch (key) {
      'tickets' => 'Tickets de mantenimiento',
      'maintenance_plans' => 'Planes de mantenimiento',
      'equipment' => 'Inventario de equipos',
      'summary' => 'Resumen operativo',
      _ => 'Reporte',
    };
