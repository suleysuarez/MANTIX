import 'package:flutter/material.dart';

import '../../bloc/catalogs/technician_search_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/queue_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/queue/queue_filters.dart';
import '../../repositories/catalogs/catalogs_repository.dart';
import '../shared/filter_widgets.dart';
import '../shared/multi_select_sheet.dart';
import '../shared/search_picker_sheet.dart';

/// Lo que devuelve la hoja: los filtros y los nombres de los técnicos elegidos (el filtro solo
/// guarda sus ids, y los chips de la pantalla necesitan el nombre).
typedef QueueFilterResult = ({QueueFilters filters, Map<int, String> technicians});

/// Hoja de filtros de la bandeja: categoría, prioridad y técnico con multiselección, y rango de
/// fechas de recepción. «Aplicar» devuelve el resultado; cerrar la hoja no cambia nada.
Future<QueueFilterResult?> showQueueFilterSheet(
  BuildContext context, {
  required QueueFilters initial,
  required Map<int, String> technicians,
  required List<RequestCategory> categories,
  required List<PriorityOption> priorities,
  required CatalogsRepository catalogs,
  DateTime? today,
}) =>
    showModalBottomSheet<QueueFilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      builder: (_) => _QueueFilterSheet(initial: initial, technicians: technicians, categories: categories, priorities: priorities, catalogs: catalogs, today: today ?? DateTime.now()),
    );

class _QueueFilterSheet extends StatefulWidget {
  const _QueueFilterSheet({required this.initial, required this.technicians, required this.categories, required this.priorities, required this.catalogs, required this.today});

  final QueueFilters initial;
  final Map<int, String> technicians;
  final List<RequestCategory> categories;
  final List<PriorityOption> priorities;
  final CatalogsRepository catalogs;
  final DateTime today;

  @override
  State<_QueueFilterSheet> createState() => _QueueFilterSheetState();
}

class _QueueFilterSheetState extends State<_QueueFilterSheet> {
  late Set<String> _categories = {...widget.initial.categories};
  late Set<String> _priorities = {...widget.initial.priorities};
  late Map<int, String> _technicians = {for (final id in widget.initial.technicianIds) id: widget.technicians[id] ?? 'Técnico #$id'};
  late DateTimeRange? _dates = widget.initial.dateFrom == null || widget.initial.dateTo == null ? null : DateTimeRange(start: widget.initial.dateFrom!, end: widget.initial.dateTo!);

  String? get _rangeError => queueRangeError(_dates?.start, _dates?.end, widget.today);

  /// Prioridades en el orden del servidor (la más urgente primero).
  List<PriorityOption> get _rankedPriorities => [...widget.priorities]..sort((a, b) => b.level.compareTo(a.level));

  void _apply() => Navigator.pop<QueueFilterResult>(
        context,
        (
          filters: widget.initial.copyWith(
            categories: [for (final c in widget.categories) if (_categories.contains(c.code)) c.code],
            priorities: [for (final p in _rankedPriorities) if (_priorities.contains(p.code)) p.code],
            technicianIds: _technicians.keys.toList(),
            dateFrom: _dates?.start,
            dateTo: _dates?.end,
            clearDates: _dates == null,
          ),
          technicians: _technicians,
        ),
      );

  Future<void> _addTechnician() async {
    final picked = await showSearchPicker<TechnicianOption>(
      context,
      title: 'Filtrar por técnico',
      hint: 'Nombre, correo o especialidad',
      emptyTitle: 'No encontramos técnicos',
      createBloc: (search) => TechnicianSearchBloc(repository: widget.catalogs, search: search),
      itemBuilder: (context, item, select) => ListTile(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        tileColor: AppColors.canvas,
        minVerticalPadding: AppSpacing.md,
        leading: const Icon(Icons.engineering_outlined, color: AppColors.steel),
        title: Text(item.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.specialization == null ? null : Text(item.specialization!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _technicians.containsKey(item.id) ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
        onTap: select,
      ),
    );
    if (picked != null && mounted) setState(() => _technicians = {..._technicians, picked.id: picked.fullName});
  }

  @override
  Widget build(BuildContext context) {
    final rangeError = _rangeError;
    return FilterSheet(
      onReset: () => setState(() {
        _categories = {};
        _priorities = {};
        _technicians = {};
        _dates = null;
      }),
      onApply: rangeError == null ? _apply : null,
      children: [
        FilterTile(
          label: 'Categoría',
          icon: Icons.sell_outlined,
          summary: _categories.isEmpty ? null : [for (final c in widget.categories) if (_categories.contains(c.code)) c.name].join(', '),
          onTap: () async {
            final picked = await showMultiSelectSheet<String>(
              context,
              title: 'Categoría',
              options: [for (final c in widget.categories) FilterOption(c.code, c.name)],
              selected: _categories,
            );
            if (picked != null) setState(() => _categories = picked);
          },
        ),
        FilterTile(
          label: 'Prioridad',
          icon: Icons.priority_high_rounded,
          summary: _priorities.isEmpty ? null : [for (final p in _rankedPriorities) if (_priorities.contains(p.code)) p.name].join(', '),
          onTap: () async {
            final picked = await showMultiSelectSheet<String>(
              context,
              title: 'Prioridad',
              options: [for (final p in _rankedPriorities) FilterOption(p.code, p.name)],
              selected: _priorities,
            );
            if (picked != null) setState(() => _priorities = picked);
          },
        ),
        _TechnicianField(selected: _technicians, onAdd: _addTechnician, onRemove: (id) => setState(() => _technicians = {..._technicians}..remove(id))),
        DateRangeFilterField(label: 'Recibidas entre', value: _dates, onChanged: (range) => setState(() => _dates = range)),
        if (rangeError != null) Text(rangeError, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error)),
      ],
    );
  }
}

/// Técnicos elegidos como chips y un botón para añadir otro con búsqueda.
class _TechnicianField extends StatelessWidget {
  const _TechnicianField({required this.selected, required this.onAdd, required this.onRemove});

  final Map<int, String> selected;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.engineering_outlined, size: 16, color: AppColors.slate),
            const SizedBox(width: 6),
            Expanded(child: Text('Técnico', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.steel))),
          ]),
        ),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(spacing: 8, runSpacing: 4, children: [for (final entry in selected.entries) ActiveFilterChip(label: entry.value, onRemove: () => onRemove(entry.key))]),
          ),
        OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Añadir técnico')),
      ]);
}

/// Texto corto del rango, para los chips de filtros activos.
String queueRangeLabel(DateTime from, DateTime to) => '${formatDate(from)} – ${formatDate(to)}';
