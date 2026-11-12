import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/inventory/inventory_models.dart';
import '../../models/page_info.dart';
import '../../repositories/inventory/inventory_repository.dart';

part 'inventory_movements_event.dart';
part 'inventory_movements_state.dart';

/// Historial de movimientos de un ítem, de 20 en 20 y con scroll infinito.
class InventoryMovementsBloc extends Bloc<InventoryMovementsEvent, InventoryMovementsState> {
  InventoryMovementsBloc({required this.repository, required this.itemId, this.pageSize = PageInfo.defaultPageSize}) : super(const InventoryMovementsState()) {
    on<InventoryMovementsStarted>(_onStarted);
    on<InventoryMovementsMoreRequested>(_onMore);
  }

  final InventoryRepository repository;
  final int itemId;
  final int pageSize;

  Future<void> _onStarted(InventoryMovementsStarted event, Emitter<InventoryMovementsState> emit) async {
    emit(state.copyWith(loading: true, clearFailure: true));
    try {
      final result = await repository.movements(itemId, page: 1, size: pageSize);
      emit(InventoryMovementsState(items: result.items, info: result.info, loaded: true));
    } catch (error) {
      emit(state.copyWith(loading: false, failure: toFailure(error)));
    }
  }

  Future<void> _onMore(InventoryMovementsMoreRequested event, Emitter<InventoryMovementsState> emit) async {
    final next = state.info?.nextPage;
    if (next == null || state.loading || state.loadingMore) return;
    emit(state.copyWith(loadingMore: true, clearFailure: true));
    try {
      final result = await repository.movements(itemId, page: next, size: pageSize);
      emit(state.copyWith(loadingMore: false, items: [...state.items, ...result.items], info: result.info, clearInfo: result.info == null));
    } catch (error) {
      emit(state.copyWith(loadingMore: false, failure: toFailure(error)));
    }
  }
}
