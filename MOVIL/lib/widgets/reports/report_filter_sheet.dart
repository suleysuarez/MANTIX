import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/format/report_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import '../shared/filter_widgets.dart';
import '../shared/multi_select_sheet.dart';

IconData _filterIcon(String key) => switch (key) {
      'statuses' => Icons.flag_outlined,
      'priorities' => Icons.priority_high_rounded,
      'equipment_type_ids' => Icons.devices_other_outlined,
      'categories' => Icons.category_outlined,
      'kinds' => Icons.swap_vert_rounded,
      _ => Icons.tune_rounded,
    };

/// Hoja con los filtros del reporte: solo los que ese reporte admite. Devuelve los valores al
/// aplicar y `null` si se cierra sin aplicar. «Limpiar» deja todo sin filtrar.
Future<ReportFilterValues?> showReportFilterSheet(BuildContext context, {required ReportDefinition definition, required ReportFilterValues initial}) => showModalBottomSheet<ReportFilterValues>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _ReportFilterSheet(definition: definition, initial: initial),
    );

class _ReportFilterSheet extends StatefulWidget {
  const _ReportFilterSheet({required this.definition, required this.initial});

  final ReportDefinition definition;
  final ReportFilterValues initial;

  @override
  State<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends State<_ReportFilterSheet> {
  late ReportFilterValues _values = widget.initial;

  Future<void> _pickMulti(ReportFilterDefinition filter) async {
    final picked = await showMultiSelectSheet<String>(
      context,
      title: filter.label,
      options: [for (final option in filter.options) FilterOption(option.value, option.label)],
      selected: _values.selected(filter.key),
    );
    if (picked != null && mounted) setState(() => _values = _values.withSelected(filter.key, picked));
  }

  /// Fechas pasadas y futuras: los planes de mantenimiento tienen fechas por venir.
  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final current = from ? _values.dateFrom : _values.dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: from ? 'Desde' : 'Hasta',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;
    setState(() => _values = from ? _values.copyWith(dateFrom: picked) : _values.copyWith(dateTo: picked));
  }

  @override
  Widget build(BuildContext context) {
    final definition = widget.definition;
    final error = reportRangeError(_values.dateFrom, _values.dateTo);
    final theme = Theme.of(context);
    return FilterSheet(
      title: 'Filtros del reporte',
      onReset: () => setState(() => _values = const ReportFilterValues()),
      onApply: error == null ? () => Navigator.pop(context, _values.compare && !canCompare(definition, _values) ? _values.copyWith(compare: false) : _values) : null,
      children: [
        for (final filter in definition.filters)
          switch (filter.kind) {
            ReportFilterKind.multiselect => FilterTile(
                label: filter.label,
                icon: _filterIcon(filter.key),
                summary: _values.selected(filter.key).isEmpty ? null : [for (final option in filter.options) if (_values.selected(filter.key).contains(option.value)) option.label].join(', '),
                onTap: () => _pickMulti(filter),
              ),
            ReportFilterKind.days => FilterDropdown<String>(
                label: filter.label,
                icon: Icons.date_range_rounded,
                value: filter.options.any((o) => o.value == _values.days) ? _values.days : filter.options.first.value,
                items: [for (final option in filter.options) DropdownMenuItem(value: option.value, child: Text(option.label))],
                onChanged: (value) => setState(() => _values = _values.copyWith(days: value)),
              ),
            ReportFilterKind.dates => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _DateField(label: 'Desde', value: _values.dateFrom, onTap: () => _pickDate(from: true), onClear: () => setState(() => _values = _withoutDate(_values, from: true))),
                const SizedBox(height: AppSpacing.md),
                _DateField(label: 'Hasta', value: _values.dateTo, onTap: () => _pickDate(from: false), onClear: () => setState(() => _values = _withoutDate(_values, from: false))),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w600))),
              ]),
          },
        if (definition.supportsCompare)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.navy,
            activeTrackColor: AppColors.mustard,
            title: const Text('Comparar con el periodo anterior', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
            subtitle: Text(canCompare(definition, _values) ? 'Mismo número de días justo antes del rango.' : 'Elige las dos fechas para comparar.'),
            value: _values.compare && canCompare(definition, _values),
            onChanged: canCompare(definition, _values) ? (on) => setState(() => _values = _values.copyWith(compare: on)) : null,
          ),
      ],
    );
  }
}

/// Quita una de las dos fechas; `copyWith` no puede poner una fecha en `null`.
ReportFilterValues _withoutDate(ReportFilterValues values, {required bool from}) => ReportFilterValues(
      statuses: values.statuses,
      priorities: values.priorities,
      categories: values.categories,
      kinds: values.kinds,
      equipmentTypeIds: values.equipmentTypeIds,
      dateFrom: from ? null : values.dateFrom,
      dateTo: from ? values.dateTo : null,
      days: values.days,
      compare: false,
    );

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, required this.onClear});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.date_range_rounded, size: 16, color: AppColors.slate),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.steel)),
          ]),
        ),
        Material(
          color: AppColors.canvas,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: value == null ? AppColors.grey : AppColors.steel)),
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTap,
            child: SizedBox(
              height: 50,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                child: Row(children: [
                  Expanded(child: Text(value == null ? 'Sin límite' : formatDate(value!), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: value == null ? AppColors.slate : AppColors.navy))),
                  if (value != null)
                    IconButton(tooltip: 'Quitar fecha «$label»', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.slate))
                  else
                    const Padding(padding: EdgeInsets.only(right: AppSpacing.md), child: Icon(Icons.calendar_month_rounded, color: AppColors.slate)),
                ]),
              ),
            ),
          ),
        ),
      ]);
}
