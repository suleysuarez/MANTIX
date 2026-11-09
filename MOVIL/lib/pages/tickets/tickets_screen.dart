import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/app_chip.dart';
import '../../widgets/shared/empty_state.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../bloc/tickets/tickets_bloc.dart';
import '../requests/my_requests_screen.dart';

abstract final class TicketRoutes {
  static const list = '/modulos/tickets';
  static const create = '/tickets/nuevo';
}

/// Gestión móvil de tickets. En pantallas pequeñas, Kanban muestra una columna
/// seleccionable en vez de comprimir todas las columnas en un tablero horizontal.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _searchController = TextEditingController();
  String? _status;
  String? _kanbanStatus;
  String _search = '';
  bool _kanban = false;

  static const _filters = <(String, String?)>[
    ('Todos', null),
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
    super.dispose();
  }

  void _applySearch() {
    final value = _searchController.text.trim();
    if (value != _search) setState(() => _search = value);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }

    return BlocProvider(
      key: ValueKey('$_status|$_search'),
      create: (context) => TicketsBloc(
        repository: context.read<RequestsRepository>(),
        status: _status,
        search: _search,
      )..add(const PagedStarted()),
      child: Builder(
        builder: (context) => Scaffold(
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
            builder: (context, state) => RefreshIndicator(
              onRefresh: context.read<TicketsBloc>().refresh,
              color: const Color(0xFF3E5C76),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gestión de tickets', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('Consulta y supervisa las incidencias técnicas.', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFE5F2FC), borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.confirmation_number_outlined, color: Color(0xFF3E5C76)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.status == PagedStatus.success) _TicketSummary(items: state.items, total: state.info?.total),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _applySearch(),
                    decoration: InputDecoration(
                      hintText: 'Buscar por número, título o descripción…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Buscar',
                        onPressed: _applySearch,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final filter in _filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(filter.$1),
                              selected: _status == filter.$2,
                              onSelected: (_) => setState(() => _status = filter.$2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.status == PagedStatus.success
                              ? '${state.info?.total ?? state.items.length} tickets'
                              : 'Tickets recientes',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined), label: Text('Lista')),
                          ButtonSegment(value: true, icon: Icon(Icons.view_kanban_outlined), label: Text('Kanban')),
                        ],
                        selected: {_kanban},
                        onSelectionChanged: (value) => setState(() => _kanban = value.first),
                      ),
                    ],
                  ),
                  if (_kanban) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final lane in _lanes)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                label: Text(statusMeta(lane).label),
                                selected: (_kanbanStatus ?? 'submitted') == lane,
                                onSelected: (_) => setState(() => _kanbanStatus = lane),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  switch (state.status) {
                    PagedStatus.initial || PagedStatus.loading => const _TicketLoading(),
                    PagedStatus.failure => EmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'No pudimos cargar los tickets',
                        message: state.failure?.message,
                        actionLabel: 'Reintentar',
                        onAction: () => context.read<TicketsBloc>().add(const PagedStarted()),
                      ),
                    PagedStatus.success => _TicketResults(
                        items: _kanban
                            ? state.items.where((item) => item.status == (_kanbanStatus ?? 'submitted')).toList()
                            : state.items,
                        kanban: _kanban,
                        hasMore: state.hasMore,
                        loadingMore: state.loadingMore,
                        loadMoreFailure: state.loadMoreFailure?.message,
                        onOpen: (item) => context.push(RequestRoutes.detail(item.id)),
                        onLoadMore: () => context.read<TicketsBloc>().add(const PagedLoadMoreRequested()),
                      ),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  const _TicketSummary({required this.items, required this.total});
  final List<TicketListItem> items;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final sent = items.where((item) => item.status == 'submitted' || item.status == 'triaged').length;
    final working = items.where((item) => ['assigned', 'in_progress', 'waiting'].contains(item.status)).length;
    final resolved = items.where((item) => item.status == 'resolved' || item.status == 'closed').length;
    final cards = [
      ('Total', total?.toString() ?? items.length.toString(), Icons.confirmation_number_outlined, const Color(0xFFE5F2FC)),
      ('Enviados', '$sent', Icons.mark_email_unread_outlined, const Color(0xFFE7F0FF)),
      ('En proceso', '$working', Icons.engineering_outlined, const Color(0xFFFFF4DE)),
      ('Resueltos', '$resolved', Icons.check_circle_outline, const Color(0xFFE2F6ED)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.35,
          children: [
            for (final card in cards)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE1EAF2))),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: card.$4, borderRadius: BorderRadius.circular(11)),
                      child: Icon(card.$3, size: 19, color: const Color(0xFF3E5C76)),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                          Text(card.$2, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text('Indicadores de los tickets cargados', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF778DA9))),
      ],
    );
  }
}

class _TicketResults extends StatelessWidget {
  const _TicketResults({
    required this.items,
    required this.kanban,
    required this.hasMore,
    required this.loadingMore,
    required this.loadMoreFailure,
    required this.onOpen,
    required this.onLoadMore,
  });

  final List<TicketListItem> items;
  final bool kanban;
  final bool hasMore;
  final bool loadingMore;
  final String? loadMoreFailure;
  final ValueChanged<TicketListItem> onOpen;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No hay tickets para mostrar',
        message: 'Prueba con otro estado o modifica la búsqueda.',
      );
    }
    return Column(
      children: [
        for (final item in items) ...[
          _TicketCard(item: item, onTap: () => onOpen(item), compact: kanban),
          const SizedBox(height: 9),
        ],
        if (loadMoreFailure != null)
          Text(loadMoreFailure!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (hasMore)
          OutlinedButton.icon(
            onPressed: loadingMore ? null : onLoadMore,
            icon: loadingMore
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(loadingMore ? 'Cargando…' : 'Cargar más tickets'),
          ),
      ],
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.item, required this.onTap, required this.compact});
  final TicketListItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.ticketNumber, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF3E5C76))),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF778DA9)),
                ],
              ),
              const SizedBox(height: 5),
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [StatusChip(item.status), PriorityChip(item.priority)],
              ),
              if (!compact) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 14, color: Color(0xFF778DA9)),
                    const SizedBox(width: 5),
                    Text(formatDate(item.createdAt), style: Theme.of(context).textTheme.bodySmall),
                    if (item.category != null) ...[
                      const SizedBox(width: 10),
                      Flexible(child: Text(item.category!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
