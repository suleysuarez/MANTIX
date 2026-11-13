import 'package:flutter/material.dart';

import '../../core/format/report_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Tres cifras de la pantalla de reportes, todas del mismo tamaño: cuántos reportes hay, cuándo fue
/// la última exportación y cuántas se han hecho. Un `null` es «aún no llega» y sale como «—».
///
/// El alto depende solo del tamaño de letra del sistema, no del texto de cada tarjeta.
class ReportsKpis extends StatelessWidget {
  const ReportsKpis({super.key, required this.available, required this.historyReady, required this.lastExport, required this.exports, required this.now});

  /// Reportes que la cuenta puede usar.
  final int? available;

  /// El historial ya cargó: sin él, «última exportación» y «exportaciones» no se pueden saber.
  final bool historyReady;

  /// Cuándo fue la última exportación; `null` si todavía no hay ninguna.
  final DateTime? lastExport;

  /// Cuántas exportaciones hay en total.
  final int? exports;
  final DateTime now;

  static const _valueSize = 16.0;
  static const _labelSize = 10.0;
  static const _iconBox = 28.0;
  static const _lineHeight = 1.25;

  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return AppSpacing.sm * 2 + _iconBox + AppSpacing.xs + scaler.scale(_valueSize * _lineHeight) + scaler.scale(_labelSize * _lineHeight) * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final height = heightFor(context);
    final cards = [
      _Card(icon: Icons.assessment_outlined, value: available == null ? '—' : '$available', label: 'Reportes disponibles'),
      _Card(icon: Icons.schedule_rounded, value: historyReady ? lastExportText(lastExport, now) : '—', label: 'Última exportación'),
      _Card(icon: Icons.download_rounded, value: historyReady && exports != null ? '$exports' : '—', label: 'Exportaciones'),
    ];
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: cards[i]),
        ],
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Material(
        color: AppColors.mustard.withValues(alpha: .16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.mustard.withValues(alpha: .7), width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: ReportsKpis._iconBox, height: ReportsKpis._iconBox, decoration: const BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle), child: Icon(icon, size: 16, color: AppColors.navy)),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: const TextStyle(color: AppColors.navy, fontSize: ReportsKpis._valueSize, fontWeight: FontWeight.w900, height: ReportsKpis._lineHeight))),
            // Siempre dos líneas de alto para el nombre: las tres tarjetas miden lo mismo.
            SizedBox(
              height: scaler.scale(ReportsKpis._labelSize * ReportsKpis._lineHeight) * 2,
              child: Align(alignment: Alignment.topCenter, child: Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: ReportsKpis._labelSize, fontWeight: FontWeight.w700, height: ReportsKpis._lineHeight))),
            ),
          ]),
        ),
      ),
    );
  }
}
