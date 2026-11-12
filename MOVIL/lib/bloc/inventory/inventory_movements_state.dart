part of 'inventory_movements_bloc.dart';

class InventoryMovementsState extends Equatable {
  const InventoryMovementsState({this.loading = false, this.loadingMore = false, this.items = const [], this.info, this.failure, this.loaded = false});

  /// Primera carga o recarga en curso.
  final bool loading;
  final bool loadingMore;
  final List<InventoryMovement> items;
  final PageInfo? info;
  final Failure? failure;

  /// Ya terminó al menos una carga con éxito (distingue «vacío» de «aún no cargó»).
  final bool loaded;

  bool get hasMore => info?.hasNext ?? false;

  /// No quedan más páginas: es el momento de mostrar el alta del ítem al final del historial.
  bool get reachedEnd => loaded && !hasMore && failure == null;

  InventoryMovementsState copyWith({
    bool? loading, bool? loadingMore, List<InventoryMovement>? items, PageInfo? info, bool clearInfo = false,
    Failure? failure, bool clearFailure = false, bool? loaded,
  }) => InventoryMovementsState(
    loading: loading ?? this.loading, loadingMore: loadingMore ?? this.loadingMore, items: items ?? this.items,
    info: clearInfo ? null : (info ?? this.info), failure: clearFailure ? null : (failure ?? this.failure), loaded: loaded ?? this.loaded,
  );

  @override
  List<Object?> get props => [loading, loadingMore, items, info, failure, loaded];
}
