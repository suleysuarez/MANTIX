import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/technicians/technician_filters.dart';
import '../shared/skeleton.dart';
import 'technician_tones.dart';

/// Cuatro indicadores operativos que ayudan a repartir la demanda sin crear rankings.
class TechniciansKpiGrid extends StatelessWidget {
  const TechniciansKpiGrid({super.key, required this.summary, required this.hasWorkload, required this.unassignedTickets});

  final TechnicianSummary? summary;
  final bool hasWorkload;
  final int? unassignedTickets;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null) {
      return const Column(children: [
        Row(children: [Expanded(child: Skeleton(height: 60, radius: AppRadius.lg)), SizedBox(width: AppSpacing.sm), Expanded(child: Skeleton(height: 84, radius: AppRadius.lg))]),
        SizedBox(height: AppSpacing.sm),
        Row(children: [Expanded(child: Skeleton(height: 84, radius: AppRadius.lg)), SizedBox(width: AppSpacing.sm), Expanded(child: Skeleton(height: 84, radius: AppRadius.lg))]),
      ]);
    }
    final cards = [
      _KpiCard(label: 'TÉCNICOS DISPONIBLES', value: hasWorkload ? '${data.available} / ${data.total}' : '—', caption: 'Personas que pueden recibir trabajo', icon: Icons.engineering_outlined, tone: neutralTone),
      _KpiCard(label: 'SIN CARGA', value: hasWorkload ? '${data.free}' : '—', caption: 'Disponibles con 0 tickets abiertos', icon: Icons.inbox_outlined, tone: statusTone(TechnicianStatus.free)),
      _KpiCard(label: 'CON SOBRECARGA', value: hasWorkload ? '${data.overloaded}' : '—', caption: 'Por encima del promedio del equipo', icon: Icons.balance_outlined, tone: neutralTone),
      _KpiCard(label: 'TICKETS SIN ASIGNAR', value: unassignedTickets == null ? '—' : '$unassignedTickets', caption: 'Trabajo que espera técnico', icon: Icons.assignment_late_outlined, tone: neutralTone),
    ];
    // Una altura explícita para las cuatro: depende solo del tamaño de la letra, no del texto de cada
    // tarjeta, así que todas miden lo mismo (con `IntrinsicHeight` una fila salía más alta que otra).
    final height = _KpiCard.heightFor(context);
    return Column(children: [
      SizedBox(height: height, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[0]), const SizedBox(width: AppSpacing.sm), Expanded(child: cards[1])])),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(height: height, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[2]), const SizedBox(width: AppSpacing.sm), Expanded(child: cards[3])])),
    ]);
  }
}

/// Una cifra informativa con su nombre, una nota y un icono.
class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.caption, required this.icon, required this.tone});

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final ChipColors tone;

  static const _labelSize = 10.0;
  static const _labelHeight = 1.4;
  static const _valueSize = 22.0;
  static const _valueHeight = 1.2;
  static const _verticalPadding = AppSpacing.sm;

  /// Alto de la tarjeta: dos líneas de nombre, una de cifra y el relleno, con la letra del usuario.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler.scale(_labelSize * _labelHeight) * 2 + scaler.scale(_valueSize * _valueHeight) + _verticalPadding * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value. $caption',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: AppColors.skyLight.withValues(alpha: .7))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: _verticalPadding),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  // Siempre se reservan dos líneas para el nombre: las cuatro tarjetas miden lo mismo
                  // aunque un nombre ocupe una línea y otro dos, también con letra agrandada.
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(_labelSize * _labelHeight) * 2,
                    child: Align(alignment: Alignment.centerLeft, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: .2, fontSize: _labelSize, height: _labelHeight))),
                  ),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: _valueSize, height: _valueHeight))),
                ]),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: tone.background, borderRadius: AppRadius.smAll),
                child: Icon(icon, size: 16, color: tone.foreground),
              ),
          ]),
        ),
      ),
    );
  }
}
