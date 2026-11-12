import 'package:flutter/material.dart';

import '../../core/format/technicians_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/technicians/technician_models.dart';
import '../shared/app_chip.dart';
import '../users/user_cards.dart' show UserAvatar;
import 'technician_tones.dart';

/// Chip con el estado de un técnico: «Disponible», «2 tickets activos» o «No disponible».
class TechnicianStatusChip extends StatelessWidget {
  const TechnicianStatusChip({super.key, required this.technician, required this.workload});

  final Technician technician;
  final Workload? workload;

  @override
  Widget build(BuildContext context) => AppChip(label: statusText(technician, workload), colors: statusTone(technicianStatus(technician, workload)), semanticPrefix: 'Estado');
}

String _count(Workload? workload, int Function(Workload) read) => workload == null ? '—' : '${read(workload)}';

/// Un técnico en la vista de tarjetas: quién es, su estado, su especialidad, sus tickets
/// abiertos y resueltos y, solo si [showRate] (quien gestiona técnicos), su tarifa por hora.
/// [highlighted] marca al técnico recién registrado.
class TechnicianCard extends StatelessWidget {
  const TechnicianCard({super.key, required this.technician, required this.workload, required this.onTap, this.showRate = false, this.highlighted = false});

  final Technician technician;

  /// `null` si la carga no está disponible: las cifras muestran «—».
  final Workload? workload;
  final VoidCallback onTap;
  final bool showRate;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specialization = technician.specialization?.trim() ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.mustard.withValues(alpha: .22) : AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: highlighted ? AppColors.mustard : AppColors.skyLight.withValues(alpha: .7), width: highlighted ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                UserAvatar(name: technician.fullName, muted: !technician.isActive),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(technician.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                    if (technician.email.isNotEmpty) Text(technician.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.folder_open_rounded, size: 15, color: AppColors.slate),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(specialization.isEmpty ? 'Sin especialización registrada' : specialization, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                TechnicianStatusChip(technician: technician, workload: workload),
                if (!technician.isActive) const AppChip(label: 'Cuenta inactiva', colors: inactiveTone, semanticPrefix: 'Cuenta'),
              ]),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Expanded(child: _Stat(icon: Icons.folder_open_rounded, value: _count(workload, (w) => w.openOf(technician.id)), label: 'ABIERTOS')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _Stat(icon: Icons.task_alt_rounded, value: _count(workload, (w) => w.resolvedOf(technician.id)), label: 'RESUELTOS')),
              ]),
              if (showRate) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label: 'Tarifa por hora: ${technician.hourlyRate == null ? 'sin registrar' : formatRate(technician.hourlyRate)}',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .28), borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.mustard.withValues(alpha: .6))),
                    child: Row(children: [
                      const Icon(Icons.payments_outlined, size: 18, color: AppColors.navy),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('TARIFA POR HORA', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800, letterSpacing: .3))),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatRate(technician.hourlyRate), style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)))),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: ${value == '—' ? 'no disponible' : value}',
      excludeSemantics: true,
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: neutralTone.background, borderRadius: AppRadius.smAll),
          child: Icon(icon, size: 18, color: neutralTone.foreground),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, height: 1.1)),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: .3))),
          ]),
        ),
      ]),
    );
  }
}

/// Vista de tabla: una fila por técnico con su estado y sus tickets abiertos y resueltos. La
/// especialidad va bajo el nombre para que quepa en un teléfono sin desplazamiento horizontal.
class TechniciansTable extends StatelessWidget {
  const TechniciansTable({super.key, required this.technicians, required this.workload, required this.onOpen, this.highlightedId});

  final List<Technician> technicians;
  final Workload? workload;
  final ValueChanged<Technician> onOpen;
  final int? highlightedId;

  static const _statusWidth = 96.0;
  static const _numberWidth = 42.0;
  static const _metricGap = 12.0;
  static const _arrowWidth = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800, letterSpacing: .3);
    Widget fitted(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, style: head));
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .7))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: AppColors.skyLight.withValues(alpha: .35),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            Expanded(child: Text('TÉCNICO', maxLines: 1, overflow: TextOverflow.ellipsis, style: head)),
            SizedBox(width: _statusWidth, child: fitted('ESTADO')),
            SizedBox(width: _numberWidth, child: fitted('ABIERTOS')),
            const SizedBox(width: _metricGap),
            SizedBox(width: _numberWidth, child: fitted('RESUELTOS')),
            const SizedBox(width: _arrowWidth),
          ]),
        ),
        for (final technician in technicians) ...[
          const Divider(height: 1, color: AppColors.canvas),
          _Row(technician: technician, workload: workload, highlighted: technician.id == highlightedId, onTap: () => onOpen(technician)),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.technician, required this.workload, required this.highlighted, required this.onTap});

  final Technician technician;
  final Workload? workload;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specialization = technician.specialization?.trim() ?? '';
    final number = theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800);
    final open = _count(workload, (w) => w.openOf(technician.id));
    final resolved = _count(workload, (w) => w.resolvedOf(technician.id));
    return Semantics(
      button: true,
      label: '${technician.fullName}. ${statusText(technician, workload)}. Abiertos: $open. Resueltos: $resolved',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: highlighted ? AppColors.mustard.withValues(alpha: .22) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(technician.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: technician.isActive ? AppColors.navy : AppColors.slate, fontWeight: FontWeight.w800)),
                    Text(
                      [if (specialization.isNotEmpty) specialization else 'Sin especialización', if (!technician.isActive) 'cuenta inactiva'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel),
                    ),
                  ]),
                ),
                SizedBox(
                  width: TechniciansTable._statusWidth,
                  child: FittedBox(fit: BoxFit.scaleDown, child: TechnicianStatusChip(technician: technician, workload: workload)),
                ),
                SizedBox(width: TechniciansTable._numberWidth, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(open, style: number)))),
                const SizedBox(width: TechniciansTable._metricGap),
                SizedBox(width: TechniciansTable._numberWidth, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(resolved, style: number)))),
                const SizedBox(width: TechniciansTable._arrowWidth, child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.slate)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
