import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/maintenance/schedules_list_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../shared/empty_state.dart';
import '../shared/filter_widgets.dart';
import '../shared/multi_select_sheet.dart' show FilterButton;
import '../shared/paginator.dart';
import 'maintenance_cards.dart';
import 'schedules_filter_sheet.dart';

/// La vista «Lista» de mantenimientos: búsqueda, filtros (estado, técnico y orden con chips que se
/// quitan) y los planes por páginas con el `Paginator`. [top] es lo que va encima (encabezado y
/// conmutador) y se desplaza con la lista. Cambiar un filtro o el tamaño de página crea un
/// `SchedulesListBloc` nuevo (con otra `key`), igual que Equipos y Usuarios; moverse entre páginas
/// es un evento. Tirar hacia abajo recarga la página.
class SchedulesTab extends StatefulWidget {
  const SchedulesTab({super.key, required this.top, required this.onOpen, this.canFilterByTechnician = false, this.now});

  final Widget top;

  /// Qué pasa al tocar un plan (su ficha).
  final ValueChanged<MaintenanceSchedule> onOpen;

  /// El filtro por técnico exige `tecnicos:ver`.
  final bool canFilterByTechnician;

  /// Hora con la que se decide si un plan está vencido (se inyecta para probarla).
  final DateTime? now;

  @override
  State<SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<SchedulesTab> {
  static const _debounce = Duration(milliseconds: 350);

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _timer;
  String _search = '';
  SchedulesFilters _filters = const SchedulesFilters();
  int _pageSize = 20;

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// La búsqueda espera a que se deje de escribir antes de pedir.
  void _onSearchChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      final term = text.trim();
      if (mounted && term != _search) setState(() => _search = term);
    });
  }

  void _clearSearch() {
    _timer?.cancel();
    _searchController.clear();
    if (_search.isNotEmpty) setState(() => _search = '');
  }

  Future<void> _showFilters() async {
    final result = await showSchedulesFilterSheet(context, initial: _filters, techniciansRepository: widget.canFilterByTechnician ? context.read<TechniciansRepository>() : null);
    if (result == null || !mounted || result == _filters) return;
    setState(() => _filters = result);
  }

  void _clearAll() {
    _timer?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _filters = const SchedulesFilters();
    });
  }

  bool get _filtered => _search.isNotEmpty || _filters.activeCount > 0;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MaintenanceRepository>();
    return BlocProvider(
      key: ValueKey('$_search|${_filters.status}|${_filters.technicianId}|${_filters.sort}|$_pageSize'),
      create: (_) => SchedulesListBloc(repository: repository, search: _search, technicianId: _filters.technicianId, status: _filters.status, sort: _filters.sort, pageSize: _pageSize)..add(const SchedulesListStarted()),
      child: Builder(
        builder: (context) => RefreshIndicator(
          color: AppColors.steel,
          onRefresh: () => context.read<SchedulesListBloc>().refresh(),
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              widget.top,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _SearchRow(controller: _searchController, activeFilters: _filters.activeCount, onChanged: _onSearchChanged, onClear: _clearSearch, onFilters: _showFilters),
                  _ActiveFilterChips(filters: _filters, onChanged: (next) => setState(() => _filters = next)),
                  const SizedBox(height: AppSpacing.md),
                  _Results(
                    filtered: _filtered,
                    pageSize: _pageSize,
                    now: widget.now ?? DateTime.now(),
                    onPageSize: (size) => setState(() => _pageSize = size),
                    onClearFilters: _clearAll,
                    onOpen: widget.onOpen,
                    onPage: (page) {
                      context.read<SchedulesListBloc>().add(SchedulesPageSelected(page));
                      if (_scrollController.hasClients) _scrollController.jumpTo(0);
                    },
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.activeFilters, required this.onChanged, required this.onClear, required this.onFilters});

  final TextEditingController controller;
  final int activeFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              maxLength: 100,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por título o equipo…',
                counterText: '',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty ? null : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close_rounded), onPressed: onClear),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilterButton(count: activeFilters, onPressed: onFilters),
      ]);
}

/// Un chip por filtro puesto, que se quita con su equis.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onChanged});

  final SchedulesFilters filters;
  final ValueChanged<SchedulesFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    if (filters.activeCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        if (filters.status != ScheduleStatusFilter.all) ActiveFilterChip(label: statusFilterLabel(filters.status), onRemove: () => onChanged(filters.copyWith(status: ScheduleStatusFilter.all))),
        if (filters.technicianId != null) ActiveFilterChip(label: filters.technicianName ?? 'Técnico #${filters.technicianId}', onRemove: () => onChanged(filters.copyWith(clearTechnician: true))),
        if (filters.sort != SchedulesFilters.defaultSort) ActiveFilterChip(label: 'Orden: ${sortOptions[filters.sort] ?? filters.sort}', onRemove: () => onChanged(filters.copyWith(sort: SchedulesFilters.defaultSort))),
      ]),
    );
  }
}

/// La lista con sus estados (cargando, error, vacío, datos) y el paginador.
class _Results extends StatelessWidget {
  const _Results({required this.filtered, required this.pageSize, required this.now, required this.onPageSize, required this.onClearFilters, required this.onPage, required this.onOpen});

  final bool filtered;
  final int pageSize;
  final DateTime now;
  final ValueChanged<int> onPageSize;
  final VoidCallback onClearFilters;
  final ValueChanged<int> onPage;
  final ValueChanged<MaintenanceSchedule> onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<SchedulesListBloc, SchedulesListState>(
        builder: (context, state) {
          final bloc = context.read<SchedulesListBloc>();
          if (state.status == SchedulesStatus.loading) return const MaintenanceListSkeleton(label: 'Cargando planes de mantenimiento');
          if (state.status == SchedulesStatus.failure) {
            return EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar los mantenimientos', message: state.failure?.message, actionLabel: 'Reintentar', onAction: () => bloc.add(const SchedulesListStarted()));
          }
          if (state.items.isEmpty) {
            return EmptyState(
              icon: filtered ? Icons.search_off_rounded : Icons.event_available_outlined,
              title: filtered ? 'Ningún mantenimiento coincide con los filtros' : 'Aún no hay mantenimientos programados',
              message: filtered ? 'Prueba con otra búsqueda o quita los filtros.' : null,
              actionLabel: filtered ? 'Quitar filtros' : null,
              onAction: filtered ? onClearFilters : null,
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (state.loadingPage) const Padding(padding: EdgeInsets.only(bottom: 6), child: LinearProgressIndicator(minHeight: 2)),
            for (final schedule in state.items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: ScheduleCard(schedule: schedule, now: now, onTap: () => onOpen(schedule))),
            const SizedBox(height: AppSpacing.md),
            Paginator(page: state.page, totalPages: state.totalPages, total: state.total, pageSize: pageSize, loading: state.loadingPage, onPage: onPage, onPageSize: onPageSize),
          ]);
        },
      );
}
