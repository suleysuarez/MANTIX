import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/technicians_format.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/technicians/technicians_repository.dart';

part 'technician_actions_event.dart';
part 'technician_actions_state.dart';

/// Registrar un técnico, editar su especialización y su tarifa, y marcarlo disponible o no
/// disponible. Valida antes de pedir nada al servidor (usuario elegido, longitud de la
/// especialización, tarifa sin negativos y con dos decimales, que haya algo que cambiar); lo que
/// solo el servidor sabe (el usuario ya tiene perfil, falta el permiso) llega por su `code` ya
/// traducido. El resultado sale como un [TechnicianOutcome] de una sola vez.
class TechnicianActionsBloc extends Bloc<TechnicianActionsEvent, TechnicianActionsState> {
  TechnicianActionsBloc({required this._repository}) : super(const TechnicianActionsState()) {
    on<TechnicianCreateRequested>(_onCreate);
    on<TechnicianEditRequested>(_onEdit);
    on<TechnicianAvailabilityRequested>(_onAvailability);
  }

  final TechniciansRepository _repository;
  int _outcomes = 0;

  void _block(Emitter<TechnicianActionsState> emit, String message) => emit(state.copyWith(outcome: TechnicianOutcome(id: ++_outcomes, kind: TechnicianOutcomeKind.blocked, message: message)));

  /// Corre [action] sin dejar empezar otra mientras tanto y emite el resultado.
  Future<void> _run(Emitter<TechnicianActionsState> emit, {required Future<Technician> Function() action, required String Function(Technician) success, required String failurePrefix, bool created = false}) async {
    emit(state.copyWith(busy: true));
    try {
      final technician = await action();
      emit(state.copyWith(busy: false, outcome: TechnicianOutcome(id: ++_outcomes, kind: TechnicianOutcomeKind.succeeded, message: success(technician), technician: technician, created: created)));
    } catch (error) {
      final failure = toFailure(error);
      emit(state.copyWith(busy: false, outcome: TechnicianOutcome(id: ++_outcomes, kind: TechnicianOutcomeKind.failed, message: '$failurePrefix ${failure.message}', failure: failure)));
    }
  }

  static String? _text(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _onCreate(TechnicianCreateRequested event, Emitter<TechnicianActionsState> emit) async {
    if (state.busy) return;
    final userId = event.userId;
    if (userId == null) return _block(emit, 'Selecciona el usuario al que pertenece el perfil de técnico.');
    final problem = specializationError(event.specialization) ?? rateError(event.rate);
    if (problem != null) return _block(emit, problem);
    await _run(
      emit,
      action: () => _repository.create(userId: userId, specialization: _text(event.specialization), hourlyRate: parseRate(event.rate)),
      success: (technician) => 'Técnico «${technician.fullName}» registrado.',
      failurePrefix: 'No se pudo registrar el técnico:',
      created: true,
    );
  }

  Future<void> _onEdit(TechnicianEditRequested event, Emitter<TechnicianActionsState> emit) async {
    if (state.busy) return;
    final technician = event.technician;
    final problem = specializationError(event.specialization) ?? rateError(event.rate);
    if (problem != null) return _block(emit, problem);
    final specialization = _text(event.specialization);
    final rate = parseRate(event.rate);
    final specializationChanged = specialization != _text(technician.specialization);
    final rateChanged = rate?.toStringAsFixed(2) != technician.hourlyRate?.toStringAsFixed(2);
    if (!specializationChanged && !rateChanged) return _block(emit, 'No hay cambios que guardar.');
    await _run(
      emit,
      action: () => _repository.update(technician.id, specialization: specializationChanged ? (value: specialization) : null, hourlyRate: rateChanged ? (value: rate) : null),
      success: (_) => 'Perfil de ${technician.fullName} actualizado.',
      failurePrefix: 'No se pudo actualizar a ${technician.fullName}:',
    );
  }

  Future<void> _onAvailability(TechnicianAvailabilityRequested event, Emitter<TechnicianActionsState> emit) async {
    if (state.busy) return;
    final technician = event.technician;
    final label = event.available ? 'disponible' : 'no disponible';
    if (technician.isAvailable == event.available) return _block(emit, '${technician.fullName} ya está $label.');
    await _run(
      emit,
      action: () => _repository.update(technician.id, isAvailable: event.available),
      success: (_) => '${technician.fullName} ahora está $label.',
      failurePrefix: 'No se pudo marcar a ${technician.fullName} como $label:',
    );
  }
}
