import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/paged/paged_bloc.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/empty_state.dart';
import '../../../shared/paged_list_view.dart';
import '../../../models/requests/request_models.dart';
import '../../../repositories/requests/requests_repository.dart';
import '../../../bloc/requests/equipment_search_bloc.dart';

/// Selector de equipo con búsqueda por etiqueta, serie, marca o modelo.
/// Devuelve el [EquipmentOption] elegido con `Navigator.pop`.
class EquipmentPickerScreen extends StatefulWidget {
  const EquipmentPickerScreen({super.key, this.debounce = const Duration(milliseconds: 400)});

  /// Espera tras la última tecla antes de buscar.
  final Duration debounce;

  @override
  State<EquipmentPickerScreen> createState() => _EquipmentPickerScreenState();
}

class _EquipmentPickerScreenState extends State<EquipmentPickerScreen> {
  final _search = TextEditingController();
  Timer? _timer;
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => setState(() => _query = text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir equipo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Buscar',
                hintText: 'Etiqueta, serie, marca o modelo',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            // Cada texto buscado es un `EquipmentSearchBloc` nuevo.
            child: BlocProvider(
              key: ValueKey(_query),
              create: (context) =>
                  EquipmentSearchBloc(repository: context.read<RequestsRepository>(), search: _query)..add(const PagedStarted()),
              child: BlocBuilder<EquipmentSearchBloc, PagedListState<EquipmentOption>>(
                builder: (context, state) => PagedListView<EquipmentOption>(
                  value: state,
                  onRefresh: context.read<EquipmentSearchBloc>().refresh,
                  onLoadMore: () => context.read<EquipmentSearchBloc>().add(const PagedLoadMoreRequested()),
                  empty: EmptyState(
                    icon: Icons.search_off,
                    title: 'No encontramos equipos',
                    message: _query.isEmpty ? 'Todavía no hay equipos registrados.' : 'Prueba con otra etiqueta, serie, marca o modelo.',
                  ),
                  itemBuilder: (context, item) => Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      minVerticalPadding: AppSpacing.md,
                      title: Text(item.label),
                      subtitle: item.typeName.isEmpty ? null : Text(item.typeName),
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
