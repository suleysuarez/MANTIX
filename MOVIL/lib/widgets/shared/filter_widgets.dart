import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'date_range_dialog.dart';

/// Hoja inferior de filtros: título, campos apilados con etiqueta y un pie con «Limpiar»
/// y, si [onApply] existe, «Aplicar».
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key, required this.children, required this.onReset, this.onApply, this.title = 'Filtros'});

  final String title;
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.tune_rounded, color: AppColors.steel),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.navy)),
              ]),
              const SizedBox(height: AppSpacing.lg),
              for (final child in children) ...[child, const SizedBox(height: AppSpacing.md)],
              const SizedBox(height: AppSpacing.xs),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(onPressed: onReset, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Limpiar')),
                ),
                if (onApply != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(onPressed: onApply, icon: const Icon(Icons.check_rounded), label: const Text('Aplicar')),
                  ),
                ],
              ]),
            ],
          ),
        ),
      );
}

/// Etiqueta pequeña con icono sobre un campo de filtro.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.slate),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.steel))),
        ]),
      );
}

final _fieldDecoration = BoxDecoration(
  color: AppColors.canvas,
  borderRadius: AppRadius.mdAll,
  border: Border.all(color: AppColors.grey),
);

/// Desplegable con etiqueta e icono, de ancho completo.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({super.key, required this.label, required this.icon, required this.value, required this.items, required this.onChanged});

  final String label;
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _FieldLabel(icon, label),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: _fieldDecoration,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                isExpanded: true,
                value: value,
                borderRadius: AppRadius.mdAll,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.navy),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ]),
      );
}

/// Rango de fechas (desde – hasta) con selector del sistema y botón para quitarlo.
class DateRangeFilterField extends StatelessWidget {
  const DateRangeFilterField({super.key, required this.value, required this.onChanged, this.label = 'Rango de fechas'});

  final String label;
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateRangeDialog(context, initial: value);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final range = value;
    final text = range == null ? 'Cualquier fecha' : '${formatDate(range.start)} – ${formatDate(range.end)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _FieldLabel(Icons.date_range_rounded, label),
      Material(
        color: AppColors.canvas,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.grey)),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: () => _pick(context),
          child: SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Row(children: [
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: range == null ? AppColors.slate : AppColors.navy),
                  ),
                ),
                if (range != null)
                  IconButton(tooltip: 'Quitar fechas', onPressed: () => onChanged(null), icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.slate))
                else
                  const Padding(padding: EdgeInsets.only(right: AppSpacing.md), child: Icon(Icons.calendar_month_rounded, color: AppColors.slate)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Filtro activo que se puede quitar tocando la equis.
class ActiveFilterChip extends StatelessWidget {
  const ActiveFilterChip({super.key, required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => InputChip(
        label: Text(label),
        onDeleted: onRemove,
        deleteButtonTooltipMessage: 'Quitar filtro',
        visualDensity: VisualDensity.compact,
        backgroundColor: AppColors.skyLight.withValues(alpha: .35),
        side: BorderSide.none,
        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.steel),
      );
}

/// Fila de la hoja de filtros que abre otra selección (por ejemplo, la multiselección de
/// categorías). Muestra lo elegido, o «Todas» si no hay nada.
class FilterTile extends StatelessWidget {
  const FilterTile({super.key, required this.label, required this.icon, required this.summary, required this.onTap});

  final String label;
  final IconData icon;

  /// Resumen de lo elegido; `null` si no hay filtro.
  final String? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _FieldLabel(icon, label),
        Material(
          color: AppColors.canvas,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: summary == null ? AppColors.grey : AppColors.steel)),
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      summary ?? 'Todas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: summary == null ? AppColors.slate : AppColors.navy),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate),
                ]),
              ),
            ),
          ),
        ),
      ]);
}
