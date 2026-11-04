import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../shared/empty_state.dart';
import '../../../shared/paged_list_view.dart';
import '../application/providers.dart';
import '../data/models.dart';

/// Selector de equipo con búsqueda por etiqueta, serie, marca o modelo.
/// Devuelve el [EquipmentOption] elegido con `Navigator.pop`.
class EquipmentPickerScreen extends ConsumerStatefulWidget {
  const EquipmentPickerScreen({super.key, this.debounce = const Duration(milliseconds: 400)});

  /// Espera tras la última tecla antes de buscar.
  final Duration debounce;

  @override
  ConsumerState<EquipmentPickerScreen> createState() => _EquipmentPickerScreenState();
}

class _EquipmentPickerScreenState extends ConsumerState<EquipmentPickerScreen> {
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

  Future<void> _refresh() async {
    final provider = equipmentSearchProvider(_query);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // El error ya se muestra en la lista.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = equipmentSearchProvider(_query);
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
            child: PagedListView<EquipmentOption>(
              value: ref.watch(provider),
              onRefresh: _refresh,
              onLoadMore: () => ref.read(provider.notifier).loadMore(),
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
        ],
      ),
    );
  }
}
