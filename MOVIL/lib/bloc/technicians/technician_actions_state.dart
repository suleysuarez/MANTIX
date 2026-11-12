part of 'technician_actions_bloc.dart';

/// Qué pasó con una acción: [succeeded], [failed] (el servidor la rechazó o no hubo red) o
/// [blocked] (ni se pidió: un dato no es válido o no hay cambios).
enum TechnicianOutcomeKind { succeeded, failed, blocked }

/// Resultado de una sola vez. [id] distingue resultados iguales seguidos.
class TechnicianOutcome extends Equatable {
  const TechnicianOutcome({required this.id, required this.kind, required this.message, this.technician, this.created = false, this.failure});

  final int id;
  final TechnicianOutcomeKind kind;

  /// Mensaje en español para mostrar.
  final String message;

  /// El técnico ya guardado, si el servidor lo devolvió.
  final Technician? technician;

  /// `true` si [technician] se acaba de registrar (la lista lo enseña de primero).
  final bool created;

  /// El error del servidor o de red, cuando [kind] es [TechnicianOutcomeKind.failed].
  final Failure? failure;

  bool get isError => kind != TechnicianOutcomeKind.succeeded;

  @override
  List<Object?> get props => [id, kind, message, technician, created, failure];
}

class TechnicianActionsState extends Equatable {
  const TechnicianActionsState({this.busy = false, this.outcome});

  /// Hay una acción en curso (no se acepta otra).
  final bool busy;
  final TechnicianOutcome? outcome;

  TechnicianActionsState copyWith({bool? busy, TechnicianOutcome? outcome}) => TechnicianActionsState(busy: busy ?? this.busy, outcome: outcome ?? this.outcome);

  @override
  List<Object?> get props => [busy, outcome];
}
