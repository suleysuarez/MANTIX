import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';

part 'upcoming_maintenance_event.dart';
part 'upcoming_maintenance_state.dart';

/// Los próximos mantenimientos: los vencidos de los últimos [pastDays] días y los programados de
/// los próximos [aheadDays], sin lo ya hecho. Falla por separado del calendario: si no carga, el
/// calendario sigue funcionando. Se recarga solo cuando alguien programa o cambia un plan.
class UpcomingMaintenanceBloc extends Bloc<UpcomingMaintenanceEvent, UpcomingMaintenanceState> {
  UpcomingMaintenanceBloc({required this._repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now, super(const UpcomingMaintenanceState()) {
    on<UpcomingRequested>(_onRequested);
    _changes = _repository.changes.listen((_) => add(const UpcomingRequested()));
  }

  /// Hasta dónde mira hacia atrás y hacia delante; juntos caben en los 62 días del servidor.
  static const pastDays = 30;
  static const aheadDays = 30;

  final MaintenanceRepository _repository;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(UpcomingRequested event, Emitter<UpcomingMaintenanceState> emit) async {
    // Al recargar se conserva lo que ya se ve; solo cambia lo que llega.
    emit(state.copyWith(status: UpcomingStatus.loading, clearFailure: true));
    try {
      final today = startOfDay(_clock());
      final data = await _repository.calendar(addDays(today, -pastDays), addDays(today, aheadDays));
      emit(state.copyWith(status: UpcomingStatus.ready, items: upcomingEvents(data.events)));
    } catch (error) {
      emit(state.copyWith(status: UpcomingStatus.failure, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
