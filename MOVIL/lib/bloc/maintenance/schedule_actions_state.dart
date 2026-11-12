part of 'schedule_actions_bloc.dart';

/// Qué pasó con una acción: [succeeded], [failed] (el servidor la rechazó o no hubo red) o
/// [blocked] (ni se pidió: un dato no es válido o no hay nada que cambiar).
enum ScheduleOutcomeKind { succeeded, failed, blocked }

/// Resultado de una sola vez. [id] distingue resultados iguales seguidos.
class ScheduleOutcome extends Equatable {
  const ScheduleOutcome({required this.id, required this.kind, required this.message, this.schedule, this.created = false, this.failure});

  final int id;
  final ScheduleOutcomeKind kind;

  /// Mensaje en español para mostrar.
  final String message;

  /// El plan ya guardado, si el servidor lo devolvió.
  final MaintenanceSchedule? schedule;

  /// `true` si [schedule] se acaba de programar.
  final bool created;

  /// El error del servidor o de red, cuando [kind] es [ScheduleOutcomeKind.failed].
  final Failure? failure;

  bool get isError => kind != ScheduleOutcomeKind.succeeded;

  @override
  List<Object?> get props => [id, kind, message, schedule, created, failure];
}

class ScheduleActionsState extends Equatable {
  const ScheduleActionsState({this.busy = false, this.outcome});

  /// Hay una acción en curso (no se acepta otra).
  final bool busy;
  final ScheduleOutcome? outcome;

  ScheduleActionsState copyWith({bool? busy, ScheduleOutcome? outcome}) => ScheduleActionsState(busy: busy ?? this.busy, outcome: outcome ?? this.outcome);

  @override
  List<Object?> get props => [busy, outcome];
}
