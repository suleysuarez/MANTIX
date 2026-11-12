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
        Row(children: [Expanded(child: Skeleton(height: 84, radius: AppRadius.lg)), SizedBox(width: AppSpacing.sm), Expanded(child: Skeleton(height: 84, radius: AppRadius.lg))]),
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
    return Column(children: [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[0]), const SizedBox(width: AppSpacing.sm), Expanded(child: cards[1])])),
      const SizedBox(height: AppSpacing.sm),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: cards[2]), const SizedBox(width: AppSpacing.sm), Expanded(child: cards[3])])),
    ]);
  }
}

/// Una cifra con su nombre, una nota y un icono. Con [onTap] es un botón; [selected] la marca
/// con el borde mostaza.
class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.caption, required this.icon, required this.tone, this.selected = false, this.onTap});

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final ChipColors tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = selected && onTap != null;
    return Semantics(
      button: onTap != null,
      selected: marked,
      label: '$label: $value. $caption',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: marked ? AppColors.mustard : AppColors.skyLight.withValues(alpha: .7), width: marked ? 2 : 1)),
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: .3)),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
                  Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel)),
                ]),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: tone.background, borderRadius: AppRadius.smAll),
                child: Icon(icon, size: 18, color: tone.foreground),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
