import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/technicians/technicians_list_bloc.dart';
import '../../core/format/technicians_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/technicians/technician_filters.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/multi_select_sheet.dart' show FilterButton;
import '../../widgets/shared/paginator.dart';
import '../../widgets/shared/skeleton.dart';
import '../../widgets/technicians/technician_detail_sheet.dart';
import '../../widgets/technicians/technician_views.dart';
import '../../widgets/technicians/technicians_filter_sheet.dart';
import '../../widgets/technicians/technicians_header.dart';
import '../../widgets/technicians/technicians_kpi_grid.dart';

/// Personal técnico: las cifras del equipo, la búsqueda y los filtros, la lista en tarjetas o en
/// tabla y la ficha de cada técnico en una hoja inferior. Ordena por carga para ayudar a repartir
/// el trabajo, no para comparar personas. Requiere `tecnicos:ver`; la ruta lo exige y la
/// autorización real es del backend.
class TechniciansScreen extends StatefulWidget {
  const TechniciansScreen({super.key});

  static const path = '/tecnicos';

  @override
  State<TechniciansScreen> createState() => _TechniciansScreenState();
}

class _TechniciansScreenState extends State<TechniciansScreen> {
  static const _debounce = Duration(milliseconds: 350);

  late final TechniciansListBloc _list;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _timer;
  bool _table = false;

  @override
  void initState() {
    super.initState();
    _list = TechniciansListBloc(repository: context.read<TechniciansRepository>())..add(const TechniciansRequested());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    unawaited(_list.close());
    super.dispose();
  }

  /// La búsqueda espera a que se deje de escribir antes de filtrar.
  void _onSearchChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) _list.add(TechniciansSearchChanged(text));
    });
  }

  void _clearSearch() {
    _timer?.cancel();
    _searchController.clear();
    _list.add(const TechniciansSearchChanged(''));
  }

  void _clearAll() {
    _timer?.cancel();
    _searchController.clear();
    _list.add(const TechniciansFiltersChanged(TechnicianFilters()));
  }

  Future<void> _showFilters() async {
    final state = _list.state;
    final result = await showTechniciansFilterSheet(context, initial: state.filters, specialties: state.specialties);
    if (result != null && mounted) _list.add(TechniciansFiltersChanged(result));
  }

  Future<void> _refresh() {
    final done = Completer<void>();
    _list.add(TechniciansRequested(done: done));
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    // La tarifa solo llega a quien gestiona técnicos; a los demás ni se les enseña el campo.
    final showRate = profile.can('tecnicos:editar');
    final showTickets = profile.can('tickets:ver');
    return BlocProvider.value(
      value: _list,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: TechniciansScreen.path),
        body: RefreshIndicator(
          color: AppColors.steel,
          onRefresh: _refresh,
          child: BlocBuilder<TechniciansListBloc, TechniciansListState>(
            builder: (context, state) => ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                const TechniciansHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (state.unavailable)
                      EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar los técnicos', message: state.failure?.message, actionLabel: 'Reintentar', onAction: () => _list.add(const TechniciansRequested()))
                    else ...[
                      TechniciansKpiGrid(
                        summary: state.initialLoading ? null : state.summary,
                        hasWorkload: state.hasWorkload,
                        windowDays: state.workload?.windowDays ?? 30,
                        selected: state.filters.status,
                        onSelect: (status) => _list.add(TechniciansFiltersChanged(state.filters.copyWith(status: status, clearStatus: status == null))),
                      ),
                      if (!state.initialLoading && !state.hasWorkload) _WorkloadNotice(message: state.workloadFailure?.message, onRetry: () => _list.add(const TechniciansRequested())),
                      const SizedBox(height: AppSpacing.md),
                      _SearchField(controller: _searchController, onChanged: _onSearchChanged, onClear: _clearSearch),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        FilterButton(count: state.filters.activeCount, onPressed: _showFilters),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _OrderButton(order: state.order, onChanged: (order) => _list.add(TechniciansOrderChanged(order)))),
                      ]),
                      _ActiveFilterChips(filters: state.filters, specialties: state.specialties, onChanged: (filters) => _list.add(TechniciansFiltersChanged(filters))),
                      const SizedBox(height: AppSpacing.md),
                      _ViewToggle(table: _table, onChanged: (table) => setState(() => _table = table)),
                      const SizedBox(height: AppSpacing.md),
                      _Results(
                        state: state,
                        table: _table,
                        showRate: showRate,
                        onClearFilters: _clearAll,
                        onOpen: (technician) => showTechnicianDetail(context, technician: technician, workload: state.workload, showRate: showRate, showTickets: showTickets),
                        onPage: (page) {
                          _list.add(TechniciansPageChanged(page));
                          if (_scrollController.hasClients) _scrollController.jumpTo(0);
                        },
                        onPageSize: (size) => _list.add(TechniciansPageSizeChanged(size)),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso de que la carga no llegó: la lista sigue, las cifras de tickets no.
class _WorkloadNotice extends StatelessWidget {
  const _WorkloadNotice({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.grey)),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.slate),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('La carga de tickets no está disponible.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel))),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          maxLength: 100,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, especialidad, código o correo…',
            counterText: '',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty ? null : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close_rounded), onPressed: onClear),
          ),
        ),
      );
}

/// Orden de la lista; por defecto, menor carga primero.
class _OrderButton extends StatelessWidget {
  const _OrderButton({required this.order, required this.onChanged});

  final TechnicianOrder order;
  final ValueChanged<TechnicianOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<TechnicianOrder>(
      tooltip: 'Ordenar la lista',
      initialValue: order,
      onSelected: onChanged,
      itemBuilder: (context) => [for (final option in TechnicianOrder.values) PopupMenuItem(value: option, child: Text(orderLabel(option)))],
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.grey)),
        child: Row(children: [
          const Icon(Icons.sort_rounded, size: 20, color: AppColors.steel),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Ordenar por', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w700)),
              Text(orderLabel(order), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700)),
            ]),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate),
        ]),
      ),
    );
  }
}

/// Un chip por cada valor filtrado en la hoja, que se quita con su equis.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.specialties, required this.onChanged});

  final TechnicianFilters filters;

  /// Las especialidades con su nombre visible (el filtro guarda la forma normalizada).
  final List<String> specialties;
  final ValueChanged<TechnicianFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    if (filters.activeCount == 0) return const SizedBox.shrink();
    final names = {for (final name in specialties) normalize(name): name};
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (final value in filters.specialties) ActiveFilterChip(label: names[value] ?? value, onRemove: () => onChanged(filters.copyWith(specialties: {...filters.specialties}..remove(value)))),
        for (final value in filters.availability) ActiveFilterChip(label: availabilityLabel(value), onRemove: () => onChanged(filters.copyWith(availability: {...filters.availability}..remove(value)))),
        for (final value in filters.accounts) ActiveFilterChip(label: 'Cuenta ${accountLabel(value).toLowerCase()}', onRemove: () => onChanged(filters.copyWith(accounts: {...filters.accounts}..remove(value)))),
        for (final value in filters.loads) ActiveFilterChip(label: loadLabel(value), onRemove: () => onChanged(filters.copyWith(loads: {...filters.loads}..remove(value)))),
      ]),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.table, required this.onChanged});

  final bool table;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Vista de la lista',
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.grid_view_rounded, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Tarjetas'))),
            ButtonSegment(value: true, icon: Icon(Icons.table_rows_outlined, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Tabla'))),
          ],
          selected: {table},
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.steel,
            selectedBackgroundColor: AppColors.skyLight,
            selectedForegroundColor: AppColors.navy,
            side: const BorderSide(color: AppColors.grey),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      );
}

/// La lista con sus estados (cargando, vacío, datos) y el paginador.
class _Results extends StatelessWidget {
  const _Results({required this.state, required this.table, required this.showRate, required this.onClearFilters, required this.onOpen, required this.onPage, required this.onPageSize});

  final TechniciansListState state;
  final bool table;
  final bool showRate;
  final VoidCallback onClearFilters;
  final ValueChanged<Technician> onOpen;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    if (state.initialLoading) {
      return Semantics(
        container: true,
        label: 'Cargando técnicos',
        child: Column(children: [for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 150, radius: AppRadius.lg))]),
      );
    }
    final total = state.technicians.length;
    final filtered = state.filtered;
    final hasFilters = !state.filters.isEmpty;
    if (filtered.isEmpty) {
      return EmptyState(
        icon: hasFilters ? Icons.search_off_rounded : Icons.engineering_outlined,
        title: hasFilters ? 'Ningún técnico coincide con los filtros' : 'Aún no hay perfiles de técnico',
        message: hasFilters ? 'Prueba con otra búsqueda o quita los filtros.' : 'Cuando se registre un técnico aparecerá aquí.',
        actionLabel: hasFilters ? 'Quitar filtros' : null,
        onAction: hasFilters ? onClearFilters : null,
      );
    }
    final items = state.pageItems;
    final theme = Theme.of(context);
    final count = hasFilters
        ? '${filtered.length} de $total ${total == 1 ? 'técnico coincide' : 'técnicos coinciden'} con los filtros'
        : '$total ${total == 1 ? 'técnico registrado' : 'técnicos registrados'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.status == TechniciansStatus.loading) const Padding(padding: EdgeInsets.only(bottom: 6), child: LinearProgressIndicator(minHeight: 2)),
      Row(children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.steel, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(count, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: AppSpacing.sm),
      if (table)
        TechniciansTable(technicians: items, workload: state.workload, onOpen: onOpen)
      else
        for (final technician in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TechnicianCard(technician: technician, workload: state.workload, showRate: showRate, onTap: () => onOpen(technician)),
          ),
      const SizedBox(height: AppSpacing.md),
      Paginator(page: state.page, totalPages: state.totalPages, total: filtered.length, pageSize: state.pageSize, onPage: onPage, onPageSize: onPageSize),
    ]);
  }
}
