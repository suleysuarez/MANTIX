import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Una opción del filtro multiselección.
class FilterOption<T> {
  const FilterOption(this.value, this.label);
  final T value;
  final String label;
}

/// Botón de filtros con embudo y, si hay filtros activos, un contador.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.count, required this.onPressed});

  /// Filtros activos.
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: count == 0 ? 'Filtros' : 'Filtros ($count activos)',
        onPressed: onPressed,
        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: AppColors.mustard,
          textColor: AppColors.navy,
          child: const Icon(Icons.filter_alt_outlined),
        ),
      );
}

/// Hoja con casillas que **no** se cierra al marcar: solo «Aplicar» devuelve la selección y
/// «Limpiar» la vacía. Devuelve `null` si se cierra sin aplicar.
Future<Set<T>?> showMultiSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<FilterOption<T>> options,
  required Set<T> selected,
}) =>
    showModalBottomSheet<Set<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => MultiSelectSheet<T>(title: title, options: options, selected: selected),
    );

class MultiSelectSheet<T> extends StatefulWidget {
  const MultiSelectSheet({super.key, required this.title, required this.options, required this.selected});

  final String title;
  final List<FilterOption<T>> options;
  final Set<T> selected;

  @override
  State<MultiSelectSheet<T>> createState() => _MultiSelectSheetState<T>();
}

class _MultiSelectSheetState<T> extends State<MultiSelectSheet<T>> {
  late final Set<T> _selected = {...widget.selected};

  void _toggle(T value, bool on) => setState(() => on ? _selected.add(value) : _selected.remove(value));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
            if (_selected.isNotEmpty)
              Text('${_selected.length} activos', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700)),
          ]),
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final option in widget.options)
              CheckboxListTile(
                value: _selected.contains(option.value),
                onChanged: (on) => _toggle(option.value, on ?? false),
                title: Text(option.label),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.steel,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => setState(_selected.clear), icon: const Icon(Icons.restart_alt_rounded), label: const Text('Limpiar'))),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(context, {..._selected}), icon: const Icon(Icons.check_rounded), label: const Text('Aplicar'))),
            ]),
          ),
        ),
      ]),
    );
  }
}
