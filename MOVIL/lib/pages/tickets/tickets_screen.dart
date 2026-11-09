import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../bloc/tickets/tickets_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/page_info.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/page_number_bar.dart';
import '../../widgets/tickets/ticket_cards.dart';
import '../../widgets/tickets/ticket_kanban.dart';
import '../../widgets/tickets/ticket_summary.dart';
import '../requests/my_requests_screen.dart';

abstract final class TicketRoutes {
  static const list = '/modulos/tickets';
  static const create = '/tickets/nuevo';
}

/// Gestión móvil de tickets: resumen, atención prioritaria, filtros y listado en tabla o
/// Kanban (columnas verticales de color que se deslizan de dos en dos).
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _searchController = TextEditingController();
  final _kanbanController = PageController();
  final _scrollController = ScrollController();
  String? _status;
  String _search = '';
  DateTimeRange? _dates;
  bool _kanban = false;
  int _kanbanPage = 0;

  static const _filters = <(String, String?)>[
    ('Enviados', 'submitted,triaged'),
    ('En proceso', 'assigned,in_progress,waiting'),
    ('Resueltos', 'resolved,closed'),
    ('Cancelados', 'cancelled'),
  ];

  static const _lanes = <String>[
    'submitted', 'triaged', 'assigned', 'in_progress', 'waiting', 'resolved', 'closed',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _kanbanController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applySearch() {
    final value = _searchController.text.trim();
    if (value != _search) setState(() => _search = value);
  }

  String? get _statusLabel => _status == null ? null : _filters.where((f) => f.$2 == _status).map((f) => f.$1).firstOrNull;

  Future<void> _showFilters() async {
    var status = _status;
    var dates = _dates;
    final result = await showModalBottomSheet<(String?, DateTimeRange?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) => FilterSheet(
          onReset: () => setSheet(() {
            status = null;
            dates = null;
          }),
          onApply: () => Navigator.pop(sheet, (status, dates)),
          children: [
            FilterDropdown<String?>(
              label: 'Estado',
              icon: Icons.flag_outlined,
              value: status,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos los estados')),
                for (final f in _filters) DropdownMenuItem<String?>(value: f.$2, child: Text(f.$1)),
              ],
              onChanged: (value) => setSheet(() => status = value),
            ),
            DateRangeFilterField(value: dates, onChanged: (range) => setSheet(() => dates = range)),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _status = result.$1;
        _dates = result.$2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    final theme = Theme.of(context);

    return BlocProvider(
      key: ValueKey('$_status|$_search|$_dates'),
      create: (context) => TicketsBloc(
        repository: context.read<RequestsRepository>(),
        status: _status,
        search: _search,
        dateFrom: _dates?.start,
        dateTo: _dates?.end,
      )..add(const PagedStarted()),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: MantixAppBar(profile: profile),
          drawer: MantixDrawer(profile: profile, selectedPath: TicketRoutes.list),
          floatingActionButton: profile.can('solicitudes:crear')
              ? FloatingActionButton.extended(
                  onPressed: () => context.push(TicketRoutes.create),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nuevo ticket'),
                )
              : null,
          body: BlocBuilder<TicketsBloc, PagedListState<TicketListItem>>(
            builder: (context, state) {
              final loaded = state.status == PagedStatus.success;
              final kanbanPages = kanbanPageCount(_lanes.length);
              return RefreshIndicator(
                onRefresh: context.read<TicketsBloc>().refresh,
                color: AppColors.steel,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    const TicketBanner(),
                    const SizedBox(height: AppSpacing.md),
                    if (loaded) ...[
                      TicketStats(items: state.items, total: state.info?.total),
                      const SizedBox(height: AppSpacing.lg),
                      TicketAttention(items: state.items, onOpen: (item) => context.push(RequestRoutes.detail(item.id))),
                      const SizedBox(height: AppSpacing.lg),
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
                      IconButton.filledTonal(
                        tooltip: 'Filtros',
                        onPressed: _showFilters,
                        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                        icon: Badge(isLabelVisible: _status != null || _dates != null, smallSize: 8, child: const Icon(Icons.tune_rounded)),
                      ),
                    ]),
                    if (_status != null || _dates != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        if (_status != null) ActiveFilterChip(label: _statusLabel ?? 'Estado', onRemove: () => setState(() => _status = null)),
                        if (_dates != null) ActiveFilterChip(label: '${formatDate(_dates!.start)} – ${formatDate(_dates!.end)}', onRemove: () => setState(() => _dates = null)),
                      ]),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Tickets recientes', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                          Text('Últimos tickets registrados en el sistema', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
                        ]),
                      ),
                      if (loaded && _kanban)
                        _PageArrows(
                          page: _kanbanPage,
                          pages: kanbanPages,
                          onPrevious: () => _kanbanController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                          onNext: () => _kanbanController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                        )
                      else if (loaded)
                        Text('${state.info?.total ?? state.items.length} tickets', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.steel, fontWeight: FontWeight.w800)),
                    ]),
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
                          lanes: _lanes,
                          controller: _kanbanController,
                          onPageChanged: (page) => setState(() => _kanbanPage = page),
                          onMove: (item, status) async {
                            try {
                              await context.read<RequestsRepository>().transitionStatus(item.id, status);
                            } catch (error) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cambiar el estado: $error')));
                            }
                          },
                          info: state.info,
                          loadingPage: state.loadingMore,
                          pageFailure: state.loadMoreFailure?.message,
                          onOpen: (item) => context.push(RequestRoutes.detail(item.id)),
                          onPage: (page) {
                            context.read<TicketsBloc>().add(PagedPageSelected(page));
                            _kanbanPage = 0;
                            if (_kanbanController.hasClients) _kanbanController.jumpToPage(0);
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
    );
  }
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

/// «1/4» con flechas, para moverse entre las páginas del Kanban.
class _PageArrows extends StatelessWidget {
  const _PageArrows({required this.page, required this.pages, required this.onPrevious, required this.onNext});
  final int page;
  final int pages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton(tooltip: 'Columnas anteriores', visualDensity: VisualDensity.compact, onPressed: page > 0 ? onPrevious : null, icon: const Icon(Icons.chevron_left_rounded)),
        Text('${page + 1}/$pages', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
        IconButton(tooltip: 'Columnas siguientes', visualDensity: VisualDensity.compact, onPressed: page < pages - 1 ? onNext : null, icon: const Icon(Icons.chevron_right_rounded)),
      ]);
}

class _TicketResults extends StatelessWidget {
  const _TicketResults({
    required this.items,
    required this.kanban,
    required this.lanes,
    required this.controller,
    required this.onPageChanged,
    required this.onMove,
    required this.info,
    required this.loadingPage,
    required this.pageFailure,
    required this.onOpen,
    required this.onPage,
  });

  final List<TicketListItem> items;
  final bool kanban;
  final List<String> lanes;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(TicketListItem, String) onMove;
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
        message: 'Prueba con otro estado o modifica la búsqueda.',
      );
    }
    return Column(
      children: [
        if (kanban)
          TicketKanban(controller: controller, items: items, lanes: lanes, onOpen: onOpen, onMove: onMove, onPageChanged: onPageChanged)
        else
          for (final item in items) ...[
            TicketListCard(item: item, onTap: () => onOpen(item)),
            const SizedBox(height: 10),
          ],
        if (pageFailure != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(pageFailure!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (info != null) ...[
          const SizedBox(height: 8),
          Text('Mostrando ${(info!.page - 1) * info!.pageSize + 1} – ${(info!.page - 1) * info!.pageSize + items.length} de ${info!.total} tickets', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.slate)),
          const SizedBox(height: 8),
          PageNumberBar(page: info!.page, totalPages: info!.totalPages, loading: loadingPage, onPage: onPage),
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
