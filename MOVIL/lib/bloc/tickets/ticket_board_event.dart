part of 'ticket_board_bloc.dart';

sealed class TicketBoardEvent {
  const TicketBoardEvent();
}

/// Carga el flujo de estados del servidor (o lo reintenta).
class TicketBoardStarted extends TicketBoardEvent {
  const TicketBoardStarted();
}

/// Pide mover [ticket] al estado [target]. [notes] y [resolutionSummary] son los datos que el
/// estado de destino exige (motivo al cancelar, resolución al resolver).
class TicketMoveRequested extends TicketBoardEvent {
  const TicketMoveRequested(this.ticket, this.target, {this.notes, this.resolutionSummary});

  final TicketListItem ticket;
  final String target;
  final String? notes;
  final String? resolutionSummary;
}
