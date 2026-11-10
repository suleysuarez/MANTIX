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
///
/// Dos destinos usan su propio endpoint: «En triaje» clasifica (necesita [category] y
/// [priority]) y «Asignado» asigna un técnico (necesita [technicianId]).
class TicketMoveRequested extends TicketBoardEvent {
  const TicketMoveRequested(this.ticket, this.target, {this.notes, this.resolutionSummary, this.category, this.priority, this.technicianId});

  final TicketListItem ticket;
  final String target;
  final String? notes;
  final String? resolutionSummary;
  final String? category;
  final String? priority;
  final int? technicianId;
}
