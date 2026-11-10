import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure_mapper.dart';
import '../../core/format/queue_format.dart';
import '../../core/format/ticket_meta.dart';
import '../../models/queue/queue_workflow.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

part 'triage_actions_event.dart';
part 'triage_actions_state.dart';

/// Clasificar, asignar, rechazar o mover una solicitud de la bandeja. Valida contra el flujo del
/// servidor antes de pedir nada (permiso, transición y datos que exige el destino) y elige el
/// endpoint según el destino, como la web: `classify`, `assignment`, `reject` o `status`.
///
/// No toca el tablero: avisa con un [TriageOutcome] (`started` al empezar, para mover la tarjeta
/// de forma optimista; `failed` si el servidor la rechaza, para devolverla) y la pantalla se lo
/// pasa a `RequestBoardBloc` y a `QueueSummaryBloc`.
class TriageActionsBloc extends Bloc<TriageActionsEvent, TriageActionsState> {
  TriageActionsBloc({required this._repository}) : super(const TriageActionsState()) {
    on<TriageMoveRequested>(_onMove);
  }

  final RequestsRepository _repository;
  int _outcomes = 0;

  String _label(String status) => columnText(status, fallback: statusMeta(status).label).title;

  TriageOutcome _outcome(TriageOutcomeKind kind, TicketListItem ticket, String target, String message) => TriageOutcome(id: ++_outcomes, kind: kind, ticket: ticket, target: target, message: message);

  /// Qué dato de los que exige el destino falta, o `null` si está todo.
  String? _missing(List<String> requires, TriageMoveRequested event) {
    final needsCategory = requires.contains('category') && (event.category == null || event.category!.isEmpty);
    final needsPriority = requires.contains('priority') && (event.priority == null || event.priority!.isEmpty);
    if (needsCategory && needsPriority) return 'Elige la categoría y la prioridad.';
    if (needsCategory) return 'Elige la categoría.';
    if (needsPriority) return 'Elige la prioridad.';
    if (requires.contains('technician') && event.technicianId == null) return 'Elige un técnico.';
    if (requires.contains('reason')) return reasonError(event.reason);
    if (requires.contains('resolution_summary') && (event.resolutionSummary ?? '').trim().isEmpty) return 'Escribe el resumen de la resolución.';
    return null;
  }

  Future<void> _onMove(TriageMoveRequested event, Emitter<TriageActionsState> emit) async {
    final ticket = event.ticket;
    final target = event.target;
    final workflow = event.workflow;

    void blocked(String message) => emit(state.copyWith(outcome: _outcome(TriageOutcomeKind.blocked, ticket, target, message)));

    if (state.inFlight.contains(ticket.id)) return;
    final permission = workflow.permissionBlock(ticket, target, label: _label);
    if (permission != null) return blocked(permission);
    if (!workflow.canMove(ticket, target)) return blocked('Ese cambio de estado no está permitido para esta solicitud.');
    final missing = _missing(workflow.requiresFor(target), event);
    if (missing != null) return blocked(missing);

    emit(state.copyWith(inFlight: {...state.inFlight, ticket.id}, outcome: _outcome(TriageOutcomeKind.started, ticket, target, '')));
    try {
      switch (target) {
        case 'triaged':
          await _repository.classify(ticket.id, category: event.category!, priority: event.priority!, notes: event.notes);
        case 'assigned':
          await _repository.assignTechnician(ticket.id, technicianId: event.technicianId!, notes: event.notes);
        case 'cancelled' when workflow.isColumn(ticket.status):
          await _repository.reject(ticket.id, reason: event.reason!);
        default:
          await _repository.transitionStatus(ticket.id, target, notes: event.notes ?? event.reason, resolutionSummary: event.resolutionSummary);
      }
      final message = target == 'cancelled' ? '${ticket.ticketNumber} fue rechazada.' : '${ticket.ticketNumber} pasó a «${_label(target)}».';
      emit(state.copyWith(inFlight: {...state.inFlight}..remove(ticket.id), outcome: _outcome(TriageOutcomeKind.succeeded, ticket, target, message)));
    } catch (error) {
      emit(state.copyWith(
        inFlight: {...state.inFlight}..remove(ticket.id),
        outcome: _outcome(TriageOutcomeKind.failed, ticket, target, 'No se pudo mover ${ticket.ticketNumber}: ${toFailure(error).message}'),
      ));
    }
  }
}
