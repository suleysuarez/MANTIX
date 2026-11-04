import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import '../errors/failure_mapper.dart';
import 'page_info.dart';

/// Lo cargado hasta ahora de un listado paginado (scroll infinito).
class PagedState<T> {
  const PagedState({required this.items, this.info, this.loadingMore = false, this.loadMoreFailure});

  final List<T> items;

  /// Paginación de la última página recibida; `null` si el servidor no la envió
  /// (entonces el listado se trata como una sola página).
  final PageInfo? info;
  final bool loadingMore;

  /// Error al pedir la página siguiente: se muestra al final de la lista con
  /// reintento, sin perder lo ya cargado.
  final Failure? loadMoreFailure;

  bool get hasMore => info?.hasNext ?? false;

  PagedState<T> copyWith({
    List<T>? items,
    PageInfo? info,
    bool? loadingMore,
    Failure? loadMoreFailure,
    bool clearFailure = false,
  }) =>
      PagedState(
        items: items ?? this.items,
        info: info ?? this.info,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreFailure: clearFailure ? null : (loadMoreFailure ?? this.loadMoreFailure),
      );
}

/// Base de un listado paginado: carga la primera página al construirse y
/// [loadMore] añade la siguiente. Para refrescar se invalida el provider.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedState<T>> {
  /// Pide una página (base 1). Debe lanzar un `Failure` ante un error.
  Future<PagedResult<T>> fetch(int page);

  @override
  Future<PagedState<T>> build() async {
    final result = await fetch(1);
    return PagedState(items: result.items, info: result.info);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    final next = current.info!.nextPage!;
    state = AsyncData(current.copyWith(loadingMore: true, clearFailure: true));
    try {
      final result = await fetch(next);
      state = AsyncData(PagedState(items: [...current.items, ...result.items], info: result.info ?? current.info));
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreFailure: toFailure(error)));
    }
  }
}
