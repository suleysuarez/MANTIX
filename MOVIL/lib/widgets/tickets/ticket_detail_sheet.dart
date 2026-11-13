import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/requests/request_detail_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../shared/app_chip.dart';
import '../shared/detail_parts.dart';
import '../shared/error_state.dart';
import '../shared/mantix_sheet.dart';
import '../shared/skeleton.dart';
import '../shared/timeline.dart';
import 'ticket_actions.dart';

/// Detalle de un ticket en una hoja inferior arrastrable (la pantalla de fondo, con su
/// encabezado, sigue visible): datos, historial de estados con el momento de creación, y
/// adjuntos. Es de lectura, salvo que [canAct] sea cierto (el ticket es de quien lo abre) y la
/// cuenta tenga `tickets:cambiar_estado`: entonces ofrece iniciar, poner en espera y resolver.
Future<void> showTicketDetail(BuildContext context, int ticketId, {bool canAct = false}) {
  final profile = context.read<AuthBloc>().state.profile;
  final withActions = canAct && (profile?.can('tickets:cambiar_estado') ?? false);
  return showMantixSheet<void>(
    context,
    title: 'Detalle del ticket',
    builder: (sheetContext, controller) => BlocProvider(
      create: (_) {
        final bloc = RequestDetailBloc(repository: context.read<RequestsRepository>(), requestId: ticketId)
          ..add(const RequestDetailRequested())
          ..add(const RequestAttachmentsRequested());
        if (withActions) bloc.add(const RequestWorkflowRequested());
        return bloc;
      },
      child: TicketDetailBody(controller: controller, withActions: withActions),
    ),
  );
}

class TicketDetailBody extends StatelessWidget {
  const TicketDetailBody({super.key, this.controller, this.onRefresh, this.withActions = false});

  final ScrollController? controller;

  /// Muestra las acciones del técnico (el detalle ya cargó el flujo de estados).
  final bool withActions;

  /// Si se da, la lista se puede recargar tirando hacia abajo (la pantalla por ruta lo usa; la
  /// hoja no, porque tirar hacia abajo ahí la arrastra).
  final Future<void> Function()? onRefresh;

  Widget _scrollable(Widget list) => onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);

  @override
  Widget build(BuildContext context) => BlocConsumer<RequestDetailBloc, RequestDetailState>(
        listenWhen: (previous, current) => previous.changeSerial != current.changeSerial,
        listener: (context, state) {
          final failure = state.changeFailure;
          final text = failure != null ? failure.message : 'Ticket actualizado: ${statusMeta(state.changedTo ?? '').label}.';
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(text)));
        },
        builder: (context, state) {
          final ticket = state.ticket;
          if (ticket == null) {
            if (state.status == LoadStatus.failure && state.failure != null) {
              return _scrollable(ListView(controller: controller, physics: const AlwaysScrollableScrollPhysics(), children: [
                ErrorState(failure: state.failure!, onRetry: () => context.read<RequestDetailBloc>().add(const RequestDetailRequested())),
              ]));
            }
            return ListView(controller: controller, padding: const EdgeInsets.all(AppSpacing.lg), children: [
              for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.md), child: Skeleton(height: 72)),
            ]);
          }
          return _scrollable(ListView(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
            children: [
              DetailHeader(
                icon: categoryIcon(ticket.category),
                pill: ticket.ticketNumber,
                title: ticket.title,
                chips: [StatusChip(ticket.status), PriorityChip(ticket.priority)],
              ),
              const SizedBox(height: AppSpacing.md),
              if (withActions)
                TicketActions(
                  ticket: ticket,
                  workflow: state.workflow,
                  changing: state.changing,
                  onChange: (target, {notes, resolutionSummary}) => context.read<RequestDetailBloc>().add(RequestStatusChangeRequested(target, notes: notes, resolutionSummary: resolutionSummary)),
                ),
              DetailSection(icon: Icons.info_outline_rounded, title: 'Datos del ticket', children: [
                DetailField('Equipo', ticket.equipment.label),
                DetailField('Técnico asignado', ticket.technicianName ?? 'Sin asignar'),
                DetailField('Creado', formatDateTime(ticket.createdAt.toLocal())),
                DetailField('Última actualización', formatDateTime(ticket.updatedAt.toLocal())),
                DetailField('Descripción', ticket.description),
                if (ticket.resolutionSummary != null) DetailField('Resolución', ticket.resolutionSummary!),
              ]),
              const SizedBox(height: AppSpacing.md),
              DetailSection(icon: Icons.history_rounded, title: 'Historial', children: [Timeline(entries: ticketTimeline(ticket))]),
              const SizedBox(height: AppSpacing.md),
              const DetailSection(icon: Icons.attach_file_rounded, title: 'Adjuntos', children: [_Attachments()]),
            ],
          ));
        },
      );
}

/// Línea de tiempo del ticket: primero su creación y luego cada cambio de estado. El primer
/// registro del servidor (sin estado anterior) es la creación misma, así que no se repite.
List<TimelineEntry> ticketTimeline(TicketDetail ticket) {
  final changes = [for (final entry in ticket.history) if (entry.fromStatus != null) entry];
  final initial = ticket.history.where((entry) => entry.fromStatus == null).firstOrNull;
  return [
    TimelineEntry(
      title: 'Ticket creado',
      subtitle: initial == null ? null : 'Estado inicial: ${statusMeta(initial.toStatus).label}',
      at: initial?.changedAt ?? ticket.createdAt,
      icon: Icons.add_circle_outline_rounded,
      color: AppColors.navy,
    ),
    for (final entry in changes)
      TimelineEntry(
        title: '${statusMeta(entry.fromStatus!).label} → ${statusMeta(entry.toStatus).label}',
        subtitle: entry.notes,
        at: entry.changedAt,
        icon: statusIcon(entry.toStatus),
        color: statusMeta(entry.toStatus).colors.dot,
      ),
  ];
}

/// Los adjuntos cargan aparte: si fallan, el resto del detalle sigue visible.
class _Attachments extends StatelessWidget {
  const _Attachments();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RequestDetailBloc>().state;
    final theme = Theme.of(context);
    return switch (state.attachmentsStatus) {
      LoadStatus.loading => const Skeleton(height: 40),
      LoadStatus.failure => Row(children: [
          Expanded(child: Text('No pudimos cargar los adjuntos.', style: theme.textTheme.bodySmall)),
          TextButton(onPressed: () => context.read<RequestDetailBloc>().add(const RequestAttachmentsRequested()), child: const Text('Reintentar')),
        ]),
      LoadStatus.success => state.attachments.isEmpty
          ? Text('Este ticket no tiene adjuntos.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate))
          : Column(children: [
              for (final item in state.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(children: [
                    Icon(item.mimeType.startsWith('image/') ? Icons.image_outlined : Icons.description_outlined, color: AppColors.steel),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(item.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy))),
                    const SizedBox(width: AppSpacing.sm),
                    Text(formatFileSize(item.fileSize), style: theme.textTheme.labelSmall?.copyWith(color: AppColors.slate)),
                  ]),
                ),
            ]),
    };
  }
}
