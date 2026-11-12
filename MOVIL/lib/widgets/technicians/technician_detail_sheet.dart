import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/technicians/technician_actions_bloc.dart';
import '../../bloc/technicians/technician_detail_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/queue_format.dart' show formatHours, formatPct, periodLabel;
import '../../core/format/technicians_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../shared/app_chip.dart';
import '../shared/confirm_dialog.dart';
import '../shared/detail_parts.dart';
import '../shared/mantix_sheet.dart';
import '../shared/skeleton.dart';
import '../tickets/ticket_cards.dart';
import '../tickets/ticket_detail_sheet.dart';
import 'technician_form_sheet.dart';
import 'technician_tones.dart';
import 'technician_views.dart';

/// Ficha de un técnico en una hoja inferior arrastrable: sus datos, su carga, sus indicadores
/// del periodo y sus tickets abiertos. Los indicadores y los tickets cargan y fallan por
/// separado. [workload] es la carga que ya tiene la lista (`null` si no está disponible).
/// [showRate] enseña la tarifa (solo a quien gestiona técnicos) y [showTickets] la lista de
/// tickets (solo a quien puede ver tickets). Con [actions] (solo para quien tiene
/// `tecnicos:editar`) salen «Editar perfil» y el cambio de disponibilidad: si la acción sale
/// bien la hoja se cierra y el aviso lo da la pantalla; si falla, el motivo sale dentro.
Future<void> showTechnicianDetail(BuildContext context, {required Technician technician, required Workload? workload, bool showRate = false, bool showTickets = true, TechnicianActionsBloc? actions}) => showMantixSheet<void>(
      context,
      title: 'Ficha del técnico',
      builder: (sheetContext, controller) => BlocProvider(
        create: (_) => TechnicianDetailBloc(
          technicians: context.read<TechniciansRepository>(),
          requests: context.read<RequestsRepository>(),
          technicianId: technician.id,
          withTickets: showTickets,
        )..add(const TechnicianDetailRequested()),
        child: _TechnicianDetail(technician: technician, workload: workload, controller: controller, showRate: showRate, showTickets: showTickets, actions: actions),
      ),
    );

class _TechnicianDetail extends StatefulWidget {
  const _TechnicianDetail({required this.technician, required this.workload, required this.controller, required this.showRate, required this.showTickets, required this.actions});

  final Technician technician;
  final Workload? workload;
  final ScrollController controller;
  final bool showRate;
  final bool showTickets;
  final TechnicianActionsBloc? actions;

  @override
  State<_TechnicianDetail> createState() => _TechnicianDetailState();
}

class _TechnicianDetailState extends State<_TechnicianDetail> {
  /// Esta hoja pidió el cambio de disponibilidad y espera su resultado.
  bool _waiting = false;
  String? _error;

  Technician get technician => widget.technician;
  Workload? get workload => widget.workload;
  ScrollController get controller => widget.controller;
  bool get showRate => widget.showRate;
  bool get showTickets => widget.showTickets;

  Future<void> _edit() async {
    final saved = await showTechnicianForm(context, actions: widget.actions!, technician: technician);
    if (saved == true && mounted) await Navigator.of(context).maybePop();
  }

  /// Marcar como no disponible pide confirmación y avisa de los tickets que siguen asignados.
  Future<void> _toggleAvailability() async {
    if (technician.isAvailable) {
      final open = workload?.openOf(technician.id) ?? 0;
      final ok = await showConfirmDialog(
        context,
        title: '¿Marcar a ${technician.fullName} como no disponible?',
        message: [
          'Aparecerá como no disponible para el equipo. Puedes volver a marcarlo como disponible cuando quieras.',
          if (open > 0) 'Tiene $open ${open == 1 ? 'ticket abierto' : 'tickets abiertos'}: ${open == 1 ? 'seguirá asignado' : 'seguirán asignados'} a esta persona.',
        ].join(' '),
        confirmLabel: 'Marcar no disponible',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _error = null);
    _waiting = true;
    widget.actions!.add(TechnicianAvailabilityRequested(technician, available: !technician.isAvailable));
  }

  void _onOutcome(BuildContext context, TechnicianActionsState state) {
    final outcome = state.outcome;
    if (outcome == null || !_waiting) return;
    _waiting = false;
    if (outcome.kind == TechnicianOutcomeKind.succeeded) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _error = outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    if (actions == null) return _content(context, busy: false);
    return BlocConsumer<TechnicianActionsBloc, TechnicianActionsState>(
      bloc: actions,
      listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
      listener: _onOutcome,
      builder: (context, state) => _content(context, busy: state.busy),
    );
  }

  Widget _content(BuildContext context, {required bool busy}) {
    final theme = Theme.of(context);
    final tags = specialties(technician);
    final loads = workload;
    final created = technician.createdAt;
    final open = loads?.openOf(technician.id) ?? 0;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: [
        DetailHeader(
          icon: Icons.engineering_outlined,
          pill: technician.employeeCode ?? 'Sin código',
          title: technician.fullName,
          chips: [
            TechnicianStatusChip(technician: technician, workload: workload),
            if (!technician.isActive) const AppChip(label: 'Cuenta inactiva', colors: inactiveTone, semanticPrefix: 'Cuenta'),
          ],
        ),
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
          if (technician.isAvailable && open > 0)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .28), borderRadius: AppRadius.mdAll),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.navy),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Tiene $open ${open == 1 ? 'ticket abierto' : 'tickets abiertos'}: ${open == 1 ? 'seguirá asignado' : 'seguirán asignados'} a esta persona aunque la marques como no disponible.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.navy, height: 1.3),
                  ),
                ),
              ]),
            ),
          FilledButton.icon(
            onPressed: busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Editar perfil', maxLines: 1)),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.navy, foregroundColor: AppColors.mustard),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: busy ? null : _toggleAvailability,
            icon: Icon(technician.isAvailable ? Icons.do_not_disturb_on_outlined : Icons.check_circle_outline_rounded, size: 18),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(technician.isAvailable ? 'Marcar como no disponible' : 'Marcar como disponible', maxLines: 1)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: AppColors.steel),
          ),
          if (busy) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: LinearProgressIndicator(minHeight: 3)),
        ],
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.info_outline_rounded, title: 'Datos', children: [
          DetailField('Correo', technician.email.isEmpty ? 'Sin registrar' : technician.email),
          Text('Especialidades', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          if (tags.isEmpty)
            Text('Aún no se registraron especialidades.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in tags) _Tag(tag)]),
          const SizedBox(height: AppSpacing.md),
          DetailField('Disponibilidad', technician.isAvailable ? 'Disponible para recibir tickets' : 'No disponible'),
          DetailField('Cuenta de usuario', technician.isActive ? 'Activa' : 'Inactiva: no se le pueden asignar tickets'),
          if (showRate) DetailField('Tarifa por hora', technician.hourlyRate == null ? 'Sin registrar' : formatRate(technician.hourlyRate)),
          if (created != null) DetailField('Perfil creado', formatDate(created.toLocal())),
        ]),
        const SizedBox(height: AppSpacing.md),
        DetailSection(icon: Icons.stacked_bar_chart_rounded, title: 'Carga de trabajo', children: [
          if (loads == null)
            Text('La carga de tickets no está disponible.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _Figure(value: '${loads.openOf(technician.id)}', label: 'Tickets abiertos')),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _Figure(value: '${loads.resolvedOf(technician.id)}', label: 'Resueltos en ${loads.windowDays} días')),
            ]),
        ]),
        const SizedBox(height: AppSpacing.md),
        const _Performance(),
        if (showTickets) ...[const SizedBox(height: AppSpacing.md), const _OpenTickets()],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: neutralTone.background, borderRadius: AppRadius.pillAll),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: neutralTone.foreground, fontWeight: FontWeight.w700)),
      );
}

/// Un número grande con su nombre debajo y, si hace falta, una nota.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.note, this.fewData = false});

  final String value;
  final String label;
  final String? note;
  final bool fewData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: [label, value == '—' ? 'sin dato' : value, if (fewData) 'pocos datos', ?note].join(', '),
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900))),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700)),
        if (fewData)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: fewDataTone.background, borderRadius: AppRadius.pillAll),
              child: Text('pocos datos', style: theme.textTheme.labelSmall?.copyWith(color: fewDataTone.foreground, fontWeight: FontWeight.w800)),
            ),
          ),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note!, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel))),
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

/// Indicadores del periodo. Se presentan como apoyo para repartir el trabajo, no como una
/// calificación: sin colores de «bueno» o «malo» ni comparación con otros técnicos.
class _Performance extends StatelessWidget {
  const _Performance();

  @override
  Widget build(BuildContext context) => BlocBuilder<TechnicianDetailBloc, TechnicianDetailState>(
        buildWhen: (previous, current) => previous.performanceStatus != current.performanceStatus || previous.performance != current.performance,
        builder: (context, state) {
          final theme = Theme.of(context);
          final period = periodLabel(state.period);
          final data = state.performance;
          return DetailSection(icon: Icons.insights_rounded, title: period == null ? 'Indicadores' : 'Indicadores de los últimos $period', children: [
            if (state.performanceStatus == DetailBlockStatus.loading)
              Semantics(label: 'Cargando indicadores', child: const Column(children: [Skeleton(height: 44), SizedBox(height: AppSpacing.sm), Skeleton(height: 44)]))
            else if (state.performanceStatus == DetailBlockStatus.failure)
              _BlockError(
                message: 'No pudimos cargar los indicadores. ${state.performanceFailure?.message ?? ''}'.trim(),
                onRetry: () => context.read<TechnicianDetailBloc>().add(const TechnicianPerformanceRetried()),
              )
            else if (data == null)
              Text('No hay indicadores disponibles para este técnico.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))
            else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _Figure(
                    value: formatHours(data.mttrMedianHours),
                    label: 'Tiempo de resolución (mediana)',
                    fewData: data.lowSample,
                    note: data.mttrMedianHours == null ? 'Sin tickets resueltos en el periodo' : 'n = ${data.sampleSize}',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Figure(
                    value: formatPct(data.slaCompliancePct),
                    label: 'Cumplimiento de SLA',
                    fewData: data.slaLowSample,
                    note: [
                      if (data.slaCompliancePct != null) 'n = ${data.slaSampleSize}' else if (data.slaExcludedNoSla == 0) 'Sin tickets resueltos con SLA',
                      if (data.slaExcludedNoSla > 0) '${data.slaExcludedNoSla} sin SLA excluidos',
                    ].join(' · '),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _Figure(value: '${data.resolved}', label: 'Resueltos')),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _Figure(value: '${data.reopened}', label: 'Reabiertos')),
              ]),
              const SizedBox(height: AppSpacing.md),
              Text(
                'n = tickets resueltos en el periodo. Las prioridades sin SLA no entran en el cumplimiento. Reabiertos: pasaron de resuelto a en curso. Estas cifras sirven para repartir el trabajo, no para comparar personas.',
                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, height: 1.35),
              ),
            ],
          ]);
        },
      );
}

class _OpenTickets extends StatelessWidget {
  const _OpenTickets();

  @override
  Widget build(BuildContext context) => BlocBuilder<TechnicianDetailBloc, TechnicianDetailState>(
        buildWhen: (previous, current) => previous.ticketsStatus != current.ticketsStatus || previous.tickets != current.tickets,
        builder: (context, state) {
          final theme = Theme.of(context);
          final ready = state.ticketsStatus == DetailBlockStatus.ready;
          final hidden = state.ticketsTotal - state.tickets.length;
          return DetailSection(icon: Icons.confirmation_number_outlined, title: ready ? 'Tickets abiertos (${state.ticketsTotal})' : 'Tickets abiertos', children: [
            if (state.ticketsStatus == DetailBlockStatus.loading)
              Semantics(label: 'Cargando tickets abiertos', child: const Column(children: [Skeleton(height: 72, radius: AppRadius.md), SizedBox(height: AppSpacing.sm), Skeleton(height: 72, radius: AppRadius.md)]))
            else if (state.ticketsStatus == DetailBlockStatus.failure)
              _BlockError(
                message: 'No pudimos cargar sus tickets. ${state.ticketsFailure?.message ?? ''}'.trim(),
                onRetry: () => context.read<TechnicianDetailBloc>().add(const TechnicianTicketsRetried()),
              )
            else if (state.tickets.isEmpty)
              Row(children: [
                const Icon(Icons.inbox_outlined, color: AppColors.slate),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('No tiene tickets abiertos.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))),
              ])
            else ...[
              for (final ticket in state.tickets) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: TicketListCard(item: ticket, onTap: () => showTicketDetail(context, ticket.id))),
              if (hidden > 0) Text(hidden == 1 ? 'Y 1 ticket más.' : 'Y $hidden tickets más.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
            ],
          ]);
        },
      );
}
