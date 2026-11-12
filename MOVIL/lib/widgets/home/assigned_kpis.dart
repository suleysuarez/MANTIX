import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../shared/skeleton.dart';

/// Una cifra del panel del técnico. [value] `null` es «aún no llega» (esqueleto si [loading], «—» si no).
class AssignedKpi {
  const AssignedKpi({required this.label, required this.value, required this.icon, required this.tone});

  final String label;
  final int? value;
  final IconData icon;
  final ChipColors tone;
}

/// Cuatro cifras en dos filas de dos, todas del mismo tamaño: el alto depende solo del tamaño de
/// letra del sistema, no del texto de cada tarjeta.
class AssignedKpis extends StatelessWidget {
  const AssignedKpis({super.key, required this.kpis, required this.loading});

  final List<AssignedKpi> kpis;
  final bool loading;

  static const _labelSize = 10.0;
  static const _labelHeight = 1.4;
  static const _valueSize = 22.0;
  static const _valueHeight = 1.2;

  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler.scale(_labelSize * _labelHeight) * 2 + scaler.scale(_valueSize * _valueHeight) + AppSpacing.sm * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final height = heightFor(context);
    Widget row(int start) => SizedBox(
          height: height,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Card(kpi: kpis[start], loading: loading)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Card(kpi: kpis[start + 1], loading: loading)),
          ]),
        );
    return Column(children: [row(0), const SizedBox(height: AppSpacing.sm), row(2)]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.kpi, required this.loading});

  final AssignedKpi kpi;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final value = kpi.value;
    final shown = value == null ? '—' : '$value';
    return Semantics(
      label: '${kpi.label}: ${value == null ? 'no disponible' : shown}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .7))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  height: scaler.scale(AssignedKpis._labelSize * AssignedKpis._labelHeight) * 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(kpi.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: .2, fontSize: AssignedKpis._labelSize, height: AssignedKpis._labelHeight)),
                  ),
                ),
                if (value == null && loading)
                  const Skeleton(width: 34, height: 22)
                else
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(shown, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: AssignedKpis._valueSize, height: AssignedKpis._valueHeight))),
              ]),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: kpi.tone.background, borderRadius: AppRadius.smAll),
              child: Icon(kpi.icon, size: 17, color: kpi.tone.foreground),
            ),
          ]),
        ),
      ),
    );
  }
}
