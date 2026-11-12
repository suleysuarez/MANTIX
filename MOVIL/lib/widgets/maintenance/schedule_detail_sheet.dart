import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/maintenance/schedule_actions_bloc.dart';
import '../../bloc/maintenance/schedule_detail_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../core/format/maintenance_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';
import '../shared/app_chip.dart';
import '../shared/confirm_dialog.dart';
import '../shared/detail_parts.dart';
import '../shared/mantix_sheet.dart';
import '../shared/skeleton.dart';
import 'complete_dialog.dart';
import 'maintenance_tones.dart';

/// La ficha de un plan en una hoja inferior arrastrable: sus datos y su historial (servicios hechos
/// y cambios de fecha). El plan y el historial cargan y fallan por separado, cada uno con su
/// reintento. [now] decide si el plan está vencido (se inyecta para probarlo). Con [actions] y
/// [canEdit] (`mantenimiento:editar`) salen «Marcar como hecho» y desactivar o activar el plan: si
/// la acción sale bien la hoja se cierra y el aviso lo da la pantalla; si falla, el motivo sale
/// dentro.
Future<void> showScheduleDetail(BuildContext context, {required int scheduleId, DateTime? now, ScheduleActionsBloc? actions, bool canEdit = false}) {
  final repository = context.read<MaintenanceRepository>();
  return showMantixSheet<void>(
    context,
    title: 'Plan de mantenimiento',
    builder: (sheetContext, controller) => BlocProvider(
      create: (_) => ScheduleDetailBloc(repository: repository, scheduleId: scheduleId)..add(const ScheduleDetailRequested()),
      child: _ScheduleDetail(controller: controller, now: now ?? DateTime.now(), actions: canEdit ? actions : null),
    ),
  );
}

class _ScheduleDetail extends StatefulWidget {
  const _ScheduleDetail({required this.controller, required this.now, required this.actions});

  final ScrollController controller;
  final DateTime now;
  final ScheduleActionsBloc? actions;

  @override
  State<_ScheduleDetail> createState() => _ScheduleDetailState();
}

class _ScheduleDetailState extends State<_ScheduleDetail> {
  /// Esta hoja pidió una acción y espera su resultado (la pantalla comparte el bloc).
  bool _waiting = false;
  String? _error;

  Future<void> _complete(MaintenanceSchedule plan) async {
    final hours = await showCompleteDialog(context, title: plan.title);
    if (hours == null || !mounted) return;
    _send(ScheduleCompleteRequested(plan, actualHours: hours));
  }

  /// Desactivar pide confirmación y explica el alcance; activar de nuevo no la pide.
  Future<void> _toggle(MaintenanceSchedule plan) async {
    if (plan.isActive) {
      final ok = await showConfirmDialog(
        context,
        title: '¿Desactivar el plan «${plan.title}»?',
        message: 'El plan quedará inactivo: dejará de verse en el calendario y en los próximos mantenimientos, y no se podrá marcar como hecho. Puedes activarlo de nuevo cuando quieras.',
        confirmLabel: 'Desactivar plan',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    _send(ScheduleActiveChangeRequested(plan, active: !plan.isActive));
  }

  void _send(ScheduleActionsEvent event) {
    setState(() => _error = null);
    _waiting = true;
    widget.actions!.add(event);
  }

  void _onOutcome(BuildContext context, ScheduleActionsState state) {
    final outcome = state.outcome;
    if (outcome == null || !_waiting) return;
    _waiting = false;
    if (outcome.kind == ScheduleOutcomeKind.succeeded) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _error = outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    if (actions == null) return _content(context, busy: false);
    return BlocConsumer<ScheduleActionsBloc, ScheduleActionsState>(
      bloc: actions,
      listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
      listener: _onOutcome,
      builder: (context, state) => _content(context, busy: state.busy),
    );
  }

  Widget _content(BuildContext context, {required bool busy}) => BlocBuilder<ScheduleDetailBloc, ScheduleDetailState>(
        builder: (context, state) {
          final bloc = context.read<ScheduleDetailBloc>();
          final plan = state.plan;
          final theme = Theme.of(context);
          return ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
            children: [
              if (plan == null && state.planStatus == PlanBlockStatus.loading)
                Semantics(label: 'Cargando el plan', child: const Column(children: [Skeleton(height: 110, radius: AppRadius.lg), SizedBox(height: AppSpacing.md), Skeleton(height: 200, radius: AppRadius.lg)]))
              else if (plan == null)
                _BlockError(message: 'No pudimos cargar el plan. ${state.planFailure?.message ?? ''}'.trim(), onRetry: () => bloc.add(const SchedulePlanRetried()))
              else ...[
                _Header(plan: plan, now: widget.now),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: AppRadius.mdAll),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.3))),
                    ]),
                  ),
                ],
                if (widget.actions != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  // Un plan inactivo no se puede marcar como hecho (el servidor lo rechaza).
                  if (plan.isActive) ...[
                    FilledButton.icon(
                      onPressed: busy ? null : () => _complete(plan),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Marcar como hecho', maxLines: 1)),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.navy, foregroundColor: AppColors.mustard),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _toggle(plan),
                    icon: Icon(plan.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded, size: 18),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(plan.isActive ? 'Desactivar plan' : 'Activar plan', maxLines: 1)),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: plan.isActive ? theme.colorScheme.error : AppColors.steel),
                  ),
                  if (busy) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: LinearProgressIndicator(minHeight: 3)),
                ],
                const SizedBox(height: AppSpacing.md),
                _Data(plan: plan, now: widget.now),
              ],
              const SizedBox(height: AppSpacing.md),
              _History(state: state, createdAt: plan?.createdAt, onRetry: () => bloc.add(const ScheduleHistoryRetried())),
            ],
          );
        },
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.plan, required this.now});

  final MaintenanceSchedule plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final state = plan.stateAt(now);
    return DetailHeader(
      icon: Icons.edit_calendar_outlined,
      pill: plan.equipment.assetTag,
      title: plan.title,
      chips: [AppChip(label: scheduleStateLabel(state), colors: scheduleTone(state), semanticPrefix: 'Estado')],
    );
  }
}

class _Data extends StatelessWidget {
  const _Data({required this.plan, required this.now});

  final MaintenanceSchedule plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final created = plan.createdAt;
    final description = plan.description?.trim();
    return DetailSection(icon: Icons.info_outline_rounded, title: 'Datos del plan', children: [
      DetailField('Equipo', '${plan.equipment.assetTag} · ${plan.equipment.brand} ${plan.equipment.model}'),
      DetailField('Próximo servicio', formatDateTime(plan.nextDueAt)),
      DetailField('Se repite', intervalText(plan.intervalDays)),
      DetailField('Recordatorio', plan.remindDaysBefore == 0 ? 'El mismo día' : '${plan.remindDaysBefore} ${plan.remindDaysBefore == 1 ? 'día' : 'días'} antes'),
      DetailField('Técnico responsable', plan.technician?.fullName ?? 'Sin asignar (los recordatorios le llegan a quien lo programó)'),
      DetailField('Horas estimadas', formatPlanHours(plan.estimatedHours)),
      if (description != null && description.isNotEmpty) DetailField('Descripción', description),
      if (created != null) DetailField('Programado', formatDate(created)),
    ]);
  }
}

class _History extends StatelessWidget {
  const _History({required this.state, required this.createdAt, required this.onRetry});

  final ScheduleDetailState state;
  final DateTime? createdAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = state.history;
    return DetailSection(icon: Icons.history_rounded, title: 'Historial', children: [
      if (history == null && state.historyStatus == PlanBlockStatus.loading)
        Semantics(label: 'Cargando el historial', child: const Column(children: [Skeleton(height: 44), SizedBox(height: AppSpacing.sm), Skeleton(height: 44)]))
      else if (history == null)
        _BlockError(message: 'No pudimos cargar el historial. ${state.historyFailure?.message ?? ''}'.trim(), onRetry: onRetry)
      else if (history.runs.isEmpty && history.reschedules.isEmpty && createdAt == null)
        Text('Este plan aún no tiene servicios hechos ni cambios de fecha.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))
      else ...[
        if (createdAt != null)
          _Entry(
            icon: Icons.add_circle_outline_rounded,
            title: 'Plan creado el ${formatDate(createdAt!)}',
            detail: 'Se registró el mantenimiento preventivo por primera vez.',
            tone: plannedTone,
          ),
        for (final run in history.runs)
          _Entry(
            icon: Icons.check_circle_outline_rounded,
            title: 'Servicio hecho el ${formatDate(run.completedAt)}',
            detail: [
              run.onTime ? 'A tiempo' : 'Con retraso',
              'previsto el ${formatDate(run.dueAt)}',
              if (run.actualHours != null) '${formatPlanHours(run.actualHours)} reales',
            ].join(' · '),
            tone: run.onTime ? StatusColors.resolved : StatusColors.inProgress,
          ),
        for (final change in history.reschedules)
          _Entry(
            icon: Icons.update_rounded,
            title: 'Fecha cambiada el ${formatDate(change.changedAt)}',
            detail: ['de ${formatDate(change.oldDueAt)} a ${formatDate(change.newDueAt)}', if ((change.reason ?? '').trim().isNotEmpty) change.reason!.trim()].join(' · '),
            tone: plannedTone,
          ),
      ],
    ]);
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.icon, required this.title, required this.detail, required this.tone});

  final IconData icon;
  final String title;
  final String detail;
  final ChipColors tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: tone.background, shape: BoxShape.circle), child: Icon(icon, size: 19, color: tone.foreground)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700)),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}

/// Bloque que no cargó: el motivo y un botón para reintentar solo ese bloque.
class _BlockError extends StatelessWidget {
  const _BlockError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
        ]),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Reintentar')),
      ]);
}
