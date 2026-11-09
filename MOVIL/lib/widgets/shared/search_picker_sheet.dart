import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/paged/paged_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'mantix_sheet.dart';
import 'skeleton.dart';

/// Abre una hoja para elegir un elemento buscando por texto. Devuelve el elegido o `null`.
///
/// [createBloc] crea el listado paginado para un texto (cada búsqueda es un Bloc nuevo).
/// Los resultados llegan por páginas: al final hay un botón «Ver más resultados», sin scroll
/// infinito ni paginador numerado. [onCreate] pone la opción «Crear nueva»: solo debe pasarse
/// si el permiso y el endpoint existen.
Future<T?> showSearchPicker<T>(
  BuildContext context, {
  required String title,
  required PagedBloc<T> Function(String search) createBloc,
  required Widget Function(BuildContext context, T item, VoidCallback select) itemBuilder,
  String hint = 'Buscar',
  String emptyTitle = 'Sin resultados',
  String? createLabel,
  Future<T?> Function()? onCreate,
}) =>
    showMantixSheet<T>(
      context,
      title: title,
      builder: (context, controller) => SearchPicker<T>(
        controller: controller,
        createBloc: createBloc,
        itemBuilder: itemBuilder,
        hint: hint,
        emptyTitle: emptyTitle,
        createLabel: createLabel,
        onCreate: onCreate,
      ),
    );

class SearchPicker<T> extends StatefulWidget {
  const SearchPicker({
    super.key,
    required this.createBloc,
    required this.itemBuilder,
    this.controller,
    this.hint = 'Buscar',
    this.emptyTitle = 'Sin resultados',
    this.createLabel,
    this.onCreate,
    this.debounce = const Duration(milliseconds: 400),
  });

  final PagedBloc<T> Function(String search) createBloc;
  final Widget Function(BuildContext context, T item, VoidCallback select) itemBuilder;
  final ScrollController? controller;
  final String hint;
  final String emptyTitle;
  final String? createLabel;
  final Future<T?> Function()? onCreate;
  final Duration debounce;

  @override
  State<SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<SearchPicker<T>> {
  final _field = TextEditingController();
  Timer? _timer;
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      final value = text.trim();
      if (mounted && value != _query) setState(() => _query = value);
    });
  }

  Future<void> _create() async {
    final created = await widget.onCreate!();
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.onCreate != null && widget.createLabel != null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: TextField(
          controller: _field,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _field.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _field.clear();
                      _timer?.cancel();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      if (canCreate)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
          child: OutlinedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: Text(widget.createLabel!),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      Expanded(
        child: BlocProvider<PagedBloc<T>>(
          key: ValueKey(_query),
          create: (_) => widget.createBloc(_query)..add(const PagedStarted()),
          child: BlocBuilder<PagedBloc<T>, PagedListState<T>>(
            builder: (context, state) => _Results<T>(
              state: state,
              controller: widget.controller,
              emptyTitle: widget.emptyTitle,
              itemBuilder: widget.itemBuilder,
              onRetry: () => context.read<PagedBloc<T>>().add(const PagedStarted()),
              onMore: () => context.read<PagedBloc<T>>().add(const PagedLoadMoreRequested()),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Results<T> extends StatelessWidget {
  const _Results({required this.state, required this.controller, required this.emptyTitle, required this.itemBuilder, required this.onRetry, required this.onMore});

  final PagedListState<T> state;
  final ScrollController? controller;
  final String emptyTitle;
  final Widget Function(BuildContext context, T item, VoidCallback select) itemBuilder;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case PagedStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: SkeletonList(itemCount: 4, itemHeight: 64));
      case PagedStatus.failure:
        return ErrorState(failure: state.failure!, onRetry: onRetry);
      case PagedStatus.success:
        if (state.items.isEmpty) return EmptyState(icon: Icons.search_off_rounded, title: emptyTitle, message: 'Prueba con otro texto.');
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          children: [
            for (final item in state.items) ...[
              itemBuilder(context, item, () => Navigator.pop(context, item)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (state.loadMoreFailure != null)
              Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(state.loadMoreFailure!.message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (state.loadingMore)
              const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator(semanticsLabel: 'Cargando más resultados')))
            else if (state.hasMore)
              OutlinedButton.icon(
                onPressed: onMore,
                icon: const Icon(Icons.expand_more_rounded, color: AppColors.steel),
                label: const Text('Ver más resultados'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
          ],
        );
    }
  }
}
