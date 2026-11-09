import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'equipment_summary_event.dart';
part 'equipment_summary_state.dart';

/// Contadores por estado de las tarjetas de «Gestión de equipos».
class EquipmentSummaryBloc extends Bloc<EquipmentSummaryEvent, EquipmentSummaryState> {
  EquipmentSummaryBloc({required this._repository}) : super(const EquipmentSummaryState()) {
    on<EquipmentSummaryStarted>(_onLoad);
    on<EquipmentSummaryRefreshed>(_onLoad);
    _changes = _repository.changes.listen((_) => add(const EquipmentSummaryRefreshed()));
  }

  final EquipmentRepository _repository;
  late final StreamSubscription<void> _changes;

  /// Vuelve a pedir los contadores y espera a que termine; sirve al «tirar para refrescar».
  Future<void> refresh() {
    final done = Completer<void>();
    add(EquipmentSummaryRefreshed(done: done));
    return done.future;
  }

  Future<void> _onLoad(EquipmentSummaryEvent event, Emitter<EquipmentSummaryState> emit) async {
    // Con contadores ya cargados se siguen mostrando mientras llegan los nuevos.
    if (state.summary == null && state.status != SummaryStatus.loading) emit(const EquipmentSummaryState());
    try {
      emit(EquipmentSummaryState(status: SummaryStatus.success, summary: await _repository.summary()));
    } catch (error) {
      emit(EquipmentSummaryState(status: SummaryStatus.failure, summary: state.summary, failure: toFailure(error)));
    } finally {
      if (event is EquipmentSummaryRefreshed) event.done?.complete();
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
