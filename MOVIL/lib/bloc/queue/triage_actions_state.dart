part of 'triage_actions_bloc.dart';

/// Qué pasó con un movimiento: [started] (se pidió al servidor), [succeeded], [failed] (el
/// servidor lo rechazó o no hubo red: hay que devolver la tarjeta) o [blocked] (ni se pidió:
/// falta permiso, la transición no existe o faltan datos).
enum TriageOutcomeKind { started, succeeded, failed, blocked }

/// Resultado de una sola vez. [id] distingue resultados iguales seguidos.
class TriageOutcome extends Equatable {
  const TriageOutcome({required this.id, required this.kind, required this.ticket, required this.target, required this.message});

  final int id;
  final TriageOutcomeKind kind;
  final TicketListItem ticket;
  final String target;

  /// Mensaje en español para mostrar; vacío en `started`.
  final String message;

  bool get isError => kind == TriageOutcomeKind.failed || kind == TriageOutcomeKind.blocked;

  @override
  List<Object?> get props => [id, kind, ticket, target, message];
}

class TriageActionsState extends Equatable {
  const TriageActionsState({this.inFlight = const {}, this.outcome});

  /// Solicitudes con un movimiento en curso (se muestran atenuadas y no aceptan otro).
  final Set<int> inFlight;
  final TriageOutcome? outcome;

  TriageActionsState copyWith({Set<int>? inFlight, TriageOutcome? outcome}) => TriageActionsState(inFlight: inFlight ?? this.inFlight, outcome: outcome ?? this.outcome);

  @override
  List<Object?> get props => [inFlight, outcome];
}
