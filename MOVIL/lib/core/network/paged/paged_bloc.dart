import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../errors/failure.dart';
import '../../errors/failure_mapper.dart';
import '../../../models/page_info.dart';

part 'paged_event.dart';
part 'paged_state.dart';

/// Pide una página (base 1). Debe lanzar un `Failure` ante un error.
typedef PageFetcher<T> = Future<PagedResult<T>> Function(int page);

/// Base de un listado paginado. Los eventos y el estado son comunes; cada listado
/// concreto (por ejemplo «mis solicitudes») solo aporta cómo pedir una página.
abstract class PagedBloc<T> extends Bloc<PagedEvent, PagedListState<T>> {
  PagedBloc() : super(PagedListState<T>()) {
    on<PagedStarted>(_onRefresh);
    on<PagedRefreshed>(_onRefresh);
    on<PagedLoadMoreRequested>(_onLoadMore);
  }

  Future<PagedResult<T>> fetch(int page);

  bool _loadMorePending = false;

  /// Los Bloc procesan los eventos de uno en uno: dos «cargar más» seguidos se
  /// encolarían y pedirían dos páginas. Mientras uno está pendiente, los demás se descartan.
  @override
  void add(PagedEvent event) {
    if (event is PagedLoadMoreRequested) {
      if (_loadMorePending) return;
      _loadMorePending = true;
    }
    super.add(event);
  }

  /// Pide la primera página y espera a que termine; sirve al «tirar para refrescar».
  Future<void> refresh() {
    final done = Completer<void>();
    add(PagedRefreshed(done: done));
    return done.future;
  }

  Future<void> _onRefresh(PagedEvent event, Emitter<PagedListState<T>> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llega la respuesta.
    if (state.status == PagedStatus.failure) emit(PagedListState<T>());
    try {
      final result = await fetch(1);
      emit(PagedListState(status: PagedStatus.success, items: result.items, info: result.info));
    } catch (error) {
      emit(PagedListState(status: PagedStatus.failure, failure: toFailure(error)));
    } finally {
      if (event is PagedRefreshed) event.done?.complete();
    }
  }

  Future<void> _onLoadMore(PagedLoadMoreRequested event, Emitter<PagedListState<T>> emit) async {
    try {
      await _loadNextPage(emit);
    } finally {
      _loadMorePending = false;
    }
  }

  Future<void> _loadNextPage(Emitter<PagedListState<T>> emit) async {
    final current = state;
    if (current.status != PagedStatus.success || current.loadingMore || !current.hasMore) return;
    final next = current.info!.nextPage!;
    emit(PagedListState(status: PagedStatus.success, items: current.items, info: current.info, loadingMore: true));
    try {
      final result = await fetch(next);
      emit(PagedListState(
        status: PagedStatus.success,
        items: [...current.items, ...result.items],
        info: result.info ?? current.info,
      ));
    } catch (error) {
      emit(PagedListState(
        status: PagedStatus.success,
        items: current.items,
        info: current.info,
        loadMoreFailure: toFailure(error),
      ));
    }
  }
}
