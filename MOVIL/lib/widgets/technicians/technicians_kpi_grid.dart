import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/technicians/technician_filters.dart';
import '../shared/skeleton.dart';
import 'technician_tones.dart';

/// Las cinco cifras del equipo: total, disponibles, con tickets activos, no disponibles y
/// resueltos. Las cuatro primeras son botones que filtran la lista por ese estado ([selected] es
/// el filtro puesto; «Total» lo quita). Sin datos de carga ([hasWorkload] `false`) las cifras que
/// dependen de ella muestran «—». Con [summary] en `null` se dibuja el esqueleto.
class TechniciansKpiGrid extends StatelessWidget {
  const TechniciansKpiGrid({super.key, required this.summary, required this.hasWorkload, required this.windowDays, required this.selected, required this.onSelect});

  final TechnicianSummary? summary;
  final bool hasWorkload;
  final int windowDays;
  final TechnicianStatus? selected;

  /// Se llama con el estado de la tarjeta tocada, o `null` para «Total».
  final ValueChanged<TechnicianStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null) {
      return Semantics(
        container: true,
        label: 'Cargando cifras del equipo técnico',
        child: Column(children: [
          for (var row = 0; row < 2; row++) ...[
            const Row(children: [Expanded(child: Skeleton(height: 84, radius: AppRadius.lg)), SizedBox(width: AppSpacing.sm), Expanded(child: Skeleton(height: 84, radius: AppRadius.lg))]),
            const SizedBox(height: AppSpacing.sm),
          ],
          const Skeleton(height: 84, radius: AppRadius.lg),
        ]),
      );
    }
    final cards = [
      _KpiCard(label: 'TOTAL TÉCNICOS', value: '${data.total}', caption: 'Perfiles registrados', icon: Icons.engineering_outlined, tone: neutralTone, selected: selected == null, onTap: () => onSelect(null)),
      _KpiCard(
        label: 'DISPONIBLES',
        value: '${data.free}',
        caption: 'Sin tickets abiertos',
        icon: Icons.check_circle_outline_rounded,
        tone: statusTone(TechnicianStatus.free),
        selected: selected == TechnicianStatus.free,
        onTap: () => onSelect(TechnicianStatus.free),
      ),
      _KpiCard(
        label: 'CON TICKETS ACTIVOS',
        value: hasWorkload ? '${data.busy}' : '—',
        caption: hasWorkload ? '${data.openTickets} ${data.openTickets == 1 ? 'ticket abierto' : 'tickets abiertos'}' : 'Carga no disponible',
        icon: Icons.construction_rounded,
        tone: statusTone(TechnicianStatus.busy),
        selected: selected == TechnicianStatus.busy,
        onTap: () => onSelect(TechnicianStatus.busy),
      ),
      _KpiCard(
        label: 'NO DISPONIBLES',
        value: '${data.unavailable}',
        caption: 'Fuera de asignación',
        icon: Icons.do_not_disturb_on_outlined,
        tone: statusTone(TechnicianStatus.unavailable),
        selected: selected == TechnicianStatus.unavailable,
        onTap: () => onSelect(TechnicianStatus.unavailable),
      ),
    ];
    return Column(children: [
      for (var row = 0; row < 2; row++) ...[
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cards[row * 2]),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards[row * 2 + 1]),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      _KpiCard(label: 'RESUELTOS', value: hasWorkload ? '${data.resolved}' : '—', caption: 'Últimos $windowDays días', icon: Icons.task_alt_rounded, tone: neutralTone),
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
