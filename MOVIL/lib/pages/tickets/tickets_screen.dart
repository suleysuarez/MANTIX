import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../bloc/requests/equipment_search_bloc.dart';
import '../../bloc/tickets/ticket_board_bloc.dart';
import '../../bloc/tickets/tickets_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/multi_select_sheet.dart';
import '../../widgets/shared/paginator.dart';
import '../../widgets/shared/search_picker_sheet.dart';
import '../../widgets/tickets/ticket_cards.dart';
import '../../widgets/tickets/ticket_detail_sheet.dart';
import '../../widgets/tickets/ticket_kanban.dart';
import '../../widgets/tickets/ticket_move_dialog.dart';
import '../../widgets/tickets/ticket_summary.dart';
import '../requests/create_request_screen.dart';

abstract final class TicketRoutes {
  static const list = '/modulos/tickets';
}

/// Gestión móvil de tickets: encabezado como el de Equipos, resumen, atención prioritaria,
/// filtros con multiselección, y listado en tabla o tablero por estados. El detalle y el
/// formulario de creación se abren en hojas inferiores.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Set<String> _statuses = {};
  Set<String> _priorities = {};
  Map<int, String> _equipments = {};
  DateTimeRange? _dates;
  String _search = '';
  bool _kanban = false;
  final int _pageSize = 20;

  /// Sube cada vez que hay que empezar de cero aunque los filtros no hayan cambiado (un
  /// ticket nuevo): la clave del Bloc cambia y el listado vuelve a la página 1.
  int _generation = 0;
  int? _highlightId;
  Timer? _highlightTimer;
  StreamSubscription<int>? _createdSub;
  late final RequestsRepository _repository;
  late final TicketBoardBloc _board;

  @override
  void initState() {
    super.initState();
    _repository = context.read<RequestsRepository>();
    _board = TicketBoardBloc(repository: _repository)..add(const TicketBoardStarted());
    _createdSub = _repository.created.listen(_onCreated);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    unawaited(_createdSub?.cancel());
    unawaited(_board.close());
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Un ticket recién creado: se limpian filtros y búsqueda, el listado vuelve a la página 1
  /// (orden por creación descendente, así que sale primero) y se resalta unos segundos.
  void _onCreated(int id) {
    if (!mounted) return;
    _highlightTimer?.cancel();
    _searchController.clear();
    setState(() {
      _statuses = {};
      _priorities = {};
      _equipments = {};
      _dates = null;
      _search = '';
      _generation++;
      _highlightId = id;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  void _applySearch() {
    final value = _searchController.text.trim();
    if (value != _search) setState(() => _search = value);
  }

  int get _activeFilterCount => _statuses.length + _priorities.length + _equipments.length + (_dates == null ? 0 : 1);

  /// Estados elegidos separados por coma y en el orden del flujo; `null` si no hay filtro.
  String? get _statusCsv => _statuses.isEmpty ? null : [for (final s in knownStatuses) if (_statuses.contains(s)) s].join(',');

  Future<void> _showFilters() async {
    var statuses = {..._statuses};
    var priorities = {..._priorities};
    var equipments = {..._equipments};
    var dates = _dates;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) => FilterSheet(
          onReset: () => setSheet(() {
            statuses = {};
            priorities = {};
            equipments = {};
            dates = null;
          }),
          onApply: () => Navigator.pop(sheet, true),
          children: [
            FilterTile(
              label: 'Estado',
              icon: Icons.flag_outlined,
              summary: statuses.isEmpty ? null : [for (final s in knownStatuses) if (statuses.contains(s)) statusMeta(s).label].join(', '),
              onTap: () async {
                final picked = await showMultiSelectSheet<String>(
                  context,
                  title: 'Estado',
                  options: [for (final s in knownStatuses) FilterOption(s, statusMeta(s).label)],
                  selected: statuses,
                );
                if (picked != null) setSheet(() => statuses = picked);
              },
            ),
            FilterTile(
              label: 'Prioridad',
              icon: Icons.priority_high_rounded,
              summary: priorities.isEmpty ? null : [for (final p in knownPriorities) if (priorities.contains(p)) priorityMeta(p).label].join(', '),
              onTap: () async {
                final picked = await showMultiSelectSheet<String>(
                  context,
                  title: 'Prioridad',
                  options: [for (final p in knownPriorities) FilterOption(p, priorityMeta(p).label)],
                  selected: priorities,
                );
                if (picked != null) setSheet(() => priorities = picked);
              },
            ),
            _EquipmentFilterField(
              selected: equipments,
              onAdd: () async {
                final picked = await showSearchPicker<EquipmentOption>(
                  context,
                  title: 'Filtrar por equipo',
                  hint: 'Etiqueta, serie, marca o modelo',
                  emptyTitle: 'No encontramos equipos',
                  createBloc: (search) => EquipmentSearchBloc(repository: _repository, search: search),
                  itemBuilder: (context, item, select) => ListTile(
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                    tileColor: AppColors.canvas,
                    minVerticalPadding: AppSpacing.md,
                    leading: const Icon(Icons.desktop_windows_outlined, color: AppColors.steel),
                    title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: equipments.containsKey(item.id) ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
                    onTap: select,
                  ),
                );
                if (picked != null) setSheet(() => equipments = {...equipments, picked.id: picked.label});
              },
              onRemove: (id) => setSheet(() => equipments = {...equipments}..remove(id)),
            ),
            DateRangeFilterField(value: dates, onChanged: (range) => setSheet(() => dates = range)),
          ],
        ),
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _statuses = statuses;
      _priorities = priorities;
      _equipments = equipments;
      _dates = dates;
    });
  }

  /// Pide lo que el estado de destino exige y, si todo está claro, manda el cambio.
  Future<void> _requestMove(BuildContext context, TicketListItem item, String target) async {
    final board = context.read<TicketBoardBloc>();
    final input = await askTicketMoveData(
      context,
      ticket: item,
      target: target,
      requires: board.state.requiresFor(target),
    );
    if (input == null || !context.mounted) return;
    board.add(TicketMoveRequested(
      item,
      target,
      notes: input.notes,
      resolutionSummary: input.resolutionSummary,
      category: input.category,
      priority: input.priority,
      technicianId: input.technicianId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }

    return BlocProvider.value(
      value: _board,
      child: BlocListener<TicketBoardBloc, TicketBoardState>(
        listenWhen: (previous, current) => current.notice != null && previous.notice != current.notice,
        listener: (context, state) {
          final notice = state.notice!;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(notice.message),
              backgroundColor: notice.isError ? AppColors.error : AppColors.navy,
            ));
        },
        child: BlocProvider(
          key: ValueKey('$_statusCsv|${_priorities.join(',')}|${_equipments.keys.join(',')}|$_search|$_dates|$_pageSize|$_generation|$_kanban'),
          create: (context) => TicketsBloc(
            repository: _repository,
            status: _statusCsv,
            search: _search,
            dateFrom: _dates?.start,
            dateTo: _dates?.end,
            priorities: [for (final p in knownPriorities) if (_priorities.contains(p)) p],
            equipmentIds: _equipments.keys.toList(),
            pageSize: _kanban ? 500 : _pageSize,
          )..add(const PagedStarted()),
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: AppColors.canvas,
              appBar: MantixAppBar(profile: profile),
              drawer: MantixDrawer(profile: profile, selectedPath: TicketRoutes.list),
              body: BlocBuilder<TicketsBloc, PagedListState<TicketListItem>>(
                builder: (context, state) {
                  final loaded = state.status == PagedStatus.success;
                  return RefreshIndicator(
                    onRefresh: context.read<TicketsBloc>().refresh,
                    color: AppColors.steel,
                    child: ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _Header(canCreate: profile.can('solicitudes:crear'), onCreate: () => CreateRequestScreen.show(context, title: 'Crear nuevo ticket', submitLabel: 'Guardar y registrar ticket')),
                        const SizedBox(height: AppSpacing.md),
                        if (loaded) ...[
                          TicketStats(items: state.items, total: state.info?.total),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _applySearch(),
                              decoration: InputDecoration(
                                hintText: 'Buscar por número, título o descripción…',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: IconButton(tooltip: 'Buscar', onPressed: _applySearch, icon: const Icon(Icons.arrow_forward_rounded)),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FilterButton(count: _activeFilterCount, onPressed: _showFilters),
                        ]),
                        if (_activeFilterCount > 0) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final s in knownStatuses)
                              if (_statuses.contains(s)) ActiveFilterChip(label: statusMeta(s).label, onRemove: () => setState(() => _statuses = {..._statuses}..remove(s))),
                            for (final p in knownPriorities)
                              if (_priorities.contains(p)) ActiveFilterChip(label: priorityMeta(p).label, onRemove: () => setState(() => _priorities = {..._priorities}..remove(p))),
                            for (final entry in _equipments.entries) ActiveFilterChip(label: entry.value, onRemove: () => setState(() => _equipments = {..._equipments}..remove(entry.key))),
                            if (_dates != null) ActiveFilterChip(label: '${formatDate(_dates!.start)} – ${formatDate(_dates!.end)}', onRemove: () => setState(() => _dates = null)),
                          ]),
                        ],
                        if (loaded) ...[
                          const SizedBox(height: AppSpacing.md),
                          TicketAttention(items: state.items, onOpen: (item) => showTicketDetail(context, item.id)),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _ViewToggle(kanban: _kanban, onChanged: (value) => setState(() => _kanban = value)),
                        const SizedBox(height: AppSpacing.md),
                        switch (state.status) {
                          PagedStatus.loading => const _TicketLoading(),
                          PagedStatus.failure => EmptyState(
                              icon: Icons.cloud_off_outlined,
                              title: 'No pudimos cargar los tickets',
                              message: state.failure?.message,
                              actionLabel: 'Reintentar',
                              onAction: () => context.read<TicketsBloc>().add(const PagedStarted()),
                            ),
                          PagedStatus.success => _TicketResults(
                              items: state.items,
                              kanban: _kanban,
                              scrollController: _scrollController,
                              highlightId: _highlightId,
                              onMove: (item, target) => _requestMove(context, item, target),
                              info: state.info,
                              loadingPage: state.loadingMore,
                              pageFailure: state.loadMoreFailure?.message,
                              onOpen: (item) => showTicketDetail(context, item.id),
                              onPage: (page) {
                                context.read<TicketsBloc>().add(PagedPageSelected(page));
                                if (_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                              },
                            ),
                        },
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Encabezado como el de Equipos: icono, botón de crear, título grande y subtítulo corto.
class _Header extends StatelessWidget {
  const _Header({required this.canCreate, required this.onCreate});
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.confirmation_number_outlined, color: AppColors.steel, size: 24),
          ),
          const Spacer(),
          if (canCreate)
            Flexible(
              child: FilledButton.tonalIcon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Nuevo ticket', maxLines: 1, overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mustard,
                  foregroundColor: AppColors.navy,
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        const Text('GESTIÓN DE TICKETS', style: TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
        const SizedBox(height: 4),
        const Text('Incidencias y órdenes de trabajo.', style: TextStyle(color: AppColors.slate, fontSize: 12.5)),
      ]);
}

/// Filtro por equipo: los equipos elegidos como chips y un botón para añadir otro con búsqueda.
class _EquipmentFilterField extends StatelessWidget {
  const _EquipmentFilterField({required this.selected, required this.onAdd, required this.onRemove});
  final Map<int, String> selected;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.devices_other_rounded, size: 16, color: AppColors.slate),
            const SizedBox(width: 6),
            Expanded(child: Text('Equipo', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.steel))),
          ]),
        ),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 4, children: [for (final entry in selected.entries) ActiveFilterChip(label: entry.value, onRemove: () => onRemove(entry.key))]),
          ),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(selected.isEmpty ? 'Elegir equipo' : 'Añadir otro equipo'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft),
        ),
      ]);
}

/// Dos botones anchos: Tabla y Kanban.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.kanban, required this.onChanged});
  final bool kanban;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _ToggleButton(icon: Icons.table_rows_rounded, label: 'Tabla', selected: !kanban, onTap: () => onChanged(false))),
        const SizedBox(width: 10),
        Expanded(child: _ToggleButton(icon: Icons.view_kanban_outlined, label: 'Kanban', selected: kanban, onTap: () => onChanged(true))),
      ]);
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.steel : AppColors.slate;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.skyLight.withValues(alpha: .45) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: selected ? AppColors.steel : AppColors.grey.withValues(alpha: .6))),
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TicketResults extends StatelessWidget {
  const _TicketResults({
    required this.items,
    required this.kanban,
    required this.scrollController,
    required this.highlightId,
    required this.onMove,
    required this.info,
    required this.loadingPage,
    required this.pageFailure,
    required this.onOpen,
    required this.onPage,
    });

  final List<TicketListItem> items;
  final bool kanban;
  final ScrollController scrollController;
  final int? highlightId;
  final void Function(TicketListItem, String) onMove;
  final PageInfo? info;
  final bool loadingPage;
  final String? pageFailure;
  final ValueChanged<TicketListItem> onOpen;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No hay tickets para mostrar',
        message: 'Prueba con otro filtro o modifica la búsqueda.',
      );
    }
    return Column(
      children: [
        if (kanban)
          BlocBuilder<TicketBoardBloc, TicketBoardState>(
            builder: (context, board) => TicketKanban(items: items, board: board, onOpen: onOpen, onMove: onMove, scrollController: scrollController, highlightId: highlightId),
          )
        else
          for (final item in items) ...[
            TicketListCard(item: item, highlighted: item.id == highlightId, onTap: () => onOpen(item)),
            const SizedBox(height: 10),
          ],
        if (pageFailure != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(pageFailure!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!kanban && info != null) ...[
          const SizedBox(height: 8),
          Paginator(page: info!.page, pageSize: info!.pageSize, total: info!.total, totalPages: info!.totalPages, loading: loadingPage, onPage: onPage),
        ],
      ],
    );
  }
}

class _TicketLoading extends StatelessWidget {
  const _TicketLoading();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < 4; i++)
            const Card(
              child: SizedBox(height: 92, child: Center(child: LinearProgressIndicator())),
            ),
        ],
      );
}
