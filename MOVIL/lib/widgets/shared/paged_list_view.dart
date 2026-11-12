import 'package:flutter/material.dart';

import '../../bloc/paged/paged_bloc.dart';
import '../../core/theme/app_tokens.dart';
import 'async_view.dart';
import 'paginator.dart';

/// Listado paginado con los cuatro estados (cargando, error, vacío, datos),
/// scroll infinito, pull-to-refresh y reintento al fallar una página.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.empty,
    this.header,
    this.onPage,
    this.onPageSize,
  });

  final PagedListState<T> value;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Recarga desde la primera página.
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Widget empty;

  /// Contenido que se desplaza con la lista, encima del primer elemento. También se
  /// muestra mientras carga, si falla o si no hay elementos.
  final Widget? header;

  /// Si se da, el listado usa paginación numerada (botones de página) en vez de scroll infinito.
  final ValueChanged<int>? onPage;

  /// Si se da junto con [onPage], el paginador ofrece cambiar el tamaño de página.
  final ValueChanged<int>? onPageSize;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PagedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar de página numerada se vuelve al principio de la lista.
    if (widget.onPage != null && oldWidget.value.info?.page != widget.value.info?.page && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  void _maybeLoadMore() {
    if (!_controller.hasClients || widget.onPage != null) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 240) widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final header = widget.header;
    final hasItems = value.status == PagedStatus.success && value.items.isNotEmpty;
    final view = AsyncView<PagedListState<T>>(
      loaded: value.status == PagedStatus.success ? value : null,
      failure: value.failure,
      onRetry: widget.onRefresh,
      isEmpty: (state) => state.items.isEmpty,
      empty: widget.empty,
      data: (state) => RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView.separated(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: state.items.length + 1 + (header == null ? 0 : 1),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            if (header != null) {
              if (index == 0) return header;
              index -= 1;
            }
            if (index < state.items.length) return widget.itemBuilder(context, state.items[index]);
            return _Footer(state: state, onLoadMore: widget.onLoadMore, onPage: widget.onPage, onPageSize: widget.onPageSize);
          },
        ),
      ),
    );
    if (header == null || hasItems) return view;
    // Cargando, con error o sin elementos: el encabezado sigue visible y el estado va debajo.
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          SizedBox(height: 380, child: view),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onLoadMore, this.onPage, this.onPageSize});

  final PagedListState<dynamic> state;
  final VoidCallback onLoadMore;
  final ValueChanged<int>? onPage;
  final ValueChanged<int>? onPageSize;

  @override
  Widget build(BuildContext context) {
    final info = state.info;
    if (onPage != null) {
      final failure = state.loadMoreFailure;
      return Column(children: [
        if (failure != null) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(failure.message, textAlign: TextAlign.center)),
        if (info != null)
          Paginator(page: info.page, pageSize: info.pageSize, total: info.total, totalPages: info.totalPages, loading: state.loadingMore, onPage: onPage!, onPageSize: onPageSize),
        const SizedBox(height: AppSpacing.xl),
      ]);
    }
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(semanticsLabel: 'Cargando más')),
      );
    }
    final failure = state.loadMoreFailure;
    if (failure != null) {
      return Column(
        children: [
          Text(failure.message, textAlign: TextAlign.center),
          TextButton.icon(onPressed: onLoadMore, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      );
    }
    if (state.hasMore) {
      return Center(child: TextButton(onPressed: onLoadMore, child: const Text('Cargar más')));
    }
    return const SizedBox(height: AppSpacing.xl);
  }
}
