import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/catalogs/category_names_cubit.dart';
import '../../bloc/catalogs/priorities_cubit.dart';
import '../../bloc/queue/queue_summary_bloc.dart';
import '../../bloc/queue/request_board_bloc.dart';
import '../../bloc/queue/triage_actions_bloc.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/queue/queue_filters.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/catalogs/catalogs_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../../repositories/queue/queue_repository.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/queue/queue_board.dart';
import '../../widgets/queue/queue_filter_sheet.dart';
import '../../widgets/queue/queue_header.dart';
import '../../widgets/queue/queue_kpi_grid.dart';
import '../../widgets/queue/queue_pulse_card.dart';
import '../../widgets/queue/queue_reject_sheet.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/multi_select_sheet.dart';
import '../../widgets/shared/skeleton.dart';
import '../../widgets/tickets/ticket_detail_sheet.dart';
import '../../widgets/tickets/ticket_move_dialog.dart';
import '../../widgets/tickets/ticket_move_sheets.dart';

/// Bandeja de triaje: las solicitudes que esperan trabajo, con sus cifras, el pulso de las
/// decisiones recientes y un tablero por estados. Requiere `solicitudes:ver_todos` (la ruta lo
/// exige; la autorización real es del backend).
class PendingRequestsScreen extends StatefulWidget {
  const PendingRequestsScreen({super.key});

  static const path = '/solicitudes-pendientes';

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  final _searchController = TextEditingController();
  late final RequestBoardBloc _board;
  late final QueueSummaryBloc _summary;
  late final PrioritiesCubit _priorities;
  late final CategoryNamesCubit _categories;
  late final TriageActionsBloc _actions;
  final _pageController = ScrollController();
  late final CatalogsRepository _catalogs;

  /// Nombre de cada técnico filtrado: el filtro solo guarda ids y los chips necesitan el nombre.
  Map<int, String> _technicians = {};

  @override
  void initState() {
    super.initState();
    _catalogs = context.read<CatalogsRepository>();
    _board = RequestBoardBloc(repository: context.read<RequestsRepository>())..add(const RequestBoardStarted());
    _summary = QueueSummaryBloc(repository: context.read<QueueRepository>())..add(const QueueSummaryRequested());
    _priorities = PrioritiesCubit(_catalogs)..load();
    _categories = CategoryNamesCubit(_catalogs)..load();
    _actions = TriageActionsBloc(repository: context.read<RequestsRepository>());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    unawaited(_actions.close());
    unawaited(_board.close());
    unawaited(_summary.close());
    unawaited(_priorities.close());
    unawaited(_categories.close());
    super.dispose();
  }

  /// Tirar para refrescar: recarga el resumen y las columnas y espera a las dos.
  Future<void> _refresh() {
    final summaryDone = Completer<void>();
    final boardDone = Completer<void>();
    _summary.add(QueueSummaryRequested(done: summaryDone));
    _board.add(RequestBoardRefreshed(done: boardDone));
    return Future.wait([summaryDone.future, boardDone.future]);
  }

  /// Mueve [ticket] a [target]. Si el movimiento no es válido (transición que el flujo no
  /// permite o falta permiso) no se pide nada: `TriageActionsBloc` lo explica. Si es válido se
  /// piden los datos que el destino exige; cancelar la hoja deja la tarjeta donde estaba.
  Future<void> _requestMove(TicketListItem ticket, String target) async {
    final workflow = _board.state.workflow;
    if (!workflow.canMove(ticket, target)) {
      _actions.add(TriageMoveRequested(ticket, target, workflow: workflow));
      return;
    }
    final requires = workflow.requiresFor(target);
    final TicketMoveInput? input;
    if (requires.contains('reason')) {
      final reason = await showRejectSheet(context, ticket: ticket);
      input = reason == null ? null : TicketMoveInput(notes: reason);
    } else if (requires.contains('category') || requires.contains('priority')) {
      input = await showClassifySheet(context, ticket: ticket, title: 'Clasificar solicitud');
    } else if (requires.contains('technician')) {
      input = await showAssignSheet(context, ticket: ticket, title: 'Asignar técnico');
    } else {
      input = await askTicketMoveData(context, ticket: ticket, target: target, requires: requires);
    }
    if (input == null || !mounted) return;
    _actions.add(TriageMoveRequested(
      ticket,
      target,
      workflow: workflow,
      category: input.category,
      priority: input.priority,
      technicianId: input.technicianId,
      // El motivo del rechazo viaja como `reason`; las notas de clasificar y asignar, como `notes`.
      reason: requires.contains('reason') ? input.notes : null,
      notes: requires.contains('reason') ? null : input.notes,
      resolutionSummary: input.resolutionSummary,
    ));
  }

  /// Lo que pasa con cada movimiento: la tarjeta se coloca al empezar, vuelve si el servidor lo
  /// rechaza y, si lo acepta, se recargan las columnas y las cifras.
  void _onOutcome(BuildContext context, TriageActionsState state) {
    final outcome = state.outcome!;
    switch (outcome.kind) {
      case TriageOutcomeKind.started:
        _board.add(RequestBoardMovedOptimistically(outcome.ticket, outcome.target));
        return;
      case TriageOutcomeKind.succeeded:
        _summary.add(const QueueSummaryRequested());
      case TriageOutcomeKind.failed:
        _board.add(RequestBoardMoveReverted(outcome.ticket.id));
      case TriageOutcomeKind.blocked:
        break;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(outcome.message), backgroundColor: outcome.isError ? AppColors.error : AppColors.navy));
  }

  /// Quita filtros y búsqueda: lo que pide «Limpiar filtros» cuando nada coincide.
  void _clearAll() {
    _searchController.clear();
    setState(() => _technicians = {});
    _board.add(const RequestBoardFiltersChanged(QueueFilters()));
  }

  Future<void> _showFilters() async {
    final result = await showQueueFilterSheet(
      context,
      initial: _board.state.filters,
      technicians: _technicians,
      categories: _categories.state.categories,
      priorities: _priorities.state.priorities,
      techniciansRepository: context.read<TechniciansRepository>(),
    );
    if (result == null || !mounted) return;
    setState(() => _technicians = result.technicians);
    _board.add(RequestBoardFiltersChanged(result.filters));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _board),
        BlocProvider.value(value: _summary),
        BlocProvider.value(value: _priorities),
        BlocProvider.value(value: _categories),
        BlocProvider.value(value: _actions),
      ],
      child: BlocListener<TriageActionsBloc, TriageActionsState>(
        listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
        listener: _onOutcome,
        child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: PendingRequestsScreen.path),
        body: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.steel,
          child: ListView(
            controller: _pageController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // El encabezado ocupa todo el ancho; lo demás conserva sus márgenes.
              const QueueHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _SearchRow(controller: _searchController, onFilters: _showFilters),
              _ActiveFilters(technicians: _technicians, searchController: _searchController),
              const SizedBox(height: AppSpacing.md),
              BlocBuilder<QueueSummaryBloc, QueueSummaryState>(
                builder: (context, state) => QueueKpiGrid(summary: state.summary, unavailable: state.unavailable, onRetry: () => _summary.add(const QueueSummaryRequested())),
              ),
              const SizedBox(height: AppSpacing.md),
              BlocBuilder<PrioritiesCubit, PrioritiesState>(
                builder: (context, priorities) => BlocBuilder<CategoryNamesCubit, CategoryNamesState>(
                  builder: (context, categories) => BlocBuilder<QueueSummaryBloc, QueueSummaryState>(
                    builder: (context, state) => QueuePulseCard(
                      summary: state.summary,
                      unavailable: state.unavailable,
                      priorities: priorities.priorities,
                      categoryNames: categories.names,
                      onRetry: () => _summary.add(const QueueSummaryRequested()),
                    ),
                  ),
                ),
              ),
                ]),
              ),
              // Las tres columnas se reparten el ancho: un margen menor les da más sitio.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, AppSpacing.lg, 8, AppSpacing.xxl),
                child: _BoardSection(onClearFilters: _clearAll, onMove: _requestMove, pageController: _pageController),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.onFilters});

  final TextEditingController controller;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: (text) => context.read<RequestBoardBloc>().add(RequestBoardSearchChanged(text)),
              decoration: InputDecoration(
                hintText: 'Buscar por número, título o descripción…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          controller.clear();
                          context.read<RequestBoardBloc>().add(const RequestBoardSearchChanged(''));
                        },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        BlocSelector<RequestBoardBloc, RequestBoardState, int>(
          selector: (state) => state.filters.activeCount,
          builder: (context, count) => FilterButton(count: count, onPressed: onFilters),
        ),
      ]);
}

/// Un chip por filtro activo, que se quita con su equis.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.technicians, required this.searchController});

  final Map<int, String> technicians;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) => BlocBuilder<RequestBoardBloc, RequestBoardState>(
        buildWhen: (a, b) => a.filters != b.filters,
        builder: (context, state) {
          final filters = state.filters;
          if (filters.activeCount == 0) return const SizedBox.shrink();
          final names = context.watch<CategoryNamesCubit>().state.names;
          final priorities = context.watch<PrioritiesCubit>().state.priorities;
          void change(QueueFilters next) => context.read<RequestBoardBloc>().add(RequestBoardFiltersChanged(next));
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final code in filters.categories) ActiveFilterChip(label: names[code] ?? code, onRemove: () => change(filters.copyWith(categories: [...filters.categories]..remove(code)))),
              for (final code in filters.priorities)
                ActiveFilterChip(
                  label: [for (final p in priorities) if (p.code == code) p.name].firstOrNull ?? code,
                  onRemove: () => change(filters.copyWith(priorities: [...filters.priorities]..remove(code))),
                ),
              for (final id in filters.technicianIds) ActiveFilterChip(label: technicians[id] ?? 'Técnico #$id', onRemove: () => change(filters.copyWith(technicianIds: [...filters.technicianIds]..remove(id)))),
              if (filters.dateFrom != null && filters.dateTo != null) ActiveFilterChip(label: queueRangeLabel(filters.dateFrom!, filters.dateTo!), onRemove: () => change(filters.copyWith(clearDates: true))),
            ]),
          );
        },
      );
}

/// «Solicitudes por estado»: el tablero con sus cuatro estados posibles (cargando, error,
/// al día/sin coincidencias y con datos).
class _BoardSection extends StatelessWidget {
  const _BoardSection({required this.onClearFilters, required this.onMove, required this.pageController});

  final VoidCallback onClearFilters;
  final void Function(TicketListItem ticket, String target) onMove;
  final ScrollController pageController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<RequestBoardBloc, RequestBoardState>(
      builder: (context, state) {
        final board = context.read<RequestBoardBloc>();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text('Solicitudes por estado', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (state.workflowPhase) {
            WorkflowPhase.loading => const _BoardSkeleton(),
            WorkflowPhase.failure => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'No pudimos cargar el tablero',
                message: state.failure?.message,
                actionLabel: 'Reintentar',
                onAction: () => board.add(const RequestBoardStarted()),
              ),
            WorkflowPhase.ready when state.isEmpty => EmptyState(
                icon: state.filters.isEmpty ? Icons.task_alt_rounded : Icons.search_off_rounded,
                title: state.filters.isEmpty ? 'La bandeja está al día' : 'Ninguna solicitud coincide con los filtros',
                message: state.filters.isEmpty ? 'No hay solicitudes esperando trabajo.' : 'Prueba con otra búsqueda o limpia los filtros.',
                actionLabel: state.filters.isEmpty ? null : 'Limpiar filtros',
                onAction: state.filters.isEmpty ? null : onClearFilters,
              ),
            WorkflowPhase.ready => QueueBoard(
                columns: state.columns,
                workflow: state.workflow,
                now: DateTime.now(),
                statusLabel: (status) => statusMeta(status).label,
                onMore: (status) => board.add(RequestBoardMoreRequested(status)),
                onRetry: (status) => board.add(RequestBoardColumnRetried(status)),
                onOpen: (ticket) => showTicketDetail(context, ticket.id),
                onMove: onMove,
                movingIds: context.watch<TriageActionsBloc>().state.inFlight,
                pageController: pageController,
              ),
          },
        ]);
      },
    );
  }
}

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Skeleton(height: 110, radius: AppRadius.md),
        SizedBox(height: AppSpacing.sm),
        Skeleton(height: 110, radius: AppRadius.md),
      ]);
}
