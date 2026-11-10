part of 'request_board_bloc.dart';

sealed class RequestBoardEvent extends Equatable {
  const RequestBoardEvent();

  @override
  List<Object?> get props => [];
}

/// Carga el flujo de estados y la primera página de cada columna.
class RequestBoardStarted extends RequestBoardEvent {
  const RequestBoardStarted();
}

/// Recarga las columnas sin vaciarlas (tirar para refrescar, tras mover una tarjeta).
class RequestBoardRefreshed extends RequestBoardEvent {
  const RequestBoardRefreshed();
}

/// Aplica la hoja de filtros (o la limpia); la búsqueda se conserva.
class RequestBoardFiltersChanged extends RequestBoardEvent {
  const RequestBoardFiltersChanged(this.filters);

  final QueueFilters filters;

  @override
  List<Object?> get props => [filters];
}

/// Texto del buscador; se espera a que deje de escribir antes de pedir.
class RequestBoardSearchChanged extends RequestBoardEvent {
  const RequestBoardSearchChanged(this.term);

  final String term;

  @override
  List<Object?> get props => [term];
}

/// «Ver más» de una columna.
class RequestBoardMoreRequested extends RequestBoardEvent {
  const RequestBoardMoreRequested(this.status);

  final String status;

  @override
  List<Object?> get props => [status];
}

/// Reintenta una columna que falló.
class RequestBoardColumnRetried extends RequestBoardEvent {
  const RequestBoardColumnRetried(this.status);

  final String status;

  @override
  List<Object?> get props => [status];
}

/// Coloca la tarjeta en su nuevo estado antes de que el servidor responda (movimiento optimista).
class RequestBoardMovedOptimistically extends RequestBoardEvent {
  const RequestBoardMovedOptimistically(this.ticket, this.target);

  final TicketListItem ticket;
  final String target;

  @override
  List<Object?> get props => [ticket, target];
}

/// El servidor rechazó el movimiento: la tarjeta vuelve a su columna y a su sitio.
class RequestBoardMoveReverted extends RequestBoardEvent {
  const RequestBoardMoveReverted(this.ticketId);

  final int ticketId;

  @override
  List<Object?> get props => [ticketId];
}
