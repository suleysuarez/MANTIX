import 'package:flutter/material.dart';

import '../../bloc/reports/report_export_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';

const _formatTexts = {
  ReportFormat.pdf: 'Documento para imprimir o compartir: tabla y resumen ejecutivo.',
  ReportFormat.xlsx: 'Hoja de cálculo para analizar: filtros, totales con fórmulas y gráficos.',
};

/// «Formato»: un desplegable con PDF y Excel. Se deshabilita mientras se genera un archivo.
class ReportFormatField extends StatelessWidget {
  const ReportFormatField({super.key, required this.format, required this.onFormat, this.enabled = true});

  final ReportFormat format;
  final ValueChanged<ReportFormat> onFormat;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Formato de exportación',
        child: DropdownButtonFormField<ReportFormat>(
          key: ValueKey(format),
          initialValue: format,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Formato', prefixIcon: Icon(Icons.description_outlined, size: 20), isDense: true),
          items: [
            for (final option in const [ReportFormat.pdf, ReportFormat.xlsx])
              DropdownMenuItem(value: option, child: Row(children: [Icon(option == ReportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined, size: 18, color: AppColors.steel), const SizedBox(width: 8), Text(option.label)])),
          ],
          onChanged: enabled ? (value) => value == null ? null : onFormat(value) : null,
        ),
      );
}

/// Exportar: el aviso del resultado (compartido, vacío o error, que se puede cerrar), una nota que
/// dice qué lleva el formato elegido y el botón mostaza. El botón solo se habilita si hay registros
/// que exportar; mientras se genera muestra el avance.
class ReportExportPanel extends StatelessWidget {
  const ReportExportPanel({super.key, required this.format, required this.state, required this.canExport, required this.onExport, required this.onDismiss});

  final ReportFormat format;
  final ReportExportState state;

  /// Hay registros y no pasan del máximo.
  final bool canExport;
  final VoidCallback onExport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final working = state.working;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.status == ExportStatus.shared || state.status == ExportStatus.empty || state.status == ExportStatus.failure)
        Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _Result(state: state, onDismiss: onDismiss)),
      _InfoNote(text: _formatTexts[format]!),
      const SizedBox(height: AppSpacing.md),
      FilledButton.icon(
        onPressed: canExport && !working ? onExport : null,
        icon: working ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.navy)) : const Icon(Icons.ios_share_rounded),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(working ? _workingLabel(state.progress) : 'Exportar ${format.label}', maxLines: 1)),
        style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, disabledBackgroundColor: AppColors.grey, disabledForegroundColor: AppColors.slate, minimumSize: const Size.fromHeight(54), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    ]);
  }

  static String _workingLabel(double? progress) => progress == null ? 'Generando archivo…' : 'Generando… ${(progress * 100).round()} %';
}

/// La nota azul con una «i»: qué lleva el formato elegido.
class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .35), borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_rounded, size: 20, color: AppColors.steel),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.navy, height: 1.3))),
        ]),
      );
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
