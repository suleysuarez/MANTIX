import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';

part 'maintenance_calendar_event.dart';
part 'maintenance_calendar_state.dart';

/// El calendario de un mes: pide los servicios que cubre su cuadrícula y recuerda el día elegido.
/// Moverse de mes borra los servicios de la vista (no se enseñan marcas de otro mes) y pide los
/// nuevos; si la persona se mueve de nuevo antes de que llegue la respuesta, esa respuesta se
/// descarta. Se recarga solo cuando alguien programa o cambia un plan.
class MaintenanceCalendarBloc extends Bloc<MaintenanceCalendarEvent, MaintenanceCalendarState> {
  MaintenanceCalendarBloc({required this._repository, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(MaintenanceCalendarState(anchor: monthStart((clock ?? DateTime.now)()))) {
    on<CalendarRequested>(_onRequested);
    on<CalendarMonthShifted>(_onShifted);
    on<CalendarTodayRequested>(_onToday);
    on<CalendarDaySelected>((event, emit) {
      // Tocar el día que ya está elegido (o pasar `null`) quita la elección.
      final unselect = event.key == null || event.key == state.selectedKey;
      emit(unselect ? state.copyWith(clearSelected: true) : state.copyWith(selectedKey: event.key));
    });
    _changes = _repository.changes.listen((_) => add(const CalendarRequested()));
  }

  final MaintenanceRepository _repository;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(CalendarRequested event, Emitter<MaintenanceCalendarState> emit) async {
    try {
      await _load(emit);
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onShifted(CalendarMonthShifted event, Emitter<MaintenanceCalendarState> emit) {
    emit(state.copyWith(anchor: shiftMonth(state.anchor, event.direction), status: CalendarStatus.loading, events: const [], truncated: false, clearSelected: true, clearFailure: true));
    return _load(emit);
  }

  Future<void> _onToday(CalendarTodayRequested event, Emitter<MaintenanceCalendarState> emit) {
    final now = _clock();
    final sameMonth = state.anchor == monthStart(now);
    emit(state.copyWith(anchor: monthStart(now), status: sameMonth ? null : CalendarStatus.loading, events: sameMonth ? null : const [], truncated: sameMonth ? null : false, selectedKey: dayKey(now), clearFailure: !sameMonth));
    return sameMonth ? Future.value() : _load(emit);
  }

  Future<void> _load(Emitter<MaintenanceCalendarState> emit) async {
    final anchor = state.anchor;
    emit(state.copyWith(status: CalendarStatus.loading, clearFailure: true));
    try {
      final range = visibleRange(anchor);
      final data = await _repository.calendar(range.start, range.end);
      if (state.anchor != anchor) return;
      emit(state.copyWith(status: CalendarStatus.ready, events: data.events, truncated: data.truncated));
    } catch (error) {
      if (state.anchor != anchor) return;
      emit(state.copyWith(status: CalendarStatus.failure, failure: toFailure(error)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
