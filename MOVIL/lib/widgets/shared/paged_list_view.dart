import 'package:flutter/material.dart';

import '../../bloc/paged/paged_bloc.dart';
import '../../core/theme/app_tokens.dart';
import 'async_view.dart';

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
  });

  final PagedListState<T> value;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Recarga desde la primera página.
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Widget empty;

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

  void _maybeLoadMore() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 240) widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return AsyncView<PagedListState<T>>(
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
          itemCount: state.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            if (index < state.items.length) return widget.itemBuilder(context, state.items[index]);
            return _Footer(state: state, onLoadMore: widget.onLoadMore);
          },
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onLoadMore});

  final PagedListState<dynamic> state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
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
