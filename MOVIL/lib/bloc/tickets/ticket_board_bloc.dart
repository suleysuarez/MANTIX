import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/ticket_meta.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';

part 'ticket_board_event.dart';
part 'ticket_board_state.dart';

/// Mover tickets entre estados en el tablero. Las transiciones válidas salen del servidor
/// (`/maintenance/requests/workflow`), no de una tabla en la app. No hay movimiento
/// optimista: la tarjeta cambia de columna solo cuando el servidor lo acepta, y si falla se
/// queda donde estaba con un aviso. Al terminar, el listado se recarga solo
/// (`RequestsRepository.changes`).
class TicketBoardBloc extends Bloc<TicketBoardEvent, TicketBoardState> {
  TicketBoardBloc({required this._repository}) : super(const TicketBoardState()) {
    on<TicketBoardStarted>(_onStarted);
    on<TicketMoveRequested>(_onMove);
  }

  final RequestsRepository _repository;
  int _notices = 0;

  Future<void> _onStarted(TicketBoardStarted event, Emitter<TicketBoardState> emit) async {
    emit(state.copyWith(status: BoardStatus.loading, clearFailure: true));
    try {
      final workflow = await _repository.workflow();
      emit(state.copyWith(status: BoardStatus.ready, workflow: workflow));
    } catch (error) {
      emit(state.copyWith(status: BoardStatus.failure, failure: toFailure(error)));
    }
  }

  Future<void> _onMove(TicketMoveRequested event, Emitter<TicketBoardState> emit) async {
    final ticket = event.ticket;
    if (!state.canMove(ticket, event.target)) {
      emit(state.copyWith(notice: BoardNotice(id: ++_notices, message: 'Ese cambio de estado no está permitido para este ticket.', isError: true)));
      return;
    }
    emit(state.copyWith(movingIds: {...state.movingIds, ticket.id}));
    try {
      await _repository.transitionStatus(ticket.id, event.target, notes: event.notes, resolutionSummary: event.resolutionSummary);
      emit(state.copyWith(
        movingIds: {...state.movingIds}..remove(ticket.id),
        notice: BoardNotice(id: ++_notices, message: '${ticket.ticketNumber} pasó a «${statusMeta(event.target).label}».', isError: false),
      ));
    } catch (error) {
      emit(state.copyWith(
        movingIds: {...state.movingIds}..remove(ticket.id),
        notice: BoardNotice(id: ++_notices, message: 'No se pudo mover ${ticket.ticketNumber}: ${toFailure(error).message}', isError: true),
      ));
    }
  }
}
