import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/permissions_cubit.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/format/formatters.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../core/theme/app_tokens.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/app_chip.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/paged_list_view.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../bloc/requests/my_requests_bloc.dart';
import 'create_request_screen.dart';

abstract final class RequestRoutes {
  static String detail(int id) => '/solicitudes/$id';
}

/// Inicio del Solicitante: sus solicitudes, con filtro por estado.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  /// Filtro elegido: estado efímero de la pantalla. Cambiarlo crea un `MyRequestsBloc` nuevo.
  String? _status;
  int _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final canCreate = context.select((PermissionsCubit cubit) => cubit.state.can('solicitudes:crear'));
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    return Scaffold(
      appBar: profile == null ? AppBar(title: const Text('Mis solicitudes')) : MantixAppBar(profile: profile),
      drawer: profile == null ? null : MantixDrawer(profile: profile, selectedPath: HomeDestination.myRequests.path),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => CreateRequestScreen.show(context),
              icon: const Icon(Icons.add),
              label: const Text('Nueva solicitud'),
            )
          : null,
      body: Column(
        children: [
          if (profile != null)
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Align(alignment: Alignment.centerLeft, child: Text('Mis solicitudes', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 20, fontWeight: FontWeight.w800))),
            ),
          _StatusFilter(selected: _status, onSelected: (value) => setState(() => _status = value)),
          Expanded(
            child: BlocProvider(
              key: ValueKey('$_status|$_pageSize'),
              create: (context) =>
                  MyRequestsBloc(repository: context.read<RequestsRepository>(), status: _status, pageSize: _pageSize)..add(const PagedStarted()),
              child: BlocBuilder<MyRequestsBloc, PagedListState<TicketListItem>>(
                builder: (context, state) => PagedListView<TicketListItem>(
                  value: state,
                  onRefresh: context.read<MyRequestsBloc>().refresh,
                  onLoadMore: () => context.read<MyRequestsBloc>().add(const PagedLoadMoreRequested()),
                  onPage: (page) => context.read<MyRequestsBloc>().add(PagedPageSelected(page)),
                  onPageSize: (size) => setState(() => _pageSize = size),
                  itemBuilder: (context, item) => _RequestCard(item: item),
                  empty: EmptyState(
                    icon: Icons.assignment_outlined,
                    title: _status == null ? 'Aún no tienes solicitudes' : 'No hay solicitudes con este estado',
                    message: _status == null && canCreate ? 'Cuando reportes un problema con un equipo, aparecerá aquí.' : null,
                    actionLabel: _status == null && canCreate ? 'Nueva solicitud' : null,
                    onAction: _status == null && canCreate ? () => CreateRequestScreen.show(context) : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        children: [
          for (final status in <String?>[null, ...knownStatuses])
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(status == null ? 'Todas' : statusMeta(status).label),
                selected: selected == status,
                onSelected: (_) => onSelected(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item});

  final TicketListItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: () => context.push(RequestRoutes.detail(item.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.ticketNumber, style: theme.textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(item.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [StatusChip(item.status), PriorityChip(item.priority)],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(formatDate(item.createdAt), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
