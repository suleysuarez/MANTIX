import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/maintenance_format.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';

part 'schedule_actions_event.dart';
part 'schedule_actions_state.dart';

/// Programar un plan, marcar un servicio como hecho y activar o desactivar un plan. Valida antes de
/// pedir nada al servidor (equipo elegido, título, intervalo, recordatorio, fecha y horas); lo que
/// solo el servidor sabe (el equipo ya no está disponible, el técnico está inactivo, falta el
/// permiso) llega por su `code` ya traducido. El resultado sale como un [ScheduleOutcome] de una
/// sola vez.
class ScheduleActionsBloc extends Bloc<ScheduleActionsEvent, ScheduleActionsState> {
  ScheduleActionsBloc({required this._repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now, super(const ScheduleActionsState()) {
    on<ScheduleCreateRequested>(_onCreate);
    on<ScheduleCompleteRequested>(_onComplete);
    on<ScheduleActiveChangeRequested>(_onActive);
  }

  final MaintenanceRepository _repository;
  final DateTime Function() _clock;
  int _outcomes = 0;

  void _block(Emitter<ScheduleActionsState> emit, String message) => emit(state.copyWith(outcome: ScheduleOutcome(id: ++_outcomes, kind: ScheduleOutcomeKind.blocked, message: message)));

  /// Corre [action] sin dejar empezar otra mientras tanto y emite el resultado.
  Future<void> _run(Emitter<ScheduleActionsState> emit, {required Future<MaintenanceSchedule> Function() action, required String Function(MaintenanceSchedule) success, required String failurePrefix, bool created = false}) async {
    emit(state.copyWith(busy: true));
    try {
      final schedule = await action();
      emit(state.copyWith(busy: false, outcome: ScheduleOutcome(id: ++_outcomes, kind: ScheduleOutcomeKind.succeeded, message: success(schedule), schedule: schedule, created: created)));
    } catch (error) {
      final failure = toFailure(error);
      emit(state.copyWith(busy: false, outcome: ScheduleOutcome(id: ++_outcomes, kind: ScheduleOutcomeKind.failed, message: '$failurePrefix ${failure.message}', failure: failure)));
    }
  }

  static String? _text(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _onCreate(ScheduleCreateRequested event, Emitter<ScheduleActionsState> emit) async {
    if (state.busy) return;
    final equipmentId = event.equipmentId;
    if (equipmentId == null) return _block(emit, 'Selecciona el equipo.');
    final problem = planTitleError(event.title) ?? planDescriptionError(event.description) ?? intervalError(event.intervalDays) ?? remindError(event.remindDays, event.intervalDays) ?? firstDueError(event.firstDueAt, _clock()) ?? hoursError(event.estimatedHours);
    if (problem != null) return _block(emit, problem);
    await _run(
      emit,
      action: () => _repository.create(
        equipmentId: equipmentId,
        title: event.title.trim(),
        description: _text(event.description),
        intervalDays: int.parse(event.intervalDays.trim()),
        remindDaysBefore: int.parse(event.remindDays.trim()),
        firstDueAt: event.firstDueAt!,
        estimatedHours: parseHours(event.estimatedHours),
        technicianId: event.technicianId,
      ),
      success: (_) => 'Mantenimiento programado.',
      failurePrefix: 'No se pudo programar el mantenimiento:',
      created: true,
    );
  }

  Future<void> _onComplete(ScheduleCompleteRequested event, Emitter<ScheduleActionsState> emit) async {
    if (state.busy) return;
    final problem = hoursError(event.actualHours);
    if (problem != null) return _block(emit, problem);
    final plan = event.schedule;
    await _run(
      emit,
      action: () => _repository.complete(plan.id, actualHours: parseHours(event.actualHours)),
      success: (_) => 'Servicio «${plan.title}» registrado como hecho.',
      failurePrefix: 'No se pudo registrar el servicio:',
    );
  }

  Future<void> _onActive(ScheduleActiveChangeRequested event, Emitter<ScheduleActionsState> emit) async {
    if (state.busy) return;
    final plan = event.schedule;
    if (plan.isActive == event.active) return _block(emit, 'El plan «${plan.title}» ya está ${event.active ? 'activo' : 'desactivado'}.');
    await _run(
      emit,
      action: () => _repository.setActive(plan.id, active: event.active),
      success: (_) => 'El plan «${plan.title}» fue ${event.active ? 'activado' : 'desactivado'}.',
      failurePrefix: 'No se pudo ${event.active ? 'activar' : 'desactivar'} el plan:',
    );
  }
}
