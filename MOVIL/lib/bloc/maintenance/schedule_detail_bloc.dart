import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';

part 'schedule_detail_event.dart';
part 'schedule_detail_state.dart';

/// La ficha de un plan: sus datos y su historial (servicios hechos y cambios de fecha). Cada
/// bloque carga y falla por separado: si el historial no llega, el plan se ve igual.
class ScheduleDetailBloc extends Bloc<ScheduleDetailEvent, ScheduleDetailState> {
  ScheduleDetailBloc({required this._repository, required this.scheduleId}) : super(const ScheduleDetailState()) {
    on<ScheduleDetailRequested>((_, emit) => Future.wait([_loadPlan(emit), _loadHistory(emit)]));
    on<SchedulePlanRetried>((_, emit) => _loadPlan(emit));
    on<ScheduleHistoryRetried>((_, emit) => _loadHistory(emit));
  }

  final MaintenanceRepository _repository;
  final int scheduleId;

  Future<void> _loadPlan(Emitter<ScheduleDetailState> emit) async {
    emit(state.copyWith(planStatus: PlanBlockStatus.loading));
    try {
      // Se espera primero: `state` se lee al emitir, no antes (la otra carga pudo cambiarlo).
      final plan = await _repository.schedule(scheduleId);
      emit(state.copyWith(planStatus: PlanBlockStatus.ready, plan: plan));
    } catch (error) {
      emit(state.copyWith(planStatus: PlanBlockStatus.failure, planFailure: toFailure(error)));
    }
  }

  Future<void> _loadHistory(Emitter<ScheduleDetailState> emit) async {
    emit(state.copyWith(historyStatus: PlanBlockStatus.loading));
    try {
      final history = await _repository.history(scheduleId);
      emit(state.copyWith(historyStatus: PlanBlockStatus.ready, history: history));
    } catch (error) {
      emit(state.copyWith(historyStatus: PlanBlockStatus.failure, historyFailure: toFailure(error)));
    }
  }
}
