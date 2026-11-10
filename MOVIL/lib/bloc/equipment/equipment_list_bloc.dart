import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/page_info.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'equipment_list_event.dart';
part 'equipment_list_state.dart';

/// Catálogo de equipos con paginación por páginas. [statuses] es el filtro de estado (lista
/// separada por comas, ver `EquipmentGroup.filter`; `null`: todos), [typeId] la categoría y
/// [search] el texto buscado. Cambiar un filtro o el tamaño de página crea un Bloc nuevo (la
/// pantalla le pone una `key`), igual que «Mis solicitudes»; moverse entre páginas es un evento.
class EquipmentListBloc extends Bloc<EquipmentListEvent, EquipmentListState> {
  EquipmentListBloc({required this._repository, this.statuses, this.search = '', this.typeIds = const [], this.dateFrom, this.dateTo, this.pageSize = 10})
      : super(const EquipmentListState()) {
    on<EquipmentListStarted>((_, emit) => _load(1, emit));
    on<EquipmentPageSelected>((event, emit) => _load(event.page, emit));
    on<EquipmentListRefreshed>((event, emit) async {
      try {
        await _load(state.page, emit);
      } finally {
        event.done?.complete();
      }
    });
    _changes = _repository.changes.listen((_) => add(const EquipmentListRefreshed()));
  }

  final EquipmentRepository _repository;
  final String? statuses;
  final String search;
  final List<int> typeIds;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int pageSize;
  late final StreamSubscription<void> _changes;

  /// Vuelve a pedir la página actual y espera a que termine; sirve al «tirar para refrescar».
  Future<void> refresh() {
    final done = Completer<void>();
    add(EquipmentListRefreshed(done: done));
    return done.future;
  }

  Future<void> _load(int page, Emitter<EquipmentListState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llega la página pedida.
    emit(state.items.isEmpty && state.status != EquipmentListStatus.success
        ? EquipmentListState(page: page)
        : state.copyWith(page: page, loadingPage: true));
    try {
      final result = await _repository.listEquipment(page: page, size: pageSize, statuses: statuses, search: search, typeIds: typeIds, dateFrom: dateFrom, dateTo: dateTo);
      emit(EquipmentListState(status: EquipmentListStatus.success, items: result.items, info: result.info, page: page));
    } catch (error) {
      emit(EquipmentListState(status: EquipmentListStatus.failure, page: page, failure: toFailure(error)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
