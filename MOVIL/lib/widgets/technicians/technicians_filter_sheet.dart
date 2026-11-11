import 'package:flutter/material.dart';

import '../../core/format/technicians_format.dart';
import '../../models/technicians/technician_filters.dart';
import '../shared/filter_widgets.dart';
import '../shared/multi_select_sheet.dart';

const _accountLabels = {true: 'Activa', false: 'Inactiva'};
const _availabilityLabels = {true: 'Disponible', false: 'No disponible'};

/// Nombre de cada valor de los filtros de cuenta y disponibilidad (la hoja y sus chips).
String accountLabel(bool active) => _accountLabels[active]!;
String availabilityLabel(bool available) => _availabilityLabels[available]!;

/// Hoja de filtros de técnicos: especialidad, cuenta, disponibilidad y carga, todos con
/// multiselección. Devuelve los filtros al aplicar (conserva la búsqueda y la tarjeta de resumen
/// de [initial]) y `null` si se cierra sin aplicar. [specialties] son las que existen hoy, con su
/// nombre visible.
Future<TechnicianFilters?> showTechniciansFilterSheet(BuildContext context, {required TechnicianFilters initial, required List<String> specialties}) => showModalBottomSheet<TechnicianFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _TechniciansFilterSheet(initial: initial, specialties: specialties),
    );

class _TechniciansFilterSheet extends StatefulWidget {
  const _TechniciansFilterSheet({required this.initial, required this.specialties});

  final TechnicianFilters initial;
  final List<String> specialties;

  @override
  State<_TechniciansFilterSheet> createState() => _TechniciansFilterSheetState();
}

class _TechniciansFilterSheetState extends State<_TechniciansFilterSheet> {
  // Una especialidad filtrada que ya no existe se descarta.
  late Set<String> _specialties = {for (final name in widget.specialties) if (widget.initial.specialties.contains(normalize(name))) normalize(name)};
  late Set<bool> _accounts = {...widget.initial.accounts};
  late Set<bool> _availability = {...widget.initial.availability};
  late Set<LoadBucket> _loads = {...widget.initial.loads};

  /// Abre la multiselección de un grupo y guarda lo elegido.
  Future<void> _pick<T>(String title, List<FilterOption<T>> options, Set<T> selected, ValueChanged<Set<T>> onPicked) async {
    final result = await showMultiSelectSheet<T>(context, title: title, options: options, selected: selected);
    if (result != null && mounted) setState(() => onPicked(result));
  }

  /// Lo elegido en un grupo, en el orden de sus opciones; `null` si no hay filtro.
  static String? _summary<T>(List<FilterOption<T>> options, Set<T> selected) => selected.isEmpty ? null : [for (final option in options) if (selected.contains(option.value)) option.label].join(', ');

  @override
  Widget build(BuildContext context) {
    final specialtyOptions = [for (final name in widget.specialties) FilterOption(normalize(name), name)];
    final accountOptions = [for (final entry in _accountLabels.entries) FilterOption(entry.key, entry.value)];
    final availabilityOptions = [for (final entry in _availabilityLabels.entries) FilterOption(entry.key, entry.value)];
    final loadOptions = [for (final bucket in LoadBucket.values) FilterOption(bucket, loadLabel(bucket))];
    return FilterSheet(
      onReset: () => setState(() {
        _specialties = {};
        _accounts = {};
        _availability = {};
        _loads = {};
      }),
      onApply: () => Navigator.pop(context, widget.initial.copyWith(specialties: _specialties, accounts: _accounts, availability: _availability, loads: _loads)),
      children: [
        FilterTile(
          label: 'Especialidad',
          icon: Icons.folder_open_rounded,
          summary: _summary(specialtyOptions, _specialties),
          onTap: () => _pick<String>('Especialidad', specialtyOptions, _specialties, (value) => _specialties = value),
        ),
        FilterTile(
          label: 'Disponibilidad',
          icon: Icons.event_available_outlined,
          summary: _summary(availabilityOptions, _availability),
          onTap: () => _pick<bool>('Disponibilidad', availabilityOptions, _availability, (value) => _availability = value),
        ),
        FilterTile(
          label: 'Estado de la cuenta',
          icon: Icons.flag_outlined,
          summary: _summary(accountOptions, _accounts),
          onTap: () => _pick<bool>('Estado de la cuenta', accountOptions, _accounts, (value) => _accounts = value),
        ),
        FilterTile(
          label: 'Carga de tickets',
          icon: Icons.stacked_bar_chart_rounded,
          summary: _summary(loadOptions, _loads),
          onTap: () => _pick<LoadBucket>('Carga de tickets', loadOptions, _loads, (value) => _loads = value),
        ),
      ],
    );
  }
}
