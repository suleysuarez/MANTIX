import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../bloc/catalogs/technician_search_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../shared/filter_widgets.dart';
import '../shared/search_picker_sheet.dart';

/// Los filtros de la lista de planes: estado, técnico responsable y orden. El orden por defecto es
/// la próxima fecha de servicio.
class SchedulesFilters extends Equatable {
  const SchedulesFilters({this.status = ScheduleStatusFilter.all, this.technicianId, this.technicianName, this.sort = defaultSort});

  static const defaultSort = 'next_due_at';

  final ScheduleStatusFilter status;
  final int? technicianId;

  /// Nombre del técnico filtrado: el filtro solo guarda su id y el chip necesita el nombre.
  final String? technicianName;

  /// `next_due_at`, `title` o `-created_at`.
  final String sort;

  /// Cuántos filtros hay puestos (para el contador del botón).
  int get activeCount => (status == ScheduleStatusFilter.all ? 0 : 1) + (technicianId == null ? 0 : 1) + (sort == defaultSort ? 0 : 1);

  SchedulesFilters copyWith({ScheduleStatusFilter? status, int? technicianId, String? technicianName, bool clearTechnician = false, String? sort}) => SchedulesFilters(
        status: status ?? this.status,
        technicianId: clearTechnician ? null : (technicianId ?? this.technicianId),
        technicianName: clearTechnician ? null : (technicianName ?? this.technicianName),
        sort: sort ?? this.sort,
      );

  @override
  List<Object?> get props => [status, technicianId, technicianName, sort];
}

String statusFilterLabel(ScheduleStatusFilter status) => switch (status) {
      ScheduleStatusFilter.all => 'Todos',
      ScheduleStatusFilter.overdue => 'Vencidos',
      ScheduleStatusFilter.active => 'Activos',
      ScheduleStatusFilter.inactive => 'Inactivos',
    };

const sortOptions = {
  'next_due_at': 'Próximo servicio',
  'title': 'Título',
  '-created_at': 'Más recientes',
};

/// Hoja de filtros de planes. Devuelve los filtros al aplicar y `null` si se cierra sin aplicar
/// (no cambia nada). El técnico solo se ofrece con [techniciansRepository] (quien puede ver
/// técnicos).
Future<SchedulesFilters?> showSchedulesFilterSheet(BuildContext context, {required SchedulesFilters initial, TechniciansRepository? techniciansRepository}) => showModalBottomSheet<SchedulesFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _SchedulesFilterSheet(initial: initial, techniciansRepository: techniciansRepository),
    );

class _SchedulesFilterSheet extends StatefulWidget {
  const _SchedulesFilterSheet({required this.initial, required this.techniciansRepository});

  final SchedulesFilters initial;
  final TechniciansRepository? techniciansRepository;

  @override
  State<_SchedulesFilterSheet> createState() => _SchedulesFilterSheetState();
}

class _SchedulesFilterSheetState extends State<_SchedulesFilterSheet> {
  late SchedulesFilters _filters = widget.initial;

  Future<void> _pickTechnician() async {
    final repository = widget.techniciansRepository!;
    final picked = await showSearchPicker<Technician>(
      context,
      title: 'Filtrar por técnico',
      hint: 'Nombre, correo o especialidad',
      emptyTitle: 'No encontramos técnicos',
      createBloc: (search) => TechnicianSearchBloc(repository: repository, search: search),
      itemBuilder: (context, item, select) => ListTile(
        minVerticalPadding: 12,
        tileColor: AppColors.canvas,
        leading: const Icon(Icons.engineering_outlined, color: AppColors.steel),
        title: Text(item.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.specialization == null ? null : Text(item.specialization!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _filters.technicianId == item.id ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
        onTap: select,
      ),
    );
    if (picked != null && mounted) setState(() => _filters = _filters.copyWith(technicianId: picked.id, technicianName: picked.fullName));
  }

  @override
  Widget build(BuildContext context) => FilterSheet(
        onReset: () => setState(() => _filters = const SchedulesFilters()),
        onApply: () => Navigator.pop(context, _filters),
        children: [
          FilterDropdown<ScheduleStatusFilter>(
            label: 'Estado',
            icon: Icons.flag_outlined,
            value: _filters.status,
            items: [for (final status in ScheduleStatusFilter.values) DropdownMenuItem(value: status, child: Text(statusFilterLabel(status)))],
            onChanged: (value) => setState(() => _filters = _filters.copyWith(status: value)),
          ),
          if (widget.techniciansRepository != null) ...[
            FilterTile(label: 'Técnico responsable', icon: Icons.engineering_outlined, summary: _filters.technicianId == null ? null : (_filters.technicianName ?? 'Técnico #${_filters.technicianId}'), onTap: _pickTechnician),
            if (_filters.technicianId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => setState(() => _filters = _filters.copyWith(clearTechnician: true)), icon: const Icon(Icons.close_rounded, size: 18), label: const Text('Quitar técnico')),
              ),
          ],
          FilterDropdown<String>(
            label: 'Ordenar por',
            icon: Icons.sort_rounded,
            value: _filters.sort,
            items: [for (final entry in sortOptions.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
            onChanged: (value) => setState(() => _filters = _filters.copyWith(sort: value)),
          ),
        ],
      );
}
