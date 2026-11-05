import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/bloc/permissions_cubit.dart';
import '../../../core/auth/home_resolver.dart';
import '../../../core/domain/ticket_meta.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/paged/paged_bloc.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/app_chip.dart';
import '../../../shared/empty_state.dart';
import '../../../shared/paged_list_view.dart';
import '../data/models.dart';
import '../data/requests_repository.dart';
import 'bloc/my_requests_bloc.dart';

abstract final class RequestRoutes {
  static const create = '/solicitudes/nueva';
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

  @override
  Widget build(BuildContext context) {
    final canCreate = context.select((PermissionsCubit cubit) => cubit.state.can('solicitudes:crear'));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis solicitudes'),
        actions: [
          IconButton(
            tooltip: 'Perfil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(HomeDestination.profile.path),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push(RequestRoutes.create),
              icon: const Icon(Icons.add),
              label: const Text('Nueva solicitud'),
            )
          : null,
      body: Column(
        children: [
          _StatusFilter(selected: _status, onSelected: (value) => setState(() => _status = value)),
          Expanded(
            child: BlocProvider(
              key: ValueKey(_status),
              create: (context) =>
                  MyRequestsBloc(repository: context.read<RequestsRepository>(), status: _status)..add(const PagedStarted()),
              child: BlocBuilder<MyRequestsBloc, PagedListState<TicketListItem>>(
                builder: (context, state) => PagedListView<TicketListItem>(
                  value: state,
                  onRefresh: context.read<MyRequestsBloc>().refresh,
                  onLoadMore: () => context.read<MyRequestsBloc>().add(const PagedLoadMoreRequested()),
                  itemBuilder: (context, item) => _RequestCard(item: item),
                  empty: EmptyState(
                    icon: Icons.assignment_outlined,
                    title: _status == null ? 'Aún no tienes solicitudes' : 'No hay solicitudes con este estado',
                    message: _status == null && canCreate ? 'Cuando reportes un problema con un equipo, aparecerá aquí.' : null,
                    actionLabel: _status == null && canCreate ? 'Nueva solicitud' : null,
                    onAction: _status == null && canCreate ? () => context.push(RequestRoutes.create) : null,
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
