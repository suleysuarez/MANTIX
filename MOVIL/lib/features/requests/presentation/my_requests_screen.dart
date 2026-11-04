import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_resolver.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/domain/ticket_meta.dart';
import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/app_chip.dart';
import '../../../shared/empty_state.dart';
import '../../../shared/paged_list_view.dart';
import '../application/providers.dart';
import '../data/models.dart';

abstract final class RequestRoutes {
  static const create = '/solicitudes/nueva';
  static String detail(int id) => '/solicitudes/$id';
}

/// Inicio del Solicitante: sus solicitudes, con filtro por estado.
class MyRequestsScreen extends ConsumerStatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  ConsumerState<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends ConsumerState<MyRequestsScreen> {
  String? _status;

  Future<void> _refresh() async {
    final provider = myRequestsProvider(_status);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // El error ya se muestra en la lista.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = myRequestsProvider(_status);
    final canCreate = ref.watch(permissionsProvider).contains('solicitudes:crear');
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
            child: PagedListView<TicketListItem>(
              value: ref.watch(provider),
              onRefresh: _refresh,
              onLoadMore: () => ref.read(provider.notifier).loadMore(),
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
