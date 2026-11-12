import 'package:flutter/material.dart';

import '../../bloc/reports/report_export_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';

/// Elegir el formato (PDF o Excel) y exportar. El botón mostaza solo se habilita si hay registros
/// que exportar; mientras se genera muestra el avance. El resultado (compartido, vacío o error)
/// sale en un aviso que se puede cerrar.
class ReportExportPanel extends StatelessWidget {
  const ReportExportPanel({super.key, required this.format, required this.onFormat, required this.state, required this.canExport, required this.onExport, required this.onDismiss});

  final ReportFormat format;
  final ValueChanged<ReportFormat> onFormat;
  final ReportExportState state;

  /// Hay registros y no pasan del máximo.
  final bool canExport;
  final VoidCallback onExport;
  final VoidCallback onDismiss;

  static const _texts = {
    ReportFormat.pdf: 'Documento para imprimir o compartir: tabla y resumen ejecutivo.',
    ReportFormat.xlsx: 'Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final working = state.working;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text('Formato de exportación', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
      const SizedBox(height: AppSpacing.sm),
      for (final option in const [ReportFormat.pdf, ReportFormat.xlsx])
        Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _FormatCard(format: option, text: _texts[option]!, selected: option == format, onTap: working ? null : () => onFormat(option))),
      const SizedBox(height: AppSpacing.xs),
      if (state.status == ExportStatus.shared || state.status == ExportStatus.empty || state.status == ExportStatus.failure)
        Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _Result(state: state, onDismiss: onDismiss)),
      FilledButton.icon(
        onPressed: canExport && !working ? onExport : null,
        icon: working ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.navy)) : const Icon(Icons.ios_share_rounded),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(working ? _workingLabel(state.progress) : 'Exportar ${format.label}', maxLines: 1)),
        style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, disabledBackgroundColor: AppColors.grey, disabledForegroundColor: AppColors.slate, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  static String _workingLabel(double? progress) => progress == null ? 'Generando archivo…' : 'Generando… ${(progress * 100).round()} %';
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({required this.format, required this.text, required this.selected, required this.onTap});

  final ReportFormat format;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Formato ${format.label}. $text',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.mustard.withValues(alpha: .22) : AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: selected ? AppColors.mustard : AppColors.grey, width: selected ? 2 : 1)),
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(format == ReportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined, color: AppColors.navy, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(format.label, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(text, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
                ]),
              ),
              if (selected) const Padding(padding: EdgeInsets.only(left: AppSpacing.sm), child: Icon(Icons.check_circle_rounded, color: AppColors.navy)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state, required this.onDismiss});

  final ReportExportState state;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final shared = state.status == ExportStatus.shared;
    final color = shared ? AppColors.steel : AppColors.error;
    final text = shared ? 'Archivo generado: ${state.fileName}. Elige dónde guardarlo o a quién enviarlo.' : (state.message ?? 'No se pudo exportar el reporte.');
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        decoration: BoxDecoration(color: shared ? AppColors.skyLight.withValues(alpha: .3) : AppColors.error.withValues(alpha: .08), borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(shared ? Icons.task_alt_rounded : Icons.error_outline, size: 20, color: color)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600, height: 1.3)))),
          IconButton(tooltip: 'Cerrar aviso', onPressed: onDismiss, icon: Icon(Icons.close_rounded, size: 20, color: color)),
        ]),
      ),
    );
  }
}
