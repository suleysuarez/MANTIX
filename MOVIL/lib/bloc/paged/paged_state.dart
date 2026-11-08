part of 'paged_bloc.dart';

enum PagedStatus { loading, success, failure }

/// Lo cargado hasta ahora de un listado paginado (scroll infinito).
class PagedListState<T> extends Equatable {
  const PagedListState({
    this.status = PagedStatus.loading,
    this.items = const [],
    this.info,
    this.loadingMore = false,
    this.failure,
    this.loadMoreFailure,
  });

  final PagedStatus status;
  final List<T> items;

  /// Paginación de la última página recibida; `null` si el servidor no la envió
  /// (entonces el listado se trata como una sola página).
  final PageInfo? info;
  final bool loadingMore;

  /// Error al pedir la primera página.
  final Failure? failure;

  /// Error al pedir la página siguiente: se muestra al final de la lista con
  /// reintento, sin perder lo ya cargado.
  final Failure? loadMoreFailure;

  bool get hasMore => info?.hasNext ?? false;

  @override
  List<Object?> get props => [status, items, info, loadingMore, failure, loadMoreFailure];
}
