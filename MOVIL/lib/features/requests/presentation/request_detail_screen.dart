import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/ticket_meta.dart';
import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/app_chip.dart';
import '../../../shared/async_view.dart';
import '../application/providers.dart';
import '../data/models.dart';

/// Detalle de una solicitud: datos, estado, historial y adjuntos (solo lectura).
class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.requestId});

  final int requestId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(requestDetailProvider(requestId));
    ref.invalidate(requestAttachmentsProvider(requestId));
    try {
      await ref.read(requestDetailProvider(requestId).future);
    } catch (_) {
      // El error ya se muestra en pantalla.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(requestDetailProvider(requestId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.ticketNumber ?? 'Solicitud')),
      body: AsyncView<TicketDetail>(
        value: detail,
        onRetry: () => _refresh(ref),
        data: (ticket) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(ticket.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [StatusChip(ticket.status), PriorityChip(ticket.priority)],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Field(label: 'Equipo', value: ticket.equipment.label),
              _Field(label: 'Técnico asignado', value: ticket.technicianName ?? 'Sin asignar'),
              _Field(label: 'Creada', value: formatDateTime(ticket.createdAt)),
              _Field(label: 'Última actualización', value: formatDateTime(ticket.updatedAt)),
              _Field(label: 'Descripción', value: ticket.description),
              if (ticket.resolutionSummary != null) _Field(label: 'Resolución', value: ticket.resolutionSummary!),
              const SizedBox(height: AppSpacing.md),
              Text('Historial', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in ticket.history) _HistoryTile(entry: entry),
              const SizedBox(height: AppSpacing.lg),
              Text('Adjuntos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _Attachments(requestId: requestId),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final StatusHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = entry.fromStatus == null ? null : statusMeta(entry.fromStatus!).label;
    final to = statusMeta(entry.toStatus).label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(from == null ? to : '$from → $to', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(formatDateTime(entry.changedAt), style: theme.textTheme.bodySmall),
          if (entry.notes != null) Text(entry.notes!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Los adjuntos cargan aparte: si fallan, el resto del detalle sigue visible.
class _Attachments extends ConsumerWidget {
  const _Attachments({required this.requestId});

  final int requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(requestAttachmentsProvider(requestId));
    return attachments.when(
      loading: () => const LinearProgressIndicator(semanticsLabel: 'Cargando adjuntos'),
      error: (error, _) => Row(
        children: [
          const Expanded(child: Text('No pudimos cargar los adjuntos.')),
          TextButton(
            onPressed: () => ref.invalidate(requestAttachmentsProvider(requestId)),
            child: const Text('Reintentar'),
          ),
        ],
      ),
      data: (items) => items.isEmpty
          ? const Text('Esta solicitud no tiene adjuntos.')
          : Column(
              children: [
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.mimeType.startsWith('image/') ? Icons.image_outlined : Icons.attach_file),
                    title: Text(item.fileName),
                    subtitle: Text(formatFileSize(item.fileSize)),
                  ),
              ],
            ),
    );
  }
}
