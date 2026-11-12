import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../models/page_info.dart';
import '../../repositories/maintenance/maintenance_repository.dart';

part 'schedules_list_event.dart';
part 'schedules_list_state.dart';

/// Lista de planes con paginación en el servidor. Los filtros ([search], [technicianId], [status]
/// y [sort]) y el tamaño de página van en el constructor: cambiar uno crea un Bloc nuevo (la
/// pantalla le pone una `key`), igual que Equipos y Usuarios; moverse entre páginas es un evento.
/// Si otra parte de la app programa o cambia un plan, la página actual se recarga sola.
class SchedulesListBloc extends Bloc<SchedulesListEvent, SchedulesListState> {
  SchedulesListBloc({required this._repository, this.search = '', this.technicianId, this.status = ScheduleStatusFilter.all, this.sort = 'next_due_at', this.pageSize = PageInfo.defaultPageSize}) : super(const SchedulesListState()) {
    on<SchedulesListStarted>((_, emit) => _load(1, emit));
    on<SchedulesPageSelected>((event, emit) => _load(event.page, emit));
    on<SchedulesListRefreshed>((event, emit) async {
      try {
        await _load(state.page, emit);
      } finally {
        event.done?.complete();
      }
    });
    _changes = _repository.changes.listen((_) => add(const SchedulesListRefreshed()));
  }

  final MaintenanceRepository _repository;
  final String search;
  final int? technicianId;
  final ScheduleStatusFilter status;
  final String sort;
  final int pageSize;
  late final StreamSubscription<void> _changes;

  /// Vuelve a pedir la página actual y espera a que termine; sirve al «tirar para refrescar».
  Future<void> refresh() {
    final done = Completer<void>();
    add(SchedulesListRefreshed(done: done));
    return done.future;
  }

  Future<void> _load(int page, Emitter<SchedulesListState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llega la página pedida.
    emit(state.items.isEmpty && state.status != SchedulesStatus.success ? SchedulesListState(page: page) : state.copyWith(page: page, loadingPage: true));
    try {
      final result = await _repository.schedules(page: page, size: pageSize, search: search, technicianId: technicianId, status: status, sort: sort);
      emit(SchedulesListState(status: SchedulesStatus.success, items: result.items, info: result.info, page: page));
    } catch (error) {
      emit(SchedulesListState(status: SchedulesStatus.failure, page: page, failure: toFailure(error)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
