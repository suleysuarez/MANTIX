part of 'ticket_board_bloc.dart';

enum BoardStatus { loading, ready, failure }

/// Aviso de una sola vez tras mover (o no poder mover) un ticket. [id] distingue avisos
/// iguales seguidos para que la pantalla muestre cada uno.
class BoardNotice extends Equatable {
  const BoardNotice({required this.id, required this.message, required this.isError});

  final int id;
  final String message;
  final bool isError;

  @override
  List<Object?> get props => [id, message, isError];
}

class TicketBoardState extends Equatable {
  const TicketBoardState({
    this.status = BoardStatus.loading,
    this.workflow = const [],
    this.movingIds = const {},
    this.notice,
    this.failure,
  });

  final BoardStatus status;
  final List<WorkflowStatus> workflow;

  /// Tickets cuyo cambio de estado está en curso (se muestran atenuados).
  final Set<int> movingIds;
  final BoardNotice? notice;
  final Failure? failure;

  WorkflowStatus? _of(String status) => workflow.where((state) => state.status == status).firstOrNull;

  /// Datos que exige el estado [target] para entrar en él.
  List<String> requiresFor(String target) => _of(target)?.requires ?? const [];

  /// ¿Puede quien llama mover [ticket] a [target]? Debe poder actuar sobre el ticket, la
  /// transición debe existir y debe tener permiso para entrar en el estado de destino.
  bool canMove(TicketListItem ticket, String target) {
    if (!ticket.canAct || ticket.status == target || movingIds.contains(ticket.id)) return false;
    final from = _of(ticket.status);
    final to = _of(target);
    return from != null && to != null && from.allowedTargets.contains(target) && to.canEnter;
  }

  /// Estados a los que se puede mover [ticket], en el orden del flujo.
  List<String> targetsFor(TicketListItem ticket) => [for (final state in workflow) if (canMove(ticket, state.status)) state.status];

  TicketBoardState copyWith({BoardStatus? status, List<WorkflowStatus>? workflow, Set<int>? movingIds, BoardNotice? notice, Failure? failure, bool clearFailure = false}) => TicketBoardState(
        status: status ?? this.status,
        workflow: workflow ?? this.workflow,
        movingIds: movingIds ?? this.movingIds,
        notice: notice ?? this.notice,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, workflow, movingIds, notice, failure];
}
