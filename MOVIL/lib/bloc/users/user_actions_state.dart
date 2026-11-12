part of 'user_actions_bloc.dart';

/// Qué pasó con una acción: [succeeded], [failed] (el servidor la rechazó o no hubo red) o
/// [blocked] (ni se pidió: la selección no es válida, no hay cambios o la regla lo impide).
enum UserOutcomeKind { succeeded, failed, blocked }

/// Resultado de una sola vez. [id] distingue resultados iguales seguidos.
class UserOutcome extends Equatable {
  const UserOutcome({required this.id, required this.kind, required this.userId, required this.message, this.user});

  final int id;
  final UserOutcomeKind kind;
  final int userId;

  /// Mensaje en español para mostrar.
  final String message;

  /// La persona ya actualizada, si el servidor la devolvió.
  final ManagedUser? user;

  bool get isError => kind != UserOutcomeKind.succeeded;

  @override
  List<Object?> get props => [id, kind, userId, message, user];
}

class UserActionsState extends Equatable {
  const UserActionsState({this.inFlight = const {}, this.outcome});

  /// Personas con una acción en curso (no aceptan otra).
  final Set<int> inFlight;
  final UserOutcome? outcome;

  UserActionsState copyWith({Set<int>? inFlight, UserOutcome? outcome}) => UserActionsState(inFlight: inFlight ?? this.inFlight, outcome: outcome ?? this.outcome);

  @override
  List<Object?> get props => [inFlight, outcome];
}
