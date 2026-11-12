import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/inventory/inventory_models.dart';
import '../../models/page_info.dart';
import '../../repositories/inventory/inventory_repository.dart';

part 'inventory_event.dart';
part 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  InventoryBloc({required this.repository}) : super(const InventoryState()) {
    on<InventoryStarted>(_onStarted);
    on<InventoryQueryChanged>(_onQueryChanged);
    on<InventoryPageChanged>(_onPageChanged);
    on<InventoryItemCreateRequested>(_onCreateItem);
    on<InventoryMovementRequested>(_onMovement);
  }

  final InventoryRepository repository;

  Future<void> _onStarted(InventoryStarted event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(loading: true, clearFailure: true));
    try {
      final values = await Future.wait<Object>([
        repository.listItems(page: state.page, size: state.pageSize, search: state.search, category: state.category, status: state.status),
        repository.overview(),
        repository.options(),
      ]);
      final page = values[0] as InventoryPage;
      emit(state.copyWith(
        loading: false, items: page.items, pageInfo: page.info, clearPageInfo: page.info == null,
        overview: values[1] as InventoryOverview, options: values[2] as List<InventoryOption>, clearFailure: true,
      ));
    } catch (error) {
      emit(state.copyWith(loading: false, failure: toFailure(error)));
    }
  }

  Future<void> _onQueryChanged(InventoryQueryChanged event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(
      search: event.search, category: event.category, status: event.status,
      clearCategory: event.clearCategory, clearStatus: event.clearStatus, page: 1, loading: true, clearFailure: true,
    ));
    try {
      final result = await repository.listItems(search: event.search, category: event.category, status: event.status, page: 1, size: state.pageSize);
      emit(state.copyWith(loading: false, items: result.items, pageInfo: result.info, clearPageInfo: result.info == null));
    } catch (error) {
      emit(state.copyWith(loading: false, failure: toFailure(error)));
    }
  }

  Future<void> _onPageChanged(InventoryPageChanged event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(page: event.page, loading: true, clearFailure: true));
    try {
      final result = await repository.listItems(search: state.search, category: state.category, status: state.status, page: event.page, size: state.pageSize);
      emit(state.copyWith(loading: false, items: result.items, pageInfo: result.info, clearPageInfo: result.info == null));
    } catch (error) {
      emit(state.copyWith(loading: false, failure: toFailure(error)));
    }
  }

  Future<void> _onCreateItem(InventoryItemCreateRequested event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(saving: true, clearFailure: true, clearCreated: true, clearNotice: true));
    try {
      final item = await repository.createItem(event.payload);
      emit(state.copyWith(saving: false, createdItem: item, notice: 'Ítem creado correctamente.'));
      add(const InventoryStarted());
    } catch (error) {
      emit(state.copyWith(saving: false, failure: toFailure(error)));
    }
  }

  Future<void> _onMovement(InventoryMovementRequested event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(saving: true, clearFailure: true, clearNotice: true));
    try {
      await repository.registerMovement(event.itemId, kind: event.kind, quantity: event.quantity, notes: event.notes);
      emit(state.copyWith(saving: false, notice: event.kind == 'out' ? 'Consumo registrado.' : 'Entrada registrada.'));
      add(const InventoryStarted());
    } catch (error) {
      emit(state.copyWith(saving: false, failure: toFailure(error)));
    }
  }
}
