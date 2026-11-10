part of 'triage_actions_bloc.dart';

sealed class TriageActionsEvent extends Equatable {
  const TriageActionsEvent();

  @override
  List<Object?> get props => [];
}

/// Mover [ticket] a [target] con los datos que el destino exige: categoría y prioridad para
/// clasificar, [technicianId] para asignar, [reason] para rechazar. [workflow] es el flujo
/// que ya tiene el tablero.
class TriageMoveRequested extends TriageActionsEvent {
  const TriageMoveRequested(this.ticket, this.target, {required this.workflow, this.category, this.priority, this.technicianId, this.reason, this.notes, this.resolutionSummary});

  final TicketListItem ticket;
  final String target;
  final QueueWorkflow workflow;
  final String? category;
  final String? priority;
  final int? technicianId;
  final String? reason;
  final String? notes;
  final String? resolutionSummary;

  @override
  List<Object?> get props => [ticket, target, workflow, category, priority, technicianId, reason, notes, resolutionSummary];
}
